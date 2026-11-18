#!/usr/bin/env node
// Generates the suite's clips on this machine (no downloads): VP9/AV1 with WebCodecs in a headless scratch Chrome
// (gen/gen.html + lib/webm.mjs), H.264/HEVC with AVAssetWriter (gen/genmp4.swift). Writes them to the clip cache
// ($VS_CLIPS, default ~/Library/Caches/ga403wm-video-suite/clips, outside git) with manifest.json.
//
// usage: node gen.mjs [clip names...|core|all] [--force]
//   default "core" = the clips the core cases need. Existing clips with a manifest entry are kept unless --force.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { startServer, CLIPS, SUITE } from './lib/server.mjs';
import { launch, killScratch } from './lib/cdp.mjs';

const SECONDS = +(process.env.VS_SECONDS || 90);
export const CLIP_SET = {
  'vp9-1080p60.webm':  { codec: 'V_VP9', wcodec: 'vp09.00.41.08', width: 1920, height: 1080, fps: 60, bitrate: 8e6 },
  'vp9-1440p60.webm':  { codec: 'V_VP9', wcodec: 'vp09.00.50.08', width: 2560, height: 1440, fps: 60, bitrate: 14e6 },
  'vp9-2160p60.webm':  { codec: 'V_VP9', wcodec: 'vp09.00.51.08', width: 3840, height: 2160, fps: 60, bitrate: 25e6 },
  'av1-1080p60.webm':  { codec: 'V_AV1', wcodec: 'av01.0.08M.08', width: 1920, height: 1080, fps: 60, bitrate: 6e6, level: 8 },
  'av1-2160p60.webm':  { codec: 'V_AV1', wcodec: 'av01.0.13M.08', width: 3840, height: 2160, fps: 60, bitrate: 20e6, level: 13 },
  'h264-1080p30.mp4':  { swift: 'h264', width: 1920, height: 1080, fps: 30, bitrate: 5e6 },
  'h264-1080p60.mp4':  { swift: 'h264', width: 1920, height: 1080, fps: 60, bitrate: 8e6 },
  'hevc-1080p60.mp4':  { swift: 'hevc', width: 1920, height: 1080, fps: 60, bitrate: 6e6 },
  'hevc-2160p60.mp4':  { swift: 'hevc', width: 3840, height: 2160, fps: 60, bitrate: 20e6 },
  // codec matrix (30 s each; mse = also played through Media Source Extensions, mime = the MSE type string)
  'mx-h264-1080p60.mp4':      { swift: 'h264', width: 1920, height: 1080, fps: 60, bitrate: 8e6, seconds: 30 },
  'mx-h264-2160p30.mp4':      { swift: 'h264', width: 3840, height: 2160, fps: 30, bitrate: 20e6, seconds: 30 },
  'mx-h264-1080p60-frag.mp4': { swift: 'h264', frag: true, width: 1920, height: 1080, fps: 60, bitrate: 8e6, seconds: 30, mime: 'video/mp4; codecs="avc1.64002a"' },
  'mx-hevc-1080p60.mp4':      { swift: 'hevc', width: 1920, height: 1080, fps: 60, bitrate: 6e6, seconds: 30 },
  'mx-hevc10-1080p60.mp4':    { swift: 'hevc10', width: 1920, height: 1080, fps: 60, bitrate: 6e6, seconds: 30 },
  'mx-hevc-2160p60.mp4':      { swift: 'hevc', width: 3840, height: 2160, fps: 60, bitrate: 20e6, seconds: 30 },
  'mx-hevc-1080p60-frag.mp4': { swift: 'hevc', frag: true, width: 1920, height: 1080, fps: 60, bitrate: 6e6, seconds: 30, mime: 'video/mp4; codecs="hvc1.1.6.L123.90"' },
  'mx-vp9-1080p30.webm':      { codec: 'V_VP9', wcodec: 'vp09.00.40.08', width: 1920, height: 1080, fps: 30, bitrate: 5e6, seconds: 30, mime: 'video/webm; codecs="vp09.00.40.08"' },
  'mx-vp9p2-1080p60.webm':    { codec: 'V_VP9', wcodec: 'vp09.02.41.10', width: 1920, height: 1080, fps: 60, bitrate: 8e6, seconds: 30, hbd: true },
  'mx-av1-1080p30.webm':      { codec: 'V_AV1', wcodec: 'av01.0.08M.08', width: 1920, height: 1080, fps: 30, bitrate: 4e6, level: 8, seconds: 30, mime: 'video/webm; codecs="av01.0.08M.08"' },
  'mx-av110-1080p60.webm':    { codec: 'V_AV1', wcodec: 'av01.0.09M.10', width: 1920, height: 1080, fps: 60, bitrate: 6e6, level: 9, seconds: 30, hbd: true },
  // AV1 in MP4 from macOS's own (hidden) AOM software encoder: the only 10-bit AV1 encoder on this machine; bitrate = quality 0..1
  'mx-av1-1080p30.mp4':       { swift: 'av1', width: 1920, height: 1080, fps: 30, bitrate: 0.35, seconds: 20 },
  'mx-av110-1080p30.mp4':     { swift: 'av110', width: 1920, height: 1080, fps: 30, bitrate: 0.35, seconds: 20 },
  'mx-av1-2160p60.webm':      { codec: 'V_AV1', wcodec: 'av01.0.13M.08', width: 3840, height: 2160, fps: 60, bitrate: 20e6, level: 13, seconds: 30 },
};
export const MATRIX = Object.keys(CLIP_SET).filter((n) => n.startsWith('mx-'));
const CORE = ['vp9-1080p60.webm', 'av1-1080p60.webm', 'h264-1080p30.mp4', 'vp9-2160p60.webm'];

if (import.meta.url === `file://${process.argv[1]}`) {
  const args = process.argv.slice(2); const force = args.includes('--force');
  let names = args.filter((a) => !a.startsWith('--'));
  if (!names.length || names.includes('core')) names = CORE;
  if (names.includes('all')) names = Object.keys(CLIP_SET);
  if (names.includes('matrix')) names = [...MATRIX, 'vp9-1080p60.webm', 'av1-1080p60.webm', 'h264-1080p30.mp4', 'vp9-2160p60.webm'];
  fs.mkdirSync(CLIPS, { recursive: true });
  const mfile = path.join(CLIPS, 'manifest.json');
  const manifest = fs.existsSync(mfile) ? JSON.parse(fs.readFileSync(mfile)) : {};
  const sha = (f) => { const h = crypto.createHash('sha256'); const fd = fs.openSync(f, 'r'); const b = Buffer.alloc(8 << 20); let n; while ((n = fs.readSync(fd, b)) > 0) h.update(b.subarray(0, n)); fs.closeSync(fd); return h.digest('hex'); };
  const record = (name, info) => {
    const f = path.join(CLIPS, name); const bytes = fs.statSync(f).size; const secs = CLIP_SET[name].seconds || SECONDS;
    manifest[name] = { ...info, mime: CLIP_SET[name].mime, bytes, avgBitrate: Math.round(bytes * 8 / secs), sha256: sha(f), made: new Date().toISOString(),
      chrome: info.chrome, host: execFileSync('sw_vers', ['-productVersion']).toString().trim() };
    fs.writeFileSync(mfile, JSON.stringify(manifest, null, 1));
    console.log(`${name}: ${(bytes / 1e6).toFixed(1)} MB, ${(bytes * 8 / secs / 1e6).toFixed(2)} Mb/s, sha256 ${manifest[name].sha256.slice(0, 12)}`);
  };
  const todo = names.filter((n) => force || !manifest[n] || !fs.existsSync(path.join(CLIPS, n)));
  const swiftTodo = todo.filter((n) => CLIP_SET[n]?.swift), webTodo = todo.filter((n) => CLIP_SET[n] && !CLIP_SET[n].swift);
  for (const n of todo) if (!CLIP_SET[n]) console.error('unknown clip', n);
  if (swiftTodo.length) {
    const bin = path.join(CLIPS, '..', 'genmp4');
    execFileSync('swiftc', ['-O', '-o', bin, path.join(SUITE, 'gen/genmp4.swift')], { stdio: 'inherit' });
    for (const n of swiftTodo) {
      const c = CLIP_SET[n]; const t0 = Date.now(); const secs = c.seconds || SECONDS;
      execFileSync(bin, [path.join(CLIPS, n), c.swift, c.width, c.height, c.fps, secs, c.bitrate, ...(c.frag ? ['frag'] : [])].map(String), { stdio: 'inherit' });
      for (const f of fs.readdirSync(CLIPS)) if (f.startsWith(n + '.sb-')) fs.unlinkSync(path.join(CLIPS, f));
      record(n, { codec: c.swift, width: c.width, height: c.height, fps: c.fps, seconds: secs, targetBitrate: c.bitrate, frames: c.fps * secs, frag: !!c.frag, encodeSeconds: (Date.now() - t0) / 1000, sizeBytes: fs.statSync(path.join(CLIPS, n)).size,
        encoder: c.swift.startsWith('av1') ? 'VTCompressionSession AV1EncoderSW (AOM, quality ' + c.bitrate + '), MP4 by AVAssetWriter passthrough' : 'AVAssetWriter (VideoToolbox, software)' });
    }
  }
  if (webTodo.length) {
    const port = 8790, prof = path.join(CLIPS, '..', 'chrome-gen');
    const srv = await startServer(port);
    const b = await launch(prof, 9340, { headless: true });
    const ver = (await b.send('Browser.getVersion')).product;
    await b.ps('Page.enable'); await b.ps('Page.navigate', { url: `http://127.0.0.1:${port}/gen/gen.html` });
    for (let i = 0; i < 40; i++) { try { if (await b.evaluate('typeof genClip')=== 'function') break; } catch {} await new Promise((r) => setTimeout(r, 250)); }
    try {
      for (const n of webTodo) {
        const c = CLIP_SET[n];
        const cpb = c.codec === 'V_AV1' ? Buffer.from([0x81, c.level & 31, c.hbd ? 0x4c : 0x0c, 0x00]).toString('hex') : '';
        const r = await b.evaluate(`genClip(${JSON.stringify({ name: n, ...c, seconds: c.seconds || SECONDS, cp: cpb })})`).catch((e) => ({ error: e.message }));
        if (r.error) { console.log(`${n}: NOT MADE: ${r.error}`); manifest[n] = { unsupported: r.error, codec: c.wcodec }; fs.writeFileSync(mfile, JSON.stringify(manifest, null, 1)); continue; }
        record(n, { ...r, chrome: ver, encoder: 'Chrome WebCodecs VideoEncoder (realtime, VBR)' });
      }
    } finally { b.close(); killScratch(prof); srv.close(); }
  }
}
