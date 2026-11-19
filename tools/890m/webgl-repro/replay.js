// Replays a capture made by capture.mjs into a WebGL2 canvas on this page.
// URL params: trace=<file>, upto=<call index to stop before> (default all), flushFrames=1 (gl.flush at frame markers),
// skipProg=<comma list of program ids whose draws are skipped>.
// Results on window: __replay = {calls, draws, errors, w, h}, __pixels() -> base64 RGBA of the default framebuffer,
// __drawInfo = per-draw [callIndex, programId, name].
'use strict';
const out = document.getElementById('out'); const say = s => { out.textContent += s + '\n'; };
window.__done = false;
(async () => {
  const q = new URLSearchParams(location.search);
  const buf = await (await fetch(q.get('trace'))).arrayBuffer();
  const hl = new DataView(buf).getUint32(0, true);
  const head = JSON.parse(new TextDecoder().decode(new Uint8Array(buf, 4, hl)));
  const base = 4 + hl; const calls = head.calls, blobs = head.blobs;
  const ctxRec = calls.find(c => c[0] === '__context');
  // the worker resizes its OffscreenCanvas after getContext: take the default framebuffer size from the viewports set
  // while framebuffer null is bound (or the size= URL parameter)
  let W = 0, H = 0, fbNull = true;
  for (const [n, a] of calls) { if (n === 'bindFramebuffer' && (a[0] === 36160 || a[0] === 36009)) fbNull = a[1] === null;
    if (n === 'viewport' && fbNull) { W = Math.max(W, a[2]); H = Math.max(H, a[3]); } }
  const qs = new URLSearchParams(location.search).get('size'); if (qs) [W, H] = qs.split('x').map(Number);
  if (!W) { W = ctxRec ? ctxRec[1][0] : 1280; H = ctxRec ? ctxRec[1][1] : 800; }
  const attrs = Object.assign(ctxRec ? JSON.parse(ctxRec[1][2]) : {}, { preserveDrawingBuffer: true });
  const cv = document.createElement('canvas'); cv.width = W; cv.height = H; document.body.appendChild(cv); cv.style.width = '640px';
  const gl = cv.getContext('webgl2', attrs);
  const renderer = (() => { const e = gl.getExtension('WEBGL_debug_renderer_info'); return e ? gl.getParameter(e.UNMASKED_RENDERER_WEBGL) : '?'; })();
  say(`renderer ${renderer}\ncanvas ${W}x${H} attrs ${JSON.stringify(attrs)} calls ${calls.length}`);
  const objs = new Map(), exts = {};
  const T = { Float32Array, Uint8Array, Uint16Array, Uint32Array, Int8Array, Int16Array, Int32Array, Uint8ClampedArray, Float64Array };
  const dec = v => {
    if (v === null || typeof v !== 'object') return v;
    if ('o' in v) return objs.get(v.o) ?? null;
    if ('a' in v) return v.a.map(dec);
    if ('t' in v) { const [off, len] = blobs[v.b]; const copy = buf.slice(base + off, base + off + len); return v.t === 'ArrayBuffer' ? copy : new T[v.t](copy); }
    if ('img' in v) { const [off, len] = blobs[v.img]; return new ImageData(new Uint8ClampedArray(buf.slice(base + off, base + off + len)), v.w, v.h); }
    if ('out' in v) return new T[v.out](v.n);
    return undefined;
  };
  const stopDraw = q.has('draw') ? +q.get('draw') : -1;
  let upto = +(q.get('upto') || calls.length), flushFrames = q.get('flushFrames') === '1';
  const skip = new Set((q.get('skipProg') || '').split(',').filter(Boolean).map(Number));
  const alignIdx = q.get('alignIdx') === '1', shadow = new Map(), scratchIB = gl.createBuffer(); let realigned = 0; window.__realigned = () => realigned;
  let cur = 0, draws = 0, errors = 0, frames = 0; const drawInfo = []; window.__drawInfo = drawInfo;
  for (let i = 0; i < upto; i++) {
    const [name, args, ret] = calls[i];
    if (name === '__frame') { frames++; if (flushFrames) gl.flush(); continue; }
    if (name[0] === '_') continue;
    let r;
    try {
      if (name.startsWith('ext:')) { const [, en, m] = name.split(':'); const x = exts[en] || (exts[en] = gl.getExtension(en)); if (!x) continue; r = x[m](...args.map(dec)); }
      else {
        const a = args.map(dec);
        if (name === 'useProgram') cur = args[0] && args[0].o || 0;
        if (/^draw|^ext:.*multiDraw/.test(name)) { drawInfo.push([i, cur, name]); draws++; if (skip.has(cur)) continue; }
        if (name === 'getExtension') { r = gl.getExtension(a[0]); if (r) exts[a[0]] = r; }
        else if (alignIdx && (name === 'drawElementsInstanced' || name === 'drawElements') && a[3] % 4) {
          // A/B: copy this draw's indices to offset 0 of a scratch buffer (4-byte aligned), draw, restore the VAO's binding
          const eb = gl.getParameter(gl.ELEMENT_ARRAY_BUFFER_BINDING); const sh = shadow.get(eb); const es = a[2] === gl.UNSIGNED_INT ? 4 : a[2] === gl.UNSIGNED_SHORT ? 2 : 1;
          if (sh) { gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, scratchIB); gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, sh.slice(a[3], a[3] + a[1] * es), gl.STREAM_DRAW);
            name === 'drawElements' ? gl.drawElements(a[0], a[1], a[2], 0) : gl.drawElementsInstanced(a[0], a[1], a[2], 0, a[4]); gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, eb); realigned++; }
          else r = gl[name](...a);
        }
        else r = gl[name](...a);
        if (alignIdx && (name === 'bufferData' || name === 'bufferSubData') && a[0] === gl.ELEMENT_ARRAY_BUFFER) {
          const eb = gl.getParameter(gl.ELEMENT_ARRAY_BUFFER_BINDING);
          if (name === 'bufferData') shadow.set(eb, typeof a[1] === 'number' ? new Uint8Array(a[1]) : new Uint8Array(a[1].buffer ? a[1].buffer.slice(a[1].byteOffset, a[1].byteOffset + a[1].byteLength) : a[1]).slice());
          else { const sh = shadow.get(eb); if (sh) sh.set(new Uint8Array(a[2].buffer, a[2].byteOffset, a[2].byteLength), a[1]); }
        }
      }
    } catch (e) { if (errors++ < 10) say(`call ${i} ${name}: ${e.message}`); }
    if (ret !== null && ret !== undefined && r !== undefined && typeof r === 'object') objs.set(ret, r);
    if (stopDraw >= 0 && draws === stopDraw + 1 && /^draw|multiDraw/.test(name)) { upto = i + 1; break; }
  }
  if (stopDraw >= 0) {   // read what the stopping draw wrote: its viewport on the bound draw framebuffer
    const vp = gl.getParameter(gl.VIEWPORT), fb = gl.getParameter(gl.DRAW_FRAMEBUFFER_BINDING);
    gl.bindFramebuffer(gl.READ_FRAMEBUFFER, fb); const ppb = gl.getParameter(gl.PIXEL_PACK_BUFFER_BINDING); gl.bindBuffer(gl.PIXEL_PACK_BUFFER, null);
    const [x, y, w, h] = vp; gl.getError(); let p = new Uint8Array(w * h * 4); gl.readPixels(x, y, w, h, gl.RGBA, gl.UNSIGNED_BYTE, p);
    let rf = 'u8'; if (gl.getError()) { const f = new Float32Array(w * h * 4); gl.readPixels(x, y, w, h, gl.RGBA, gl.FLOAT, f); rf = 'f32:' + gl.getError();
      for (let k = 0; k < f.length; k++) p[k] = Math.max(0, Math.min(255, Math.round(f[k] * 255))); }
    window.__stop = { vp, fbId: [...objs].find(([k, v]) => v === fb)?.[0] ?? 0, prog: cur, call: calls[upto - 1][0], err: gl.getError(), rf };
    let s = ''; for (let k = 0; k < p.length; k += 32768) s += String.fromCharCode.apply(null, p.subarray(k, k + 32768)); window.__stopPx = btoa(s);
    window.__replay = { stop: window.__stop }; say(JSON.stringify(window.__stop)); window.__done = true; return;
  }
  gl.bindFramebuffer(gl.FRAMEBUFFER, null);
  const px = new Uint8Array(W * H * 4); gl.readPixels(0, 0, W, H, gl.RGBA, gl.UNSIGNED_BYTE, px);
  window.__px = px;
  window.__pixels = (x0 = 0, y0 = 0, w = W, h = H) => { let s = ''; for (let y = y0; y < y0 + h; y++) { const row = px.subarray((y * W + x0) * 4, (y * W + x0 + w) * 4); for (let k = 0; k < row.length; k += 32768) s += String.fromCharCode.apply(null, row.subarray(k, k + 32768)); } return btoa(s); };
  window.__png = async () => { const c = new OffscreenCanvas(W, H); const x = c.getContext('2d'); const id = new ImageData(W, H);
    for (let y = 0; y < H; y++) id.data.set(px.subarray((H - 1 - y) * W * 4, (H - y) * W * 4), y * W * 4);
    x.putImageData(id, 0, 0); const b = await c.convertToBlob({ type: 'image/png' }); const u = new Uint8Array(await b.arrayBuffer()); let s = ''; for (let k = 0; k < u.length; k += 32768) s += String.fromCharCode.apply(null, u.subarray(k, k + 32768)); return btoa(s); };
  window.__replay = { realigned, renderer, calls: upto, draws, frames, errors, w: W, h: H, glError: gl.getError() };
  say(JSON.stringify(window.__replay)); window.__done = true;
})().catch(e => { say('replay failed: ' + e.stack); window.__done = true; });
