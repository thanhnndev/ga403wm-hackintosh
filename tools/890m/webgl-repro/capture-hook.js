// WebGL2 call capture, injected into the page and its workers before any script runs (CDP Runtime.evaluate on attach).
// Records every state-changing WebGL2 call (and extension calls) with its data until self.__capStop is set.
// self.__capDump() -> number of bytes; self.__capChunk(i) -> base64 of 4 MiB chunk i. Format: u32 header length,
// JSON header {calls:[[name, args, retId]], blobs:[[offset,len,type]]}, then the blob bytes.
(() => {
  if (!self.WebGL2RenderingContext || self.__capInstalled) return; self.__capInstalled = true;
  const calls = [], blobs = []; let blobBytes = 0; const ids = new WeakMap(); let nid = 0; self.__capStop = false;
  const idOf = o => { if (!ids.has(o)) ids.set(o, ++nid); return ids.get(o); };
  const SKIP = /^(get(?!BufferSubData|UniformLocation|UniformBlockIndex|Extension|AttribLocation|FragDataLocation)|is|checkFramebufferStatus|validateProgram|getError)/;
  const bytesBy = {}; self.__capBytesBy = () => JSON.stringify(Object.entries(bytesBy).sort((a,b)=>b[1]-a[1]).slice(0,12)); let curName = '';
  const blob = (u8, type) => { bytesBy[curName] = (bytesBy[curName] || 0) + u8.byteLength; if (u8.byteLength > (64 << 20)) throw new Error('blob too large: ' + curName + ' ' + u8.byteLength); const c = u8.slice(); blobs.push([blobBytes, c.byteLength, type, c]); blobBytes += c.byteLength; return blobs.length - 1; };
  const enc = (v) => {
    if (v === null || v === undefined || typeof v === 'number' || typeof v === 'boolean' || typeof v === 'string') return v;
    if (ArrayBuffer.isView(v)) return { t: v.constructor.name, b: blob(new Uint8Array(v.buffer, v.byteOffset, v.byteLength), v.constructor.name) };
    if (v instanceof ArrayBuffer) return { t: 'ArrayBuffer', b: blob(new Uint8Array(v), 'ArrayBuffer') };
    if (Array.isArray(v)) return { a: v.map(enc) };
    if (ids.has(v)) return { o: ids.get(v) };
    if (v && v.out) return v;
    const isImg = (typeof ImageBitmap !== 'undefined' && v instanceof ImageBitmap) || (typeof OffscreenCanvas !== 'undefined' && v instanceof OffscreenCanvas) ||
      (typeof ImageData !== 'undefined' && v instanceof ImageData) || (typeof HTMLCanvasElement !== 'undefined' && v instanceof HTMLCanvasElement) || (typeof HTMLImageElement !== 'undefined' && v instanceof HTMLImageElement);
    if (isImg) {
      let d;
      if (v instanceof ImageData) d = v;
      else { const c = new OffscreenCanvas(v.width, v.height); const x = c.getContext('2d'); x.drawImage(v, 0, 0); d = x.getImageData(0, 0, v.width, v.height); }
      return { img: blob(new Uint8Array(d.data.buffer), 'img'), w: d.width, h: d.height };
    }
    if (typeof v === 'object' && v.constructor && /^WebGL/.test(v.constructor.name)) return { o: idOf(v) };
    return { u: String(v && v.constructor && v.constructor.name) };
  };
  // WebGL2 overloads take (view, srcOffset[, length]) into a large heap view: keep only the bytes the call reads.
  const G = WebGL2RenderingContext; let unpackAlign = 4, unpackRowLen = 0, unpackImgH = 0;
  const bpp = (f, t) => { const comps = { [G.RED]: 1, [G.RED_INTEGER]: 1, [G.RG]: 2, [G.RG_INTEGER]: 2, [G.RGB]: 3, [G.RGB_INTEGER]: 3, [G.RGBA]: 4, [G.RGBA_INTEGER]: 4,
      [G.ALPHA]: 1, [G.LUMINANCE]: 1, [G.LUMINANCE_ALPHA]: 2, [G.DEPTH_COMPONENT]: 1, [G.DEPTH_STENCIL]: 1 }[f] || 4;
    const sz = { [G.UNSIGNED_BYTE]: 1, [G.BYTE]: 1, [G.UNSIGNED_SHORT]: 2, [G.SHORT]: 2, [G.HALF_FLOAT]: 2, [G.UNSIGNED_INT]: 4, [G.INT]: 4, [G.FLOAT]: 4 }[t];
    if (sz) return comps * sz; return { [G.UNSIGNED_SHORT_5_6_5]: 2, [G.UNSIGNED_SHORT_4_4_4_4]: 2, [G.UNSIGNED_SHORT_5_5_5_1]: 2 }[t] || 4; };
  const sliceView = (v, offEl, lenEl) => { const C = v.constructor; const e = C.BYTES_PER_ELEMENT || 1; const start = offEl || 0;
    const n = lenEl ? lenEl : v.length - start; return new C(v.buffer, v.byteOffset + start * e, Math.max(0, Math.min(n, v.length - start))); };
  const texBytes = (w, h, d, f, t) => { const rowLen = unpackRowLen || w; const row = Math.ceil(rowLen * bpp(f, t) / unpackAlign) * unpackAlign; const imgH = unpackImgH || h;
    return row * (imgH * (d - 1) + (h - 1)) + w * bpp(f, t); };
  const texView = (v, off, bytes) => { const e = v.BYTES_PER_ELEMENT || 1; return sliceView(v, off || 0, Math.ceil(bytes / e)); };
  const norm = (name, a) => {
    const V = x => ArrayBuffer.isView(x);
    switch (name) {
      case 'pixelStorei': if (a[0] === G.UNPACK_ALIGNMENT) unpackAlign = a[1]; if (a[0] === G.UNPACK_ROW_LENGTH) unpackRowLen = a[1]; if (a[0] === G.UNPACK_IMAGE_HEIGHT) unpackImgH = a[1]; return a;
      case 'bufferData': if (V(a[1])) return [a[0], sliceView(a[1], a[3], a[4]), a[2]]; return a;
      case 'bufferSubData': if (V(a[2])) return [a[0], a[1], sliceView(a[2], a[3], a[4])]; return a;
      case 'texSubImage2D': if (a.length >= 9 && V(a[8])) return [...a.slice(0, 8), texView(a[8], a[9], texBytes(a[4], a[5], 1, a[6], a[7]))]; return a;
      case 'texImage2D': if (a.length >= 9 && V(a[8])) return [...a.slice(0, 8), texView(a[8], a[9], texBytes(a[3], a[4], 1, a[6], a[7]))]; return a;
      case 'texSubImage3D': if (a.length >= 11 && V(a[10])) return [...a.slice(0, 10), texView(a[10], a[11], texBytes(a[5], a[6], a[7], a[8], a[9]))]; return a;
      case 'texImage3D': if (a.length >= 10 && V(a[9])) return [...a.slice(0, 9), texView(a[9], a[10], texBytes(a[3], a[4], a[5], a[7], a[8]))]; return a;
      case 'compressedTexSubImage2D': if (V(a[7])) return [...a.slice(0, 7), sliceView(a[7], a[8], a[9])]; return a;
      case 'compressedTexImage2D': if (V(a[6])) return [...a.slice(0, 6), sliceView(a[6], a[7], a[8])]; return a;
      case 'readPixels': if (V(a[6])) return [...a.slice(0, 6), { out: a[6].constructor.name, n: a[6].length - (a[7] || 0) }]; return a;
      case 'clearBufferfv': case 'clearBufferiv': case 'clearBufferuiv': if (V(a[2])) return [a[0], a[1], sliceView(a[2], a[3], 4)]; return a;
      case 'getBufferSubData': return [a[0], a[1], { out: a[2].constructor.name, n: a[4] || (a[2].length - (a[3] || 0)) }];
    }
    if (/^uniform(Matrix)?[1-4](x[2-4])?[fiu]v$/.test(name)) { const m = /Matrix/.test(name); const i = m ? 2 : 1; if (V(a[i])) return [...a.slice(0, i), sliceView(a[i], a[i + 1], a[i + 2])]; }
    return a;
  };
  const rec = (name, args, ret) => {
    if (self.__capStop) return;
    args = norm(name, args); curName = name;
    let r = null; if (ret && typeof ret === 'object') r = idOf(ret); else if (typeof ret === 'number' && /^(getUniformBlockIndex|getAttribLocation|getFragDataLocation)$/.test(name)) r = ret;
    calls.push([name, args.map(enc), r]);
  };
  const wrapProto = (P, prefix) => {
    for (const n of Object.getOwnPropertyNames(P)) {
      const d = Object.getOwnPropertyDescriptor(P, n); if (!d || typeof d.value !== 'function' || n === 'constructor') continue;
      if (SKIP.test(n)) continue; const f = d.value;
      P[n] = function (...a) { const ret = f.apply(this, a); try { rec(prefix + n, a, ret); } catch (e) { calls.push(['__err', [String(e)], null]); } return ret; };
    }
  };
  wrapProto(WebGL2RenderingContext.prototype, '');
  const ge = WebGL2RenderingContext.prototype.getExtension; const wrapped = new Set();
  WebGL2RenderingContext.prototype.getExtension = function (name) {
    const x = ge.call(this, name);
    if (x && !wrapped.has(name)) { wrapped.add(name); const P = Object.getPrototypeOf(x); for (const n of Object.getOwnPropertyNames(P)) { const d = Object.getOwnPropertyDescriptor(P, n);
      if (!d || typeof d.value !== 'function' || n === 'constructor') continue; const f = d.value; P[n] = function (...a) { const ret = f.apply(this, a); try { rec('ext:' + name + ':' + n, a, ret); } catch (e) {} return ret; }; } }
    return x;
  };
  const gc = (self.OffscreenCanvas || {}).prototype?.getContext;
  if (gc) OffscreenCanvas.prototype.getContext = function (t, o) { const c = gc.call(this, t, o); if (t === 'webgl2' && c) calls.push(['__context', [this.width, this.height, JSON.stringify(o || {})], null]); return c; };
  const hc = (self.HTMLCanvasElement || {}).prototype?.getContext;
  if (hc) HTMLCanvasElement.prototype.getContext = function (t, o) { const c = hc.call(this, t, o); if (t === 'webgl2' && c) calls.push(['__context', [this.width, this.height, JSON.stringify(o || {})], null]); return c; };
  if (self.requestAnimationFrame) { const raf = self.requestAnimationFrame.bind(self); self.requestAnimationFrame = cb => raf(t => { if (!self.__capStop) calls.push(['__frame', [t], null]); return cb(t); }); }
  let dump = null;
  self.__capCount = () => [calls.length, blobBytes];
  self.__capDump = () => {
    self.__capStop = true;
    const head = new TextEncoder().encode(JSON.stringify({ calls, blobs: blobs.map(b => [b[0], b[1], b[2]]) }));
    dump = new Uint8Array(4 + head.byteLength + blobBytes); new DataView(dump.buffer).setUint32(0, head.byteLength, true); dump.set(head, 4);
    for (const b of blobs) dump.set(b[3], 4 + head.byteLength + b[0]);
    return dump.byteLength;
  };
  self.__capChunk = (i) => { const s = dump.subarray(i * 4194304, (i + 1) * 4194304); let str = ''; for (let k = 0; k < s.length; k += 32768) str += String.fromCharCode.apply(null, s.subarray(k, k + 32768)); return btoa(str); };
})();
