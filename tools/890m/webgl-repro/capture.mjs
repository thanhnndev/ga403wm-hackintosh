// node capture.mjs <cdp-port> <out.bin> [url] [seconds=14]
// Captures the WebGL2 call stream of every worker/page context of a page loaded in a running Chrome.
import fs from 'fs';
const [port, outf, url = 'https://www.google.com/maps/@21.0285,105.8542,16z?hl=en', secs = '14'] = process.argv.slice(2);
const wait = ms => new Promise(r => setTimeout(r, ms));
let tabs; for (let i = 0; i < 60 && !tabs; i++) { try { tabs = await (await fetch(`http://127.0.0.1:${port}/json`)).json(); } catch (e) { await wait(500); } }
const ws = new WebSocket(tabs.find(t => t.type === 'page').webSocketDebuggerUrl); await new Promise(r => ws.onopen = r);
let id = 0; const pend = new Map(); const hook = fs.readFileSync(new URL('capture-hook.js', import.meta.url), 'utf8'); const targets = [];
const send = (method, params = {}, sessionId) => new Promise(r => { const i = ++id; pend.set(i, r); ws.send(JSON.stringify(sessionId ? { id: i, method, params, sessionId } : { id: i, method, params })); });
ws.onmessage = async e => { const m = JSON.parse(e.data); if (m.id && pend.has(m.id)) { pend.get(m.id)(m); pend.delete(m.id); }
  if (m.method === 'Target.attachedToTarget') { const sid = m.params.sessionId; targets.push([sid, m.params.targetInfo.type]);
    await send('Runtime.evaluate', { expression: hook }, sid); await send('Runtime.runIfWaitingForDebugger', {}, sid); } };
const evs = async (x, sid, ms = 60000) => { const r = await Promise.race([send('Runtime.evaluate', { expression: x, returnByValue: true }, sid), wait(ms).then(() => ({ error: 'timeout' }))]); if (r.result?.exceptionDetails || r.error) console.log('eval error', x.slice(0, 40), JSON.stringify(r.error || r.result.exceptionDetails).slice(0, 300)); return r.result?.result?.value; };
await send('Target.setAutoAttach', { autoAttach: true, waitForDebuggerOnStart: true, flatten: true });
await send('Page.addScriptToEvaluateOnNewDocument', { source: hook });
await send('Page.navigate', { url });
await wait(+secs * 1000);
const shot = await send('Page.captureScreenshot', { format: 'png' }); fs.writeFileSync(outf.replace(/\.bin$/, '') + '.png', Buffer.from(shot.result.data, 'base64'));
let best = null;
for (const [sid, type] of [[undefined, 'page'], ...targets]) { if (type === 'service_worker') continue; const c = await evs('self.__capCount ? JSON.stringify(self.__capCount()) : null', sid, 3000); if (!c) continue; const [n, b] = JSON.parse(c);
  console.log(type, 'calls', n, 'bytes', b, await evs('self.__capBytesBy()', sid), await evs(`JSON.stringify(self.__capErrs||null)`, sid)); if (n > 1000 && (!best || n > best[2])) best = [sid, type, n]; }
if (process.env.STATS_ONLY) process.exit(0);
const T0 = Date.now(); const tlog = (...a) => console.log(((Date.now() - T0) / 1000).toFixed(1) + 's', ...a);
await evs('self.__capStop = true', best[0]); tlog('stopped');
const total = await evs('self.__capDump()', best[0]); tlog('dump', total); const parts = [];
for (let i = 0; i * 4194304 < total; i++) { parts.push(Buffer.from(await evs(`self.__capChunk(${i})`, best[0]), 'base64')); tlog('chunk', i); }
fs.writeFileSync(outf, Buffer.concat(parts)); console.log('wrote', outf, total, 'bytes from', best[1]);
process.exit(0);
