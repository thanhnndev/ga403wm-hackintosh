// node trace-shaders.mjs <trace.bin> <outdir> : writes p<program>.vert/.frag from the captured shaderSource/attachShader calls
import fs from 'fs';
const [tf, od] = process.argv.slice(2); fs.mkdirSync(od, { recursive: true });
const buf = fs.readFileSync(tf); const hl = buf.readUInt32LE(0); const { calls } = JSON.parse(buf.subarray(4, 4 + hl).toString());
const src = {}, kind = {};
for (const [n, a, r] of calls) {
  if (n === 'createShader') kind[r] = a[0] === 35633 ? 'vert' : 'frag';
  if (n === 'shaderSource') src[a[0].o] = a[1];
  if (n === 'attachShader') fs.writeFileSync(`${od}/p${a[0].o}.${kind[a[1].o]}`, src[a[1].o] || '');
}
console.log(fs.readdirSync(od).join(' '));
