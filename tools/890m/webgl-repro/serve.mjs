// node serve.mjs <port> <dir>... : tiny static server on 127.0.0.1 (first dir that has the file wins); POST /report?name= saves to <last dir>/reports
import http from 'http'; import fs from 'fs'; import path from 'path';
const [port, ...dirs] = process.argv.slice(2);
const types = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.bin': 'application/octet-stream', '.png': 'image/png', '.json': 'application/json' };
// POST /report?name=X writes the body to <first dir>/../reports/X.json (browsers with no automation: Safari)
http.createServer((q, r) => {
  if (q.method === 'POST') { const u = new URL(q.url, 'http://x'); const n = (u.searchParams.get('name') || 'report').replace(/[^\w.-]/g, '_');
    const out = path.join(dirs[dirs.length - 1], 'reports'); fs.mkdirSync(out, { recursive: true }); const chunks = [];
    q.on('data', c => chunks.push(c)); q.on('end', () => { fs.writeFileSync(path.join(out, n + '.json'), Buffer.concat(chunks)); r.writeHead(204); r.end(); console.log('report', n); }); return; }
  const p = decodeURIComponent(new URL(q.url, 'http://x').pathname).replace(/^\/+/, '');
  for (const d of dirs) { const f = path.join(d, p); if (f.startsWith(path.resolve(d)) && fs.existsSync(f) && fs.statSync(f).isFile()) {
    r.writeHead(200, { 'content-type': types[path.extname(f)] || 'application/octet-stream' }); fs.createReadStream(f).pipe(r); return; } }
  r.writeHead(404); r.end(); }).listen(+port, '127.0.0.1', () => console.log('serving', dirs.join(' '), 'on', port));
