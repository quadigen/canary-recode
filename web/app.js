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
  const stats = window.__kinemiumStats = {surfaces:0,draws2d:0,filamentContexts:0,meshes:0,frames:0};

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
    KeyA:4,KeyB:5,KeyC:6,KeyD:7,KeyE:8,KeyF:9,KeyG:10,KeyH:11,KeyI:12,KeyJ:13,KeyK:14,KeyL:15,KeyM:16,
    KeyN:17,KeyO:18,KeyP:19,KeyQ:20,KeyR:21,KeyS:22,KeyT:23,KeyU:24,KeyV:25,KeyW:26,KeyX:27,KeyY:28,KeyZ:29,
    Digit1:30,Digit2:31,Digit3:32,Digit4:33,Digit5:34,Digit6:35,Digit7:36,Digit8:37,Digit9:38,Digit0:39,
    Enter:40,Escape:41,Backspace:42,Tab:43,Space:44,Minus:45,Equal:46,BracketLeft:47,BracketRight:48,Backslash:49,
    Semicolon:51,Quote:52,Backquote:53,Comma:54,Period:55,Slash:56,CapsLock:57,F1:58,F2:59,F3:60,F4:61,F5:62,F6:63,
    F7:64,F8:65,F9:66,F10:67,F11:68,F12:69,Insert:73,Home:74,PageUp:75,Delete:76,End:77,PageDown:78,
    ArrowRight:79,ArrowLeft:80,ArrowDown:81,ArrowUp:82,ControlLeft:224,ShiftLeft:225,AltLeft:226,MetaLeft:227,
    ControlRight:228,ShiftRight:229,AltRight:230,MetaRight:231
  };
  const mods = e => (e.shiftKey?1:0)|(e.ctrlKey?64:0)|(e.altKey?256:0)|(e.metaKey?1024:0);
  const point = e => ({ x:e.clientX*dpr(), y:e.clientY*dpr() });
  addEventListener("keydown", e => { const scancode=scanCodes[e.code]||0; keys.add(scancode); events.push({type:8,scancode,mods:mods(e),repeat:e.repeat}); });
  addEventListener("keyup", e => { const scancode=scanCodes[e.code]||0; keys.delete(scancode); events.push({type:9,scancode,mods:mods(e)}); });
  addEventListener("keypress", e => { if (e.key.length === 1) events.push({type:10,text:e.key}); });
  addEventListener("mousemove", e => { const p=point(e); mouse.dx=e.movementX*dpr(); mouse.dy=e.movementY*dpr(); mouse.x=p.x; mouse.y=p.y; events.push({type:11,...p,dx:mouse.dx,dy:mouse.dy}); });
  addEventListener("mousedown", e => { const p=point(e),button=e.button===0?1:e.button===1?2:3; mouse.buttons|=1<<(button-1); events.push({type:12,...p,button,clicks:e.detail}); });
  addEventListener("mouseup", e => { const p=point(e),button=e.button===0?1:e.button===1?2:3; mouse.buttons&=~(1<<(button-1)); events.push({type:13,...p,button,clicks:e.detail}); });
  addEventListener("wheel", e => { const p=point(e); events.push({type:14,...p,dx:-Math.sign(e.deltaX),dy:-Math.sign(e.deltaY)}); e.preventDefault(); }, {passive:false});
  addEventListener("focus", () => { mouse.focused=true; events.push({type:6}); });
  addEventListener("blur", () => { mouse.focused=false; keys.clear(); events.push({type:5}); });
  addEventListener("resize", () => events.push({type:7}));

  const platform = {
    host_width:width, host_height:height, host_dpi_scale:dpr,
    host_mouse_x:()=>mouse.x, host_mouse_y:()=>mouse.y,
    host_mouse_dx:()=>{const v=mouse.dx;mouse.dx=0;return v;}, host_mouse_dy:()=>{const v=mouse.dy;mouse.dy=0;return v;},
    host_mouse_buttons:()=>mouse.buttons, host_modifiers:()=>0, host_focused:()=>mouse.focused?1:0,
    host_key_down:sc=>keys.has(sc)?1:0,
    host_poll_event:()=>{ currentEvent=events.shift()||{}; return currentEvent.type||0; },
    host_event_scancode:()=>currentEvent.scancode||0, host_event_modifiers:()=>currentEvent.mods||0,
    host_event_repeat:()=>currentEvent.repeat?1:0, host_event_button:()=>currentEvent.button||0,
    host_event_clicks:()=>currentEvent.clicks||0, host_event_x:()=>currentEvent.x||0, host_event_y:()=>currentEvent.y||0,
    host_event_dx:()=>currentEvent.dx||0, host_event_dy:()=>currentEvent.dy||0,
    host_copy_event_text:(ptr,cap)=>copyString(currentEvent.text||"",ptr,cap),
    host_system_theme:()=>matchMedia("(prefers-color-scheme: dark)").matches?2:1,
    host_set_relative:on=>{ if(on) filamentEl.requestPointerLock?.(); else document.exitPointerLock?.(); },
    host_show_cursor:visible=>document.body.style.cursor=visible?"default":"none",
    host_warp_mouse:()=>{}, host_text_input:()=>{},
    host_set_cursor:kind=>{ document.body.style.cursor=["default","text","wait","crosshair","progress","nwse-resize","nesw-resize","ew-resize","ns-resize","move","not-allowed","pointer"][kind]||"default"; },
    host_set_clipboard:ptr=>{ navigator.clipboard?.writeText(cstr(ptr)); return 1; },
    host_copy_clipboard:()=>0
    ,host_debug_phase:()=>{}
  };

  const surfaces = new Map(), images = new Map(), shaders = new Map();
  let nextHandle = 1;
  const handle = (map,value) => { const id=nextHandle++; map.set(id,value); return id; };
  const paint = (r,g,b,a,stroke=0) => { const p=new CanvasKit.Paint(); p.setAntiAlias(true); p.setColor(CanvasKit.Color(r,g,b,a)); if(stroke>0){p.setStyle(CanvasKit.PaintStyle.Stroke);p.setStrokeWidth(stroke);} return p; };
  const withPaint = (rgba,stroke,fn) => { const p=paint(...rgba,stroke); try{fn(p);}finally{p.delete();} };
  const surf = id => surfaces.get(id);
  const color = (r,g,b,a) => [r,g,b,a/255];
  const rect = (x,y,w,h) => CanvasKit.XYWHRect(x,y,w,h);
  const roundRect = (x,y,w,h,rx,ry) => CanvasKit.RRectXY(rect(x,y,w,h),rx,ry);
  const skia = {
    Kine_Skia_Surface_Create:(w,h)=>{ const el=(surfaceSerial++%2===0)?baseEl:overlayEl; el.width=w;el.height=h; const s=CanvasKit.MakeSWCanvasSurface(el); stats.surfaces++; return handle(surfaces,{surface:s,canvas:s.getCanvas(),el,w,h}); },
    Kine_Skia_Surface_Destroy:id=>{const s=surf(id);if(s){s.surface.delete();surfaces.delete(id);}},
    Kine_Skia_Surface_GetWidth:id=>surf(id)?.w||0, Kine_Skia_Surface_GetHeight:id=>surf(id)?.h||0,
    Kine_Skia_Surface_GetRowBytes:id=>(surf(id)?.w||0)*4, Kine_Skia_Surface_GetPixels:()=>0,
    Kine_Skia_Surface_Flush:id=>surf(id)?.surface.flush(),
    Kine_Skia_Surface_Clear:(id,r,g,b,a)=>surf(id)?.canvas.clear(CanvasKit.Color(r,g,b,a)),
    Kine_Skia_Surface_DrawRect:(id,x,y,w,h,r,g,b,a,sw)=>{stats.draws2d++;withPaint(color(r,g,b,a),sw,p=>surf(id)?.canvas.drawRect(rect(x,y,w,h),p));},
    Kine_Skia_Surface_DrawRoundRect:(id,x,y,w,h,rx,ry,r,g,b,a,sw)=>withPaint(color(r,g,b,a),sw,p=>surf(id)?.canvas.drawRRect(roundRect(x,y,w,h,rx,ry),p)),
    Kine_Skia_Surface_DrawRotatedRect:(id,cx,cy,w,h,degrees,r,g,b,a,sw)=>{const c=surf(id)?.canvas;if(!c)return;c.save();c.rotate(degrees,cx,cy);withPaint(color(r,g,b,a),sw,p=>c.drawRect(rect(cx-w/2,cy-h/2,w,h),p));c.restore();},
    Kine_Skia_Surface_DrawCircle:(id,cx,cy,rad,r,g,b,a,sw)=>withPaint(color(r,g,b,a),sw,p=>surf(id)?.canvas.drawCircle(cx,cy,rad,p)),
    Kine_Skia_Surface_DrawOval:(id,x,y,w,h,r,g,b,a,sw)=>withPaint(color(r,g,b,a),sw,p=>surf(id)?.canvas.drawOval(rect(x,y,w,h),p)),
    Kine_Skia_Surface_DrawLine:(id,x0,y0,x1,y1,sw,r,g,b,a)=>withPaint(color(r,g,b,a),Math.max(sw,.01),p=>surf(id)?.canvas.drawLine(x0,y0,x1,y1,p)),
    Kine_Skia_Surface_DrawArc:(id,x,y,w,h,start,sweep,useCenter,r,g,b,a,sw)=>withPaint(color(r,g,b,a),sw,p=>surf(id)?.canvas.drawArc(rect(x,y,w,h),start,sweep,!!useCenter,p)),
    Kine_Skia_Surface_DrawPolygon:(id,ptr,count,closed,r,g,b,a,sw)=>{const c=surf(id)?.canvas;if(!c||count<2)return;const v=new Float32Array(memory.buffer,ptr,count*2),path=new CanvasKit.Path();path.moveTo(v[0],v[1]);for(let i=1;i<count;i++)path.lineTo(v[i*2],v[i*2+1]);if(closed)path.close();withPaint(color(r,g,b,a),sw,p=>c.drawPath(path,p));path.delete();},
    Kine_Skia_Surface_Save:id=>surf(id)?.canvas.save(), Kine_Skia_Surface_Restore:id=>surf(id)?.canvas.restore(),
    Kine_Skia_Surface_Translate:(id,x,y)=>surf(id)?.canvas.translate(x,y), Kine_Skia_Surface_Rotate:(id,d)=>surf(id)?.canvas.rotate(d,0,0), Kine_Skia_Surface_Scale:(id,x,y)=>surf(id)?.canvas.scale(x,y),
    Kine_Skia_Surface_ClipRect:(id,x,y,w,h)=>surf(id)?.canvas.clipRect(rect(x,y,w,h),CanvasKit.ClipOp.Intersect,true),
    Kine_Skia_Surface_ClipRoundRect:(id,x,y,w,h,rx,ry)=>surf(id)?.canvas.clipRRect(roundRect(x,y,w,h,rx,ry),CanvasKit.ClipOp.Intersect,true),
    Kine_Skia_Surface_ClipSquircle:(id,x,y,w,h,rad)=>surf(id)?.canvas.clipRRect(roundRect(x,y,w,h,rad,rad),CanvasKit.ClipOp.Intersect,true),
    Kine_Skia_Surface_DrawSquircle:(id,x,y,w,h,rad,exp,r,g,b,a,sw)=>skia.Kine_Skia_Surface_DrawRoundRect(id,x,y,w,h,rad,rad,r,g,b,a,sw),
    Kine_Skia_Surface_DrawUIShadow:(id,x,y,w,h,rad,exp,ox,oy,blur,spread,r,g,b,a)=>{const p=paint(r,g,b,a/255);p.setMaskFilter(CanvasKit.MaskFilter.MakeBlur(CanvasKit.BlurStyle.Normal,blur,true));surf(id)?.canvas.drawRRect(roundRect(x+ox-spread,y+oy-spread,w+spread*2,h+spread*2,rad,rad),p);p.delete();},
    Kine_Skia_Surface_DrawBackdropBlurRect:(id,x,y,w,h,rx,ry,blur,alpha,r,g,b,a)=>skia.Kine_Skia_Surface_DrawRoundRect(id,x,y,w,h,rx,ry,r,g,b,Math.round(a*alpha/255),0),
    Kine_Skia_Surface_DrawBackdropBlurSquircle:(id,x,y,w,h,rad,exp,blur,alpha,r,g,b,a)=>skia.Kine_Skia_Surface_DrawRoundRect(id,x,y,w,h,rad,rad,r,g,b,Math.round(a*alpha/255),0),
    Kine_Skia_Surface_DrawText:(id,text,x,y,size,font,r,g,b,a)=>{const c=surf(id)?.canvas;if(!c)return;const f=new CanvasKit.Font(defaultTypeface,size);withPaint(color(r,g,b,a),0,p=>c.drawText(cstr(text),x,y,p,f));f.delete();},
    Kine_Skia_Surface_DrawTextShadow:(id,text,x,y,size,font,ox,oy,blur,spread,r,g,b,a)=>skia.Kine_Skia_Surface_DrawText(id,text,x+ox,y+oy,size,font,r,g,b,a),
    Kine_Skia_Surface_MeasureText:(text,size)=>{const f=new CanvasKit.Font(defaultTypeface,size),m=f.measureText(cstr(text));f.delete();return m;},
    Kine_Skia_Surface_GetFontAscent:size=>-size*.8, Kine_Skia_Surface_GetFontLineHeight:size=>size*1.2,
    Kine_Skia_Image_LoadFromFile:()=>0,
    Kine_Skia_Image_LoadFromMemory:(ptr,size)=>{const img=CanvasKit.MakeImageFromEncoded(heap8().slice(ptr,ptr+size));return img?handle(images,img):0;},
    Kine_Skia_Image_Destroy:id=>{images.get(id)?.delete();images.delete(id);}, Kine_Skia_Image_GetWidth:id=>images.get(id)?.width()||0, Kine_Skia_Image_GetHeight:id=>images.get(id)?.height()||0,
    Kine_Skia_Surface_DrawImage:(id,img,x,y)=>{const i=images.get(img);if(i)surf(id)?.canvas.drawImage(i,x,y);},
    Kine_Skia_Surface_DrawImageSized:(id,img,x,y,w,h)=>{const i=images.get(img);if(i)surf(id)?.canvas.drawImageRect(i,rect(x,y,w,h));},
    Kine_Skia_Surface_DrawImageRect:(id,img,sx,sy,sw,sh,dx,dy,dw,dh)=>{const i=images.get(img);if(i)surf(id)?.canvas.drawImageRectOptions(i,rect(sx,sy,sw,sh),rect(dx,dy,dw,dh),CanvasKit.FilterMode.Linear,CanvasKit.MipmapMode.None);},
    Kine_Skia_Surface_DrawImageOutlineSized:(id,img,x,y,w,h,t,r,g,b,a)=>skia.Kine_Skia_Surface_DrawRoundRect(id,x,y,w,h,0,0,r,g,b,a,t),
    Kine_Skia_Surface_DrawImageShadow:(id,img,x,y,w,h,ox,oy,blur,spread,r,g,b,a)=>{
      const i=images.get(img),c=surf(id)?.canvas;if(!i||!c)return;
      const dx=x+ox-spread,dy=y+oy-spread,dw=w+spread*2,dh=h+spread*2;
      const pad=Math.max(blur,1),bounds=rect(dx-pad,dy-pad,dw+pad*2,dh+pad*2);
      const src=rect(0,0,i.width(),i.height()),dst=rect(dx,dy,dw,dh);
      const layer=new CanvasKit.Paint();
      c.save();
      c.clipRect(bounds,CanvasKit.ClipOp.Intersect,false);
      c.saveLayer(bounds,layer);
      const mp=paint(r,g,b,a/255);
      mp.setMaskFilter(CanvasKit.MaskFilter.MakeBlur(CanvasKit.BlurStyle.Normal,blur,true));
      c.drawImageRectOptions(i,src,dst,CanvasKit.FilterMode.Linear,CanvasKit.MipmapMode.None,mp);
      const tp=paint(r,g,b,a/255);
      tp.setBlendMode(CanvasKit.BlendMode.SrcIn);
      c.drawRect(bounds,tp);
      c.restore();
      c.restore();
      layer.delete();mp.delete();tp.delete();
    },
    Kine_Skia_Surface_DrawPixels:()=>{}, Kine_Skia_Surface_GetPixel:(id,x,y,pr,pg,pb,pa)=>{const data=surf(id)?.surface.readPixels(x,y,{width:1,height:1});if(data){const h=heap8();h[pr]=data[0];h[pg]=data[1];h[pb]=data[2];h[pa]=data[3];}},
    Kine_Skia_RuntimeShader_Create:src=>handle(shaders,{source:cstr(src)}), Kine_Skia_RuntimeShader_Destroy:id=>shaders.delete(id), Kine_Skia_RuntimeShader_SetUniform:()=>1,
    Kine_Skia_RuntimeShader_GetLastError:()=>0, Kine_Skia_Surface_DrawRuntimeShaderRect:()=>{}
  };

  const filamentContexts=new Map(), filamentMeshes=new Map(), filamentLights=new Map();
  let materialBytes=null;
  const cubeGeometry=()=>({positions:new Float32Array([-1,-1,-1,1,-1,-1,1,1,-1,-1,1,-1,-1,-1,1,1,-1,1,1,1,1,-1,1,1]),indices:new Uint16Array([0,1,2,0,2,3,4,6,5,4,7,6,0,4,5,0,5,1,3,2,6,3,6,7,1,5,6,1,6,2,0,3,7,0,7,4])});
  const sphereGeometry=()=>{const rings=16,segments=24,positions=[],indices=[];for(let y=0;y<=rings;y++){const v=y/rings,phi=v*Math.PI;for(let x=0;x<=segments;x++){const u=x/segments,theta=u*Math.PI*2;positions.push(Math.sin(phi)*Math.cos(theta),Math.cos(phi),Math.sin(phi)*Math.sin(theta));}}for(let y=0;y<rings;y++){for(let x=0;x<segments;x++){const a=y*(segments+1)+x,b=a+segments+1;indices.push(a,b,a+1,b,b+1,a+1);}}return {positions:new Float32Array(positions),indices:new Uint16Array(indices)};};
  const buildEntity=(ctx,geo)=>{const F=Filament,e=F.EntityManager.get().create();const vb=F.VertexBuffer.Builder().vertexCount(geo.positions.length/3).bufferCount(1).attribute(F.VertexAttribute.POSITION,0,F.VertexBuffer$AttributeType.FLOAT3,0,12).build(ctx.engine);vb.setBufferAt(ctx.engine,0,geo.positions);const ib=F.IndexBuffer.Builder().indexCount(geo.indices.length).bufferType(F.IndexBuffer$IndexType.USHORT).build(ctx.engine);ib.setBuffer(ctx.engine,geo.indices);const mi=ctx.material.createInstance();mi.setFloat4Parameter("baseColor",[.55,.65,.82,1]);F.RenderableManager.Builder(1).boundingBox({center:[0,0,0],halfExtent:[1,1,1]}).material(0,mi).geometry(0,F.RenderableManager$PrimitiveType.TRIANGLES,vb,ib).build(ctx.engine,e);ctx.scene.addEntity(e);return {entity:e,vb,ib,material:mi};};
  const filament = {
    Kine_Filament_CreateForSDLWindow:(win,w,h)=>{const engine=Filament.Engine.create(filamentEl),scene=engine.createScene(),view=engine.createView(),renderer=engine.createRenderer(),swap=engine.createSwapChain(),ce=Filament.EntityManager.get().create(),camera=engine.createCamera(ce),material=engine.createMaterial(materialBytes);view.setScene(scene);view.setCamera(camera);view.setViewport([0,0,w,h]);view.setPostProcessingEnabled(true);camera.setProjectionFov(60,w/h,.1,1000,Filament.Camera$Fov.VERTICAL);camera.lookAt([8,7,12],[0,0,0],[0,1,0]);renderer.setClearOptions({clear:true,clearColor:[.035,.055,.09,1]});const ctx={engine,scene,view,renderer,swap,camera,material,w,h};stats.filamentContexts++;return handle(filamentContexts,ctx);},
    Kine_Filament_CreateMesh:(cid,shape)=>{const ctx=filamentContexts.get(cid);if(!ctx)return 0;stats.meshes++;return handle(filamentMeshes,{ctx,...buildEntity(ctx,shape===2?sphereGeometry():cubeGeometry())});},
    Kine_Filament_DrawMeshList:(cid,ptr,count)=>{const ctx=filamentContexts.get(cid);if(!ctx)return;const dv=heap32(),stride=116,tm=ctx.engine.getTransformManager();for(let n=0;n<count;n++){const p=ptr+n*stride,m=filamentMeshes.get(dv.getUint32(p,true));if(!m)continue;const matrix=[];for(let i=0;i<16;i++)matrix.push(dv.getFloat32(p+8+i*4,true));const inst=tm.getInstance(m.entity);tm.setTransform(inst,matrix);inst.delete();m.material.setFloat4Parameter("baseColor",[dv.getFloat32(p+72,true),dv.getFloat32(p+76,true),dv.getFloat32(p+80,true),1]);}},
    Kine_Filament_RenderFrame:cid=>{const c=filamentContexts.get(cid);if(c){stats.frames++;c.renderer.render(c.swap,c.view);c.engine.execute();}},
    Kine_Filament_Resize:(cid,w,h)=>{const c=filamentContexts.get(cid);if(c){filamentEl.width=w;filamentEl.height=h;c.view.setViewport([0,0,w,h]);c.camera.setProjectionFov(60,w/h,.1,1000,Filament.Camera$Fov.VERTICAL);}},
    Kine_Filament_SetViewport:(cid,x,y,w,h)=>{const c=filamentContexts.get(cid);if(c)c.view.setViewport([x,height()-y-h,w,h]);const s=[...surfaces.values()][0];if(s){s.canvas.save();s.canvas.clipRect(rect(x,y,w,h),CanvasKit.ClipOp.Intersect,false);s.canvas.clear(CanvasKit.TRANSPARENT);s.canvas.restore();s.surface.flush();}},
    Kine_Filament_SetCameraPerspective:(cid,fov,aspect,near,far)=>filamentContexts.get(cid)?.camera.setProjectionFov(fov,aspect,near,far,Filament.Camera$Fov.VERTICAL),
    Kine_Filament_SetCameraLookAt:(cid,ex,ey,ez,tx,ty,tz,ux,uy,uz)=>filamentContexts.get(cid)?.camera.lookAt([ex,ey,ez],[tx,ty,tz],[ux,uy,uz]),
    Kine_Filament_SetSkyAtmosphere:(cid,r,g,b)=>{const c=filamentContexts.get(cid);if(c)c.renderer.setClearOptions({clear:true,clearColor:[r,g,b,1]});return 1;},
    Kine_Filament_DestroyMesh:(cid,id)=>{const m=filamentMeshes.get(id);if(m){m.ctx.scene.remove(m.entity);m.ctx.engine.destroyEntity(m.entity);filamentMeshes.delete(id);}return 1;},
    Kine_Filament_CreatePbrTexFromPixels:()=>0,Kine_Filament_DestroyTex:()=>1,
    Kine_Filament_CreateLightEx:()=>handle(filamentLights,{}),Kine_Filament_RemoveLight:id=>{filamentLights.delete(id);return 1;},
    Kine_Filament_SetPositionLight:()=>1,Kine_Filament_SetColorLight:()=>1,Kine_Filament_SetIntensityLight:()=>1,Kine_Filament_SetFalloffLight:()=>1,Kine_Filament_SetEnabledLight:()=>1,Kine_Filament_SetDirectionLight:()=>1,Kine_Filament_SetConeLight:()=>1,Kine_Filament_SetShadowLight:()=>1
  };

  const env = new Proxy({}, {get:(_,name)=>{
    if(name==="emscripten_get_now"||name==="emscripten_date_now")return ()=>performance.now();
    if(name==="emscripten_get_heap_max")return ()=>memory.buffer.byteLength;
    if(name==="emscripten_resize_heap")return requested=>{try{memory.grow(Math.max(0,Math.ceil((requested-memory.buffer.byteLength)/65536)));return 1;}catch{return 0;}};
    if(String(name).startsWith("invoke_"))return (index,...args)=>table.get(index)(...args);
    if(name==="__cxa_begin_catch")return p=>p;
    if(name==="__cxa_find_matching_catch_2"||name==="__cxa_find_matching_catch_3")return ()=>0;
    if(name==="__cxa_throw"||name==="__resumeException"||name==="_emscripten_throw_longjmp")return p=>{throw new Error(`native exception ${p||""}`);};
    return ()=>0;
  }});
  const wasi={fd_close:()=>0,fd_seek:()=>0,fd_write:(fd,iovs,count,written)=>{let total=0,out="";const dv=heap32();for(let i=0;i<count;i++){const p=dv.getUint32(iovs+i*8,true),n=dv.getUint32(iovs+i*8+4,true);out+=decoder.decode(heap8().subarray(p,p+n));total+=n;}if(written)dv.setUint32(written,total,true);if(out.trim())console.log(out.trimEnd());return 0;}};

  const loadFilament=()=>new Promise((resolve,reject)=>{try{Filament.init([],resolve);}catch(e){reject(e);}});
  async function start(){
    report("Loading Skia CanvasKit…");
    CanvasKit=await CanvasKitInit({locateFile:f=>`canvaskit/${f}`});
    defaultTypeface=CanvasKit.Typeface.MakeFreeTypeFaceFromData(await (await fetch("fonts/Roboto.ttf")).arrayBuffer());
    report("Loading Filament WebGL…");
    await loadFilament();
    materialBytes=new Uint8Array(await (await fetch("filament/kine_web.filamat")).arrayBuffer());
    await phase("starting-odin-luau-jolt");
    const memoryInterface=new odin.WasmMemoryInterface();
    let imports=odin.setupDefaultImports(memoryInterface,null,memoryInterface.memory);
    window.__kinemiumLogs=[];
    const odinWrite=imports.odin_env.write;
    imports.odin_env.write=(fd,ptr,len)=>{const line=memoryInterface.loadString(ptr,len);window.__kinemiumLogs.push(line);odinWrite(fd,ptr,len);};
    imports={...imports,kinemium_platform:platform,kinemium_skia:skia,kinemium_filament:filament,env,wasi_snapshot_preview1:wasi};
    const result=await WebAssembly.instantiateStreaming(fetch("kinemium_engine.wasm"),imports);
    wasm=result.instance.exports;memory=wasm.memory;table=wasm.__indirect_function_table;
    memoryInterface.setExports(wasm);memoryInterface.setMemory(memory);
    const context=wasm.default_context_ptr();
    await phase("odin-context-ready");
    wasm._start();
    await phase("luau-vm-ready");
    await phase("installing-engine-environment");
    await new Promise(resolve=>requestAnimationFrame(resolve));
    wasm.initialize_environment(context);
    await phase("engine-environment-ready");
    await phase("running-studio-luau-modules");
    await new Promise(resolve=>requestAnimationFrame(resolve));
    wasm.initialize_scripts(context);
    await phase("studio-luau-modules-ready");
    await phase("creating-skia-and-filament");
    await new Promise(resolve=>requestAnimationFrame(resolve));
    wasm.initialize_renderer(context);
    await phase("engine-ready");
    runtimeEl.textContent="Running in Firefox";document.documentElement.dataset.engineReady="true";
    let then=performance.now();
    const frame=now=>{try{stats.frameCalls=(stats.frameCalls||0)+1;const keep=wasm.step(Math.min((now-then)/1000,.1),context);then=now;if(keep)requestAnimationFrame(frame);else wasm._end();}catch(error){console.error(error);window.__kinemiumError=String(error?.stack||error);document.documentElement.dataset.engineError="true";runtimeEl.textContent="Frame failed";statusEl.textContent=error.message;}};
    requestAnimationFrame(frame);
  }
  start().catch(error=>{console.error(error);window.__kinemiumError=String(error?.stack||error);runtimeEl.textContent="Startup failed";statusEl.textContent=error.message;statusEl.style.color="#ff7088";document.documentElement.dataset.engineError="true";});
})();
