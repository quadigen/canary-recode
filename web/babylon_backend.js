/* Kinemium web renderer. The Kine_Filament_* names are a compatibility ABI,
 * not a dependency on Filament. All GPU resources here belong to Babylon.js. */
(function (global) {
  "use strict";
  const GLB_COMP_SIZE = { 5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4 };
  const GLB_NUM_COMP = { SCALAR: 1, VEC2: 2, VEC3: 3, VEC4: 4 };
  const parseGlbMesh = (bytes, meshIndex = null) => {
    const dv = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    if (bytes.byteLength < 12 || dv.getUint32(0, true) !== 0x46546C67 || dv.getUint32(4,true)!==2 || dv.getUint32(8,true)!==bytes.byteLength) return null;
    let off = 12, json = null, bin = null;
    while (off + 8 <= bytes.byteLength) {
      const clen = dv.getUint32(off, true), ctype = dv.getUint32(off + 4, true), start = off + 8;
      if(start+clen>bytes.byteLength)return null;
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
    for (const mesh of (meshIndex == null ? (json.meshes || []) : [json.meshes?.[meshIndex]].filter(Boolean))) {
      for (const p of mesh.primitives) {
        if (p.mode != null && p.mode !== 4) continue;
        if(p.attributes?.POSITION==null)continue;
        const pos = read(p.attributes.POSITION);
        const uv = p.attributes.TEXCOORD_0 != null ? read(p.attributes.TEXCOORD_0) : null;
        const nrm = p.attributes.NORMAL != null ? read(p.attributes.NORMAL) : null;
        const base = positions.length / 3, vcount = pos.length / 3;
        for (let i = 0; i < pos.length; i++)positions.push(pos[i]);
        for (let i = 0; i < vcount; i++)uvs.push(uv ? uv[i * 2] : 0, uv ? uv[i * 2 + 1] : 0);
        const primStart = indices.length;
        if (p.indices != null) { const idx = read(p.indices); for (let i = 0; i < idx.length; i++){if(idx[i]>=vcount)return null;indices.push(base + idx[i]);} }
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
    return { positions: new Float32Array(positions), uvs: new Float32Array(uvs), normals: new Float32Array(normals), indices: positions.length / 3 > 65535 ? new Uint32Array(indices) : new Uint16Array(indices) };
  };

  global.createKinemiumBabylonBackend = function ({ B, canvas, heap8, heap32, stats, materialManifest = {} }) {
    let next = 1;
    const contexts = new Map(), meshes = new Map(), textures = new Map(), lights = new Map();
    const put = (map, value) => { const id = next++; map.set(id, value); return id; };
    const clamp = (x, lo = 0, hi = 1) => Math.max(lo, Math.min(hi, x));
    const color = (r, g, b) => new B.Color3(Math.max(0, r), Math.max(0, g), Math.max(0, b));
    const vec = (x, y, z) => new B.Vector3(x, y, z);
    const get = id => contexts.get(id);
    const valid = (ptr, size) => Number.isSafeInteger(size) && ptr > 0 && size >= 0 && ptr + size <= heap8().length;
    const floats = (ptr, count) => {
      if (!valid(ptr, count * 4)) throw new RangeError("Invalid renderer float buffer");
      const dv = heap32(), data = new Float32Array(count);
      for (let i = 0; i < count; i++) data[i] = dv.getFloat32(ptr + i * 4, true);
      return data;
    };
    const writeVec = (ptr, v) => { if (!valid(ptr, 12)) return; const d = heap32(); d.setFloat32(ptr, v.x, true); d.setFloat32(ptr + 4, v.y, true); d.setFloat32(ptr + 8, v.z, true); };
    const primitive = (c, shape) => {
      const opts = { size: 2, diameter: 2, height: 2, diameterTop: 2, diameterBottom: 2, tessellation: 32 };
      switch (shape) {
        case 2: return B.MeshBuilder.CreateSphere("sphere", { diameter: 2, segments: 24 }, c.scene);
        case 3: return B.MeshBuilder.CreateCylinder("pyramid", { height: 2, diameterTop: 0, diameterBottom: Math.SQRT2 * 2, tessellation: 4 }, c.scene);
        case 4: return B.MeshBuilder.CreatePlane("quad", { size: 2 }, c.scene);
        case 6: return B.MeshBuilder.CreateCylinder("cylinder", opts, c.scene);
        case 7: return B.MeshBuilder.CreateGround("water", { width: 1, height: 1, subdivisions: 16 }, c.scene);
        default: return B.MeshBuilder.CreateBox("box", opts, c.scene);
      }
    };
    const registerMesh = (c, source, geo = null) => {
      source.setEnabled(false); source.isPickable = false;
      source.refreshBoundingInfo();
      const id = put(meshes, { c, source, geo, nodes: [], used: 0, doubleSided: false });
      stats.meshes = meshes.size;
      return id;
    };
    const fromGeo = (c, g) => {
      const source = new B.Mesh("geometry", c.scene), v = new B.VertexData();
      v.positions = g.positions; v.normals = g.normals; v.uvs = g.uvs; v.indices = g.indices;
      if (g.colors) v.colors = g.colors;
      v.applyToMesh(source, true);
      return registerMesh(c, source, g);
    };
    const parseCustom = (ptr, cp, vc, ip, ic, wide) => {
      if (vc <= 0 || ic <= 0 || ic % 3 || !valid(ip, ic * (wide ? 4 : 2))) return null;
      const raw = floats(ptr, vc * 8), positions = new Float32Array(vc * 3), normals = new Float32Array(vc * 3), uvs = new Float32Array(vc * 2);
      for (let i = 0; i < vc; i++) { positions.set(raw.subarray(i * 8, i * 8 + 3), i * 3); normals.set(raw.subarray(i * 8 + 3, i * 8 + 6), i * 3); uvs.set(raw.subarray(i * 8 + 6, i * 8 + 8), i * 2); }
      const d = heap32(), indices = wide ? new Uint32Array(ic) : new Uint16Array(ic);
      for (let i = 0; i < ic; i++) { indices[i] = wide ? d.getUint32(ip + i * 4, true) : d.getUint16(ip + i * 2, true); if (indices[i] >= vc) return null; }
      return { positions, normals, uvs, indices, colors: cp ? floats(cp, vc * 4) : null };
    };
    const custom = (id, p, cp, n, i, k, wide) => { const c = get(id); if (!c) return 0; try { const g = parseCustom(p, cp, n, i, k, wide); return g ? fromGeo(c, g) : 0; } catch (e) { console.warn("Custom mesh", e); return 0; } };
    const loadGlb = (id, p, n, index = null) => { const c = get(id); if (!c || !valid(p, n)) return 0; try { const g = parseGlbMesh(heap8().subarray(p, p + n), index); return g ? fromGeo(c, g) : 0; } catch (e) { console.warn("GLB mesh", e); return 0; } };
    const makeShadow = (c, light, size = 1024) => {
      const sh = new B.ShadowGenerator(size, light);
      sh.usePercentageCloserFiltering = true;
      sh.bias = .0005; sh.normalBias = .02;
      for (const m of meshes.values()) if (m.c === c) for (const n of m.nodes) if (n.cast) sh.addShadowCaster(n.mesh, false);
      return sh;
    };
    const allShadows = c => [c.shadow, ...Array.from(lights.values()).filter(l => l.c === c).map(l => l.shadow)].filter(Boolean);
    const setCaster = (c, n, on) => {
      if (n.cast === on) return;
      n.cast = on;
      for (const sh of allShadows(c)) on ? sh.addShadowCaster(n.mesh, false) : sh.removeShadowCaster(n.mesh, false);
    };
    const setShadowEnabled = (c, on) => { c.scene.shadowsEnabled = !!on; };
    const nodeFor = m => {
      const k = m.used++; let n = m.nodes[k];
      if (!n) {
        const mesh = m.source.clone("draw-" + k, null, true);
        const mat = new B.PBRMaterial("material-" + k, m.c.scene);
        mat.metallic = 0; mat.roughness = .5; mat.maxSimultaneousLights = 8;
        mesh.material = mat; mesh.isPickable = false; mesh.rotationQuaternion = B.Quaternion.Identity();
        n = { mesh, mat, cast: false, textureKey: "", views: [] }; m.nodes[k] = n;
      }
      n.mesh.setEnabled(true);
      return n;
    };
    const releaseViews = n => { for (const t of n.views) t.dispose(); n.views = []; n.textureKey = ""; n.mat.albedoTexture = null; n.mat.bumpTexture = null; n.mat.metallicTexture = null; };
    const texView = (n, t, uv) => {
      if (!t) return null;
      const view = t.clone(); if (!view) return t;
      view.uScale = uv; view.vScale = uv; n.views.push(view); return view;
    };
    const setTexture = (n, id, uv) => {
      const t = textures.get(id), key = t ? id + ":" + uv + ":" + t.revision : "";
      if (n.textureKey === key) return;
      releaseViews(n); n.textureKey = key;
      if (t) {
        n.mat.albedoTexture = texView(n, t.albedo, uv);
        n.mat.bumpTexture = texView(n, t.normal, uv);
        n.mat.metallicTexture = texView(n, t.orm, uv);
        n.mat.useRoughnessFromMetallicTextureAlpha = false;
        n.mat.useRoughnessFromMetallicTextureGreen = true;
        n.mat.useMetallnessFromMetallicTextureBlue = true;
        n.mat.useAmbientOcclusionFromMetallicTextureRed = true;
      }
    };
    const draw = (c, mid, tid, raw, r, g, b, p1, p2, p3, trans, kind, flags, reserved = 0) => {
      const m = meshes.get(mid); if (!m || m.c !== c || raw.some(x => !Number.isFinite(x))) return;
      const n = nodeFor(m), mat = n.mat;
      // Odin submits row-major matrices. Babylon stores translation at 12..14.
      const matrix = B.Matrix.FromArray([raw[0], raw[4], raw[8], raw[12], raw[1], raw[5], raw[9], raw[13], raw[2], raw[6], raw[10], raw[14], raw[3], raw[7], raw[11], raw[15]]);
      n.mesh.freezeWorldMatrix(matrix);
      mat.albedoColor.copyFromFloats(Math.max(0, r), Math.max(0, g), Math.max(0, b));
      mat.emissiveColor.copyFromFloats(0, 0, 0);
      mat.roughness = kind === 0 || kind === 14 ? clamp(p1, .04, 1) : .35;
      mat.metallic = kind === 0 || kind === 14 ? clamp(p2) : 0;
      mat.alpha = 1;
      if (kind === 1) { mat.roughness = clamp(p1, .04, 1); mat.alpha = clamp(1 - trans, .05, 1); }
      if (kind === 3) { mat.roughness = .12; mat.alpha = reserved > 0 ? clamp(reserved) : .65; }
      if (kind === 13) mat.alpha = reserved > 0 ? clamp(reserved) : .45;
      if (kind === 14 || kind === 15) mat.alpha = clamp(1 - trans);
      if (kind === 2 || kind === 15) mat.emissiveColor.copyFromFloats(r * Math.max(1, p1), g * Math.max(1, p1), b * Math.max(1, p1));
      mat.transparencyMode = mat.alpha < 1 ? B.Material.MATERIAL_ALPHABLEND : B.Material.MATERIAL_OPAQUE;
      mat.backFaceCulling = !m.doubleSided;
      n.mesh.receiveShadows = !!(flags & 2);
      setCaster(c, n, !!(flags & 1));
      n.textureId=tid; n.textureUV=Number.isFinite(p3) && p3 > .0001 ? p3 : 1;
      setTexture(n, n.textureId, n.textureUV);
    };
    const render = (id, dt, world = true) => {
      const c = get(id); if (!c) return;
      const start = performance.now();
      for (const m of meshes.values()) if (m.c === c) {
        for (let i = m.used; i < m.nodes.length; i++) { m.nodes[i].mesh.setEnabled(false); setCaster(c, m.nodes[i], false); }
        for(let i=0;i<m.used;i++){const n=m.nodes[i];setTexture(n,n.textureId,n.textureUV);}
        m.used = 0;
      }
      if (world) c.scene.render(false);
      stats.frames++; stats.renderMs = performance.now() - start;
    };
    const pixels = (ptr, w, h, stride) => {
      if (w <= 0 || h <= 0 || stride < w * 4 || !valid(ptr, h * stride)) throw new RangeError("Invalid RGBA texture");
      const src = heap8(), out = new Uint8Array(w * h * 4);
      for (let y = 0; y < h; y++)out.set(src.subarray(ptr + y * stride, ptr + y * stride + w * 4), y * w * 4);
      return out;
    };
    const rawTex = (c, w, h, row, p, srgb) => { if (!p || w <= 0 || h <= 0) return null; const t = B.RawTexture.CreateRGBATexture(pixels(p, w, h, row), w, h, c.scene, false, false, B.Texture.BILINEAR_SAMPLINGMODE, B.Constants.TEXTURETYPE_UNSIGNED_BYTE, srgb); t.gammaSpace = srgb; t.wrapU = t.wrapV = B.Texture.WRAP_ADDRESSMODE; return t; };
    const makeTexture = (id, w, h, row, p, nw = 0, nh = 0, nrow = 0, np = 0, ow = 0, oh = 0, orow = 0, op = 0) => {
      const c = get(id); if (!c) return 0;
      let albedo, normal, orm;
      try { albedo = rawTex(c, w, h, row, p, true); if (!albedo) return 0; normal = rawTex(c, nw, nh, nrow, np, false); orm = rawTex(c, ow, oh, orow, op, false); const id = put(textures, { c, albedo, normal, orm, w, h, revision: 0 }); stats.textures = textures.size; return id; }
      catch (e) { albedo?.dispose(); normal?.dispose(); orm?.dispose(); console.warn("Texture", e); return 0; }
    };
    const destroyTexture = (id, cid) => {
      const t = textures.get(id); if (!t || (cid && get(cid) !== t.c)) return 0;
      for (const m of meshes.values()) if (m.c === t.c) for (const n of m.nodes) if (n.textureKey.startsWith(id + ":")) releaseViews(n);
      for(const tex of new Set([t.albedo,t.normal,t.orm,...(t.pending||[])]))tex?.dispose(); textures.delete(id); stats.textures = textures.size; return 1;
    };
    const destroyMesh = (cid, id) => {
      const m = meshes.get(id); if (!m || m.c !== get(cid)) return 0;
      for (const n of m.nodes) { setCaster(m.c, n, false); releaseViews(n); n.mesh.dispose(); n.mat.dispose(); }
      m.source.dispose(); meshes.delete(id); stats.meshes = meshes.size; return 1;
    };
    const shadowLight = (l, on) => { if (on && !l.shadow) l.shadow = makeShadow(l.c, l.light); else if (!on && l.shadow) { l.shadow.dispose(); l.shadow = null; } };
    const lightFor = (cid, id) => { const l = lights.get(id); return l?.c === get(cid) ? l : null; };
    const removeLight = (cid, id) => { const l = lightFor(cid, id); if (!l) return 0; l.shadow?.dispose(); l.light.dispose(); lights.delete(id); return 1; };
    const applySun = (c, x, y, z, i, fade) => { const d = vec(-x, -y, -z); if (d.lengthSquared() > 0) c.sun.direction = d.normalize(); c.sun.intensity = Math.max(0, i) / 100000 * (fade ? clamp((y + .05) / .15) : 1); };
    const sky = (c, r, g, b, a = 1) => { c.scene.clearColor.copyFromFloats(r, g, b, a); };
    const pipeline = c => { if (!c.pipeline) c.pipeline = new B.DefaultRenderingPipeline("kinemium", true, c.scene, [c.camera]); return c.pipeline; };
    const withContext = fn => (id, ...a) => { const c = get(id); if (!c) return 0; fn(c, ...a); return 1; };
    const withLight = fn => (cid, id, ...a) => { const l = lightFor(cid, id); if (!l) return 0; fn(l, ...a); return 1; };
    const api = {
      Kine_Filament_CreateForSDLWindow: (_win, w, h) => {
        try {
          const engine = new B.Engine(canvas, true, { preserveDrawingBuffer: true, stencil: true, disableWebGL2Support: false }, false);
          engine.setSize(w, h, true);
          const scene = new B.Scene(engine); scene.useRightHandedSystem = true;
          const camera = new B.FreeCamera("Camera", vec(8, 7, 12), scene);
          camera.setTarget(vec(0, 0, 0)); camera.fov = Math.PI / 3; camera.minZ = .1; camera.maxZ = 1000; scene.activeCamera = camera;
          const sun = new B.DirectionalLight("Sun", vec(-.5, -1, -.8).normalize(), scene); sun.intensity = 1;
          const ambient = new B.HemisphericLight("Ambient", vec(0, 1, 0), scene); ambient.intensity = .65; ambient.groundColor = color(.25, .25, .3);
          const c = { engine, scene, camera, sun, ambient, w, h, shadow: null, shadowSize: 1024, pipeline: null };
          sky(c, .035, .055, .09); c.shadow = makeShadow(c, sun, c.shadowSize);
          const id = put(contexts, c); stats.babylonContexts = contexts.size; stats.renderer = "Babylon.js WebGL" + engine.webGLVersion; return id;
        } catch (e) { console.error("Babylon renderer initialization", e); return 0; }
      },
      Kine_Filament_Destroy: id => { const c = get(id); if (!c) return; for (const [k, m] of meshes) if (m.c === c) destroyMesh(id, k); for (const [k, t] of textures) if (t.c === c) destroyTexture(k, id); for (const [k, l] of lights) if (l.c === c) removeLight(id, k); c.pipeline?.dispose(); c.shadow?.dispose(); c.scene.dispose(); c.engine.dispose(); contexts.delete(id); stats.babylonContexts = contexts.size; },
      Kine_Filament_CreateMesh: (id, shape) => { const c = get(id); return c ? registerMesh(c, primitive(c, shape)) : 0; },
      Kine_Filament_CreateMeshFromMemory: (id, p, n) => loadGlb(id, p, n),
      Kine_Filament_CreateMeshFromMemoryIndexed: (id, p, n, _hint, index) => loadGlb(id, p, n, index),
      Kine_Filament_CreateCustomMesh: (id, p, n, i, k) => custom(id, p, 0, n, i, k, false),
      Kine_Filament_CreateCustomMesh32: (id, p, n, i, k) => custom(id, p, 0, n, i, k, true),
      Kine_Filament_CreateCustomMeshEx: (id, p, cp, n, i, k) => custom(id, p, cp, n, i, k, false),
      Kine_Filament_CreateCustomMeshEx32: (id, p, cp, n, i, k) => custom(id, p, cp, n, i, k, true),
      Kine_Filament_CreateTerrainMesh: (id, p, _weights, n, i, k) => custom(id, p, 0, n, i, k, false),
      Kine_Filament_UpdateCustomMesh: (id, mid, p, n) => { const m = meshes.get(mid); if (!m || m.c !== get(id) || !m.geo || n !== m.geo.positions.length / 3) return 0; try { const raw = floats(p, n * 8); for (let i = 0; i < n; i++) { m.geo.positions.set(raw.subarray(i * 8, i * 8 + 3), i * 3); m.geo.normals.set(raw.subarray(i * 8 + 3, i * 8 + 6), i * 3); m.geo.uvs.set(raw.subarray(i * 8 + 6, i * 8 + 8), i * 2); } for (const [kind, data] of [[B.VertexBuffer.PositionKind, m.geo.positions], [B.VertexBuffer.NormalKind, m.geo.normals], [B.VertexBuffer.UVKind, m.geo.uvs]]) m.source.updateVerticesData(kind, data, true); return 1; } catch { return 0; } },
      Kine_Filament_GetMeshBounds: (mid, center, half) => { const m = meshes.get(mid); if (!m) return 0; const box = m.source.getBoundingInfo().boundingBox; writeVec(center, box.center); writeVec(half, box.extendSize); return 1; },
      Kine_Filament_SetMeshDoubleSided: mid => { const m = meshes.get(mid); if (m) m.doubleSided = true; },
      Kine_Filament_DestroyMesh: destroyMesh,
      Kine_Filament_DrawMeshList: (id, p, count) => {
        const c = get(id), stride = 116; if (!c || count < 0 || (count && !valid(p, count * stride))) return 0;
        const d = heap32(); stats.drawListCalls = (stats.drawListCalls || 0) + 1; stats.drawItems = (stats.drawItems || 0) + count;
        for (let i = 0; i < count; i++) { const o = p + i * stride, f = j => d.getFloat32(o + j, true); draw(c, d.getUint32(o, true), d.getUint32(o + 4, true), floats(o + 8, 16), f(72), f(76), f(80), f(84), f(88), f(92), f(96), d.getInt32(o + 100, true), d.getUint32(o + 104, true), f(108)); }
        return 1;
      },
      Kine_Filament_DrawMeshListVersioned: (...a) => api.Kine_Filament_DrawMeshList(...a),
      Kine_Filament_DrawMeshEx: (id, m, k, r, g, b, p1, p2, p3, tr, ptr, cast, recv, _cull, t) => { const c = get(id); if (!c || !valid(ptr, 64)) return 0; draw(c, m, t, floats(ptr, 16), r, g, b, p1, p2, p3, tr, k, (cast ? 1 : 0) | (recv ? 2 : 0)); return 1; },
      Kine_Filament_RenderFrame: render,
      Kine_Filament_Viewport_RenderFrame: render,
      Kine_Filament_Resize: withContext((c, w, h) => { c.w = w; c.h = h; c.engine.setSize(w, h, true); c.camera.viewport = new B.Viewport(0, 0, 1, 1); }),
      Kine_Filament_SetViewport: withContext((c, x, y, w, h) => { c.camera.viewport = new B.Viewport(x / c.w, 1 - (y + h) / c.h, w / c.w, h / c.h); }),
      Kine_Filament_SetCameraPerspective: withContext((c, fov, _aspect, near, far) => { c.camera.fov = fov * Math.PI / 180; c.camera.minZ = Math.max(.001, near); c.camera.maxZ = Math.max(c.camera.minZ + .001, far); }),
      Kine_Filament_SetCameraLookAt: withContext((c, x, y, z, tx, ty, tz, ux, uy, uz) => { c.camera.position.copyFromFloats(x, y, z); c.camera.upVector.copyFromFloats(ux, uy, uz); c.camera.setTarget(vec(tx, ty, tz)); }),
      Kine_Filament_SetCameraPosition: withContext((c, x, y, z) => c.camera.position.copyFromFloats(x, y, z)),
      Kine_Filament_SetCameraDirection: withContext((c, x, y, z) => c.camera.setTarget(c.camera.position.add(vec(x, y, z)))),
      Kine_Filament_CreateSky: withContext(sky),
      Kine_Filament_SetSun: withContext((c, x, y, z, i) => applySun(c, x, y, z, i, false)),
      Kine_Filament_SetSkyAtmosphere: withContext((c, x, y, z, sr, sg, sb, hr, hg, hb, gr, gg, gb, i) => { const t = y >= 0 ? Math.pow(clamp(y), .45) : clamp((y + .1) / .1); const a = y >= 0 ? [hr, hg, hb] : [gr, gg, gb], b = y >= 0 ? [sr, sg, sb] : [hr, hg, hb]; sky(c, ...a.map((v, j) => v + (b[j] - v) * t)); c.ambient.diffuse.copyFromFloats(sr, sg, sb); c.ambient.groundColor.copyFromFloats(gr, gg, gb); applySun(c, x, y, z, i, true); }),
      Kine_Filament_SetShadowOptions: withContext((c, on, filter) => { setShadowEnabled(c, on); if (c.shadow) { c.shadow.usePercentageCloserFiltering = filter !== 3; c.shadow.useContactHardeningShadow = filter === 3; } }),
      Kine_Filament_SetSunShadowOptions: withContext((c, size, _cascades, far) => { const n = 2 ** Math.round(Math.log2(clamp(size, 128, 4096))); if (n !== c.shadowSize) { c.shadow?.dispose(); c.shadow = makeShadow(c, c.sun, n); c.shadowSize = n; } if (far > 0) c.sun.shadowMaxZ = far; }),
      Kine_Filament_SetPostProcessing: withContext((c, on) => { c.scene.postProcessesEnabled = !!on; }),
      Kine_Filament_SetAmbientOcclusion:(id,on,radius,_power,intensity,quality)=>{
        const c=get(id);if(!c)return 0;
        if(!on){c.ssao?.dispose();c.ssao=null;return 1;}
        if(!B.SSAO2RenderingPipeline?.IsSupported)return 0;
        if(!c.ssao)c.ssao=new B.SSAO2RenderingPipeline("ambient-occlusion",c.scene,{ssaoRatio:.5,blurRatio:.5},[c.camera]);
        c.ssao.radius=Math.max(.001,radius);c.ssao.totalStrength=Math.max(0,intensity);c.ssao.samples=[8,16,24,32][clamp(quality|0,0,3)];
        return 1;
      },
      Kine_Filament_SetScreenSpaceReflections:(id,on,thickness,bias,maxDistance,stride)=>{
        const c=get(id);if(!c)return 0;
        if(!on){c.ssr?.dispose();c.ssr=null;return 1;}
        if(!B.SSRRenderingPipeline||c.engine.webGLVersion<2)return 0;
        if(!c.ssr){c.ssr=new B.SSRRenderingPipeline("reflections",c.scene,[c.camera]);if(!c.ssr.isSupported){c.ssr.dispose();c.ssr=null;return 0;}}
        c.ssr.thickness=Math.max(.001,thickness);c.ssr.maxDistance=Math.max(.001,maxDistance);
        c.ssr.step=Math.max(1,Math.round(stride));c.ssr.selfCollisionNumSkip=Math.max(1,Math.ceil(bias));
        return 1;
      },
      Kine_Filament_SetDynamicResolution:withContext((c,on,lo,hi)=>{
        // Babylon uses a hardware backbuffer scale. The viewport coordinates
        // remain normalized against the full-resolution engine surface.
        c.scale=on?clamp(hi,.1,1):1;
        c.minScale=on?clamp(lo,.1,c.scale):1;
        c.maxScale=c.scale;c.frameAverage=1/60;c.scaleClock=0;
        c.engine.setSize(Math.max(1,Math.round(c.w*c.scale)),Math.max(1,Math.round(c.h*c.scale)),true);
      }),
      Kine_Filament_SetBloom: withContext((c, on, strength) => { if (!on && !c.pipeline) return; const p = pipeline(c); p.bloomEnabled = !!on; p.bloomWeight = clamp(strength, 0, 2); }),
      Kine_Filament_SetAntiAliasing: withContext((c, fxaa, _taa, msaa, samples) => { if (!fxaa && !msaa && !c.pipeline) return; const p = pipeline(c); p.fxaaEnabled = !!fxaa; p.samples = msaa ? clamp(samples | 0, 1, 8) : 1; }),
      Kine_Filament_SetDepthOfField: withContext((c, on, scale, _aspect, aperture) => { if (!on && !c.pipeline) return; const p = pipeline(c); p.depthOfFieldEnabled = !!on; if (on) { p.depthOfField.fStop = Math.max(.1, 1 / Math.max(.01, aperture || scale || 1)); } }),
      Kine_Filament_SetFocusDistance: withContext((c, d) => { if (c.pipeline) c.pipeline.depthOfField.focusDistance = Math.max(.001, d) * 1000; }),
      Kine_Filament_SetVignette: withContext((c, on, mid, round, feather, r, g, b, a) => { const v = c.scene.imageProcessingConfiguration; v.vignetteEnabled = !!on; v.vignetteWeight = clamp(feather) * 4; v.vignetteStretch = clamp(round); v.vignetteColor = new B.Color4(r, g, b, a); }),
      Kine_Filament_SetColorGrading: withContext((c, exp, contrast) => { const v = c.scene.imageProcessingConfiguration; v.exposure = 2 ** clamp(exp, -10, 10); v.contrast = Math.max(.001, contrast); }),
      Kine_Filament_ClearColorGrading: withContext(c => { c.scene.imageProcessingConfiguration.exposure = 1; c.scene.imageProcessingConfiguration.contrast = 1; }),
      Kine_Filament_SetSunRays: withContext((c, on, distance, _cut, _opacity, _height, _fall, density, _start, _size, r, g, b) => { c.scene.fogMode = on ? B.Scene.FOGMODE_EXP2 : B.Scene.FOGMODE_NONE; c.scene.fogDensity = Math.max(0, density); c.scene.fogStart = Math.max(0, distance); c.scene.fogColor.copyFromFloats(r, g, b); }),
      host_load_builtin_material: (cid, material) => {
        const c=get(cid), paths=materialManifest[material];
        if(!c||!paths?.albedo)return 0;
        const entry={c,albedo:null,normal:null,orm:null,revision:0};
        const id=put(textures,entry);stats.textures=textures.size;
        for(const name of ["albedo","normal","orm"]){
          if(!paths[name])continue;
          let t;
          t=new B.Texture(paths[name],c.scene,false,false,B.Texture.TRILINEAR_SAMPLINGMODE,()=>{
            if(textures.get(id)!==entry){t.dispose();return;}
            entry[name]=t;entry.revision++;
            stats.materialChannelsLoaded=(stats.materialChannelsLoaded||0)+1;
          },(message)=>{stats.materialTextureErrors=(stats.materialTextureErrors||0)+1;console.warn("Material texture",paths[name],message);t?.dispose();});
          t.gammaSpace=name==="albedo";t.wrapU=t.wrapV=B.Texture.WRAP_ADDRESSMODE;
          (entry.pending??=[]).push(t);
        }
        return id;
      },
      Kine_Filament_CreateTexFromPixels: makeTexture,
      Kine_Filament_CreatePbrTexFromPixels: makeTexture,
      Kine_Filament_UpdateTexFromPixels: (id, tid, w, h, row, p) => { const t = textures.get(tid); if (!t || t.c !== get(id) || w !== t.w || h !== t.h) return 0; try { t.albedo.update(pixels(p, w, h, row)); return 1; } catch { return 0; } },
      Kine_Filament_DestroyTex: (cid, id) => destroyTexture(id, cid),
      Kine_Filament_CreateLightEx: (id, type, x, y, z, dx, dy, dz, r, g, b, i, range, inner, outer, shadow, on) => {
        const c = get(id); if (!c) return -1; const pos = vec(x, y, z), dir = vec(dx, dy, dz);
        const light = type === 0 ? new B.PointLight("PointLight", pos, c.scene) : new B.SpotLight("SpotLight", pos, dir, Math.max(.001, outer * 2), 2, c.scene);
        light.diffuse = color(r, g, b); light.intensity = Math.max(0, i); light.range = Math.max(.001, range); light.setEnabled(!!on);
        const l = { c, light, shadow: null }; if (type !== 0) light.innerAngle = inner * 2; shadowLight(l, !!shadow); return put(lights, l);
      },
      Kine_Filament_RemoveLight: removeLight,
      Kine_Filament_SetPositionLight: withLight((l, x, y, z) => l.light.position.copyFromFloats(x, y, z)),
      Kine_Filament_SetDirectionLight: withLight((l, x, y, z) => l.light.direction?.copyFromFloats(x, y, z)),
      Kine_Filament_SetColorLight: withLight((l, r, g, b) => l.light.diffuse.copyFromFloats(r, g, b)),
      Kine_Filament_SetIntensityLight: withLight((l, v) => l.light.intensity = Math.max(0, v)),
      Kine_Filament_SetFalloffLight: withLight((l, v) => l.light.range = Math.max(.001, v)),
      Kine_Filament_SetEnabledLight: withLight((l, v) => l.light.setEnabled(!!v)),
      Kine_Filament_SetConeLight: withLight((l, i, o) => { if (l.light instanceof B.SpotLight) { l.light.angle = o * 2; l.light.innerAngle = i * 2; } }),
      Kine_Filament_SetShadowLight: withLight((l, on) => shadowLight(l, !!on)),
    };
    return api;
  };
})(globalThis);
