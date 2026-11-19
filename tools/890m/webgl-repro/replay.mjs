// node replay.mjs <cdp-port> <http-base> <trace> <out.png> [extra query]
import fs from 'fs';
const [port, httpBase, trace, outPng, extra = ''] = process.argv.slice(2);
const wait = ms => new Promise(r => setTimeout(r, ms));
let tabs; for (let i = 0; i < 60 && !tabs; i++) { try { tabs = await (await fetch(`http://127.0.0.1:${port}/json`)).json(); } catch (e) { await wait(500); } }
const ws = new WebSocket(tabs.find(t => t.type === 'page').webSocketDebuggerUrl); await new Promise(r => ws.onopen = r);
let id = 0; const pend = new Map(); ws.onmessage = e => { const m = JSON.parse(e.data); if (m.id && pend.has(m.id)) { pend.get(m.id)(m); pend.delete(m.id); } };
const send = (method, params = {}) => new Promise(r => { const i = ++id; pend.set(i, r); ws.send(JSON.stringify({ id: i, method, params })); });
const ev = async x => { const r = await send('Runtime.evaluate', { expression: x, returnByValue: true, awaitPromise: true }); return r.result?.result?.value ?? JSON.stringify(r.result?.exceptionDetails || r.error); };
await send('Page.navigate', { url: `${httpBase}/replay.html?trace=${encodeURIComponent(trace)}${extra ? '&' + extra : ''}` });
for (let i = 0; i < 240; i++) { await wait(500); if (await ev('window.__done === true')) break; }
console.log(await ev(`document.getElementById('out').textContent`));
if (outPng) { fs.writeFileSync(outPng, Buffer.from(await ev('window.__png()'), 'base64')); console.log('wrote', outPng); }
process.exit(0);
