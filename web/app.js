(() => {
  "use strict";

  const baseEl = document.getElementById("skia-base");
  const overlayEl = document.getElementById("skia-overlay");
  const worldEl = document.getElementById("world-canvas");
  const statusEl = document.getElementById("startup-status");
  const runtimeEl = document.getElementById("runtime-value");
  const encoder = new TextEncoder();
  const decoder = new TextDecoder();
  const events = [];
  const keys = new Set();
  const mouse = { x: 0, y: 0, dx: 0, dy: 0, buttons: 0, focused: true };
  let currentEvent = {};
  let wasm = null;
  let memory = null;
  let table = null;
  let CanvasKit = null;
  let defaultTypeface = null;
  let surfaceSerial = 0;
  const stats = window.__kinemiumStats = { surfaces: 0, draws2d: 0, babylonContexts: 0, meshes: 0, frames: 0 };

  const dpr = () => Math.min(window.devicePixelRatio || 1, 2);
  const width = () => Math.max(1, Math.round(innerWidth * dpr()));
  const height = () => Math.max(1, Math.round(innerHeight * dpr()));
  const heap8 = () => new Uint8Array(memory.buffer);
  const heap32 = () => new DataView(memory.buffer);
  const cstr = (ptr) => {
    if (!ptr) return "";
    const bytes = heap8();
    let end = ptr;
    while (end < bytes.length && bytes[end]) end++;
    return decoder.decode(bytes.subarray(ptr, end));
  };
  const copyString = (value, ptr, capacity) => {
    if (!ptr || capacity <= 0) return 0;
    const bytes = encoder.encode(value || "");
    const count = Math.min(bytes.length, capacity - 1);
    heap8().set(bytes.subarray(0, count), ptr);
    heap8()[ptr + count] = 0;
    return count;
  };
  const bootStart = performance.now();
  stats.startup = {};
  const report = text => { statusEl.textContent = text; };
  const phase = async text => {
    stats.startup[text] = Math.round(performance.now() - bootStart);
    document.documentElement.dataset.enginePhase = text;
    report(text);
    console.info("[Kinemium startup]", text, stats.startup[text] + "ms");
    await new Promise(resolve => setTimeout(resolve, 0));
  };

  const scanCodes = {
    KeyA: 4, KeyB: 5, KeyC: 6, KeyD: 7, KeyE: 8, KeyF: 9, KeyG: 10, KeyH: 11, KeyI: 12, KeyJ: 13, KeyK: 14, KeyL: 15, KeyM: 16,
    KeyN: 17, KeyO: 18, KeyP: 19, KeyQ: 20, KeyR: 21, KeyS: 22, KeyT: 23, KeyU: 24, KeyV: 25, KeyW: 26, KeyX: 27, KeyY: 28, KeyZ: 29,
    Digit1: 30, Digit2: 31, Digit3: 32, Digit4: 33, Digit5: 34, Digit6: 35, Digit7: 36, Digit8: 37, Digit9: 38, Digit0: 39,
    Enter: 40, Escape: 41, Backspace: 42, Tab: 43, Space: 44, Minus: 45, Equal: 46, BracketLeft: 47, BracketRight: 48, Backslash: 49,
    Semicolon: 51, Quote: 52, Backquote: 53, Comma: 54, Period: 55, Slash: 56, CapsLock: 57, F1: 58, F2: 59, F3: 60, F4: 61, F5: 62, F6: 63,
    F7: 64, F8: 65, F9: 66, F10: 67, F11: 68, F12: 69, Insert: 73, Home: 74, PageUp: 75, Delete: 76, End: 77, PageDown: 78,
    ArrowRight: 79, ArrowLeft: 80, ArrowDown: 81, ArrowUp: 82, ControlLeft: 224, ShiftLeft: 225, AltLeft: 226, MetaLeft: 227,
    ControlRight: 228, ShiftRight: 229, AltRight: 230, MetaRight: 231
  };
  const mods = e => (e.shiftKey ? 1 : 0) | (e.ctrlKey ? 64 : 0) | (e.altKey ? 256 : 0) | (e.metaKey ? 1024 : 0);
  const point = e => ({ x: e.clientX * dpr(), y: e.clientY * dpr() });
  addEventListener("keydown", e => { const scancode = scanCodes[e.code] || 0; keys.add(scancode); events.push({ type: 8, scancode, mods: mods(e), repeat: e.repeat }); });
  addEventListener("keyup", e => { const scancode = scanCodes[e.code] || 0; keys.delete(scancode); events.push({ type: 9, scancode, mods: mods(e) }); });
  addEventListener("keypress", e => { if (e.key.length === 1) events.push({ type: 10, text: e.key }); });
  // Babylon cancels pointerdown's default action, which suppresses the
  // compatibility mousedown/mouseup events. Consume native pointer events
  // before the 3D renderer sees them, with one queue entry per actual event.
  const pointerButtons = new Map();
  const lastClicks = new Map();
  const mouseButton = button => [1, 2, 3, 4, 5][button] || 0;
  const updatePointer = e => {
    const p = point(e);
    mouse.x = p.x; mouse.y = p.y;
    return p;
  };
  const releasePointer = (e, cancelled = false) => {
    const pressed = pointerButtons.get(e.pointerId);
    if (!pressed) return;
    const p = cancelled ? {x: mouse.x, y: mouse.y} : updatePointer(e);
    const button = mouseButton(e.button);
    const release = cancelled ? [...pressed.keys()] : [button];
    for (const b of release) {
      if (!pressed.has(b)) continue;
      const clicks = pressed.get(b);
      pressed.delete(b);
      mouse.buttons &= ~(1 << (b - 1));
      // Cancelled gestures release away from the GUI so they cannot activate it.
      events.push({type:13, ...(cancelled ? {x:-1,y:-1} : p), button:b, clicks});
    }
    if (!pressed.size) pointerButtons.delete(e.pointerId);
  };
  addEventListener("pointermove", e => {
    if (!e.isPrimary) return;
    const p=updatePointer(e), dx=(e.movementX || 0)*dpr(), dy=(e.movementY || 0)*dpr();
    mouse.dx += dx; mouse.dy += dy;
    // Pointer Events uses pointerdown/up for the first/last button only.
    // A chorded mouse button change is reported via pointermove.
    if (e.pointerType === "mouse" && e.button >= 0 && e.button <= 4) {
      const b=mouseButton(e.button), mask=[1,4,2,8,16][e.button];
      const isDown=!!(e.buttons & mask), wasDown=pointerButtons.get(e.pointerId)?.has(b);
      if (isDown && !wasDown) pressPointer(e);
      else if (!isDown && wasDown) releasePointer(e);
    }
    events.push({type:11,...p,dx,dy,buttons:mouse.buttons});
  }, true);
  function pressPointer(e) {
    if (!e.isPrimary) return;
    const p=updatePointer(e), button=mouseButton(e.button);
    if (!button) return;
    let pressed=pointerButtons.get(e.pointerId);
    if (!pressed) pointerButtons.set(e.pointerId,pressed=new Map());
    if (pressed.has(button)) return;
    const now=performance.now(), last=lastClicks.get(button);
    const clicks=last && now-last.time<=500 && Math.hypot(p.x-last.x,p.y-last.y)<=5*dpr() ? Math.min(last.clicks+1,255) : 1;
    lastClicks.set(button,{...p,time:now,clicks});
    pressed.set(button,clicks);
    mouse.buttons |= 1 << (button-1);
    events.push({type:12,...p,button,clicks});
  }
  addEventListener("pointerdown", pressPointer, true);
  addEventListener("pointerup", e => releasePointer(e), true);
  addEventListener("pointercancel", e => releasePointer(e,true), true);
  addEventListener("lostpointercapture", e => {
    if(!e.buttons) releasePointer(e,true);
  }, true);
  addEventListener("wheel", e => { const p = point(e); events.push({ type: 14, ...p, dx: -Math.sign(e.deltaX), dy: -Math.sign(e.deltaY) }); e.preventDefault(); }, { passive: false });
  addEventListener("contextmenu", e => e.preventDefault());
  addEventListener("focus", () => { mouse.focused = true; events.push({ type: 6 }); });
  addEventListener("blur", () => {
    mouse.focused = false; keys.clear();
    for(const pointerId of [...pointerButtons.keys()]) releasePointer({pointerId},true);
    mouse.buttons=0; mouse.dx=mouse.dy=0; lastClicks.clear();
    events.push({type:5});
  });
  addEventListener("resize", () => events.push({ type: 7 }));

  const platform = {
    host_width: width, host_height: height, host_dpi_scale: dpr,
    host_mouse_x: () => mouse.x, host_mouse_y: () => mouse.y,
    host_mouse_dx: () => { const v = mouse.dx; mouse.dx = 0; return v; }, host_mouse_dy: () => { const v = mouse.dy; mouse.dy = 0; return v; },
    host_mouse_buttons: () => mouse.buttons, host_modifiers: () => 0, host_focused: () => mouse.focused ? 1 : 0,
    host_now_ns: () => BigInt(Math.round(performance.now() * 1e6)),
    host_key_down: sc => keys.has(sc) ? 1 : 0,
    host_poll_event: () => {
      currentEvent = events.shift() || {};
      if(currentEvent.type===12)stats.pointerDowns=(stats.pointerDowns||0)+1;
      if(currentEvent.type===13)stats.pointerUps=(stats.pointerUps||0)+1;
      return currentEvent.type || 0;
    },
    host_event_scancode: () => currentEvent.scancode || 0, host_event_modifiers: () => currentEvent.mods || 0,
    host_event_repeat: () => currentEvent.repeat ? 1 : 0, host_event_button: () => currentEvent.button || 0,
    host_event_clicks: () => currentEvent.clicks || 0, host_event_x: () => currentEvent.x || 0, host_event_y: () => currentEvent.y || 0,
    host_event_dx: () => currentEvent.dx || 0, host_event_dy: () => currentEvent.dy || 0,
    host_copy_event_text: (ptr, cap) => copyString(currentEvent.text || "", ptr, cap),
    host_system_theme: () => matchMedia("(prefers-color-scheme: dark)").matches ? 2 : 1,
    host_set_relative: on => { if (on) worldEl.requestPointerLock?.(); else document.exitPointerLock?.(); },
    host_show_cursor: visible => document.body.style.cursor = visible ? "default" : "none",
    host_warp_mouse: () => { }, host_text_input: () => { },
    host_set_cursor: kind => { document.body.style.cursor = ["default", "text", "wait", "crosshair", "progress", "nwse-resize", "nesw-resize", "ew-resize", "ns-resize", "move", "not-allowed", "pointer"][kind] || "default"; },
    host_set_clipboard: ptr => { navigator.clipboard?.writeText(cstr(ptr)); return 1; },
    host_copy_clipboard: () => 0
    , host_debug_phase: code => {stats.startup["native-"+code]=Math.round(performance.now()-bootStart);console.info("[Kinemium native]",code);}
  };

  // File playback retains its existing behavior. Generated PCM uses an owned
  // WAV Blob and a per-sound element so transport and cleanup remain independent.
  const pcmSounds = new Map();
  let nextPcmId = 1;
  const audio = {
    host_play_sound: ptr => { try { const a = new Audio(cstr(ptr)); a.play?.().catch?.(() => { }); } catch { } },
    host_pcm_load: (ptr, frames, rate, channels) => {
      try {
        const bytes = frames * channels * 4;
        const wave = new ArrayBuffer(44 + bytes), view = new DataView(wave);
        const tag = (offset, value) => { for (let i = 0; i < 4; i++) view.setUint8(offset+i, value.charCodeAt(i)); };
        tag(0, "RIFF"); view.setUint32(4, 36 + bytes, true); tag(8, "WAVE");
        tag(12, "fmt "); view.setUint32(16, 16, true);
        view.setUint16(20, 3, true); view.setUint16(22, channels, true);
        view.setUint32(24, rate, true); view.setUint32(28, rate*channels*4, true);
        view.setUint16(32, channels*4, true); view.setUint16(34, 32, true);
        tag(36, "data"); view.setUint32(40, bytes, true);
        new Uint8Array(wave, 44).set(new Uint8Array(memory.buffer, ptr, bytes));
        const url = URL.createObjectURL(new Blob([wave], {type:"audio/wav"}));
        const element = new Audio(url);
        element.preservesPitch = false;
        const id = nextPcmId++;
        pcmSounds.set(id, {element, url});
        return id;
      } catch { return 0; }
    },
    host_pcm_destroy: id => { const s = pcmSounds.get(id); if (!s) return; s.element.pause(); s.element.removeAttribute("src"); s.element.load(); URL.revokeObjectURL(s.url); pcmSounds.delete(id); },
    host_pcm_play: id => { const a = pcmSounds.get(id)?.element; if (!a) return 0; try { a.play().catch(() => {}); return 1; } catch { return 0; } },
    host_pcm_pause: id => pcmSounds.get(id)?.element.pause(),
    host_pcm_playing: id => { const a = pcmSounds.get(id)?.element; return a && !a.paused && !a.ended ? 1 : 0; },
    host_pcm_ended: id => pcmSounds.get(id)?.element.ended ? 1 : 0,
    host_pcm_volume: (id,v) => {const a=pcmSounds.get(id)?.element; if(a) a.volume=Math.max(0,Math.min(1,v));},
    host_pcm_pitch: (id,v) => {const a=pcmSounds.get(id)?.element; if(a) {try {a.playbackRate=v;} catch {}}},
    host_pcm_loop: (id,v) => {const a=pcmSounds.get(id)?.element; if(a) a.loop=!!v;},
    host_pcm_cursor: id => pcmSounds.get(id)?.element.currentTime || 0,
    host_pcm_seek: (id,v) => {const a=pcmSounds.get(id)?.element; if(a) {try {a.currentTime=v;} catch {}}},
  };

  // Browser-backed key/value store for services that would otherwise touch a
  // real filesystem. Backed by localStorage so project data survives reloads;
  // the engine only ever sees opaque string keys and byte buffers.
  const storage = {
    host_random_guid: (ptr, cap) => copyString(crypto.randomUUID(), ptr, cap),
    host_storage_get: (keyPtr, outPtr, cap) => {
      let value = null; try { value = localStorage.getItem(cstr(keyPtr)); } catch { value = null; }
      if (value === null) return -1;
      const bytes = encoder.encode(value);
      if (outPtr && cap > 0) heap8().set(bytes.subarray(0, Math.min(bytes.length, cap)), outPtr);
      return bytes.length;
    },
    host_storage_set: (keyPtr, valPtr, len) => {
      try { localStorage.setItem(cstr(keyPtr), decoder.decode(heap8().subarray(valPtr, valPtr + len))); return 1; } catch { return 0; }
    },
    host_storage_remove: keyPtr => { try { localStorage.removeItem(cstr(keyPtr)); return 1; } catch { return 0; } }
  };

  // Browser WebSocket transport. Browsers cannot open the raw UDP socket ENet
  // uses, so the engine's client transport talks to a native server over a
  // WebSocket on the same port. Each connection is identified by a small integer
  // handle; inbound messages are queued as whole frames so the engine can size
  // its buffer before copying.
  const sockets = new Map();
  let nextSocketId = 1;
  const net = {
    host_net_connect: urlPtr => {
      // The engine only ever builds ws://host:port, but a full address
      // (https://host) is how you join through a TLS reverse proxy or tunnel.
      // Rebuild the URL from the page query so the scheme/port are correct, and
      // so an https page can open a wss:// socket.
      let url = cstr(urlPtr);
      try {
        const query = new URLSearchParams(location.search);
        const addr = query.get("address") || "", port = query.get("port") || "";
        if (addr) {
          if (/^wss?:\/\//i.test(addr)) url = addr;
          else if (/^https:\/\//i.test(addr)) url = "wss://" + addr.slice(8);
          else if (/^http:\/\//i.test(addr)) url = "ws://" + addr.slice(7);
          else url = (location.protocol === "https:" ? "wss://" : "ws://") + addr + (port ? ":" + port : "");
        }
        if (location.protocol === "https:" && /^ws:\/\//i.test(url)) url = "wss://" + url.slice(5);
        const ws = new WebSocket(url);
        ws.binaryType = "arraybuffer";
        const id = nextSocketId++;
        const conn = { ws, state: 0, queue: [] };
        ws.onopen = () => { conn.state = 1; };
        ws.onclose = () => { conn.state = 2; };
        ws.onerror = () => { conn.state = 2; };
        ws.onmessage = ev => { conn.queue.push(new Uint8Array(ev.data)); };
        sockets.set(id, conn);
        return id;
      } catch (e) { console.error("[net] could not open WebSocket to", url, e); return -1; }
    },
    host_net_state: id => { const c = sockets.get(id); return c ? c.state : 2; },
    host_net_send: (id, ptr, len, disposable = 0) => {
      const c = sockets.get(id);
      if (!c || c.state !== 1) return 0;
      if (disposable && c.ws.bufferedAmount > 16 * 1024) return 0;
      try { c.ws.send(heap8().subarray(ptr, ptr + len).slice()); return 1; } catch { return 0; }
    },
    host_net_message_size: id => { const c = sockets.get(id); return (c && c.queue.length) ? c.queue[0].length : 0; },
    host_net_receive: (id, outPtr, cap) => {
      const c = sockets.get(id);
      if (!c || !c.queue.length) return -1;
      const msg = c.queue[0];
      if (msg.length > cap) return -2;
      heap8().set(msg, outPtr);
      c.queue.shift();
      return msg.length;
    },
    host_net_close: id => { const c = sockets.get(id); if (c) { try { c.ws.close(); } catch { } sockets.delete(id); } },
    host_net_now_ms: () => performance.now(),
    host_net_param: (namePtr, outPtr, cap) => {
      try {
        const value = new URLSearchParams(location.search).get(cstr(namePtr)) || "";
        const bytes = encoder.encode(value);
        if (outPtr && cap > 0) heap8().set(bytes.subarray(0, Math.min(bytes.length, cap)), outPtr);
        return bytes.length;
      } catch { return -1; }
    }
  };

  // The native engine imports more of the Skia/Filament surface than this shell
  // implements yet. Missing entries resolve to a no-op so the module stays
  // instantiable; the real implementations defined above take precedence, so
  // wrapping a module is safe to keep as features are filled in.
  const withStubs = module => new Proxy(module, {
    get: (target, key) => (key in target ? target[key] : (..._args) => 0)
  });

  const surfaces = new Map(), images = new Map(), shaders = new Map(), typefaces = new Map();
  let nextHandle = 1;
  const handle = (map, value) => { const id = nextHandle++; map.set(id, value); return id; };
  const builtinFontHandles = new Map(), pinnedFaces = new Set();
  const pendingFontNotifications = new Set();
  const clearFontCaches = id => {
    const prefix = id + "|";
    for (const [k,f] of fontCache) if (k.startsWith(prefix)) {f.delete();fontCache.delete(k);}
    for (const k of widthCache.keys()) if (k.startsWith(prefix)) widthCache.delete(k);
  };
  const getBuiltinFont = name => {
    if (!/^[a-zA-Z0-9_. -]+$/.test(name)) return 0;
    if (builtinFontHandles.has(name)) return builtinFontHandles.get(name);
    const id = handle(typefaces, defaultTypeface);
    builtinFontHandles.set(name,id);pinnedFaces.add(id);
    fetch("fonts/"+encodeURIComponent(name)).then(r=>{if(!r.ok)throw Error(r.status);return r.arrayBuffer();}).then(bytes=>{
      const face=CanvasKit.Typeface.MakeFreeTypeFaceFromData(bytes);
      if(face){clearFontCaches(id);typefaces.set(id,face);pendingFontNotifications.add(id);}
    }).catch(error=>console.warn("Builtin font fallback:",name,error));
    return id;
  };
  const preloadFont = async name => {
    const r=await fetch("fonts/"+encodeURIComponent(name));
    if(!r.ok)throw Error("Font "+name+" "+r.status);
    const face=CanvasKit.Typeface.MakeFreeTypeFaceFromData(await r.arrayBuffer());
    if(face){const id=handle(typefaces,face);builtinFontHandles.set(name,id);pinnedFaces.add(id);}
  };
  const measure = (font, text) => { if (!font || !text) return 0; const glyphs = font.getGlyphIDs(text); if (!glyphs || !glyphs.length) return 0; const widths = font.getGlyphWidths(glyphs); let w = 0; for (let i = 0; i < widths.length; i++) w += widths[i]; return w; };
  // Fonts and glyph-advance widths are requested hundreds of times per frame by
  // the text layout pass. Reuse Font objects and memoize widths; both Font
  // construction and getGlyphWidths cross into CanvasKit's own wasm module.
  const fontCache = new Map(), widthCache = new Map();
  const fontFor = (face, id, size) => { const k = id + "|" + size; let f = fontCache.get(k); if (!f) { f = new CanvasKit.Font(face, size); fontCache.set(k, f); } return f; };
  const measureCached = (face, id, size, str) => { const k = id + "|" + size + "|" + str; let w = widthCache.get(k); if (w === undefined) { w = measure(fontFor(face, id, size), str); if (widthCache.size > 20000) widthCache.clear(); widthCache.set(k, w); } return w; };
  const paint = (r, g, b, a, stroke = 0) => { const p = new CanvasKit.Paint(); p.setAntiAlias(true); p.setColor(CanvasKit.Color(r, g, b, a)); if (stroke > 0) { p.setStyle(CanvasKit.PaintStyle.Stroke); p.setStrokeWidth(stroke); } return p; };
  // Shape/text primitives are drawn with fill/stroke paints that are rebuilt
  // every frame (dozens of rounded panels, borders, labels). Allocating and
  // freeing a CanvasKit.Paint per draw crosses into CanvasKit's wasm heap and
  // dominated the 2D frame budget, so cache paints by colour+stroke and reuse
  // them. These paints are never mutated after creation, so sharing is safe;
  // the few call sites that do mutate (blur/mask filters) still allocate via
  // paint() directly.
  const paintCache = new Map();
  const getPaint = (r, g, b, a, stroke) => { const k = r + "|" + g + "|" + b + "|" + a + "|" + stroke; let p = paintCache.get(k); if (!p) { p = paint(r, g, b, a, stroke); paintCache.set(k, p); } return p; };
  const withPaint = (rgba, stroke, fn) => fn(getPaint(rgba[0], rgba[1], rgba[2], rgba[3], stroke));
  const surf = id => surfaces.get(id);
  const color = (r, g, b, a) => [r, g, b, a / 255];
  const rect = (x, y, w, h) => CanvasKit.XYWHRect(x, y, w, h);
  const roundRect = (x, y, w, h, rx, ry) => CanvasKit.RRectXY(rect(x, y, w, h), rx, ry);

  // CanvasKit's MakeImageFromEncoded only decodes raster formats (PNG/JPEG/WebP/
  // GIF). Nearly every built-in UI icon is an SVG, and the engine hands those
  // bytes to the same entry point, so an encoded-only decode returns null and
  // leaves the label blank. SVG payloads are rasterized through the browser
  // (createImageBitmap) and handed back as a CanvasKit image. That decode is
  // async, so LoadFromMemory returns a placeholder handle that the draw path
  // picks up once the bitmap resolves.
  const looksLikeSvg = bytes => {
    const limit = Math.min(bytes.length, 1024);
    for (let i = 0; i + 3 < limit; i++) {
      if (bytes[i] === 0x3c && (bytes[i + 1] | 0x20) === 0x73 && (bytes[i + 2] | 0x20) === 0x76 && (bytes[i + 3] | 0x20) === 0x67) return true;
    }
    return false;
  };
  const decodeSvgAsync = (bytes, resolve) => {
    const settle = image => {
      if (image) stats.svgLoaded = (stats.svgLoaded || 0) + 1; else stats.svgFailed = (stats.svgFailed || 0) + 1;
      resolve(image);
    };
    const blob = new Blob([bytes], { type: "image/svg+xml" });
    const toImage = source => { try { return CanvasKit.MakeImageFromCanvasImageSource(source); } catch { return null; } };
    // createImageBitmap rejects on SVG in some builds (headless with no raster
    // backend, for one), so a failed decode falls back to an <img> element,
    // which rasterizes SVG through the document's own renderer.
    const viaElement = () => {
      const url = URL.createObjectURL(blob);
      const image = new Image();
      image.onload = () => { settle(toImage(image)); URL.revokeObjectURL(url); };
      image.onerror = () => { settle(null); URL.revokeObjectURL(url); };
      image.src = url;
    };
    if (typeof createImageBitmap !== "function") { viaElement(); return; }
    createImageBitmap(blob).then(bitmap => {
      if (bitmap.width && bitmap.height) { settle(toImage(bitmap)); return; }
      createImageBitmap(blob, { resizeWidth: 256, resizeHeight: 256, resizeQuality: "high" })
        .then(scaled => settle(toImage(scaled)))
        .catch(viaElement);
    }).catch(viaElement);
  };
  const loadImageFromMemory = (ptr, size) => {
    const bytes = heap8().slice(ptr, ptr + size);
    if (looksLikeSvg(bytes)) {
      const id = handle(images, null);
      decodeSvgAsync(bytes, image => {
        if (!images.has(id)) { image?.delete?.(); return; }
        if (image) images.set(id, image);
      });
      return id;
    }
    const image = CanvasKit.MakeImageFromEncoded(bytes);
    if (image) { stats.rasterLoaded = (stats.rasterLoaded || 0) + 1; return handle(images, image); }
    stats.rasterFailed = (stats.rasterFailed || 0) + 1;
    return 0;
  };

  const skia = {
    // Prefer a GPU-backed surface: the software raster surface re-rasterizes
    // every panel/border/label on the CPU each frame, which dominated the 2D
    // frame budget. Fall back to software only when WebGL is unavailable.
    Kine_Skia_Surface_Create: (w, h) => { const el = (surfaceSerial++ % 2 === 0) ? baseEl : overlayEl; el.width = w; el.height = h; const s = CanvasKit.MakeWebGLCanvasSurface(el) || CanvasKit.MakeSWCanvasSurface(el); stats.surfaces++; return handle(surfaces, { surface: s, canvas: s.getCanvas(), el, w, h }); },
    Kine_Skia_Surface_Destroy: id => { const s = surf(id); if (s) { s.surface.delete(); surfaces.delete(id); } },
    Kine_Skia_Surface_GetWidth: id => surf(id)?.w || 0, Kine_Skia_Surface_GetHeight: id => surf(id)?.h || 0,
    Kine_Skia_Surface_GetRowBytes: id => (surf(id)?.w || 0) * 4, Kine_Skia_Surface_GetPixels: () => 0,
    Kine_Skia_Surface_Flush: id => { const t = performance.now(); surf(id)?.surface.flush(); stats.flushMs = performance.now() - t; },
    Kine_Skia_Surface_Clear: (id, r, g, b, a) => { const t = performance.now(); surf(id)?.canvas.clear(CanvasKit.Color(r, g, b, a)); stats.clearMs = performance.now() - t; },
    Kine_Skia_Surface_DrawRect: (id, x, y, w, h, r, g, b, a, sw) => { stats.draws2d++; withPaint(color(r, g, b, a), sw, p => surf(id)?.canvas.drawRect(rect(x, y, w, h), p)); },
    Kine_Skia_Surface_DrawRoundRect: (id, x, y, w, h, rx, ry, r, g, b, a, sw) => withPaint(color(r, g, b, a), sw, p => surf(id)?.canvas.drawRRect(roundRect(x, y, w, h, rx, ry), p)),
    Kine_Skia_Surface_DrawRotatedRect: (id, cx, cy, w, h, degrees, r, g, b, a, sw) => { const c = surf(id)?.canvas; if (!c) return; c.save(); c.rotate(degrees, cx, cy); withPaint(color(r, g, b, a), sw, p => c.drawRect(rect(cx - w / 2, cy - h / 2, w, h), p)); c.restore(); },
    Kine_Skia_Surface_DrawCircle: (id, cx, cy, rad, r, g, b, a, sw) => withPaint(color(r, g, b, a), sw, p => surf(id)?.canvas.drawCircle(cx, cy, rad, p)),
    Kine_Skia_Surface_DrawOval: (id, x, y, w, h, r, g, b, a, sw) => withPaint(color(r, g, b, a), sw, p => surf(id)?.canvas.drawOval(rect(x, y, w, h), p)),
    Kine_Skia_Surface_DrawLine: (id, x0, y0, x1, y1, sw, r, g, b, a) => withPaint(color(r, g, b, a), Math.max(sw, .01), p => surf(id)?.canvas.drawLine(x0, y0, x1, y1, p)),
    Kine_Skia_Surface_DrawArc: (id, x, y, w, h, start, sweep, useCenter, r, g, b, a, sw) => withPaint(color(r, g, b, a), sw, p => surf(id)?.canvas.drawArc(rect(x, y, w, h), start, sweep, !!useCenter, p)),
    Kine_Skia_Surface_DrawPolygon: (id, ptr, count, closed, r, g, b, a, sw) => { const c = surf(id)?.canvas; if (!c || count < 2) return; const v = new Float32Array(memory.buffer, ptr, count * 2), path = new CanvasKit.Path(); path.moveTo(v[0], v[1]); for (let i = 1; i < count; i++)path.lineTo(v[i * 2], v[i * 2 + 1]); if (closed) path.close(); withPaint(color(r, g, b, a), sw, p => c.drawPath(path, p)); path.delete(); },
    Kine_Skia_Surface_Save: id => surf(id)?.canvas.save(), Kine_Skia_Surface_Restore: id => surf(id)?.canvas.restore(),
    Kine_Skia_Surface_Translate: (id, x, y) => surf(id)?.canvas.translate(x, y), Kine_Skia_Surface_Rotate: (id, d) => surf(id)?.canvas.rotate(d, 0, 0), Kine_Skia_Surface_Scale: (id, x, y) => surf(id)?.canvas.scale(x, y),
    Kine_Skia_Surface_ClipRect: (id, x, y, w, h) => surf(id)?.canvas.clipRect(rect(x, y, w, h), CanvasKit.ClipOp.Intersect, true),
    Kine_Skia_Surface_ClipRoundRect: (id, x, y, w, h, rx, ry) => surf(id)?.canvas.clipRRect(roundRect(x, y, w, h, rx, ry), CanvasKit.ClipOp.Intersect, true),
    Kine_Skia_Surface_ClipSquircle: (id, x, y, w, h, rad) => surf(id)?.canvas.clipRRect(roundRect(x, y, w, h, rad, rad), CanvasKit.ClipOp.Intersect, true),
    Kine_Skia_Surface_DrawSquircle: (id, x, y, w, h, rad, exp, r, g, b, a, sw) => skia.Kine_Skia_Surface_DrawRoundRect(id, x, y, w, h, rad, rad, r, g, b, a, sw),
    Kine_Skia_Surface_DrawUIShadow: (id, x, y, w, h, rad, exp, ox, oy, blur, spread, r, g, b, a) => { const p = paint(r, g, b, a / 255); p.setMaskFilter(CanvasKit.MaskFilter.MakeBlur(CanvasKit.BlurStyle.Normal, blur, true)); surf(id)?.canvas.drawRRect(roundRect(x + ox - spread, y + oy - spread, w + spread * 2, h + spread * 2, rad, rad), p); p.delete(); },
    Kine_Skia_Surface_DrawBackdropBlurRect: (id, x, y, w, h, rx, ry, blur, alpha, r, g, b, a) => skia.Kine_Skia_Surface_DrawRoundRect(id, x, y, w, h, rx, ry, r, g, b, Math.round(a * alpha / 255), 0),
    Kine_Skia_Surface_DrawBackdropBlurSquircle: (id, x, y, w, h, rad, exp, blur, alpha, r, g, b, a) => skia.Kine_Skia_Surface_DrawRoundRect(id, x, y, w, h, rad, rad, r, g, b, Math.round(a * alpha / 255), 0),
    Kine_Skia_Surface_DrawText: (id, text, x, y, size, font, r, g, b, a) => { const c = surf(id)?.canvas; if (!c || !defaultTypeface) return; const f = fontFor(defaultTypeface, 0, size); withPaint(color(r, g, b, a), 0, p => c.drawText(cstr(text), x, y, p, f)); },
    Kine_Skia_Surface_DrawTextShadow: (id, text, x, y, size, font, ox, oy, blur, spread, r, g, b, a) => skia.Kine_Skia_Surface_DrawText(id, text, x + ox, y + oy, size, font, r, g, b, a),
    Kine_Skia_Surface_MeasureText: (text, size) => measureCached(defaultTypeface, 0, size, cstr(text)),
    Kine_Skia_Surface_GetFontAscent: size => -size * .8, Kine_Skia_Surface_GetFontLineHeight: size => size * 1.2,
    Kine_Skia_Typeface_LoadFromMemory: (ptr, size) => { const bytes = heap8().slice(ptr, ptr + size); const tf = CanvasKit.Typeface.MakeFreeTypeFaceFromData(bytes.buffer); return tf ? handle(typefaces, tf) : 0; },
    Kine_Skia_Typeface_LoadFromFile: ptr => {const path=cstr(ptr);return path.startsWith("builtin://fonts/")?getBuiltinFont(path.slice(16)):0;},
    Kine_Skia_Typeface_Destroy: id => { if(pinnedFaces.has(id))return;clearFontCaches(id);typefaces.get(id)?.delete();typefaces.delete(id); },
    Kine_Skia_Typeface_MeasureText: (tf, text, size) => { const face = typefaces.get(tf) || defaultTypeface; if (!face) return 0; return measureCached(face, tf, size, cstr(text)); },
    Kine_Skia_Typeface_GetLineHeight: (tf, size) => size * 1.2, Kine_Skia_Typeface_GetAscent: (tf, size) => -size * .8,
    Kine_Skia_Surface_DrawTextTypeface: (id, text, x, y, size, tf, r, g, b, a) => { const c = surf(id)?.canvas, face = typefaces.get(tf) || defaultTypeface; if (!c || !face) return; const f = fontFor(face, tf, size); stats.draws2d++; withPaint(color(r, g, b, a), 0, p => c.drawText(cstr(text), x, y, p, f)); },
    Kine_Skia_Surface_DrawTextShadowTypeface: (id, text, x, y, size, tf, ox, oy, blur, spread, r, g, b, a) => skia.Kine_Skia_Surface_DrawTextTypeface(id, text, x + ox, y + oy, size, tf, r, g, b, a),
    Kine_Skia_Surface_DrawTextBlurredTypeface: (id, text, x, y, size, tf, blur, r, g, b, a) => { const c = surf(id)?.canvas, face = typefaces.get(tf) || defaultTypeface; if (!c || !face) return; const f = fontFor(face, tf, size), p = paint(r, g, b, a); if (blur > 0) p.setMaskFilter(CanvasKit.MaskFilter.MakeBlur(CanvasKit.BlurStyle.Normal, blur, true)); c.drawText(cstr(text), x, y, p, f); p.delete(); },
    Kine_Skia_Image_LoadFromFile: () => 0,
    Kine_Skia_Image_LoadFromMemory: loadImageFromMemory,
    Kine_Skia_Image_Destroy: id => { images.get(id)?.delete(); images.delete(id); }, Kine_Skia_Image_GetWidth: id => images.get(id)?.width() || 0, Kine_Skia_Image_GetHeight: id => images.get(id)?.height() || 0,
    Kine_Skia_Surface_DrawImage: (id, img, x, y) => { const i = images.get(img); if (i) surf(id)?.canvas.drawImage(i, x, y); },
    Kine_Skia_Surface_DrawImageSized: (id, img, x, y, w, h) => { const i = images.get(img); if (i) surf(id)?.canvas.drawImageRectOptions(i, rect(0, 0, i.width(), i.height()), rect(x, y, w, h), CanvasKit.FilterMode.Linear, CanvasKit.MipmapMode.None); },
    Kine_Skia_Surface_DrawImageRect: (id, img, sx, sy, sw, sh, dx, dy, dw, dh) => { const i = images.get(img); if (i) surf(id)?.canvas.drawImageRectOptions(i, rect(sx, sy, sw, sh), rect(dx, dy, dw, dh), CanvasKit.FilterMode.Linear, CanvasKit.MipmapMode.None); },
    Kine_Skia_Surface_DrawImageScaled: (id, img, srcX, srcY, srcWidth, srcHeight, dstX, dstY, dstWidth, dstHeight, tileSizeX, tileSizeY, scaleType, resample, r, g, b, colorA, alpha) => {
      const i = images.get(img), c = surf(id)?.canvas; if (!i || !c) return;
      stats.draws2d++;
      const sw = srcWidth > 0 ? srcWidth : i.width(), sh = srcHeight > 0 ? srcHeight : i.height();
      const filter = resample === 2 ? CanvasKit.FilterMode.Nearest : CanvasKit.FilterMode.Linear, mip = CanvasKit.MipmapMode.None;
      const p = new CanvasKit.Paint();
      if (alpha != null && alpha < 255) p.setAlphaf(alpha / 255);
      if (colorA > 0) p.setColorFilter(CanvasKit.ColorFilter.MakeBlend(CanvasKit.Color(r, g, b, colorA), CanvasKit.BlendMode.SrcIn));
      const blit = (sx, sy, ssw, ssh, dx, dy, ddw, ddh) => c.drawImageRectOptions(i, rect(sx, sy, ssw, ssh), rect(dx, dy, ddw, ddh), filter, mip, p);
      if (scaleType === 1 && (tileSizeX > 0 || tileSizeY > 0)) {
        const bx = Math.min(tileSizeX > 0 ? tileSizeX : sw, sw), by = Math.min(tileSizeY > 0 ? tileSizeY : sh, sh);
        const dxs = [dstX, dstX + bx, dstX + dstWidth - bx], dxw = [bx, dstWidth - 2 * bx, bx];
        const dys = [dstY, dstY + by, dstY + dstHeight - by], dyh = [by, dstHeight - 2 * by, by];
        const sxs = [srcX, srcX + bx, srcX + sw - bx], sxw = [bx, sw - 2 * bx, bx];
        const sys = [srcY, srcY + by, srcY + sh - by], syh = [by, sh - 2 * by, by];
        for (let a = 0; a < 3; a++)for (let e = 0; e < 3; e++)if (dxw[e] > 0 && dyh[a] > 0) blit(sxs[e], sys[a], sxw[e], syh[a], dxs[e], dys[a], dxw[e], dyh[a]);
      } else if (scaleType === 2) {
        const tw = (tileSizeX > 0 ? tileSizeX : sw), th = (tileSizeY > 0 ? tileSizeY : sh);
        c.save(); c.clipRect(rect(dstX, dstY, dstWidth, dstHeight), CanvasKit.ClipOp.Intersect, true);
        for (let y = 0; y < dstHeight; y += th)for (let x = 0; x < dstWidth; x += tw)blit(srcX, srcY, Math.min(tw, dstWidth - x), Math.min(th, dstHeight - y), dstX + x, dstY + y, Math.min(tw, dstWidth - x), Math.min(th, dstHeight - y));
        c.restore();
      } else if (scaleType === 3 || scaleType === 4) {
        const k = scaleType === 3 ? Math.min(dstWidth / sw, dstHeight / sh) : Math.max(dstWidth / sw, dstHeight / sh);
        const dw = sw * k, dh = sh * k, dx = dstX + (dstWidth - dw) / 2, dy = dstY + (dstHeight - dh) / 2;
        if (scaleType === 4) { c.save(); c.clipRect(rect(dstX, dstY, dstWidth, dstHeight), CanvasKit.ClipOp.Intersect, true); blit(srcX, srcY, sw, sh, dx, dy, dw, dh); c.restore(); }
        else blit(srcX, srcY, sw, sh, dx, dy, dw, dh);
      } else {
        blit(srcX, srcY, sw, sh, dstX, dstY, dstWidth, dstHeight);
      }
      p.delete();
    },
    Kine_Skia_Surface_DrawImageOutlineSized: (id, img, x, y, w, h, t, r, g, b, a) => skia.Kine_Skia_Surface_DrawRoundRect(id, x, y, w, h, 0, 0, r, g, b, a, t),
    Kine_Skia_Surface_DrawImageShadow: (id, img, x, y, w, h, ox, oy, blur, spread, r, g, b, a) => {
      const i = images.get(img), c = surf(id)?.canvas; if (!i || !c) return;
      const dx = x + ox - spread, dy = y + oy - spread, dw = w + spread * 2, dh = h + spread * 2;
      const pad = Math.max(blur, 1), bounds = rect(dx - pad, dy - pad, dw + pad * 2, dh + pad * 2);
      const src = rect(0, 0, i.width(), i.height()), dst = rect(dx, dy, dw, dh);
      const layer = new CanvasKit.Paint();
      c.save();
      c.clipRect(bounds, CanvasKit.ClipOp.Intersect, false);
      c.saveLayer(layer, bounds);
      const mp = paint(r, g, b, a / 255);
      mp.setMaskFilter(CanvasKit.MaskFilter.MakeBlur(CanvasKit.BlurStyle.Normal, blur, true));
      c.drawImageRectOptions(i, src, dst, CanvasKit.FilterMode.Linear, CanvasKit.MipmapMode.None, mp);
      const tp = paint(r, g, b, a / 255);
      tp.setBlendMode(CanvasKit.BlendMode.SrcIn);
      c.drawRect(bounds, tp);
      c.restore();
      c.restore();
      layer.delete(); mp.delete(); tp.delete();
    },
    Kine_Skia_Surface_DrawPixels: () => { }, Kine_Skia_Surface_GetPixel: (id, x, y, pr, pg, pb, pa) => { const data = surf(id)?.surface.readPixels(x, y, { width: 1, height: 1 }); if (data) { const h = heap8(); h[pr] = data[0]; h[pg] = data[1]; h[pb] = data[2]; h[pa] = data[3]; } },
    Kine_Skia_RuntimeShader_Create: src => handle(shaders, { source: cstr(src) }), Kine_Skia_RuntimeShader_Destroy: id => shaders.delete(id), Kine_Skia_RuntimeShader_SetUniform: () => 1,
    Kine_Skia_RuntimeShader_GetLastError: () => 0, Kine_Skia_Surface_DrawRuntimeShaderRect: () => { }
  };

  // Keep the existing Odin import ABI; GPU work is handled by Babylon.js.
  let renderer3D;

  // Emscripten setjmp/longjmp + C++ exception runtime. Luau and Jolt use C++
  // exceptions that unwind across indirect calls; the wasm references these
  // helpers from `env`, so the browser shell must implement the full handshake
  // (exception metadata, tempRet0 selector, invoke_* catch trampolines).
  const EH = (() => {
    const u8 = () => new Int8Array(memory.buffer);
    const u32 = () => new Uint32Array(memory.buffer);
    const setTempRet0 = v => wasm._emscripten_tempret_set(v);
    const stackSave = () => wasm.emscripten_stack_get_current();
    const stackRestore = p => wasm._emscripten_stack_restore(p);
    let exceptionLast = 0, uncaughtExceptionCount = 0;
    const exceptionCaught = [];
    class ExceptionInfo {
      constructor(excPtr) { this.excPtr = excPtr; this.ptr = excPtr - 24; }
      set_type(t) { u32()[(this.ptr + 4) >> 2] = t; } get_type() { return u32()[(this.ptr + 4) >> 2]; }
      set_destructor(d) { u32()[(this.ptr + 8) >> 2] = d; } get_destructor() { return u32()[(this.ptr + 8) >> 2]; }
      set_caught(c) { u8()[this.ptr + 12] = c ? 1 : 0; } get_caught() { return u8()[this.ptr + 12] !== 0; }
      set_rethrown(r) { u8()[this.ptr + 13] = r ? 1 : 0; } get_rethrown() { return u8()[this.ptr + 13] !== 0; }
      init(type, destructor) { this.set_adjusted_ptr(0); this.set_type(type); this.set_destructor(destructor); }
      set_adjusted_ptr(p) { u32()[(this.ptr + 16) >> 2] = p; } get_adjusted_ptr() { return u32()[(this.ptr + 16) >> 2]; }
    }
    const findMatchingCatch = args => {
      const thrown = exceptionLast;
      if (!thrown) { setTempRet0(0); return 0; }
      const info = new ExceptionInfo(thrown);
      info.set_adjusted_ptr(thrown);
      const thrownType = info.get_type();
      if (!thrownType) { setTempRet0(0); return thrown; }
      for (const caughtType of args) {
        if (caughtType === 0 || caughtType === thrownType) break;
        if (wasm.__cxa_can_catch(caughtType, thrownType, info.ptr + 16)) { setTempRet0(caughtType); return thrown; }
      }
      setTempRet0(thrownType);
      return thrown;
    };
    const invoke = (ret, index, args) => {
      const sp = stackSave();
      try { return ret ? table.get(index)(...args) : table.get(index)(...args); }
      catch (e) { stackRestore(sp); if (e !== e + 0) throw e; wasm.setThrew(1, 0); return ret ? 0 : undefined; }
    };
    return {
      __cxa_begin_catch: ptr => {
        const info = new ExceptionInfo(ptr);
        if (!info.get_caught()) { info.set_caught(true); uncaughtExceptionCount--; }
        info.set_rethrown(false);
        exceptionCaught.push(info);
        return wasm.__cxa_get_exception_ptr(ptr);
      },
      __cxa_end_catch: () => {
        wasm.setThrew(0, 0);
        const info = exceptionCaught.pop();
        if (info) wasm.__cxa_decrement_exception_refcount(info.excPtr);
        exceptionLast = 0;
      },
      __cxa_throw: (ptr, type, destructor) => {
        const info = new ExceptionInfo(ptr);
        info.init(type, destructor);
        wasm.__cxa_increment_exception_refcount(ptr);
        exceptionLast = ptr;
        uncaughtExceptionCount++;
        throw ptr;
      },
      __cxa_rethrow_primary_exception: ptr => {
        if (!ptr) return;
        const info = new ExceptionInfo(ptr);
        exceptionCaught.push(info);
        info.set_rethrown(true);
        const last = exceptionCaught.pop();
        if (!last) { throw new Error("no exception to throw"); }
        const p = last.excPtr;
        if (!last.get_rethrown()) { exceptionCaught.push(last); last.set_rethrown(true); last.set_caught(false); uncaughtExceptionCount++; }
        wasm.__cxa_increment_exception_refcount(p);
        exceptionLast = p;
        throw p;
      },
      __cxa_find_matching_catch_2: () => findMatchingCatch([]),
      __cxa_find_matching_catch_3: a0 => findMatchingCatch([a0]),
      __cxa_find_matching_catch_4: (a0, a1) => findMatchingCatch([a0, a1]),
      __resumeException: ptr => { if (!exceptionLast) exceptionLast = ptr; throw exceptionLast; },
      _emscripten_throw_longjmp: () => { throw Infinity; },
      invoke_v: index => invoke(false, index, []),
      invoke_vi: (index, a1) => invoke(false, index, [a1]),
      invoke_vii: (index, a1, a2) => invoke(false, index, [a1, a2]),
      invoke_viii: (index, a1, a2, a3) => invoke(false, index, [a1, a2, a3]),
      invoke_ii: (index, a1) => invoke(true, index, [a1]),
      invoke_iii: (index, a1, a2) => invoke(true, index, [a1, a2]),
      invoke_iiii: (index, a1, a2, a3) => invoke(true, index, [a1, a2, a3]),
      invoke_j: index => { const sp = stackSave(); try { return table.get(index)(); } catch (e) { stackRestore(sp); if (e !== e + 0) throw e; wasm.setThrew(1, 0); return 0n; } }
    };
  })();

  const env = new Proxy({}, {
    get: (_, name) => {
      if (name in EH) return EH[name];
      if (name === "emscripten_get_now" || name === "emscripten_date_now") return () => performance.now();
      if (name === "emscripten_get_heap_max") return () => memory.buffer.byteLength;
      if (name === "emscripten_resize_heap") return requested => { try { memory.grow(Math.max(0, Math.ceil((requested - memory.buffer.byteLength) / 65536))); return 1; } catch { return 0; } };
      if (String(name).startsWith("invoke_")) return (index, ...args) => table.get(index)(...args);
      return () => 0;
    }
  });
  const wasi = { fd_close: () => 0, fd_seek: () => 0, fd_write: (fd, iovs, count, written) => { let total = 0, out = ""; const dv = heap32(); for (let i = 0; i < count; i++) { const p = dv.getUint32(iovs + i * 8, true), n = dv.getUint32(iovs + i * 8 + 4, true); out += decoder.decode(heap8().subarray(p, p + n)); total += n; } if (written) dv.setUint32(written, total, true); if (out.trim()) console.log(out.trimEnd()); return 0; } };

  async function start() {
    await phase("Loading CanvasKit");
    const engineFetch = fetch("kinemium_engine.wasm");
    // Begin compiling as soon as bytes arrive, in parallel with UI setup.
    const compiled = engineFetch.then(response=>{if(!response.ok)throw Error("WASM download: "+response.status);return WebAssembly.compileStreaming(response);});
    compiled.catch(()=>{});
    const manifestFetch = fetch("material-manifest.json").then(r=>r.ok?r.json():{}).catch(()=>({}));
    CanvasKit = await CanvasKitInit({ locateFile: f => `canvaskit/${f}` });
    defaultTypeface = CanvasKit.Typeface.MakeFreeTypeFaceFromData(await (await fetch("fonts/Roboto.ttf")).arrayBuffer());
    await phase("Loading core fonts");
    await Promise.all(["Montserrat-Regular.ttf","JetBrainsMono-Regular.ttf","RobotoMono-Regular.ttf"].map(name=>preloadFont(name).catch(error=>console.warn(error))));
    await phase("Loading Babylon.js renderer");
    if (!globalThis.BABYLON || !globalThis.createKinemiumBabylonBackend) throw new Error("Babylon.js renderer bundle is missing");
    renderer3D = createKinemiumBabylonBackend({ B: BABYLON, canvas: worldEl, heap8, heap32, stats, materialManifest: await manifestFetch });
    await phase("starting-odin-luau-jolt");
    const memoryInterface = new odin.WasmMemoryInterface();
    let imports = odin.setupDefaultImports(memoryInterface, null, memoryInterface.memory);
    imports = { ...imports, kinemium_platform: withStubs(platform), kinemium_skia: withStubs(skia), kinemium_filament: withStubs(renderer3D), kinemium_audio: withStubs(audio), kinemium_storage: withStubs(storage), kinemium_net: withStubs(net), env, wasi_snapshot_preview1: wasi };
    await phase("Downloading and compiling WebAssembly");
    const module = await compiled;
    await phase("Instantiating WebAssembly");
    const instance = await WebAssembly.instantiate(module, imports);
    wasm = instance.exports; memory = wasm.memory; table = wasm.__indirect_function_table;
    memoryInterface.setExports(wasm); memoryInterface.setMemory(memory);
    await phase("Initializing native libraries");
    // wasm-ld must not wrap every exported function with C++ constructors.
    // Run them exactly once before starting Luau/Jolt/Odin.
    wasm.__wasm_call_ctors?.();
    await phase("Starting Odin runtime");
    wasm._start();
    const context = wasm.default_context_ptr();
    await phase("odin-context-ready");
    await phase("luau-vm-ready");
    await phase("installing-engine-environment");
    await new Promise(resolve => requestAnimationFrame(resolve));
    wasm.initialize_environment(context);
    await phase("engine-environment-ready");
    await phase("running-studio-luau-modules");
    await new Promise(resolve => requestAnimationFrame(resolve));
    wasm.initialize_scripts(context);
    await phase("studio-luau-modules-ready");
    await phase("creating-skia-and-babylon");
    await new Promise(resolve => requestAnimationFrame(resolve));
    if (!wasm.initialize_renderer(context)) throw Error("Renderer initialization failed");
    await phase("engine-ready");
    runtimeEl.textContent = stats.renderer || "Running in browser"; document.documentElement.dataset.engineReady = "true";
    let then = performance.now();
    const frame = now => { try { stats.frameCalls = (stats.frameCalls || 0) + 1; const t0 = performance.now(); for(const id of pendingFontNotifications){wasm.web_font_ready?.(id,context);} pendingFontNotifications.clear(); const keep = wasm.step(Math.min((now - then) / 1000, .1), context); stats.stepMs = performance.now() - t0; if (now - then > 0) stats.fps = Math.round(1000 / (now - then)); then = now; if (keep) requestAnimationFrame(frame); else wasm._end(); } catch (error) { console.error(error); document.documentElement.dataset.engineError = "true"; runtimeEl.textContent = "Frame failed"; statusEl.textContent = error.message; } };
    requestAnimationFrame(frame);
  }
  start().catch(error => { console.error(error); runtimeEl.textContent = "Startup failed"; statusEl.textContent = error.message; statusEl.style.color = "#ff7088"; document.documentElement.dataset.engineError = "true"; });
})();
