// node serve.mjs <port> <dir>... : tiny static server on 127.0.0.1 (first dir that has the file wins)
import http from 'http'; import fs from 'fs'; import path from 'path';
const [port, ...dirs] = process.argv.slice(2);
const types = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.bin': 'application/octet-stream', '.png': 'image/png', '.json': 'application/json' };
http.createServer((q, r) => { const p = decodeURIComponent(new URL(q.url, 'http://x').pathname).replace(/^\/+/, '');
  for (const d of dirs) { const f = path.join(d, p); if (f.startsWith(path.resolve(d)) && fs.existsSync(f) && fs.statSync(f).isFile()) {
    r.writeHead(200, { 'content-type': types[path.extname(f)] || 'application/octet-stream' }); fs.createReadStream(f).pipe(r); return; } }
  r.writeHead(404); r.end(); }).listen(+port, '127.0.0.1', () => console.log('serving', dirs.join(' '), 'on', port));
