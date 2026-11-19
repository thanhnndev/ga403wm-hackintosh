// Localhost server for the suite: serves pages/ and the clip cache (HTTP Range, so <video> can seek), takes the
// pages' per-second reports (POST /report) and the generator's encoded chunks (POST /gen/*, muxed to WebM here).
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { WebmWriter } from './webm.mjs';

export const SUITE = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
export const CLIPS = process.env.VS_CLIPS || path.join(process.env.HOME, 'Library/Caches/ga403wm-video-suite/clips');
const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.json': 'application/json',
  '.webm': 'video/webm', '.mp4': 'video/mp4', '.mov': 'video/quicktime', '.css': 'text/css' };

const body = (req) => new Promise((res, rej) => { const a = []; req.on('data', (d) => a.push(d)); req.on('end', () => res(Buffer.concat(a))); req.on('error', rej); });

function serveFile(req, res, file) {
  let st; try { st = fs.statSync(file); } catch { res.writeHead(404); return res.end('not found'); }
  if (!st.isFile()) { res.writeHead(404); return res.end('not found'); }
  const type = TYPES[path.extname(file)] || 'application/octet-stream';
  const range = /bytes=(\d*)-(\d*)/.exec(req.headers.range || '');
  const head = { 'Content-Type': type, 'Accept-Ranges': 'bytes', 'Cache-Control': 'no-store' };
  if (range) {
    let a = range[1] === '' ? st.size - +range[2] : +range[1];
    let b = range[1] === '' || range[2] === '' ? st.size - 1 : Math.min(+range[2], st.size - 1);
    if (a > b || a >= st.size) { res.writeHead(416, { 'Content-Range': `bytes */${st.size}` }); return res.end(); }
    res.writeHead(206, { ...head, 'Content-Range': `bytes ${a}-${b}/${st.size}`, 'Content-Length': b - a + 1 });
    if (req.method === 'HEAD') return res.end();
    return fs.createReadStream(file, { start: a, end: b }).pipe(res);
  }
  res.writeHead(200, { ...head, 'Content-Length': st.size });
  if (req.method === 'HEAD') return res.end();
  fs.createReadStream(file).pipe(res);
}

// opts.onReport(obj) gets every page report; opts.onGenDone(info) every finished clip.
export function startServer(port, opts = {}) {
  const writers = new Map();
  const srv = http.createServer(async (req, res) => {
    const u = new URL(req.url, 'http://127.0.0.1');
    const q = Object.fromEntries(u.searchParams);
    try {
      if (req.method === 'POST' && u.pathname === '/report') {
        const b = await body(req); res.writeHead(204); res.end();
        try { opts.onReport?.(JSON.parse(b.toString())); } catch (e) { console.error('bad report', e.message); }
        return;
      }
      if (req.method === 'POST' && u.pathname === '/gen/start') {
        fs.mkdirSync(CLIPS, { recursive: true });
        const cp = q.cp ? Buffer.from(q.cp, 'hex') : null;
        writers.set(q.name, new WebmWriter(path.join(CLIPS, q.name), { codec: q.codec, width: +q.w, height: +q.h, fps: +q.fps, codecPrivate: cp }));
        res.writeHead(204); return res.end();
      }
      if (req.method === 'POST' && u.pathname === '/gen/chunk') {
        // batch: repeated [u32 frameIndex][u8 key][u32 len][bytes], little endian
        const b = await body(req); const w = writers.get(q.name);
        for (let o = 0; o < b.length;) { const i = b.readUInt32LE(o), k = b[o + 4], n = b.readUInt32LE(o + 5); w.add(i, !!k, b.subarray(o + 9, o + 9 + n)); o += 9 + n; }
        res.writeHead(204); return res.end();
      }
      if (req.method === 'POST' && u.pathname === '/gen/finish') {
        const extra = JSON.parse((await body(req)).toString() || '{}');
        const r = writers.get(q.name).finish(); writers.delete(q.name);
        const info = { name: q.name, ...r, ...extra };
        opts.onGenDone?.(info);
        res.writeHead(200, { 'Content-Type': 'application/json' }); return res.end(JSON.stringify(info));
      }
      if (req.method === 'POST' && u.pathname === '/log') { console.log('[page]', (await body(req)).toString()); res.writeHead(204); return res.end(); }
      if (u.pathname.startsWith('/clips/')) return serveFile(req, res, path.join(CLIPS, path.basename(u.pathname)));
      const rel = u.pathname === '/' ? 'pages/index.html' : u.pathname.replace(/^\/+/, '');
      const file = path.resolve(SUITE, rel);
      if (!file.startsWith(SUITE + path.sep) || !(rel.startsWith('pages/') || rel.startsWith('gen/'))) { res.writeHead(403); return res.end(); }
      return serveFile(req, res, file);
    } catch (e) { console.error(e); try { res.writeHead(500); res.end(String(e)); } catch {} }
  });
  return new Promise((r) => srv.listen(port, '127.0.0.1', () => r(srv)));
}
