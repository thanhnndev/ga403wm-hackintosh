// node trace-draw.mjs <trace.bin> <drawIndex> [context=60] : prints the calls before draw N (draw counting as replay.js)
import fs from 'fs';
const [tf, dn, ctx = '60'] = process.argv.slice(2);
const buf = fs.readFileSync(tf); const hl = buf.readUInt32LE(0); const { calls, blobs } = JSON.parse(buf.subarray(4, 4 + hl).toString());
let d = -1, at = -1;
for (let i = 0; i < calls.length; i++) { const n = calls[i][0]; if (n[0] !== '_' && /^draw|multiDraw/.test(n)) { d++; if (d === +dn) { at = i; break; } } }
const show = a => JSON.stringify(a, (k, v) => (v && v.t && v.b !== undefined) ? `<${v.t} ${blobs[v.b][1]}B>` : v);
for (let i = Math.max(0, at - +ctx); i <= at; i++) console.log(i, calls[i][0], show(calls[i][1]).slice(0, 220), calls[i][2] ?? '');
