// WebGL2 sub-tests for the features Google Maps' vector renderer uses (see docs/MAPS-WEBGL.md).
// Each test draws into a small FBO, reads it back and compares with the expected image computed on the CPU.
// Results: window.__results = [{name, pass, info}], also printed. Run offscreen (headless) on the 890M and on SwiftShader.
'use strict';
const W = 64, H = 64;
const out = document.getElementById('out');
const results = []; window.__results = results; window.__done = false;
const cv = document.createElement('canvas'); cv.width = W; cv.height = H;
const gl = cv.getContext('webgl2', { antialias: false, preserveDrawingBuffer: true, stencil: true, depth: true });
function say(s, cls) { const d = document.createElement('div'); d.textContent = s; if (cls) d.className = cls; out.appendChild(d); }
function prog(vs, fs) {
  const p = gl.createProgram();
  for (const [t, s] of [[gl.VERTEX_SHADER, vs], [gl.FRAGMENT_SHADER, fs]]) {
    const sh = gl.createShader(t); gl.shaderSource(sh, '#version 300 es\nprecision highp float; precision highp int;\n' + s); gl.compileShader(sh);
    if (!gl.getShaderParameter(sh, gl.COMPILE_STATUS)) throw new Error('compile: ' + gl.getShaderInfoLog(sh));
    gl.attachShader(p, sh);
  }
  gl.linkProgram(p); if (!gl.getProgramParameter(p, gl.LINK_STATUS)) throw new Error('link: ' + gl.getProgramInfoLog(p));
  return p;
}
function fbo(opts = {}) {
  const f = gl.createFramebuffer(); gl.bindFramebuffer(gl.FRAMEBUFFER, f);
  const t = gl.createTexture(); gl.bindTexture(gl.TEXTURE_2D, t); gl.texStorage2D(gl.TEXTURE_2D, 1, gl.RGBA8, W, H);
  gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, t, 0);
  if (opts.ds) { const r = gl.createRenderbuffer(); gl.bindRenderbuffer(gl.RENDERBUFFER, r);
    gl.renderbufferStorage(gl.RENDERBUFFER, opts.ds, W, H);
    gl.framebufferRenderbuffer(gl.FRAMEBUFFER, opts.ds === gl.DEPTH_COMPONENT32F ? gl.DEPTH_ATTACHMENT : gl.DEPTH_STENCIL_ATTACHMENT, gl.RENDERBUFFER, r); }
  gl.viewport(0, 0, W, H); gl.clearColor(0, 0, 0, 1); gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT | gl.STENCIL_BUFFER_BIT);
  return f;
}
function read() { const px = new Uint8Array(W * H * 4); gl.readPixels(0, 0, W, H, gl.RGBA, gl.UNSIGNED_BYTE, px); return px; }
// expected: function (x,y) -> [r,g,b] 0..255. Compares pixel centres with tolerance 3; skips pixels where skip(x,y) is true.
function compare(px, exp, skip) {
  let bad = 0, first = '';
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    if (skip && skip(x, y)) continue;
    const e = exp(x, y), i = (y * W + x) * 4;
    if (Math.abs(px[i] - e[0]) > 3 || Math.abs(px[i + 1] - e[1]) > 3 || Math.abs(px[i + 2] - e[2]) > 3) {
      if (!bad) first = `(${x},${y}) got ${px[i]},${px[i + 1]},${px[i + 2]} want ${e.join(',')}`; bad++; }
  }
  return { pass: bad === 0, info: bad ? `${bad} px wrong, first ${first}` : 'ok' };
}
// 4x4 grid of 16x16 cells; cell colour for index i
const cellCol = i => [(i * 53 + 40) & 255, (i * 97 + 20) & 255, (i * 29 + 200) & 255];
const cellOf = (x, y) => (y >> 4) * 4 + (x >> 4);
const gridExp = (x, y) => cellCol(cellOf(x, y));
const cellRect = i => [((i & 3) * 16) / W * 2 - 1, ((i >> 2) * 16) / H * 2 - 1, 16 / W * 2, 16 / H * 2]; // x0,y0,w,h in NDC
const QUAD_VS_UNIT = `const vec2 Q[6] = vec2[6](vec2(0,0),vec2(1,0),vec2(0,1),vec2(0,1),vec2(1,0),vec2(1,1));`;
const tests = [];
const T = (name, fn) => tests.push([name, fn]);

// --- 1. UBO slices via bindBufferRange (Maps: 7709 bindBufferRange per load) ---
T('ubo_bindBufferRange_offsets', () => {
  const p = prog(`${QUAD_VS_UNIT} layout(std140) uniform U { vec4 rect; vec4 col; }; out vec4 c;
    void main(){ vec2 q=Q[gl_VertexID]; gl_Position=vec4(rect.xy+q*rect.zw,0,1); c=col; }`,
    `in vec4 c; out vec4 o; void main(){ o=c; }`);
  gl.uniformBlockBinding(p, gl.getUniformBlockIndex(p, 'U'), 0);
  const al = gl.getParameter(gl.UNIFORM_BUFFER_OFFSET_ALIGNMENT), stride = Math.max(al, 32);
  const data = new Float32Array(16 * stride / 4);
  for (let i = 0; i < 16; i++) { data.set(cellRect(i), i * stride / 4); data.set(cellCol(i).map(v => v / 255).concat([1]), i * stride / 4 + 4); }
  const b = gl.createBuffer(); gl.bindBuffer(gl.UNIFORM_BUFFER, b); gl.bufferData(gl.UNIFORM_BUFFER, data, gl.STATIC_DRAW);
  fbo(); gl.useProgram(p);
  for (let i = 0; i < 16; i++) { gl.bindBufferRange(gl.UNIFORM_BUFFER, 0, b, i * stride, 32); gl.drawArrays(gl.TRIANGLES, 0, 6); }
  return compare(read(), gridExp);
});
// --- 2. UBO rewritten between draws (bufferSubData at offset 0 before each draw: GL requires each draw to see its own data) ---
T('ubo_rewrite_between_draws', () => {
  const p = prog(`${QUAD_VS_UNIT} layout(std140) uniform U { vec4 rect; vec4 col; }; out vec4 c;
    void main(){ vec2 q=Q[gl_VertexID]; gl_Position=vec4(rect.xy+q*rect.zw,0,1); c=col; }`, `in vec4 c; out vec4 o; void main(){ o=c; }`);
  gl.uniformBlockBinding(p, gl.getUniformBlockIndex(p, 'U'), 0);
  const b = gl.createBuffer(); gl.bindBuffer(gl.UNIFORM_BUFFER, b); gl.bufferData(gl.UNIFORM_BUFFER, 32, gl.DYNAMIC_DRAW);
  gl.bindBufferBase(gl.UNIFORM_BUFFER, 0, b); fbo(); gl.useProgram(p);
  for (let i = 0; i < 16; i++) { gl.bufferSubData(gl.UNIFORM_BUFFER, 0, new Float32Array(cellRect(i).concat(cellCol(i).map(v => v / 255), [1]))); gl.drawArrays(gl.TRIANGLES, 0, 6); }
  return compare(read(), gridExp);
});
// --- 3. UBO re-specified with bufferData before each draw (Maps: 983 bufferData(UNIFORM_BUFFER)) ---
T('ubo_bufferData_each_draw', () => {
  const p = prog(`${QUAD_VS_UNIT} layout(std140) uniform U { vec4 rect; vec4 col; }; out vec4 c;
    void main(){ vec2 q=Q[gl_VertexID]; gl_Position=vec4(rect.xy+q*rect.zw,0,1); c=col; }`, `in vec4 c; out vec4 o; void main(){ o=c; }`);
  gl.uniformBlockBinding(p, gl.getUniformBlockIndex(p, 'U'), 0);
  const b = gl.createBuffer(); gl.bindBuffer(gl.UNIFORM_BUFFER, b); gl.bindBufferBase(gl.UNIFORM_BUFFER, 0, b); fbo(); gl.useProgram(p);
  for (let i = 0; i < 16; i++) { gl.bufferData(gl.UNIFORM_BUFFER, new Float32Array(cellRect(i).concat(cellCol(i).map(v => v / 255), [1])), gl.DYNAMIC_DRAW); gl.drawArrays(gl.TRIANGLES, 0, 6); }
  return compare(read(), gridExp);
});
// --- 4. instanced draw, per-instance data from gl_InstanceID + texelFetch on an RGBA32F texture ---
T('instanced_instanceID_texelFetch_rgba32f', () => {
  const p = prog(`${QUAD_VS_UNIT} uniform highp sampler2D D; out vec4 c;
    void main(){ vec4 r=texelFetch(D, ivec2(gl_InstanceID,0),0); vec4 col=texelFetch(D, ivec2(gl_InstanceID,1),0); vec2 q=Q[gl_VertexID];
      gl_Position=vec4(r.xy+q*r.zw,0,1); c=col; }`, `in vec4 c; out vec4 o; void main(){ o=c; }`);
  const t = gl.createTexture(); gl.bindTexture(gl.TEXTURE_2D, t); gl.texStorage2D(gl.TEXTURE_2D, 1, gl.RGBA32F, 16, 2);
  const d = new Float32Array(16 * 2 * 4); for (let i = 0; i < 16; i++) { d.set(cellRect(i), i * 4); d.set(cellCol(i).map(v => v / 255).concat([1]), 64 + i * 4); }
  gl.texSubImage2D(gl.TEXTURE_2D, 0, 0, 0, 16, 2, gl.RGBA, gl.FLOAT, d);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST); gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
  fbo(); gl.bindTexture(gl.TEXTURE_2D, t); gl.useProgram(p); gl.uniform1i(gl.getUniformLocation(p, 'D'), 0);
  const ib = gl.createBuffer(); gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, ib); gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, new Uint16Array([0, 1, 2, 3, 4, 5]), gl.STATIC_DRAW);
  gl.drawElementsInstanced(gl.TRIANGLES, 6, gl.UNSIGNED_SHORT, 0, 16);
  return compare(read(), gridExp);
});
// --- 5/6. constant (non-array) vertex attributes, float and integer, changed between draws (Maps: 912 vertexAttrib4f, 81 vertexAttribI4ui) ---
T('const_attrib_vertexAttrib4f', () => {
  const p = prog(`${QUAD_VS_UNIT} layout(location=0) in vec4 rect; layout(location=1) in vec4 col; out vec4 c;
    void main(){ vec2 q=Q[gl_VertexID]; gl_Position=vec4(rect.xy+q*rect.zw,0,1); c=col; }`, `in vec4 c; out vec4 o; void main(){ o=c; }`);
  const va = gl.createVertexArray(); gl.bindVertexArray(va); gl.disableVertexAttribArray(0); gl.disableVertexAttribArray(1);
  fbo(); gl.useProgram(p);
  for (let i = 0; i < 16; i++) { gl.vertexAttrib4fv(0, cellRect(i)); const c = cellCol(i); gl.vertexAttrib4f(1, c[0] / 255, c[1] / 255, c[2] / 255, 1); gl.drawArrays(gl.TRIANGLES, 0, 6); }
  gl.bindVertexArray(null); return compare(read(), gridExp);
});
T('const_attrib_vertexAttribI4ui', () => {
  const p = prog(`${QUAD_VS_UNIT} layout(location=0) in uvec4 cell; out vec4 c;
    void main(){ vec2 q=Q[gl_VertexID]; vec2 o=vec2(float(cell.x%4u),float(cell.x/4u))*0.5-1.0; gl_Position=vec4(o+q*0.5,0,1); c=vec4(vec3(cell.yzw)/255.0,1); }`,
    `in vec4 c; out vec4 o; void main(){ o=c; }`);
  const va = gl.createVertexArray(); gl.bindVertexArray(va); gl.disableVertexAttribArray(0);
  fbo(); gl.useProgram(p);
  for (let i = 0; i < 16; i++) { const c = cellCol(i); gl.vertexAttribI4ui(0, i, c[0], c[1], c[2]); gl.drawArrays(gl.TRIANGLES, 0, 6); }
  gl.bindVertexArray(null); return compare(read(), gridExp);
});
// --- 7/8. SHORT, non-normalised positions (size 2 and size 4) read as float (Maps: size2/size4 SHORT normalized=false) ---
for (const size of [2, 4]) T(`attrib_short${size}_unnormalized`, () => {
  const p = prog(`layout(location=0) in vec${size} pos; layout(location=1) in vec4 col; out vec4 c; uniform float S;
    void main(){ gl_Position=vec4(pos.xy*S-1.0,0,1); c=col; }`, `in vec4 c; out vec4 o; void main(){ o=c; }`);
  const pos = [], col = [];
  for (let i = 0; i < 16; i++) { const x0 = (i & 3) * 16, y0 = (i >> 2) * 16; const c = cellCol(i);
    for (const [qx, qy] of [[0, 0], [1, 0], [0, 1], [0, 1], [1, 0], [1, 1]]) { pos.push(x0 + qx * 16, y0 + qy * 16); if (size === 4) pos.push(7, 1); col.push(c[0] / 255, c[1] / 255, c[2] / 255, 1); } }
  const va = gl.createVertexArray(); gl.bindVertexArray(va);
  const pb = gl.createBuffer(); gl.bindBuffer(gl.ARRAY_BUFFER, pb); gl.bufferData(gl.ARRAY_BUFFER, new Int16Array(pos), gl.STATIC_DRAW);
  gl.enableVertexAttribArray(0); gl.vertexAttribPointer(0, size, gl.SHORT, false, 0, 0);
  const cb = gl.createBuffer(); gl.bindBuffer(gl.ARRAY_BUFFER, cb); gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(col), gl.STATIC_DRAW);
  gl.enableVertexAttribArray(1); gl.vertexAttribPointer(1, 4, gl.FLOAT, false, 0, 0);
  fbo(); gl.useProgram(p); gl.uniform1f(gl.getUniformLocation(p, 'S'), 2 / W); gl.drawArrays(gl.TRIANGLES, 0, 96);
  gl.bindVertexArray(null); return compare(read(), gridExp);
});
// --- 9. texStorage3D data textures of the formats Maps uses, texelFetch'd per instance ---
for (const [fmt, ifmt, type, mk, swz] of [
  ['RGBA16I', 'RGBA16I', 'SHORT', c => new Int16Array(c), 'isampler3D'],
  ['RGBA8', 'RGBA8', 'UNSIGNED_BYTE', c => new Uint8Array(c), 'sampler3D'],
  ['R16F_as_float', 'R16F', 'FLOAT', c => new Float32Array(c), 'sampler3D'],
  ['RGB10_A2', 'RGB10_A2', 'UNSIGNED_INT_2_10_10_10_REV', c => new Uint32Array(c), 'sampler3D'],
  ['RGBA32F', 'RGBA32F', 'FLOAT', c => new Float32Array(c), 'sampler3D']]) T(`texStorage3D_texelFetch_${fmt}`, () => {
  // 16 texels in a 4x2x2 volume; each texel encodes the cell colour; fragment fetches texel by cell index
  const n = 16, vals = [];
  for (let i = 0; i < n; i++) { const c = cellCol(i);
    if (fmt === 'RGBA16I') vals.push(c[0], c[1], c[2], 1);
    else if (fmt === 'RGBA8') vals.push(c[0], c[1], c[2], 255);
    else if (fmt === 'R16F_as_float') vals.push(c[0] / 255);
    else if (fmt === 'RGB10_A2') vals.push(((c[0] * 4) | ((c[1] * 4) << 10) | ((c[2] * 4) << 20) | (3 << 30)) >>> 0);
    else vals.push(c[0] / 255, c[1] / 255, c[2] / 255, 1); }
  const t = gl.createTexture(); gl.bindTexture(gl.TEXTURE_3D, t); gl.texStorage3D(gl.TEXTURE_3D, 1, gl[ifmt], 4, 2, 2);
  gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1);
  gl.texSubImage3D(gl.TEXTURE_3D, 0, 0, 0, 0, 4, 2, 2, fmt === 'RGBA16I' ? gl.RGBA_INTEGER : fmt === 'R16F_as_float' ? gl.RED : gl.RGBA, gl[type], mk(vals));
  gl.pixelStorei(gl.UNPACK_ALIGNMENT, 4);
  gl.texParameteri(gl.TEXTURE_3D, gl.TEXTURE_MIN_FILTER, gl.NEAREST); gl.texParameteri(gl.TEXTURE_3D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
  const isI = swz[0] === 'i';
  const p = prog(`${QUAD_VS_UNIT} void main(){ vec2 q=Q[gl_VertexID]; gl_Position=vec4(q*2.0-1.0,0,1); }`,
    `uniform highp ${swz} D; out vec4 o; void main(){ ivec2 f=ivec2(gl_FragCoord.xy)/16; int i=f.y*4+f.x; ivec3 t=ivec3(i%4,(i/4)%2,i/8);
      ${isI ? 'o=vec4(texelFetch(D,t,0))/255.0; o.a=1.0;' : fmt === 'R16F_as_float' ? 'o=vec4(texelFetch(D,t,0).r,0,0,1);' : 'o=vec4(texelFetch(D,t,0).rgb,1);'} }`);
  fbo(); gl.useProgram(p); gl.uniform1i(gl.getUniformLocation(p, 'D'), 0); gl.drawArrays(gl.TRIANGLES, 0, 6);
  return compare(read(), fmt === 'R16F_as_float' ? (x, y) => [cellCol(cellOf(x, y))[0], 0, 0] : gridExp);
});
// --- 10. element buffer byte offsets: one big index buffer, each cell drawn from its own offset (> 64 KiB for the later cells) ---
T('drawElementsInstanced_index_offsets_large', () => {
  const p = prog(`layout(location=0) in vec2 pos; layout(location=1) in vec4 col; out vec4 c; void main(){ gl_Position=vec4(pos,0,1); c=col; }`,
    `in vec4 c; out vec4 o; void main(){ o=c; }`);
  const verts = [], cols = []; for (let i = 0; i < 16; i++) { const r = cellRect(i), c = cellCol(i);
    for (const [qx, qy] of [[0, 0], [1, 0], [0, 1], [1, 1]]) { verts.push(r[0] + qx * r[2], r[1] + qy * r[3]); cols.push(c[0] / 255, c[1] / 255, c[2] / 255, 1); } }
  const va = gl.createVertexArray(); gl.bindVertexArray(va);
  const vb = gl.createBuffer(); gl.bindBuffer(gl.ARRAY_BUFFER, vb); gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(verts), gl.STATIC_DRAW); gl.enableVertexAttribArray(0); gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);
  const cb = gl.createBuffer(); gl.bindBuffer(gl.ARRAY_BUFFER, cb); gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(cols), gl.STATIC_DRAW); gl.enableVertexAttribArray(1); gl.vertexAttribPointer(1, 4, gl.FLOAT, false, 0, 0);
  const SPAN = 9000; const idx = new Uint16Array(SPAN * 16); // cell i's 6 indices at i*SPAN (byte offset i*18000)
  for (let i = 0; i < 16; i++) idx.set([0, 1, 2, 2, 1, 3].map(k => i * 4 + k), i * SPAN);
  const ib = gl.createBuffer(); gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, ib); gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, idx, gl.STATIC_DRAW);
  fbo(); gl.useProgram(p); for (let i = 0; i < 16; i++) gl.drawElementsInstanced(gl.TRIANGLES, 6, gl.UNSIGNED_SHORT, i * SPAN * 2, 1);
  gl.bindVertexArray(null); return compare(read(), gridExp);
});
// --- 11. index buffer updated with bufferSubData between draws (Maps: 101 bufferSubData(ELEMENT_ARRAY_BUFFER)) ---
T('index_bufferSubData_between_draws', () => {
  const p = prog(`layout(location=0) in vec2 pos; layout(location=1) in vec4 col; out vec4 c; void main(){ gl_Position=vec4(pos,0,1); c=col; }`, `in vec4 c; out vec4 o; void main(){ o=c; }`);
  const verts = [], cols = []; for (let i = 0; i < 16; i++) { const r = cellRect(i), c = cellCol(i);
    for (const [qx, qy] of [[0, 0], [1, 0], [0, 1], [1, 1]]) { verts.push(r[0] + qx * r[2], r[1] + qy * r[3]); cols.push(c[0] / 255, c[1] / 255, c[2] / 255, 1); } }
  const va = gl.createVertexArray(); gl.bindVertexArray(va);
  const vb = gl.createBuffer(); gl.bindBuffer(gl.ARRAY_BUFFER, vb); gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(verts), gl.STATIC_DRAW); gl.enableVertexAttribArray(0); gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);
  const cb = gl.createBuffer(); gl.bindBuffer(gl.ARRAY_BUFFER, cb); gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(cols), gl.STATIC_DRAW); gl.enableVertexAttribArray(1); gl.vertexAttribPointer(1, 4, gl.FLOAT, false, 0, 0);
  const ib = gl.createBuffer(); gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, ib); gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, 12, gl.DYNAMIC_DRAW);
  fbo(); gl.useProgram(p);
  for (let i = 0; i < 16; i++) { gl.bufferSubData(gl.ELEMENT_ARRAY_BUFFER, 0, new Uint16Array([0, 1, 2, 2, 1, 3].map(k => i * 4 + k))); gl.drawElementsInstanced(gl.TRIANGLES, 6, gl.UNSIGNED_SHORT, 0, 1); }
  gl.bindVertexArray(null); return compare(read(), gridExp);
});
// --- 12. vertex buffer offsets: many VAOs into one big shared vertex buffer at large offsets ---
T('vao_attrib_offsets_large', () => {
  const p = prog(`layout(location=0) in vec2 pos; uniform vec4 col; out vec4 c; void main(){ gl_Position=vec4(pos,0,1); c=col; }`, `in vec4 c; out vec4 o; void main(){ o=c; }`);
  const SPAN = 70000; const big = new Float32Array(SPAN * 16 / 4 + 64);
  for (let i = 0; i < 16; i++) { const r = cellRect(i); big.set([r[0], r[1], r[0] + r[2], r[1], r[0], r[1] + r[3], r[0], r[1] + r[3], r[0] + r[2], r[1], r[0] + r[2], r[1] + r[3]], i * SPAN / 4); }
  const vb = gl.createBuffer(); gl.bindBuffer(gl.ARRAY_BUFFER, vb); gl.bufferData(gl.ARRAY_BUFFER, big, gl.STATIC_DRAW);
  const vaos = []; for (let i = 0; i < 16; i++) { const va = gl.createVertexArray(); gl.bindVertexArray(va); gl.enableVertexAttribArray(0); gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 8, i * SPAN); vaos.push(va); }
  fbo(); gl.useProgram(p); const ul = gl.getUniformLocation(p, 'col');
  for (let i = 0; i < 16; i++) { gl.bindVertexArray(vaos[i]); const c = cellCol(i); gl.uniform4f(ul, c[0] / 255, c[1] / 255, c[2] / 255, 1); gl.drawArrays(gl.TRIANGLES, 0, 6); }
  gl.bindVertexArray(null); return compare(read(), gridExp);
});
// --- 13. stencil-clipped tiles: write ref i per cell, then full-screen draws with EQUAL i (Maps: 3476 stencilFuncSeparate) ---
T('stencil_clip_tiles_funcSeparate', () => {
  const p = prog(`${QUAD_VS_UNIT} uniform vec4 rect; void main(){ vec2 q=Q[gl_VertexID]; gl_Position=vec4(rect.xy+q*rect.zw,0,1); }`,
    `uniform vec4 col; out vec4 o; void main(){ o=col; }`);
  fbo({ ds: gl.DEPTH24_STENCIL8 }); gl.useProgram(p); const ur = gl.getUniformLocation(p, 'rect'), uc = gl.getUniformLocation(p, 'col');
  gl.enable(gl.STENCIL_TEST); gl.colorMask(false, false, false, false); gl.stencilOpSeparate(gl.FRONT_AND_BACK, gl.KEEP, gl.KEEP, gl.REPLACE);
  for (let i = 0; i < 16; i++) { gl.stencilFuncSeparate(gl.FRONT_AND_BACK, gl.ALWAYS, i + 1, 0xff); gl.uniform4fv(ur, cellRect(i)); gl.drawArrays(gl.TRIANGLES, 0, 6); }
  gl.colorMask(true, true, true, true); gl.stencilOpSeparate(gl.FRONT_AND_BACK, gl.KEEP, gl.KEEP, gl.KEEP);
  for (let i = 0; i < 16; i++) { gl.stencilFuncSeparate(gl.FRONT, gl.EQUAL, i + 1, 0xff); gl.stencilFuncSeparate(gl.BACK, gl.EQUAL, i + 1, 0xff);
    gl.uniform4fv(ur, [-1, -1, 2, 2]); const c = cellCol(i); gl.uniform4f(uc, c[0] / 255, c[1] / 255, c[2] / 255, 1); gl.drawArrays(gl.TRIANGLES, 0, 6); }
  gl.disable(gl.STENCIL_TEST); return compare(read(), gridExp);
});
// --- 14. depth32F + GEQUAL (reversed-Z style with clearBufferfi) ---
T('depth32f_gequal_clearBufferfi', () => {
  const p = prog(`${QUAD_VS_UNIT} uniform vec4 rect; uniform float z; void main(){ vec2 q=Q[gl_VertexID]; gl_Position=vec4(rect.xy+q*rect.zw,z,1); }`,
    `uniform vec4 col; out vec4 o; void main(){ o=col; }`);
  fbo({ ds: gl.DEPTH32F_STENCIL8 }); gl.useProgram(p); gl.clearBufferfi(gl.DEPTH_STENCIL, 0, 0.0, 0);
  gl.enable(gl.DEPTH_TEST); gl.depthFunc(gl.GEQUAL);
  const ur = gl.getUniformLocation(p, 'rect'), uc = gl.getUniformLocation(p, 'col'), uz = gl.getUniformLocation(p, 'z');
  // full-screen far (z=-0.5 -> depth .25) in white, then each cell nearer (z=0.5 -> .75) in its colour, then a full-screen farther red that must lose
  gl.uniform4fv(ur, [-1, -1, 2, 2]); gl.uniform1f(uz, -0.5); gl.uniform4f(uc, 1, 1, 1, 1); gl.drawArrays(gl.TRIANGLES, 0, 6);
  for (let i = 0; i < 16; i++) { gl.uniform4fv(ur, cellRect(i)); gl.uniform1f(uz, 0.5); const c = cellCol(i); gl.uniform4f(uc, c[0] / 255, c[1] / 255, c[2] / 255, 1); gl.drawArrays(gl.TRIANGLES, 0, 6); }
  gl.uniform4fv(ur, [-1, -1, 2, 2]); gl.uniform1f(uz, 0.0); gl.uniform4f(uc, 1, 0, 0, 1); gl.drawArrays(gl.TRIANGLES, 0, 6);
  gl.disable(gl.DEPTH_TEST); return compare(read(), gridExp);
});
// --- 15. many draws per frame in one pass: 4096 tiny instanced draws, each with its own UBO slice (Maps-like volume) ---
T('ubo_slices_4096_draws', () => {
  const p = prog(`${QUAD_VS_UNIT} layout(std140) uniform U { vec4 rect; vec4 col; }; out vec4 c;
    void main(){ vec2 q=Q[gl_VertexID]; gl_Position=vec4(rect.xy+q*rect.zw,0,1); c=col; }`, `in vec4 c; out vec4 o; void main(){ o=c; }`);
  gl.uniformBlockBinding(p, gl.getUniformBlockIndex(p, 'U'), 0);
  const al = gl.getParameter(gl.UNIFORM_BUFFER_OFFSET_ALIGNMENT), stride = Math.max(al, 32), N = 4096;
  const data = new Float32Array(N * stride / 4);
  for (let k = 0; k < N; k++) { const x = k % 64, y = (k / 64) | 0, i = cellOf(x, y); data.set([x / W * 2 - 1, y / H * 2 - 1, 2 / W, 2 / H], k * stride / 4); data.set(cellCol(i).map(v => v / 255).concat([1]), k * stride / 4 + 4); }
  const b = gl.createBuffer(); gl.bindBuffer(gl.UNIFORM_BUFFER, b); gl.bufferData(gl.UNIFORM_BUFFER, data, gl.STATIC_DRAW);
  fbo(); gl.useProgram(p);
  for (let k = 0; k < N; k++) { gl.bindBufferRange(gl.UNIFORM_BUFFER, 0, b, k * stride, 32); gl.drawArrays(gl.TRIANGLES, 0, 6); }
  return compare(read(), gridExp);
});
// --- 16. readPixels into a PIXEL_PACK_BUFFER + fence + getBufferSubData (Maps' async picking readback) ---
T('pbo_readPixels_fence_getBufferSubData', () => {
  const p = prog(`${QUAD_VS_UNIT} uniform vec4 rect; void main(){ vec2 q=Q[gl_VertexID]; gl_Position=vec4(rect.xy+q*rect.zw,0,1); }`, `uniform vec4 col; out vec4 o; void main(){ o=col; }`);
  fbo(); gl.useProgram(p); const ur = gl.getUniformLocation(p, 'rect'), uc = gl.getUniformLocation(p, 'col');
  for (let i = 0; i < 16; i++) { gl.uniform4fv(ur, cellRect(i)); const c = cellCol(i); gl.uniform4f(uc, c[0] / 255, c[1] / 255, c[2] / 255, 1); gl.drawArrays(gl.TRIANGLES, 0, 6); }
  const pb = gl.createBuffer(); gl.bindBuffer(gl.PIXEL_PACK_BUFFER, pb); gl.bufferData(gl.PIXEL_PACK_BUFFER, W * H * 4, gl.STREAM_READ);
  gl.readPixels(0, 0, W, H, gl.RGBA, gl.UNSIGNED_BYTE, 0);
  const s = gl.fenceSync(gl.SYNC_GPU_COMMANDS_COMPLETE, 0); gl.flush();
  let st, n = 0; do { st = gl.clientWaitSync(s, 0, 0); n++; } while (st === gl.TIMEOUT_EXPIRED && n < 2000000);
  gl.deleteSync(s); const px = new Uint8Array(W * H * 4); gl.getBufferSubData(gl.PIXEL_PACK_BUFFER, 0, px); gl.bindBuffer(gl.PIXEL_PACK_BUFFER, null);
  return compare(px, gridExp);
});
// --- 17. instanced draw with an instance-stepped attribute (divisor 1) and one with divisor 2 ---
for (const div of [1, 2]) T(`instanced_divisor_${div}`, () => {
  const p = prog(`${QUAD_VS_UNIT} layout(location=0) in vec4 rect; layout(location=1) in vec4 col; out vec4 c;
    void main(){ vec2 q=Q[gl_VertexID]; gl_Position=vec4(rect.xy+q*rect.zw,0,1); c=col; }`, `in vec4 c; out vec4 o; void main(){ o=c; }`);
  // 16*div instances; instance k draws cell (k / div) when divisor = div
  const rects = [], cols = []; for (let i = 0; i < 16; i++) { rects.push(...cellRect(i)); cols.push(...cellCol(i).map(v => v / 255), 1); }
  const va = gl.createVertexArray(); gl.bindVertexArray(va);
  const rb = gl.createBuffer(); gl.bindBuffer(gl.ARRAY_BUFFER, rb); gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(rects), gl.STATIC_DRAW); gl.enableVertexAttribArray(0); gl.vertexAttribPointer(0, 4, gl.FLOAT, false, 0, 0); gl.vertexAttribDivisor(0, div);
  const cb = gl.createBuffer(); gl.bindBuffer(gl.ARRAY_BUFFER, cb); gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(cols), gl.STATIC_DRAW); gl.enableVertexAttribArray(1); gl.vertexAttribPointer(1, 4, gl.FLOAT, false, 0, 0); gl.vertexAttribDivisor(1, div);
  fbo(); gl.useProgram(p); gl.drawArraysInstanced(gl.TRIANGLES, 0, 6, 16 * div);
  gl.bindVertexArray(null); return compare(read(), gridExp);
});
// --- 18. large render target (Maps at 2x: 2560x1514 canvas, 3584x2048 helper) - draw cells near the far corner ---
T('large_target_3584x2048_far_corner', () => {
  const BW = 3584, BH = 2048;
  const f = gl.createFramebuffer(); gl.bindFramebuffer(gl.FRAMEBUFFER, f);
  const t = gl.createTexture(); gl.bindTexture(gl.TEXTURE_2D, t); gl.texStorage2D(gl.TEXTURE_2D, 1, gl.RGBA8, BW, BH);
  gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, t, 0);
  gl.viewport(0, 0, BW, BH); gl.clearColor(0, 0, 0, 1); gl.clear(gl.COLOR_BUFFER_BIT);
  const p = prog(`${QUAD_VS_UNIT} uniform vec4 rect; void main(){ vec2 q=Q[gl_VertexID]; gl_Position=vec4(rect.xy+q*rect.zw,0,1); }`, `uniform vec4 col; out vec4 o; void main(){ o=col; }`);
  gl.useProgram(p); const ur = gl.getUniformLocation(p, 'rect'), uc = gl.getUniformLocation(p, 'col');
  const X0 = BW - W, Y0 = BH - H;
  for (let i = 0; i < 16; i++) { const px = X0 + (i & 3) * 16, py = Y0 + (i >> 2) * 16;
    gl.uniform4fv(ur, [px / BW * 2 - 1, py / BH * 2 - 1, 16 / BW * 2, 16 / BH * 2]); const c = cellCol(i); gl.uniform4f(uc, c[0] / 255, c[1] / 255, c[2] / 255, 1); gl.drawArrays(gl.TRIANGLES, 0, 6); }
  const px = new Uint8Array(W * H * 4); gl.readPixels(X0, Y0, W, H, gl.RGBA, gl.UNSIGNED_BYTE, px);
  gl.viewport(0, 0, W, H); return compare(px, gridExp);
});

// --- 19-21. CPU write after flush while the GPU may still read the old contents (cross-command-buffer hazard).
// Frame A draws a slow pass that reads buffer/texture X, gl.flush() commits it; then X is overwritten (bufferSubData /
// texSubImage) and frame B draws. Frame A's result must still show the OLD contents. ANGLE writes in place only when
// the Metal driver says the command buffer that used X has completed (addCompletedHandler / status); an early answer
// lets the CPU write race the GPU read.
const SLOW = 4000; // fragment-loop iterations in the slow pass (bounded: 256x256 px)
const SW = 256, SH = 256;
function slowTarget() { const f = gl.createFramebuffer(); gl.bindFramebuffer(gl.FRAMEBUFFER, f); const t = gl.createTexture(); gl.bindTexture(gl.TEXTURE_2D, t);
  gl.texStorage2D(gl.TEXTURE_2D, 1, gl.RGBA8, SW, SH); gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, t, 0);
  gl.viewport(0, 0, SW, SH); gl.clearColor(0, 0, 0, 1); gl.clear(gl.COLOR_BUFFER_BIT); return f; }
function readSlow(f) { gl.bindFramebuffer(gl.FRAMEBUFFER, f); const px = new Uint8Array(SW * SH * 4); gl.readPixels(0, 0, SW, SH, gl.RGBA, gl.UNSIGNED_BYTE, px); return px; }
function checkFlat(px, want) { let bad = 0, first = ''; for (let i = 0; i < SW * SH; i++) { const o = i * 4;
  if (Math.abs(px[o] - want[0]) > 3 || Math.abs(px[o + 1] - want[1]) > 3 || Math.abs(px[o + 2] - want[2]) > 3) { if (!bad) first = `px ${i % SW},${(i / SW) | 0} got ${px[o]},${px[o + 1]},${px[o + 2]} want ${want}`; bad++; } }
  return { pass: !bad, info: bad ? `${bad} px wrong, first ${first}` : 'ok' }; }
const SLOW_FS = `uniform float k; out vec4 o; in vec4 c; void main(){ float a=0.0; for(int i=0;i<${SLOW};i++){ a+=sin(a+float(i)*k+gl_FragCoord.x); } o=vec4(c.rgb + a*1e-30, 1); }`;
for (const kind of ['vertex', 'uniform', 'index']) T(`cross_flush_rewrite_${kind}_buffer`, () => {
  const p = prog(kind === 'uniform'
    ? `${QUAD_VS_UNIT} layout(std140) uniform U { vec4 col; }; out vec4 c; void main(){ vec2 q=Q[gl_VertexID]; gl_Position=vec4(q*2.0-1.0,0,1); c=col; }`
    : `layout(location=0) in vec2 pos; layout(location=1) in vec4 col; out vec4 c; void main(){ gl_Position=vec4(pos,0,1); c=col; }`, SLOW_FS);
  gl.useProgram(p); gl.uniform1f(gl.getUniformLocation(p, 'k'), 0.001);
  const A = [0.2, 0.6, 1.0], B = [1.0, 0.4, 0.0];
  const va = gl.createVertexArray(); gl.bindVertexArray(va); let buf;
  const quadCol = c => { const a = []; for (let i = 0; i < 4; i++) a.push(...c, 1); return new Float32Array(a); };
  if (kind === 'uniform') { gl.uniformBlockBinding(p, gl.getUniformBlockIndex(p, 'U'), 0); buf = gl.createBuffer(); gl.bindBuffer(gl.UNIFORM_BUFFER, buf); gl.bufferData(gl.UNIFORM_BUFFER, new Float32Array([...A, 1]), gl.DYNAMIC_DRAW); gl.bindBufferBase(gl.UNIFORM_BUFFER, 0, buf); }
  else {
    const vb = gl.createBuffer(); gl.bindBuffer(gl.ARRAY_BUFFER, vb); gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1, 5, 5, 6, 5, 5, 6, 6, 6]), gl.STATIC_DRAW);
    gl.enableVertexAttribArray(0); gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);
    buf = gl.createBuffer(); gl.bindBuffer(gl.ARRAY_BUFFER, buf); gl.bufferData(gl.ARRAY_BUFFER, kind === 'vertex' ? quadCol(A) : new Float32Array([...quadCol(A), ...quadCol(B)]), gl.DYNAMIC_DRAW);
    gl.enableVertexAttribArray(1); gl.vertexAttribPointer(1, 4, gl.FLOAT, false, 0, 0);
    const ib = gl.createBuffer(); gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, ib); gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, new Uint16Array([0, 1, 2, 2, 1, 3]), gl.DYNAMIC_DRAW); if (kind === 'index') buf = ib;
  }
  let res = { pass: true, info: 'ok' };
  for (let rep = 0; rep < 6 && res.pass; rep++) {
    // reset to A
    if (kind === 'uniform') gl.bufferSubData(gl.UNIFORM_BUFFER, 0, new Float32Array([...A, 1]));
    else if (kind === 'vertex') { gl.bindBuffer(gl.ARRAY_BUFFER, buf); gl.bufferSubData(gl.ARRAY_BUFFER, 0, quadCol(A)); }
    else gl.bufferSubData(gl.ELEMENT_ARRAY_BUFFER, 0, new Uint16Array([0, 1, 2, 2, 1, 3]));
    const s0 = gl.fenceSync(gl.SYNC_GPU_COMMANDS_COMPLETE, 0); gl.flush(); let n = 0; while (gl.clientWaitSync(s0, 0, 0) === gl.TIMEOUT_EXPIRED && n++ < 5e6); gl.deleteSync(s0);
    const draw = () => kind === 'uniform' ? gl.drawArrays(gl.TRIANGLES, 0, 6) : gl.drawElements(gl.TRIANGLES, 6, gl.UNSIGNED_SHORT, 0);
    const t0 = performance.now(); const fa = slowTarget(); draw(); gl.flush();      // frame A committed, GPU busy
    // overwrite X with B (the index case points the indices at vertices 4..7, whose colour is B and position off-screen)
    if (kind === 'uniform') gl.bufferSubData(gl.UNIFORM_BUFFER, 0, new Float32Array([...B, 1]));
    else if (kind === 'vertex') gl.bufferSubData(gl.ARRAY_BUFFER, 0, quadCol(B));
    else gl.bufferSubData(gl.ELEMENT_ARRAY_BUFFER, 0, new Uint16Array([4, 5, 6, 6, 5, 7]));
    const fb = slowTarget(); draw(); gl.flush();
    const r = checkFlat(readSlow(fa), A.map(v => Math.round(v * 255))); window.__slowMs = (performance.now() - t0).toFixed(1);
    if (!r.pass) res = { pass: false, info: `rep ${rep}: frame A saw the later write: ${r.info}` };
  }
  gl.bindVertexArray(null); gl.viewport(0, 0, W, H); if (res.pass) res.info = `ok (two slow passes + readback ${window.__slowMs} ms)`; return res;
});
T('cross_flush_rewrite_texture', () => {
  const p = prog(`${QUAD_VS_UNIT} out vec4 c; void main(){ vec2 q=Q[gl_VertexID]; gl_Position=vec4(q*2.0-1.0,0,1); c=vec4(0); }`,
    `uniform highp sampler2D D; uniform float k; out vec4 o; in vec4 c; void main(){ float a=0.0; for(int i=0;i<${SLOW};i++){ a+=sin(a+float(i)*k+gl_FragCoord.x); } o=vec4(texelFetch(D,ivec2(0),0).rgb + a*1e-30, 1); }`);
  const A = [51, 153, 255], B = [255, 102, 0];
  const t = gl.createTexture(); gl.activeTexture(gl.TEXTURE1); gl.bindTexture(gl.TEXTURE_2D, t); gl.texStorage2D(gl.TEXTURE_2D, 1, gl.RGBA8, 1, 1);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST); gl.activeTexture(gl.TEXTURE0);
  gl.useProgram(p); gl.uniform1i(gl.getUniformLocation(p, 'D'), 1); gl.uniform1f(gl.getUniformLocation(p, 'k'), 0.001);
  let res = { pass: true, info: 'ok' };
  for (let rep = 0; rep < 6 && res.pass; rep++) {
    gl.activeTexture(gl.TEXTURE1); gl.texSubImage2D(gl.TEXTURE_2D, 0, 0, 0, 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, new Uint8Array([...A, 255])); gl.activeTexture(gl.TEXTURE0);
    const s0 = gl.fenceSync(gl.SYNC_GPU_COMMANDS_COMPLETE, 0); gl.flush(); let n = 0; while (gl.clientWaitSync(s0, 0, 0) === gl.TIMEOUT_EXPIRED && n++ < 5e6); gl.deleteSync(s0);
    const fa = slowTarget(); gl.drawArrays(gl.TRIANGLES, 0, 6); gl.flush();
    gl.activeTexture(gl.TEXTURE1); gl.texSubImage2D(gl.TEXTURE_2D, 0, 0, 0, 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, new Uint8Array([...B, 255])); gl.activeTexture(gl.TEXTURE0);
    const fb = slowTarget(); gl.drawArrays(gl.TRIANGLES, 0, 6); gl.flush();
    const r = checkFlat(readSlow(fa), A);
    if (!r.pass) res = { pass: false, info: `rep ${rep}: frame A saw the later write: ${r.info}` };
  }
  gl.viewport(0, 0, W, H); return res;
});

// --- 23. async readback after a slow pass: readPixels into a PIXEL_PACK_BUFFER, fenceSync, poll clientWaitSync(0) across
// tasks (as Maps does), then getBufferSubData. The fence may only signal after the slow pass and the copy are done.
T('pbo_fence_after_slow_pass', async () => {
  const p = prog(`${QUAD_VS_UNIT} out vec4 c; uniform vec4 col; void main(){ vec2 q=Q[gl_VertexID]; gl_Position=vec4(q*2.0-1.0,0,1); c=col; }`, SLOW_FS);
  gl.useProgram(p); gl.uniform1f(gl.getUniformLocation(p, 'k'), 0.001);
  const pb = gl.createBuffer(); gl.bindBuffer(gl.PIXEL_PACK_BUFFER, pb); gl.bufferData(gl.PIXEL_PACK_BUFFER, SW * SH * 4, gl.STREAM_READ); gl.bindBuffer(gl.PIXEL_PACK_BUFFER, null);
  let res = { pass: true, info: '' }; const polls = [];
  for (let rep = 0; rep < 8 && res.pass; rep++) {
    const want = [(rep * 37 + 20) & 255, (rep * 91 + 60) & 255, 200];
    const f = slowTarget(); gl.uniform4f(gl.getUniformLocation(p, 'col'), want[0] / 255, want[1] / 255, want[2] / 255, 1); gl.drawArrays(gl.TRIANGLES, 0, 6);
    gl.bindBuffer(gl.PIXEL_PACK_BUFFER, pb); gl.readPixels(0, 0, SW, SH, gl.RGBA, gl.UNSIGNED_BYTE, 0); gl.bindBuffer(gl.PIXEL_PACK_BUFFER, null);
    const s = gl.fenceSync(gl.SYNC_GPU_COMMANDS_COMPLETE, 0); gl.flush();
    let n = 0; while (gl.clientWaitSync(s, 0, 0) === gl.TIMEOUT_EXPIRED && n < 2000) { n++; await new Promise(r => setTimeout(r, 1)); }
    polls.push(n); gl.deleteSync(s);
    const px = new Uint8Array(SW * SH * 4); gl.bindBuffer(gl.PIXEL_PACK_BUFFER, pb); gl.getBufferSubData(gl.PIXEL_PACK_BUFFER, 0, px); gl.bindBuffer(gl.PIXEL_PACK_BUFFER, null);
    const r = checkFlat(px, want); if (!r.pass) res = { pass: false, info: `rep ${rep} (fence signalled after ${n} polls): ${r.info}` };
  }
  gl.viewport(0, 0, W, H); if (res.pass) res.info = `ok (polls per fence ${polls.join(',')})`; return res;
});

// --- 24-26. Vertex-stage texture reads (Maps/Filament road shader: IsPresent() = textureLod(styleProperties) in the VERTEX
// shader; a zero read collapses the road to vec4(0)). Style texture RGBA8, sampler object, texSubImage2D updates.
function vsPresenceTest({ useSampler, frames, rowsPerUpdate, lodFetch }) {
  return async () => {
    const TW = 16, TH = 4;  // style texture: texel (i, 0) .x > 0.01 means cell i is present; texel (i,1).rgb = colour
    const p = prog(`${QUAD_VS_UNIT} uniform mediump sampler2D S; out vec4 c;
      void main(){ int i=gl_InstanceID; vec2 sz=vec2(${TW}.0, ${TH}.0);
        ${lodFetch ? 'float pres=textureLod(S, (vec2(float(i),0.0)+0.5)/sz, 0.0).x; vec4 col=textureLod(S, (vec2(float(i),1.0)+0.5)/sz, 0.0);'
                   : 'float pres=texelFetch(S, ivec2(i,0), 0).x; vec4 col=texelFetch(S, ivec2(i,1), 0);'}
        vec2 o=vec2(float(i%4),float(i/4))*0.5-1.0; vec2 q=Q[gl_VertexID];
        gl_Position = pres>0.01 ? vec4(o+q*0.5,0,1) : vec4(0.0); c=vec4(col.rgb,1); }`, `in vec4 c; out vec4 o; void main(){ o=c; }`);
    const t = gl.createTexture(); gl.activeTexture(gl.TEXTURE2); gl.bindTexture(gl.TEXTURE_2D, t); gl.texStorage2D(gl.TEXTURE_2D, 1, gl.RGBA8, TW, TH);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR); gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR); // overridden by the sampler when used
    let smp = null; if (useSampler) { smp = gl.createSampler(); gl.samplerParameteri(smp, gl.TEXTURE_MIN_FILTER, gl.NEAREST); gl.samplerParameteri(smp, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
      gl.samplerParameteri(smp, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE); gl.samplerParameteri(smp, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE); gl.bindSampler(2, smp); }
    else { gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST); gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST); }
    gl.activeTexture(gl.TEXTURE0);
    let res = { pass: true, info: 'ok' };
    for (let fr = 0; fr < frames && res.pass; fr++) {
      // frame fr: cells with (i + fr) % 3 != 0 are present, colour shifts with the frame
      const present = i => (i + fr) % 3 !== 0, colf = i => cellCol((i + fr * 5) & 15);
      const data = new Uint8Array(TW * TH * 4);
      for (let i = 0; i < 16; i++) { data.set([present(i) ? 255 : 0, 0, 0, 255], i * 4); data.set([...colf(i), 255], (TW + i) * 4); }
      gl.activeTexture(gl.TEXTURE2);
      if (rowsPerUpdate === 1) { for (let r = 0; r < 2; r++) gl.texSubImage2D(gl.TEXTURE_2D, 0, 0, r, TW, 1, gl.RGBA, gl.UNSIGNED_BYTE, data.subarray(r * TW * 4, (r + 1) * TW * 4)); }
      else gl.texSubImage2D(gl.TEXTURE_2D, 0, 0, 0, TW, TH, gl.RGBA, gl.UNSIGNED_BYTE, data);
      gl.activeTexture(gl.TEXTURE0);
      fbo(); gl.useProgram(p); gl.uniform1i(gl.getUniformLocation(p, 'S'), 2);
      gl.drawArraysInstanced(gl.TRIANGLES, 0, 6, 16);
      const r = compare(read(), (x, y) => { const i = cellOf(x, y); return present(i) ? colf(i) : [0, 0, 0]; });
      if (!r.pass) res = { pass: false, info: `frame ${fr}: ${r.info}` };
      gl.bindFramebuffer(gl.FRAMEBUFFER, null); await new Promise(r => requestAnimationFrame(r));
    }
    if (smp) gl.bindSampler(2, null); return res;
  };
}
T('vs_texelFetch_style_texture_1frame', vsPresenceTest({ useSampler: false, frames: 1, rowsPerUpdate: 0, lodFetch: false }));
T('vs_textureLod_style_texture_1frame', vsPresenceTest({ useSampler: false, frames: 1, rowsPerUpdate: 0, lodFetch: true }));
T('vs_textureLod_sampler_object_1frame', vsPresenceTest({ useSampler: true, frames: 1, rowsPerUpdate: 0, lodFetch: true }));
T('vs_textureLod_sampler_object_texSubImage_rows_12frames', vsPresenceTest({ useSampler: true, frames: 12, rowsPerUpdate: 1, lodFetch: true }));
T('vs_texelFetch_texSubImage_12frames', vsPresenceTest({ useSampler: false, frames: 12, rowsPerUpdate: 0, lodFetch: false }));

// --- 29-31. UNSIGNED_SHORT index offsets that are 2 mod 4 (Metal needs 4-byte aligned index buffer offsets, so ANGLE
// re-packs these draws). Maps' line material draws at offsets 414, 438, 498 ... in one shared index buffer.
for (const [tag, off0, inst] of [['unaligned_2mod4', 2, 1], ['unaligned_2mod4_instanced', 2, 3], ['aligned_control', 0, 1]]) T(`index_offset_${tag}`, () => {
  const p = prog(`layout(location=0) in vec2 pos; layout(location=1) in vec4 col; out vec4 c; void main(){ gl_Position=vec4(pos,0,1); c=col; }`, `in vec4 c; out vec4 o; void main(){ o=c; }`);
  const verts = [], cols = []; for (let i = 0; i < 16; i++) { const r = cellRect(i), c = cellCol(i);
    for (const [qx, qy] of [[0, 0], [1, 0], [0, 1], [1, 1]]) { verts.push(r[0] + qx * r[2], r[1] + qy * r[3]); cols.push(c[0] / 255, c[1] / 255, c[2] / 255, 1); } }
  const va = gl.createVertexArray(); gl.bindVertexArray(va);
  const vb = gl.createBuffer(); gl.bindBuffer(gl.ARRAY_BUFFER, vb); gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(verts), gl.STATIC_DRAW); gl.enableVertexAttribArray(0); gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);
  const cb = gl.createBuffer(); gl.bindBuffer(gl.ARRAY_BUFFER, cb); gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(cols), gl.STATIC_DRAW); gl.enableVertexAttribArray(1); gl.vertexAttribPointer(1, 4, gl.FLOAT, false, 0, 0);
  // cell i's 6 indices start at element 1 + 7*i (byte offset 2 + 14*i: alternates 2 and 0 mod 4) or at 8*i (aligned)
  const idx = new Uint16Array(8 * 16 + 8); const offs = [];
  for (let i = 0; i < 16; i++) { const e = off0 ? 1 + 7 * i + (i & 1 ? 0 : 0) : 8 * i; idx.set([0, 1, 2, 2, 1, 3].map(k => i * 4 + k), e); offs.push(e * 2); }
  const ib = gl.createBuffer(); gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, ib); gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, idx, gl.STATIC_DRAW);
  fbo(); gl.useProgram(p); for (let i = 0; i < 16; i++) gl.drawElementsInstanced(gl.TRIANGLES, 6, gl.UNSIGNED_SHORT, offs[i], inst);
  gl.bindVertexArray(null); const r = compare(read(), gridExp); r.info += ` (byte offsets mod 4: ${offs.map(o => o % 4).join('')})`; return r;
});

(async () => {
  if (!gl) { say('no webgl2'); window.__done = true; return; }
  const e = gl.getExtension('WEBGL_debug_renderer_info');
  say('renderer: ' + (e ? gl.getParameter(e.UNMASKED_RENDERER_WEBGL) : gl.getParameter(gl.RENDERER)));
  const only = new URLSearchParams(location.search).get('only');
  for (const [name, fn] of tests) {
    if (only && !name.includes(only)) continue;
    let r; try { r = await fn(); const err = gl.getError(); if (err) r = { pass: false, info: r.info + ` glError 0x${err.toString(16)}` }; }
    catch (ex) { r = { pass: false, info: 'exception ' + ex.message }; }
    results.push({ name, ...r }); say(`${r.pass ? 'PASS' : 'FAIL'} ${name}: ${r.info}`, r.pass ? 'PASS' : 'FAIL');
    gl.bindFramebuffer(gl.FRAMEBUFFER, null); await new Promise(res => setTimeout(res, 0));
  }
  say(`${results.filter(r => r.pass).length}/${results.length} PASS`); window.__done = true;
})();
