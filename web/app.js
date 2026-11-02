(() => {
  "use strict";

  const baseEl = document.getElementById("skia-base");
  const overlayEl = document.getElementById("skia-overlay");
  const filamentEl = document.getElementById("filament-canvas");
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
  const stats = window.__kinemiumStats = { surfaces: 0, draws2d: 0, filamentContexts: 0, meshes: 0, frames: 0 };

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
  const report = text => { statusEl.textContent = text; };
  const phase = async text => { report(text); };

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
  addEventListener("mousemove", e => { const p = point(e); mouse.dx = e.movementX * dpr(); mouse.dy = e.movementY * dpr(); mouse.x = p.x; mouse.y = p.y; events.push({ type: 11, ...p, dx: mouse.dx, dy: mouse.dy }); });
  addEventListener("mousedown", e => { const p = point(e), button = e.button === 0 ? 1 : e.button === 1 ? 2 : 3; mouse.buttons |= 1 << (button - 1); events.push({ type: 12, ...p, button, clicks: e.detail }); });
  addEventListener("mouseup", e => { const p = point(e), button = e.button === 0 ? 1 : e.button === 1 ? 2 : 3; mouse.buttons &= ~(1 << (button - 1)); events.push({ type: 13, ...p, button, clicks: e.detail }); });
  addEventListener("wheel", e => { const p = point(e); events.push({ type: 14, ...p, dx: -Math.sign(e.deltaX), dy: -Math.sign(e.deltaY) }); e.preventDefault(); }, { passive: false });
  addEventListener("contextmenu", e => e.preventDefault());
  addEventListener("focus", () => { mouse.focused = true; events.push({ type: 6 }); });
  addEventListener("blur", () => { mouse.focused = false; keys.clear(); events.push({ type: 5 }); });
  addEventListener("resize", () => events.push({ type: 7 }));

  const platform = {
    host_width: width, host_height: height, host_dpi_scale: dpr,
    host_mouse_x: () => mouse.x, host_mouse_y: () => mouse.y,
    host_mouse_dx: () => { const v = mouse.dx; mouse.dx = 0; return v; }, host_mouse_dy: () => { const v = mouse.dy; mouse.dy = 0; return v; },
    host_mouse_buttons: () => mouse.buttons, host_modifiers: () => 0, host_focused: () => mouse.focused ? 1 : 0,
    host_now_ns: () => BigInt(Math.round(performance.now() * 1e6)),
    host_key_down: sc => keys.has(sc) ? 1 : 0,
    host_poll_event: () => { currentEvent = events.shift() || {}; return currentEvent.type || 0; },
    host_event_scancode: () => currentEvent.scancode || 0, host_event_modifiers: () => currentEvent.mods || 0,
    host_event_repeat: () => currentEvent.repeat ? 1 : 0, host_event_button: () => currentEvent.button || 0,
    host_event_clicks: () => currentEvent.clicks || 0, host_event_x: () => currentEvent.x || 0, host_event_y: () => currentEvent.y || 0,
    host_event_dx: () => currentEvent.dx || 0, host_event_dy: () => currentEvent.dy || 0,
    host_copy_event_text: (ptr, cap) => copyString(currentEvent.text || "", ptr, cap),
    host_system_theme: () => matchMedia("(prefers-color-scheme: dark)").matches ? 2 : 1,
    host_set_relative: on => { if (on) filamentEl.requestPointerLock?.(); else document.exitPointerLock?.(); },
    host_show_cursor: visible => document.body.style.cursor = visible ? "default" : "none",
    host_warp_mouse: () => { }, host_text_input: () => { },
    host_set_cursor: kind => { document.body.style.cursor = ["default", "text", "wait", "crosshair", "progress", "nwse-resize", "nesw-resize", "ew-resize", "ns-resize", "move", "not-allowed", "pointer"][kind] || "default"; },
    host_set_clipboard: ptr => { navigator.clipboard?.writeText(cstr(ptr)); return 1; },
    host_copy_clipboard: () => 0
    , host_debug_phase: () => { }
  };

  // Minimal audio host: the web engine's audio backend forwards each fire-and-
  // forget play to a one-shot HTMLAudioElement. Autoplay policies may reject
  // until the user interacts, so failures are swallowed.
  const audio = {
    host_play_sound: ptr => { try { const a = new Audio(cstr(ptr)); a.play?.().catch?.(() => { }); } catch { } }
  };

  // Browser-backed key/value store for services that would otherwise touch a
  // real filesystem. Backed by localStorage so project data survives reloads;
  // the engine only ever sees opaque string keys and byte buffers.
  const storage = {
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
    host_net_send: (id, ptr, len) => {
      const c = sockets.get(id);
      if (!c || c.state !== 1) return 0;
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
    Kine_Skia_Typeface_LoadFromFile: () => 0,
    Kine_Skia_Typeface_Destroy: id => { typefaces.get(id)?.delete(); typefaces.delete(id); },
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

  const filamentContexts = new Map(), filamentMeshes = new Map(), filamentLights = new Map(), filamentTextures = new Map();
  let materialBytes = null;
  let _filamentSampler = null;
  const filamentSampler = () => _filamentSampler ??= new Filament.TextureSampler(Filament.MinFilter.LINEAR, Filament.MagFilter.LINEAR, Filament.WrapMode.REPEAT);
  // Meshes carry positions, uv0 and normals: the web material is lit, so the
  // shading model reads the geometry normal and the sun light casts shadows.
  const cubeGeometry = () => {
    const positions = [], uvs = [], normals = [], indices = [];
    const faces = [[[0, 0, 1], [1, 0, 0], [0, 1, 0]], [[0, 0, -1], [-1, 0, 0], [0, 1, 0]], [[1, 0, 0], [0, 0, -1], [0, 1, 0]], [[-1, 0, 0], [0, 0, 1], [0, 1, 0]], [[0, 1, 0], [1, 0, 0], [0, 0, -1]], [[0, -1, 0], [1, 0, 0], [0, 0, 1]]];
    for (const [n, u, v] of faces) {
      const base = positions.length / 3;
      for (const [su, sv] of [[-1, -1], [1, -1], [1, 1], [-1, 1]]) {
        positions.push(n[0] + u[0] * su + v[0] * sv, n[1] + u[1] * su + v[1] * sv, n[2] + u[2] * su + v[2] * sv);
        uvs.push((su + 1) / 2, (sv + 1) / 2);
        normals.push(n[0], n[1], n[2]);
      }
      indices.push(base, base + 1, base + 2, base, base + 2, base + 3);
    }
    return { positions: new Float32Array(positions), uvs: new Float32Array(uvs), normals: new Float32Array(normals), indices: new Uint16Array(indices) };
  };
  // The sphere is a unit sphere, so position doubles as the outward normal.
  const sphereGeometry = () => { const rings = 16, segments = 24, positions = [], uvs = [], normals = [], indices = []; for (let y = 0; y <= rings; y++) { const v = y / rings, phi = v * Math.PI; for (let x = 0; x <= segments; x++) { const u = x / segments, theta = u * Math.PI * 2; const nx = Math.sin(phi) * Math.cos(theta), ny = Math.cos(phi), nz = Math.sin(phi) * Math.sin(theta); positions.push(nx, ny, nz); uvs.push(u, v); normals.push(nx, ny, nz); } } for (let y = 0; y < rings; y++) { for (let x = 0; x < segments; x++) { const a = y * (segments + 1) + x, b = a + segments + 1; indices.push(a, b, a + 1, b, b + 1, a + 1); } } return { positions: new Float32Array(positions), uvs: new Float32Array(uvs), normals: new Float32Array(normals), indices: new Uint16Array(indices) }; };
  // Upload the shape's vertex/index buffers once. Geometry is shared by every
  // instance of a shape; only the entity (transform + material instance) is
  // per-instance, because the engine draws each object as its own list entry
  // (it does not pack instances into a single draw). A shared entity would make
  // all instances overwrite one transform and one material.
  // This Filament version has no NORMAL attribute: the geometry normal is fed
  // through TANGENTS as a packed tangent-frame quaternion, which the built-in
  // SurfaceOrientation helper produces from the normals.
  const uploadGeometry = (ctx, geo) => { const F = Filament; const count = geo.positions.length / 3; const normals = geo.normals && geo.normals.length === count * 3 ? geo.normals : new Float32Array(count * 3); const sob = new F.SurfaceOrientation$Builder(); sob.vertexCount(count); sob.normals(normals, 0); const orientation = sob.build(); const tangents = orientation.getQuats(count); const vb = F.VertexBuffer.Builder().vertexCount(count).bufferCount(3).attribute(F.VertexAttribute.POSITION, 0, F.VertexBuffer$AttributeType.FLOAT3, 0, 12).attribute(F.VertexAttribute.UV0, 1, F.VertexBuffer$AttributeType.FLOAT2, 0, 8).attribute(F.VertexAttribute.TANGENTS, 2, F.VertexBuffer$AttributeType.SHORT4, 0, 8).normalized(F.VertexAttribute.TANGENTS).build(ctx.engine); vb.setBufferAt(ctx.engine, 0, geo.positions); vb.setBufferAt(ctx.engine, 1, geo.uvs); vb.setBufferAt(ctx.engine, 2, tangents); const ib = F.IndexBuffer.Builder().indexCount(geo.indices.length).bufferType(F.IndexBuffer$IndexType.USHORT).build(ctx.engine); ib.setBuffer(ctx.engine, geo.indices); return { vb, ib }; };
  const createNode = mesh => { const ctx = mesh.ctx, F = Filament, e = F.EntityManager.get().create(); const mi = ctx.material.createInstance(); mi.setFloat4Parameter("baseColor", [.55, .65, .82, 1]); mi.setFloatParameter("hasTexture", 0); mi.setFloatParameter("roughness", .4); mi.setFloatParameter("metallic", 0); mi.setFloatParameter("shadowStrength", 1); F.RenderableManager.Builder(1).boundingBox({ center: [0, 0, 0], halfExtent: [1, 1, 1] }).castShadows(true).receiveShadows(true).material(0, mi).geometry(0, F.RenderableManager$PrimitiveType.TRIANGLES, mesh.vb, mesh.ib).build(ctx.engine, e); return { entity: e, material: mi, inScene: false, castShadow: true, receiveShadow: true }; };
  // Per-part CastShadow/ReceiveShadow ride in the draw item flags (see
  // workspace_part_flags). The renderable is per pooled node, so the flags are
  // only pushed when they differ from what the node already has.
  const applyNodeShadowFlags = (ctx, node, flags) => { const cast = (flags & 1) !== 0, receive = (flags & 2) !== 0; if (node.castShadow === cast && node.receiveShadow === receive) return; try { const rm = ctx.renderables, inst = rm.getInstance(node.entity); if (inst) { rm.setCastShadows(inst, cast); rm.setReceiveShadows(inst, receive); inst.delete?.(); } } catch { } node.castShadow = cast; node.receiveShadow = receive; };
  // Nodes are pooled per shape and reused frame to frame; `used` counts how many
  // nodes this frame's draw list touched so stale nodes can be hidden again.
  const acquireNode = mesh => { const k = mesh.used; let node = mesh.nodes[k]; if (!node) { node = createNode(mesh); mesh.nodes[k] = node; } mesh.used = k + 1; return node; };
  const buildTexture = (ctx, width, height, pixels) => { const F = Filament; const tex = F.Texture.Builder().width(width).height(height).levels(1).sampler(F.Texture$Sampler.SAMPLER_2D).format(F.Texture$InternalFormat.SRGB8_A8).build(ctx.engine); tex.setImage(ctx.engine, 0, new F.PixelBuffer(pixels, F.PixelDataFormat.RGBA, F.PixelDataType.UBYTE)); return tex; };
  // A single scene-wide skybox/IBL is enough: the web shell hosts one Filament
  // view. The engine drives the sky through SetSkyAtmosphere, which supplies the
  // zenith/horizon/ground colours; we rebuild the skybox and the ambient IBL
  // from the same blend the native shim uses.
  let skybox = null, indirectLight = null;
  const atmosphereColor = (elev, skyR, skyG, skyB, horR, horG, horB, gndR, gndG, gndB) => {
    const clamp = v => v < 0 ? 0 : v > 1 ? 1 : v; let r, g, b;
    if (elev >= 0) { const t = Math.pow(clamp(elev), .45); r = horR + t * (skyR - horR); g = horG + t * (skyG - horG); b = horB + t * (skyB - horB); }
    else if (elev >= -0.1) { const t = (elev + 0.1) / 0.1; r = gndR + t * (horR - gndR); g = gndG + t * (horG - gndG); b = gndB + t * (horB - gndB); }
    else { r = gndR; g = gndG; b = gndB; }
    return [clamp(r), clamp(g), clamp(b)];
  };
  const setSkybox = (ctx, r, g, b, a) => {
    try {
      if (skybox) { ctx.scene.setSkybox(null); skybox.delete?.(); skybox = null; }
      skybox = Filament.Skybox.Builder().color([r, g, b, a]).build(ctx.engine);
      ctx.scene.setSkybox(skybox);
      ctx.renderer.setClearOptions({ clear: true, clearColor: [r, g, b, 1] });
      stats.skybox = (stats.skybox || 0) + 1;
    } catch { stats.skyboxFailed = (stats.skyboxFailed || 0) + 1; }
  };
  const setIndirectLight = (ctx, r, g, b, intensity) => {
    try {
      if (indirectLight) { ctx.scene.setIndirectLight(null); indirectLight.delete?.(); indirectLight = null; }
      indirectLight = Filament.IndirectLight.Builder().irradianceSh(1, new Float32Array([r, g, b])).intensity(intensity > 0 ? intensity : 15000).build(ctx.engine);
      ctx.scene.setIndirectLight(indirectLight);
    } catch { }
  };
  // A single directional sun drives the lit material and casts shadows. The
  // engine points it and scales its intensity through SetSkyAtmosphere/SetSun;
  // the initial direction only matters until the first atmosphere apply.
  const createSunLight = (ctx, dir) => {
    const F = Filament;
    const len = Math.hypot(dir[0], dir[1], dir[2]) || 1;
    const e = F.EntityManager.get().create();
    F.LightManager.Builder(F.LightManager$Type.SUN)
      .color([1, .98, .95]).intensity(100000)
      .direction([dir[0] / len, dir[1] / len, dir[2] / len])
      .sunAngularRadius(1.9).castShadows(true)
      .shadowOptions({ mapSize: 4096, shadowCascades: 4, shadowFar: 0, shadowNearHint: .5, shadowFarHint: 160, stable: true, screenSpaceContactShadows: true })
      .build(ctx.engine, e);
    ctx.scene.addEntity(e);
    ctx.sunLight = e; ctx.sunDir = dir.slice();
    return e;
  };
  // Direction (and optionally intensity) of the sun light. `scaleByElevation`
  // mirrors the native shim: a sun below the horizon fades the light out.
  const applySun = (ctx, dx, dy, dz, intensity, scaleByElevation) => {
    if (!ctx.sunLight) return;
    const len = Math.hypot(dx, dy, dz) || 1; dx /= len; dy /= len; dz /= len;
    let value = intensity;
    if (scaleByElevation) { let e = (dy + .05) / .15; e = e < 0 ? 0 : e > 1 ? 1 : e; value = intensity * e; }
    try { const lm = ctx.engine.getLightManager(), inst = lm.getInstance(ctx.sunLight); lm.setDirection(inst, [-dx, -dy, -dz]); lm.setIntensity(inst, value); } catch { }
  };
  const SHADOW_TYPES = { 0: "PCF", 1: "VSM", 2: "DPCF", 3: "PCSS" };
  const applySunShadow = ctx => {
    if (!ctx.sunLight || !ctx.sunShadow) return;
    try {
      const T = Filament.View$ShadowType, lm = ctx.engine.getLightManager(), inst = lm.getInstance(ctx.sunLight);
      lm.setShadowOptions(inst, { ...ctx.sunShadow, shadowType: T[SHADOW_TYPES[ctx.shadowFilter] || "PCF"] });
    } catch { }
  };
  const qualityFromInt = q => { const Q = Filament.View$QualityLevel; return [Q.LOW, Q.MEDIUM, Q.HIGH, Q.ULTRA][q | 0] ?? Q.MEDIUM; };
  // Minimal GLB reader: the engine ships one primitive per shape with
  // POSITION / NORMAL / TEXCOORD_0 / uint16 indices, so the web shell extracts
  // the attributes the lit material needs and rebuilds a Filament vertex buffer.
  // Primitives without a NORMAL accessor get averaged face normals.
  const GLB_COMP_SIZE = { 5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4 };
  const GLB_NUM_COMP = { SCALAR: 1, VEC2: 2, VEC3: 3, VEC4: 4 };
  const parseGlbMesh = bytes => {
    const dv = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    if (bytes.byteLength < 12 || dv.getUint32(0, true) !== 0x46546C67) return null;
    let off = 12, json = null, bin = null;
    while (off + 8 <= bytes.byteLength) {
      const clen = dv.getUint32(off, true), ctype = dv.getUint32(off + 4, true), start = off + 8;
      if (ctype === 0x4E4F534A) json = JSON.parse(new TextDecoder().decode(bytes.subarray(start, start + clen)));
      else if (ctype === 0x004E4942) bin = bytes.subarray(start, start + clen);
      off = start + clen;
    }
    if (!json || !bin) return null;
    const bdv = new DataView(bin.buffer, bin.byteOffset, bin.byteLength);
    const read = (accIdx) => {
      const acc = json.accessors[accIdx], bv = json.bufferViews[acc.bufferView];
      const cs = GLB_COMP_SIZE[acc.componentType], nc = GLB_NUM_COMP[acc.type];
      const stride = bv.byteStride || cs * nc, base = (bv.byteOffset || 0) + (acc.byteOffset || 0);
      if (acc.componentType === 5126) { const out = new Float32Array(acc.count * nc); for (let i = 0; i < acc.count; i++)for (let c = 0; c < nc; c++)out[i * nc + c] = bdv.getFloat32(base + i * stride + c * 4, true); return out; }
      if (acc.componentType === 5123) { const out = new Uint16Array(acc.count); for (let i = 0; i < acc.count; i++)out[i] = bdv.getUint16(base + i * stride, true); return out; }
      if (acc.componentType === 5125) { const out = new Uint32Array(acc.count); for (let i = 0; i < acc.count; i++)out[i] = bdv.getUint32(base + i * stride, true); return out; }
      const out = new Uint8Array(acc.count); for (let i = 0; i < acc.count; i++)out[i] = bdv.getUint8(base + i * stride); return out;
    };
    const positions = [], uvs = [], normals = [], indices = [];
    for (const mesh of (json.meshes || [])) {
      for (const p of mesh.primitives) {
        const pos = read(p.attributes.POSITION);
        const uv = p.attributes.TEXCOORD_0 != null ? read(p.attributes.TEXCOORD_0) : null;
        const nrm = p.attributes.NORMAL != null ? read(p.attributes.NORMAL) : null;
        const base = positions.length / 3, vcount = pos.length / 3;
        for (let i = 0; i < pos.length; i++)positions.push(pos[i]);
        for (let i = 0; i < vcount; i++)uvs.push(uv ? uv[i * 2] : 0, uv ? uv[i * 2 + 1] : 0);
        const primStart = indices.length;
        if (p.indices != null) { const idx = read(p.indices); for (let i = 0; i < idx.length; i++)indices.push(base + idx[i]); }
        else { for (let i = 0; i < vcount; i++)indices.push(base + i); }
        if (nrm) { for (let i = 0; i < vcount; i++)normals.push(nrm[i * 3], nrm[i * 3 + 1], nrm[i * 3 + 2]); }
        else {
          for (let i = 0; i < vcount; i++)normals.push(0, 0, 0);
          for (let i = primStart; i + 2 < indices.length; i += 3) {
            const ia = indices[i] * 3, ib = indices[i + 1] * 3, ic = indices[i + 2] * 3;
            const ux = positions[ib] - positions[ia], uy = positions[ib + 1] - positions[ia + 1], uz = positions[ib + 2] - positions[ia + 2];
            const vx = positions[ic] - positions[ia], vy = positions[ic + 1] - positions[ia + 1], vz = positions[ic + 2] - positions[ia + 2];
            const fx = uy * vz - uz * vy, fy = uz * vx - ux * vz, fz = ux * vy - uy * vx;
            for (const o of [ia, ib, ic]) { normals[o] += fx; normals[o + 1] += fy; normals[o + 2] += fz; }
          }
          for (let i = 0; i < vcount; i++) {
            const o = (base + i) * 3, len = Math.hypot(normals[o], normals[o + 1], normals[o + 2]) || 1;
            normals[o] /= len; normals[o + 1] /= len; normals[o + 2] /= len;
          }
        }
      }
    }
    if (positions.length === 0 || indices.length === 0) return null;
    return { positions: new Float32Array(positions), uvs: new Float32Array(uvs), normals: new Float32Array(normals), indices: new Uint16Array(indices) };
  };
  const filament = {
    Kine_Filament_CreateForSDLWindow: (win, w, h) => { const engine = Filament.Engine.create(filamentEl), scene = engine.createScene(), view = engine.createView(), renderer = engine.createRenderer(), swap = engine.createSwapChain(), ce = Filament.EntityManager.get().create(), camera = engine.createCamera(ce), material = engine.createMaterial(materialBytes); view.setScene(scene); view.setCamera(camera); view.setViewport([0, 0, w, h]); view.setPostProcessingEnabled(true); view.setShadowingEnabled(true); camera.setProjectionFov(60, w / h, .1, 1000, Filament.Camera$Fov.VERTICAL); camera.lookAt([8, 7, 12], [0, 0, 0], [0, 1, 0]); renderer.setClearOptions({ clear: true, clearColor: [.035, .055, .09, 1] }); const ctx = { engine, scene, view, renderer, swap, camera, material, w, h, shadowFilter: 0, sunShadow: null, renderables: engine.getRenderableManager() }; stats.filamentContexts++; createSunLight(ctx, [.5, -1, .8]); return handle(filamentContexts, ctx); },
    Kine_Filament_CreateMesh: (cid, shape) => { const ctx = filamentContexts.get(cid); if (!ctx) return 0; stats.meshes++; const { vb, ib } = uploadGeometry(ctx, shape === 2 ? sphereGeometry() : cubeGeometry()); return handle(filamentMeshes, { ctx, vb, ib, nodes: [], used: 0 }); },
    Kine_Filament_CreateMeshFromMemory: (cid, ptr, len, hint) => { const ctx = filamentContexts.get(cid); if (!ctx || !ptr || !len) return 0; try { const geo = parseGlbMesh(heap8().subarray(ptr, ptr + len)); if (!geo) return 0; stats.meshes++; const { vb, ib } = uploadGeometry(ctx, geo); return handle(filamentMeshes, { ctx, vb, ib, nodes: [], used: 0 }); } catch (e) { console.error("CreateMeshFromMemory", e); return 0; } },
    Kine_Filament_CreateMeshFromPath: () => 0,
    Kine_Filament_DrawMeshList: (cid, ptr, count) => { const ctx = filamentContexts.get(cid); if (!ctx) return; stats.drawListCalls = (stats.drawListCalls || 0) + 1; stats.drawItems = (stats.drawItems || 0) + count; const dv = heap32(), stride = 116, tm = ctx.engine.getTransformManager(), sampler = filamentSampler(); for (let n = 0; n < count; n++) { const p = ptr + n * stride, m = filamentMeshes.get(dv.getUint32(p, true)); if (!m) continue; const node = acquireNode(m); if (!node.inScene) { ctx.scene.addEntity(node.entity); node.inScene = true; } applyNodeShadowFlags(ctx, node, dv.getUint32(p + 104, true)); if (dv.getUint32(p + 4, true)) stats.texSeen = (stats.texSeen || 0) + 1; const raw = []; for (let i = 0; i < 16; i++)raw.push(dv.getFloat32(p + 8 + i * 4, true)); const matrix = [raw[0], raw[4], raw[8], raw[12], raw[1], raw[5], raw[9], raw[13], raw[2], raw[6], raw[10], raw[14], raw[3], raw[7], raw[11], raw[15]]; const inst = tm.getInstance(node.entity); tm.setTransform(inst, matrix); inst.delete(); node.material.setFloat4Parameter("baseColor", [dv.getFloat32(p + 72, true), dv.getFloat32(p + 76, true), dv.getFloat32(p + 80, true), 1]); if (dv.getInt32(p + 100, true) === 0) { node.material.setFloatParameter("roughness", dv.getFloat32(p + 84, true)); node.material.setFloatParameter("metallic", dv.getFloat32(p + 88, true)); } const uv = dv.getFloat32(p + 92, true), texEntry = filamentTextures.get(dv.getUint32(p + 4, true)); if (texEntry) { node.material.setTextureParameter("baseColorMap", texEntry, sampler); node.material.setFloatParameter("hasTexture", 1); node.material.setFloat2Parameter("uvScale", [uv > 0.0001 ? uv : 1, uv > 0.0001 ? uv : 1]); stats.texBound = (stats.texBound || 0) + 1; } else { node.material.setFloatParameter("hasTexture", 0); node.material.setFloat2Parameter("uvScale", [1, 1]); } } },
    Kine_Filament_DrawMeshListVersioned: (cid, ptr, count) => filament.Kine_Filament_DrawMeshList(cid, ptr, count),
    Kine_Filament_RenderFrame: cid => { const c = filamentContexts.get(cid); if (c) { const t = performance.now(); stats.frames++; for (const mesh of filamentMeshes.values()) { for (let i = mesh.used; i < mesh.nodes.length; i++) { const nd = mesh.nodes[i]; if (nd && nd.inScene) { c.scene.remove(nd.entity); nd.inScene = false; } } mesh.used = 0; } c.renderer.render(c.swap, c.view); c.engine.execute(); stats.renderMs = performance.now() - t; } },
    Kine_Filament_Resize: (cid, w, h) => { const c = filamentContexts.get(cid); if (c) { filamentEl.width = w; filamentEl.height = h; c.view.setViewport([0, 0, w, h]); c.camera.setProjectionFov(60, w / h, .1, 1000, Filament.Camera$Fov.VERTICAL); } },
    Kine_Filament_SetViewport: (cid, x, y, w, h) => { const c = filamentContexts.get(cid); if (c) c.view.setViewport([x, height() - y - h, w, h]); const s = [...surfaces.values()][0]; if (s) { s.canvas.save(); s.canvas.clipRect(rect(x, y, w, h), CanvasKit.ClipOp.Intersect, false); s.canvas.clear(CanvasKit.TRANSPARENT); s.canvas.restore(); s.surface.flush(); } },
    Kine_Filament_SetCameraPerspective: (cid, fov, aspect, near, far) => filamentContexts.get(cid)?.camera.setProjectionFov(fov, aspect, near, far, Filament.Camera$Fov.VERTICAL),
    Kine_Filament_SetCameraLookAt: (cid, ex, ey, ez, tx, ty, tz, ux, uy, uz) => filamentContexts.get(cid)?.camera.lookAt([ex, ey, ez], [tx, ty, tz], [ux, uy, uz]),
    Kine_Filament_CreateSky: (cid, r, g, b, a) => { const c = filamentContexts.get(cid); if (c) setSkybox(c, r, g, b, a > 0 ? a : 1); },
    Kine_Filament_SetSkyAtmosphere: (cid, sunX, sunY, sunZ, skyR, skyG, skyB, horR, horG, horB, gndR, gndG, gndB, sunIntensity) => { const c = filamentContexts.get(cid); if (!c) return 1; const [r, g, b] = atmosphereColor(sunY, skyR, skyG, skyB, horR, horG, horB, gndR, gndG, gndB); setSkybox(c, r, g, b, 1); setIndirectLight(c, r, g, b, 15000); applySun(c, sunX, sunY, sunZ, sunIntensity, true); return 1; },
    Kine_Filament_SetSun: (cid, sunX, sunY, sunZ, sunIntensity) => { const c = filamentContexts.get(cid); if (c) applySun(c, sunX, sunY, sunZ, sunIntensity, false); return 1; },
    Kine_Filament_SetShadowOptions: (cid, enabled, filter) => { const c = filamentContexts.get(cid); if (!c) return 1; try { c.view.setShadowingEnabled(!!enabled); } catch { } c.shadowFilter = filter | 0; applySunShadow(c); return 1; },
    Kine_Filament_SetSunShadowOptions: (cid, mapSize, cascades, shadowFar, shadowNearHint, shadowFarHint, stable, contactShadows) => { const c = filamentContexts.get(cid); if (!c) return 1; let p = 8; const want = Math.max(mapSize | 0, 8); while (p < want) p <<= 1; c.sunShadow = { mapSize: Math.min(p, 8192), shadowCascades: Math.max(1, Math.min(cascades | 0, 4)), shadowFar: Math.max(shadowFar, 0), shadowNearHint: Math.max(shadowNearHint, .001), shadowFarHint: Math.max(shadowFarHint, shadowNearHint + .001), stable: !!stable, lispsm: !stable, constantBias: .004, normalBias: 1.25, polygonOffsetConstant: .75, polygonOffsetSlope: 2.5, screenSpaceContactShadows: !!contactShadows, stepCount: 16 }; applySunShadow(c); return 1; },
    Kine_Filament_SetPostProcessing: (cid, enabled) => { const c = filamentContexts.get(cid); if (c) { try { c.view.setPostProcessingEnabled(!!enabled); } catch { } } return 1; },
    Kine_Filament_SetBloom: (cid, enabled, strength, resolution, levels, threshold, lensFlare) => { const c = filamentContexts.get(cid); if (c) { try { c.view.setBloomOptions({ enabled: !!enabled, strength: Math.min(Math.max(strength, 0), 1), resolution: Math.min(Math.max(resolution | 0, 8), 4096), levels: Math.min(Math.max(levels | 0, 1), 11), threshold: !!threshold, lensFlare: !!lensFlare }); } catch { } } return 1; },
    Kine_Filament_SetAmbientOcclusion: (cid, enabled, radius, power, intensity, quality, aoType) => { const c = filamentContexts.get(cid); if (c) { try { const AO = Filament.View$AmbientOcclusionOptions$AmbientOcclusionType; c.view.setAmbientOcclusionOptions({ enabled: !!enabled, radius: Math.min(Math.max(radius, 0), 10), power: Math.max(power, .001), intensity: Math.max(intensity, 0), quality: qualityFromInt(quality), aoType: (aoType | 0) === 1 ? AO.GTAO : AO.SAO }); } catch { } } return 1; },
    Kine_Filament_SetAntiAliasing: (cid, fxaa, taa, msaa, sampleCount) => { const c = filamentContexts.get(cid); if (c) { try { const AA = Filament.View$AntiAliasing; c.view.setAntiAliasing(fxaa ? AA.FXAA : AA.NONE); c.view.setTemporalAntiAliasingOptions({ enabled: !!taa }); c.view.setMultiSampleAntiAliasingOptions({ enabled: !!msaa, sampleCount: Math.min(Math.max(sampleCount | 0, 1), 8) }); } catch { } } return 1; },
    Kine_Filament_SetDynamicResolution: (cid, enabled, minScale, maxScale, quality, sharpness) => { const c = filamentContexts.get(cid); if (c) { try { const lo = Math.min(Math.max(minScale, .1), 1), hi = Math.min(Math.max(maxScale, lo), 2); c.view.setDynamicResolutionOptions({ enabled: !!enabled, minScale: [lo, lo], maxScale: [hi, hi], sharpness: Math.min(Math.max(sharpness, 0), 1), quality: qualityFromInt(quality) }); } catch { } } return 1; },
    Kine_Filament_SetDepthOfField: (cid, enabled, cocScale, cocAspectRatio, maxApertureDiameter, maxForegroundCOC, maxBackgroundCOC) => { const c = filamentContexts.get(cid); if (c) { try { c.view.setDepthOfFieldOptions({ enabled: !!enabled, cocScale: Math.max(cocScale, 0), cocAspectRatio: Math.max(cocAspectRatio, .001), maxApertureDiameter: Math.max(maxApertureDiameter, 0), maxForegroundCOC: Math.min(Math.max(maxForegroundCOC | 0, 0), 32), maxBackgroundCOC: Math.min(Math.max(maxBackgroundCOC | 0, 0), 32) }); } catch { } } return 1; },
    Kine_Filament_SetFocusDistance: (cid, distance) => { const c = filamentContexts.get(cid); if (c) { try { c.camera.setFocusDistance(Math.max(distance, .001)); } catch { } } return 1; },
    Kine_Filament_SetVignette: (cid, enabled, midPoint, roundness, feather, r, g, b, a) => { const c = filamentContexts.get(cid); if (c) { try { c.view.setVignetteOptions({ enabled: !!enabled, midPoint: Math.min(Math.max(midPoint, 0), 1), roundness: Math.min(Math.max(roundness, 0), 1), feather: Math.min(Math.max(feather, 0), 1), color: [Math.max(r, 0), Math.max(g, 0), Math.max(b, 0), Math.min(Math.max(a, 0), 1)] }); } catch { } } return 1; },
    Kine_Filament_SetScreenSpaceReflections: (cid, enabled, thickness, bias, maxDistance, stride) => { const c = filamentContexts.get(cid); if (c) { try { c.view.setScreenSpaceReflectionsOptions({ enabled: !!enabled, thickness: Math.max(thickness, 0), bias: Math.max(bias, 0), maxDistance: Math.max(maxDistance, 0), stride: Math.max(stride, .001) }); } catch { } } return 1; },
    Kine_Filament_SetColorGrading: (cid, exposure, contrast, saturation, vibrance, temperature, tint) => { const c = filamentContexts.get(cid); if (c) { try { if (c.colorGrading) { c.view.setColorGrading(null); c.colorGrading.delete?.(); c.colorGrading = null; } const cg = Filament.ColorGrading.Builder().exposure(exposure).contrast(Math.max(contrast, .001)).saturation(Math.max(saturation, 0)).vibrance(Math.max(vibrance, 0)).whiteBalance(temperature, tint).build(c.engine); c.colorGrading = cg; c.view.setColorGrading(cg); } catch { } } return 1; },
    Kine_Filament_ClearColorGrading: (cid) => { const c = filamentContexts.get(cid); if (c && c.colorGrading) { try { c.view.setColorGrading(null); c.colorGrading.delete?.(); } catch { } c.colorGrading = null; } return 1; },
    Kine_Filament_SetRenderQuality: (cid, hdrQuality) => { const c = filamentContexts.get(cid); if (c) { try { c.view.setRenderQuality({ hdrColorBuffer: qualityFromInt(hdrQuality) }); } catch { } } return 1; },
    Kine_Filament_SetDithering: (cid, enabled) => { const c = filamentContexts.get(cid); if (c) { try { const D = Filament.View$Dithering; c.view.setDithering(enabled ? D.TEMPORAL : D.NONE); } catch { } } return 1; },
    Kine_Filament_SetSunRays: (cid, enabled, distance, cutOffDistance, maximumOpacity, height, heightFalloff, density, inScatteringStart, inScatteringSize, r, g, b, fogColorFromIbl) => { const c = filamentContexts.get(cid); if (c) { try { c.view.setFogOptions({ enabled: !!enabled, distance: Math.max(distance, 0), cutOffDistance: cutOffDistance > 0 ? Math.max(cutOffDistance, distance) : Infinity, maximumOpacity: Math.min(Math.max(maximumOpacity, 0), 1), height: height, heightFalloff: Math.max(heightFalloff, 0), density: Math.max(density, 0), inScatteringStart: Math.max(inScatteringStart, 0), inScatteringSize: enabled ? Math.max(inScatteringSize, .001) : -1, color: [Math.max(r, 0), Math.max(g, 0), Math.max(b, 0)], fogColorFromIbl: !!fogColorFromIbl }); } catch { } } return 1; },
    Kine_Filament_DestroyMesh: (cid, id) => { const m = filamentMeshes.get(id); if (m) { for (const node of m.nodes) { if (node) { if (node.inScene) m.ctx.scene.remove(node.entity); m.ctx.engine.destroyEntity(node.entity); } } filamentMeshes.delete(id); } return 1; },
    Kine_Filament_CreateTexFromPixels: (cid, w, h, rowBytes, ptr) => { const c = filamentContexts.get(cid); if (!c || !ptr || w <= 0 || h <= 0) return 0; const tex = buildTexture(c, w, h, heap8().slice(ptr, ptr + h * rowBytes)); stats.textures = (stats.textures || 0) + 1; return handle(filamentTextures, tex); },
    Kine_Filament_UpdateTexFromPixels: (cid, id, w, h, rowBytes, ptr) => { const tex = filamentTextures.get(id), c = filamentContexts.get(cid); if (!tex || !c || !ptr) return 0; tex.setImage(c.engine, 0, new Filament.PixelBuffer(heap8().slice(ptr, ptr + h * rowBytes), Filament.PixelDataFormat.RGBA, Filament.PixelDataType.UBYTE)); return 1; },
    Kine_Filament_CreatePbrTexFromPixels: (cid, w, h, rowBytes, ptr) => { const c = filamentContexts.get(cid); if (!c || !ptr || w <= 0 || h <= 0) return 0; const tex = buildTexture(c, w, h, heap8().slice(ptr, ptr + h * rowBytes)); stats.textures = (stats.textures || 0) + 1; return handle(filamentTextures, tex); },
    Kine_Filament_GetMeshTexture: () => 0, Kine_Filament_CreateTex: () => 0,
    Kine_Filament_DestroyTex: (cid, id) => { const tex = filamentTextures.get(id); if (tex) tex.delete?.(); filamentTextures.delete(id); return 1; },
    Kine_Filament_CreateLightEx: () => handle(filamentLights, {}), Kine_Filament_RemoveLight: id => { filamentLights.delete(id); return 1; },
    Kine_Filament_SetPositionLight: () => 1, Kine_Filament_SetColorLight: () => 1, Kine_Filament_SetIntensityLight: () => 1, Kine_Filament_SetFalloffLight: () => 1, Kine_Filament_SetEnabledLight: () => 1, Kine_Filament_SetDirectionLight: () => 1, Kine_Filament_SetConeLight: () => 1, Kine_Filament_SetShadowLight: () => 1
  };

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

  const loadFilament = () => new Promise((resolve, reject) => { try { Filament.init([], resolve); } catch (e) { reject(e); } });
  async function start() {
    report("Loading Skia CanvasKit…");
    CanvasKit = await CanvasKitInit({ locateFile: f => `canvaskit/${f}` });
    defaultTypeface = CanvasKit.Typeface.MakeFreeTypeFaceFromData(await (await fetch("fonts/Roboto.ttf")).arrayBuffer());
    report("Loading Filament WebGL…");
    await loadFilament();
    materialBytes = new Uint8Array(await (await fetch("filament/kine_web.filamat")).arrayBuffer());
    await phase("starting-odin-luau-jolt");
    const memoryInterface = new odin.WasmMemoryInterface();
    let imports = odin.setupDefaultImports(memoryInterface, null, memoryInterface.memory);
    imports = { ...imports, kinemium_platform: withStubs(platform), kinemium_skia: withStubs(skia), kinemium_filament: withStubs(filament), kinemium_audio: withStubs(audio), kinemium_storage: withStubs(storage), kinemium_net: withStubs(net), env, wasi_snapshot_preview1: wasi };
    const result = await WebAssembly.instantiateStreaming(fetch("kinemium_engine.wasm"), imports);
    wasm = result.instance.exports; memory = wasm.memory; table = wasm.__indirect_function_table;
    memoryInterface.setExports(wasm); memoryInterface.setMemory(memory);
    const context = wasm.default_context_ptr();
    await phase("odin-context-ready");
    wasm._start();
    await phase("luau-vm-ready");
    await phase("installing-engine-environment");
    await new Promise(resolve => requestAnimationFrame(resolve));
    wasm.initialize_environment(context);
    await phase("engine-environment-ready");
    await phase("running-studio-luau-modules");
    await new Promise(resolve => requestAnimationFrame(resolve));
    wasm.initialize_scripts(context);
    await phase("studio-luau-modules-ready");
    await phase("creating-skia-and-filament");
    await new Promise(resolve => requestAnimationFrame(resolve));
    wasm.initialize_renderer(context);
    await phase("engine-ready");
    runtimeEl.textContent = "Running in Firefox"; document.documentElement.dataset.engineReady = "true";
    let then = performance.now();
    const frame = now => { try { stats.frameCalls = (stats.frameCalls || 0) + 1; const t0 = performance.now(); const keep = wasm.step(Math.min((now - then) / 1000, .1), context); stats.stepMs = performance.now() - t0; if (now - then > 0) stats.fps = Math.round(1000 / (now - then)); then = now; if (keep) requestAnimationFrame(frame); else wasm._end(); } catch (error) { console.error(error); document.documentElement.dataset.engineError = "true"; runtimeEl.textContent = "Frame failed"; statusEl.textContent = error.message; } };
    requestAnimationFrame(frame);
  }
  start().catch(error => { console.error(error); runtimeEl.textContent = "Startup failed"; statusEl.textContent = error.message; statusEl.style.color = "#ff7088"; document.documentElement.dataset.engineError = "true"; });
})();
