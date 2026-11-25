// Minimal WebM writer for one video track (VP9 or AV1), enough for Chrome's <video> and MSE: EBML header, Segment
// with known size, SeekHead, Info (duration), Tracks, Clusters of SimpleBlocks (a new cluster at every keyframe),
// Cues at the end (one CuePoint per cluster) so seeking works.
//
// Usage: const w = new WebmWriter(path, {codec:'V_VP9', width, height, fps}); w.add(frameIndex, isKey, bytes)...;
//        w.finish() -> {bytes, frames, durationMs}
// Clusters are streamed to path + '.part' while encoding; finish() assembles the final file and removes the part.
import fs from 'node:fs';

const id = (n) => { const b = []; while (n > 0) { b.unshift(n & 0xff); n = Math.floor(n / 256); } return Buffer.from(b); };
// EBML variable-size integer; size 8 bytes when fixed8 (used where the value is patched or must have a known length)
function vint(n, fixed8 = false) {
  if (!fixed8) for (let len = 1; len <= 8; len++) if (n < 2 ** (7 * len) - 1) {
    const b = Buffer.alloc(len); let v = n; for (let i = len - 1; i >= 0; i--) { b[i] = v & 0xff; v = Math.floor(v / 256); }
    b[0] |= 1 << (8 - len); return b;
  }
  const b = Buffer.alloc(8); let v = n; for (let i = 7; i >= 1; i--) { b[i] = v & 0xff; v = Math.floor(v / 256); } b[0] = 0x01; return b;
}
const uintBytes = (n, len) => { const b = Buffer.alloc(len); let v = n; for (let i = len - 1; i >= 0; i--) { b[i] = v & 0xff; v = Math.floor(v / 256); } return b; };
const uint = (n) => { let len = 1; while (n >= 2 ** (8 * len)) len++; return uintBytes(n, len); };
const el = (eid, payload) => Buffer.concat([id(eid), vint(payload.length), payload]);
const elU = (eid, n) => el(eid, uint(n));
const elU8 = (eid, n) => el(eid, uintBytes(n, 8));      // fixed 8-byte uint (SeekHead positions)
const elS = (eid, s) => el(eid, Buffer.from(s, 'utf8'));
const elF = (eid, f) => { const b = Buffer.alloc(8); b.writeDoubleBE(f); return el(eid, b); };
const cat = (...a) => Buffer.concat(a);

export class WebmWriter {
  constructor(path, { codec, width, height, fps, codecPrivate = null }) {
    Object.assign(this, { path, codec, width, height, fps, codecPrivate });
    this.part = path + '.part';
    this.fd = fs.openSync(this.part, 'w');
    this.pos = 0;              // bytes written to the part file (cluster offsets relative to the first cluster)
    this.cues = [];            // [timeMs, clusterOffsetInPart]
    this.cluster = null;       // {timeMs, blocks: Buffer[]}
    this.frames = 0; this.lastMs = 0;
  }
  ms(i) { return Math.round(i * 1000 / this.fps); }
  add(i, key, data) {
    const t = this.ms(i);
    if (key || !this.cluster || t - this.cluster.timeMs > 30000) this.flushCluster(t);
    const rel = t - this.cluster.timeMs;
    const hdr = Buffer.alloc(4); hdr[0] = 0x81; hdr.writeInt16BE(rel, 1); hdr[3] = key ? 0x80 : 0x00;
    this.cluster.blocks.push(el(0xA3, cat(hdr, Buffer.from(data))));
    this.frames++; this.lastMs = t;
  }
  flushCluster(nextMs) {
    if (this.cluster) {
      const body = cat(elU(0xE7, this.cluster.timeMs), ...this.cluster.blocks);
      const buf = cat(id(0x1F43B675), vint(body.length), body);
      this.cues.push([this.cluster.timeMs, this.pos]);
      fs.writeSync(this.fd, buf); this.pos += buf.length;
    }
    this.cluster = nextMs == null ? null : { timeMs: nextMs, blocks: [] };
  }
  finish() {
    this.flushCluster(null); fs.closeSync(this.fd);
    const durMs = this.lastMs + 1000 / this.fps;
    const ebml = el(0x1A45DFA3, cat(elU(0x4286, 1), elU(0x42F7, 1), elU(0x42F2, 4), elU(0x42F3, 8), elS(0x4282, 'webm'), elU(0x4287, 4), elU(0x4285, 2)));
    const info = el(0x1549A966, cat(elU(0x2AD7B1, 1000000), elF(0x4489, durMs), elS(0x4D80, 'ga403wm-video-suite'), elS(0x5741, 'ga403wm-video-suite')));
    const video = el(0xE0, cat(elU(0xB0, this.width), elU(0xBA, this.height)));
    const entry = el(0xAE, cat(elU(0xD7, 1), elU(0x73C5, 1), elU(0x83, 1), elS(0x86, this.codec), elU(0x9C, 0),
      elU(0x23E383, Math.round(1e9 / this.fps)), this.codecPrivate ? el(0x63A2, Buffer.from(this.codecPrivate)) : Buffer.alloc(0), video));
    const tracks = el(0x1654AE6B, entry);
    // SeekHead with fixed-size positions: its length doesn't depend on the values
    const seekHead = (pInfo, pTracks, pCues) => el(0x114D9B74, cat(
      el(0x4DBB, cat(el(0x53AB, id(0x1549A966)), elU8(0x53AC, pInfo))),
      el(0x4DBB, cat(el(0x53AB, id(0x1654AE6B)), elU8(0x53AC, pTracks))),
      el(0x4DBB, cat(el(0x53AB, id(0x1C53BB6B)), elU8(0x53AC, pCues)))));
    const shLen = seekHead(0, 0, 0).length;
    const pInfo = shLen, pTracks = pInfo + info.length, pClusters = pTracks + tracks.length, pCues = pClusters + this.pos;
    const cues = el(0x1C53BB6B, cat(...this.cues.map(([t, off]) =>
      el(0xBB, cat(elU(0xB3, t), el(0xB7, cat(elU(0xF7, 1), elU(0xF1, pClusters + off))))))));
    const segBody = pCues + cues.length;
    const head = cat(ebml, id(0x18538067), vint(segBody, true), seekHead(pInfo, pTracks, pCues), info, tracks);
    const out = fs.openSync(this.path, 'w');
    fs.writeSync(out, head);
    const inp = fs.openSync(this.part, 'r'); const buf = Buffer.alloc(8 << 20); let n;
    while ((n = fs.readSync(inp, buf, 0, buf.length, null)) > 0) fs.writeSync(out, buf, 0, n);
    fs.closeSync(inp); fs.writeSync(out, cues); fs.closeSync(out); fs.unlinkSync(this.part);
    return { bytes: head.length + this.pos + cues.length, frames: this.frames, durationMs: durMs };
  }
}
