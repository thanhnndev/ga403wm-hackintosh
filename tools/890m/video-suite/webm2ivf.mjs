#!/usr/bin/env node
// webm2ivf: copy the VP9 / AV1 frames of a video-suite WebM (one video track, SimpleBlocks, written by lib/webm.mjs)
// into an IVF file, so the VCNDec tools (vt_test, vcndec_test: IVF only) can decode the suite's clips.
// usage: node webm2ivf.mjs in.webm out.ivf [maxFrames]
import fs from 'node:fs';

const [inp, outp, maxArg] = process.argv.slice(2);
if (!inp || !outp) { console.error('usage: node webm2ivf.mjs in.webm out.ivf [maxFrames]'); process.exit(2); }
const max = maxArg ? +maxArg : Infinity;
const buf = fs.readFileSync(inp);

// EBML variable-size integers
function vint(p, keepMarker) {
  const b = buf[p]; let len = 1, mask = 0x80;
  while (len <= 8 && !(b & mask)) { len++; mask >>= 1; }
  let v = keepMarker ? b : b & (mask - 1);
  for (let i = 1; i < len; i++) v = v * 256 + buf[p + i];
  const unknown = !keepMarker && v === 2 ** (7 * len) - 1;
  return { v, len, unknown };
}
const MASTER = new Set([0x18538067, 0x1F43B675, 0x1654AE6B, 0xAE, 0xE0]); // Segment, Cluster, Tracks, TrackEntry, Video
let codec = null, width = 0, height = 0, frames = [];
function walk(start, end) {
  let p = start;
  while (p < end && frames.length < max) {
    const id = vint(p, true); p += id.len;
    const sz = vint(p, false); p += sz.len;
    const stop = sz.unknown ? end : p + sz.v;
    if (MASTER.has(id.v)) walk(p, stop);
    else if (id.v === 0x86) codec = buf.toString('latin1', p, stop);           // CodecID
    else if (id.v === 0xB0) width = buf.readUIntBE(p, stop - p);                  // PixelWidth
    else if (id.v === 0xBA) height = buf.readUIntBE(p, stop - p);                 // PixelHeight
    else if (id.v === 0xA3) { const tn = vint(p, false); frames.push(buf.subarray(p + tn.len + 3, stop)); } // SimpleBlock: track, int16 time, flags
    p = stop;
  }
}
walk(0, buf.length);
const fourcc = { V_VP9: 'VP90', V_AV1: 'AV01' }[codec];
if (!fourcc) { console.error(`unsupported codec ${codec}`); process.exit(1); }
const h = Buffer.alloc(32);
h.write('DKIF', 0, 'latin1'); h.writeUInt16LE(0, 4); h.writeUInt16LE(32, 6); h.write(fourcc, 8, 'latin1');
h.writeUInt16LE(width, 12); h.writeUInt16LE(height, 14); h.writeUInt32LE(60, 16); h.writeUInt32LE(1, 20); h.writeUInt32LE(frames.length, 24);
const parts = [h];
frames.forEach((f, i) => { const fh = Buffer.alloc(12); fh.writeUInt32LE(f.length, 0); fh.writeBigUInt64LE(BigInt(i), 4); parts.push(fh, f); });
fs.writeFileSync(outp, Buffer.concat(parts));
console.log(`${outp}: ${codec} ${width}x${height}, ${frames.length} frames`);
