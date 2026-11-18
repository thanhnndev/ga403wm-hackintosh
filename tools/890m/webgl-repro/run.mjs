// node run.mjs <cdp-port> [url] : loads the sub-test page in a running Chrome (remote debugging) and prints PASS/FAIL
const port = process.argv[2] || '9412';
const url = process.argv[3] || 'file://' + new URL('index.html', import.meta.url).pathname;
const wait = ms => new Promise(r => setTimeout(r, ms));
let tabs; for (let i = 0; i < 60 && !tabs; i++) { try { tabs = await (await fetch(`http://127.0.0.1:${port}/json`)).json(); } catch (e) { await wait(500); } }
const ws = new WebSocket(tabs.find(t => t.type === 'page').webSocketDebuggerUrl); await new Promise(r => ws.onopen = r);
let id = 0; const pend = new Map(); ws.onmessage = e => { const m = JSON.parse(e.data); if (m.id && pend.has(m.id)) { pend.get(m.id)(m); pend.delete(m.id); } };
const send = (method, params = {}) => new Promise(r => { const i = ++id; pend.set(i, r); ws.send(JSON.stringify({ id: i, method, params })); });
const ev = async x => (await send('Runtime.evaluate', { expression: x, returnByValue: true })).result?.result?.value;
await send('Page.navigate', { url });
for (let i = 0; i < 120; i++) { await wait(500); if (await ev('window.__done === true')) break; }
console.log(await ev(`document.getElementById('out').innerText`));
process.exit(0);
