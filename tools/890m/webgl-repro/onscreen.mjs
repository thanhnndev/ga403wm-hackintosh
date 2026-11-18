// node onscreen.mjs <cdp-port> <out-prefix> [secs=60]
// Drives Google Maps in a VISIBLE scratch-profile Chrome (start it windowed with --remote-debugging-port; keep the window
// uncovered, or Chrome marks the page hidden and throttles it). Hanoi at zoom 14..17: screenshot each, then pans and
// wheel-zooms for <secs> seconds while recording requestAnimationFrame intervals. Writes <out-prefix>-z<N>.png and
// <out-prefix>-after.png, prints the frame-time summary.
import fs from "fs"; import { execFileSync } from "child_process";
// FRONT_PID=<scratch Chrome pid>: re-raise that process before every step (something else keeps taking the front).
const front = () => { if (process.env.FRONT_PID) try { execFileSync("osascript", ["-e", `tell application "System Events" to set frontmost of (first process whose unix id is ${process.env.FRONT_PID}) to true`]); } catch {} };
const [port, out, secsArg] = process.argv.slice(2); const secs = +(secsArg || 60);
const wait = ms => new Promise(r => setTimeout(r, ms));
let ts = [];
for (let i = 0; i < 40 && !ts.length; i++) { try { ts = (await (await fetch(`http://127.0.0.1:${port}/json`)).json()).filter(t => t.type === 'page'); } catch {} if (!ts.length) await wait(250); }
const ws = new WebSocket(ts[0].webSocketDebuggerUrl); let id = 0; const pend = new Map();
const send = (m, p = {}, ms = 8000) => new Promise(r => { const i = ++id; pend.set(i, r);
  setTimeout(() => { if (pend.has(i)) { pend.delete(i); console.log('timeout', m); r({}); } }, ms); ws.send(JSON.stringify({ id: i, method: m, params: p })); });
ws.onmessage = e => { const m = JSON.parse(e.data); if (m.id && pend.has(m.id)) { pend.get(m.id)(m); pend.delete(m.id); } };
await new Promise(r => ws.onopen = r);
const ev = async (x, aw = false, ms = 8000) => (await send('Runtime.evaluate', { expression: x, returnByValue: true, awaitPromise: aw }, ms)).result?.result?.value;
const shot = async n => { const r = await send('Page.captureScreenshot', { format: 'png' }, 20000); if (r.result) fs.writeFileSync(`${out}-${n}.png`, Buffer.from(r.result.data, 'base64')); };
await send('Page.enable'); await send('Page.bringToFront');
for (const z of [14, 15, 16, 17]) {
  front();
  await send('Page.navigate', { url: `https://www.google.com/maps/@21.0285,105.8542,${z}z` }); front(); await wait(12000);
  console.log(`z${z}`, JSON.stringify(await ev(`({vis:document.visibilityState})`))); await shot(`z${z}`);
}
await ev(`(window.__ft=[], (function f(t){ window.__ft.push(t); requestAnimationFrame(f); })(performance.now()), 1)`);
const t0 = Date.now(); let k = 0;
while (Date.now() - t0 < secs * 1000) {
  front();
  const y = 450, x0 = k % 2 ? 350 : 950, x1 = k % 2 ? 950 : 350, dy = ((k % 5) - 2) * 40;
  await send('Input.dispatchMouseEvent', { type: 'mousePressed', x: x0, y, button: 'left', clickCount: 1 });
  for (let s = 1; s <= 30; s++) { await send('Input.dispatchMouseEvent', { type: 'mouseMoved', x: x0 + (x1 - x0) * s / 30, y: y + dy * s / 30, button: 'left', buttons: 1 }); await wait(16); }
  await send('Input.dispatchMouseEvent', { type: 'mouseReleased', x: x1, y: y + dy, button: 'left', clickCount: 1 });
  if (k % 3 === 2) for (let s = 0; s < 6; s++) { await send('Input.dispatchMouseEvent', { type: 'mouseWheel', x: 640, y: 450, deltaX: 0, deltaY: k % 6 === 2 ? -120 : 120 }); await wait(60); }
  await wait(250); k++;
}
const ft = await ev(`(()=>{const t=window.__ft; const d=[]; for(let i=1;i<t.length;i++) d.push(t[i]-t[i-1]); const s=[...d].sort((a,b)=>a-b); const n=s.length;
  return {gestures:${k}, frames:n, fps:(n/((t[n]-t[0])/1000)).toFixed(1), p50:s[n>>1].toFixed(1), p95:s[Math.floor(n*.95)].toFixed(1), p99:s[Math.floor(n*.99)].toFixed(1), max:s[n-1].toFixed(1), over33:d.filter(x=>x>33.4).length, over50:d.filter(x=>x>50).length, vis:document.visibilityState}})()`);
console.log('pan/zoom frame times', JSON.stringify(ft));
await wait(5000); await shot('after');
console.log('renderer', await ev(`(()=>{const c=document.createElement('canvas').getContext('webgl2'); const e=c&&c.getExtension('WEBGL_debug_renderer_info'); return e?c.getParameter(e.UNMASKED_RENDERER_WEBGL):'none'})()`));
process.exit(0);
