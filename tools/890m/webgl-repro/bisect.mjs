// node bisect.mjs <port-gpu> <port-ref> <http-base> <trace> [lo] [hi]
// Finds the first draw whose own output (viewport of its framebuffer) differs between the GPU under test and the reference
// (SwiftShader). A pixel counts as different if any channel differs by more than 24; a draw differs if > 0.5 % of its viewport does.
const [pg, pr, base, trace, lo0, hi0] = process.argv.slice(2);
const wait = ms => new Promise(r => setTimeout(r, ms));
async function conn(port) { let tabs; for (let i = 0; i < 60 && !tabs; i++) { try { tabs = await (await fetch(`http://127.0.0.1:${port}/json`)).json(); } catch (e) { await wait(500); } }
  const ws = new WebSocket(tabs.find(t => t.type === 'page').webSocketDebuggerUrl); await new Promise(r => ws.onopen = r);
  let id = 0; const pend = new Map(); ws.onmessage = e => { const m = JSON.parse(e.data); if (m.id && pend.has(m.id)) { pend.get(m.id)(m); pend.delete(m.id); } };
  const send = (method, params = {}) => new Promise(r => { const i = ++id; pend.set(i, r); ws.send(JSON.stringify({ id: i, method, params })); });
  const ev = async x => (await send('Runtime.evaluate', { expression: x, returnByValue: true, awaitPromise: true })).result?.result?.value;
  return async (draw) => { await send('Page.navigate', { url: `${base}/replay.html?trace=${trace}&size=2560x1514&draw=${draw}` });
    for (let i = 0; i < 400; i++) { await wait(250); if (await ev('window.__done === true')) break; }
    return { stop: await ev('JSON.stringify(window.__stop)'), px: Buffer.from((await ev('window.__stopPx')) || '', 'base64') }; };
}
const G = await conn(pg), R = await conn(pr);
async function differs(d) {
  const [a, b] = await Promise.all([G(d), R(d)]);
  if (a.px.length !== b.px.length) return { d, bad: 1, info: 'size ' + a.px.length + ' vs ' + b.px.length, stop: a.stop };
  let n = 0; for (let i = 0; i < a.px.length; i += 4) if (Math.abs(a.px[i] - b.px[i]) > 24 || Math.abs(a.px[i + 1] - b.px[i + 1]) > 24 || Math.abs(a.px[i + 2] - b.px[i + 2]) > 24 || Math.abs(a.px[i + 3] - b.px[i + 3]) > 24) n++;
  const frac = n / (a.px.length / 4); return { d, bad: frac > 0.005, frac: (frac * 100).toFixed(3) + '%', stop: a.stop };
}
let lo = +(lo0 || 0), hi = +(hi0 || 9141);
console.log('hi', JSON.stringify(await differs(hi)));
while (lo < hi) { const mid = (lo + hi) >> 1; const r = await differs(mid); console.log(JSON.stringify(r)); if (r.bad) hi = mid; else lo = mid + 1; }
console.log('first differing draw', lo, JSON.stringify(await differs(lo)), 'previous', JSON.stringify(await differs(lo - 1)));
process.exit(0);
