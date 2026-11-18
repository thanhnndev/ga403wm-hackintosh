// node trace-info.mjs <trace.bin> : framebuffers with their attachments (texture/renderbuffer format, size, samples)
import fs from 'fs';
const buf = fs.readFileSync(process.argv[2]); const hl = buf.readUInt32LE(0); const { calls } = JSON.parse(buf.subarray(4, 4 + hl).toString());
const G = { 32856: 'RGBA8', 35907: 'SRGB8_ALPHA8', 34842: 'RGBA16F', 34836: 'RGBA32F', 35898: 'R11F_G11F_B10F', 33325: 'R16F', 33321: 'R8', 36012: 'DEPTH_COMPONENT32F', 36013: 'DEPTH32F_STENCIL8', 35056: 'DEPTH24_STENCIL8', 33190: 'DEPTH_COMPONENT24', 32859: 'RGBA16?', 34843: 'RGB16F', 36975: 'RGB10_A2', 36220: 'RGBA8UI', 36214: 'RGBA16UI' };
const bound = {}; const store = {}; const fbs = {}; let curTex = {}, unit = 0, curRb = 0, curFb = { 36160: 0, 36009: 0, 36008: 0 };
calls.forEach(([n, a, r], i) => {
  if (n === 'activeTexture') unit = a[0];
  if (n === 'bindTexture') curTex[unit + ':' + a[0]] = a[1] && a[1].o;
  if (n === 'texStorage2D') store['t' + curTex[unit + ':' + a[0]]] = `${G[a[2]] || a[2]} ${a[3]}x${a[4]} lv${a[1]} @${i}`;
  if (n === 'texStorage3D') store['t' + curTex[unit + ':' + a[0]]] = `${G[a[2]] || a[2]} ${a[3]}x${a[4]}x${a[5]} 3D @${i}`;
  if (n === 'bindRenderbuffer') curRb = a[1] && a[1].o;
  if (n === 'renderbufferStorage') store['r' + curRb] = `${G[a[1]] || a[1]} ${a[2]}x${a[3]} @${i}`;
  if (n === 'renderbufferStorageMultisample') store['r' + curRb] = `${G[a[2]] || a[2]} ${a[3]}x${a[4]} x${a[1]}samples @${i}`;
  if (n === 'bindFramebuffer') { const id = a[1] && a[1].o || 0; if (a[0] === 36160) { curFb[36160] = curFb[36009] = curFb[36008] = id; } else curFb[a[0]] = id; }
  if (n === 'framebufferTexture2D') { const fb = curFb[a[0] === 36008 ? 36008 : 36009]; (fbs[fb] = fbs[fb] || []).push(`${a[1]}<-t${a[3] && a[3].o} lv${a[4]} @${i}`); }
  if (n === 'framebufferTextureLayer') { const fb = curFb[a[0] === 36008 ? 36008 : 36009]; (fbs[fb] = fbs[fb] || []).push(`${a[1]}<-t${a[2] && a[2].o} layer${a[4]} @${i}`); }
  if (n === 'framebufferRenderbuffer') { const fb = curFb[a[0] === 36008 ? 36008 : 36009]; (fbs[fb] = fbs[fb] || []).push(`${a[1]}<-r${a[3] && a[3].o} @${i}`); }
});
const want = process.argv.slice(3).map(Number);
for (const [fb, at] of Object.entries(fbs)) { if (want.length && !want.includes(+fb)) continue;
  console.log('fb' + fb, at.map(s => { const m = /<-([tr]\d+)/.exec(s); return s + ' [' + (store[m[1]] || '?') + ']'; }).join(' | ')); }
