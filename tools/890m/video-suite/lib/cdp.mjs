// Scratch-profile Chrome over CDP. Never touches the owner's profiles: every launch has its own --user-data-dir,
// and kill() only matches that exact directory. Never Edge.
import { spawn, execFileSync } from 'node:child_process';
import fs from 'node:fs';

export const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
export const wait = (ms) => new Promise((r) => setTimeout(r, ms));

const COMMON = ['--no-first-run', '--no-default-browser-check', '--autoplay-policy=no-user-gesture-required',
  // same as the yt-probe runs (the GPU process needs it for the 890M plugin path), keeps results comparable
  '--disable-gpu-sandbox',
  // keep background work out of the measurement: no component/variations downloads, no sync, no translate prompt
  '--disable-background-networking', '--disable-component-update', '--disable-sync', '--disable-features=Translate,MediaRouter',
  '--password-store=basic', '--use-mock-keychain'];

export function killScratch(profile) {
  try { execFileSync('pkill', ['-f', `user-data-dir=${profile}`]); } catch {}
}

// headless: generator; visible: `open -na` so Chrome is a normal foreground app (focus + window server like a user)
export async function launch(profile, port, { headless = false, extra = [] } = {}) {
  killScratch(profile); await wait(800);
  fs.mkdirSync(profile, { recursive: true });
  const args = [`--user-data-dir=${profile}`, `--remote-debugging-port=${port}`, ...COMMON, ...extra];
  if (headless) spawn(CHROME, ['--headless=new', ...args, 'about:blank'], { stdio: 'ignore', detached: true }).unref();
  else execFileSync('open', ['-na', 'Google Chrome', '--args', ...args, 'about:blank']);
  for (let i = 0; i < 60; i++) {
    try { const v = await (await fetch(`http://127.0.0.1:${port}/json/version`)).json(); return await connect(v.webSocketDebuggerUrl, port); } catch {}
    await wait(250);
  }
  throw new Error('chrome did not open the debugging port');
}

async function connect(url, port) {
  const ws = new WebSocket(url);
  await new Promise((r, j) => { ws.onopen = r; ws.onerror = j; });
  let n = 0; const pend = new Map(); const handlers = [];
  ws.onmessage = (e) => {
    const m = JSON.parse(e.data);
    if (m.id && pend.has(m.id)) { const p = pend.get(m.id); pend.delete(m.id); m.error ? p.j(new Error(m.error.message)) : p.r(m.result); }
    else if (m.method) for (const h of handlers) h(m);
  };
  const send = (method, params = {}, sessionId) => new Promise((r, j) => { const i = ++n; pend.set(i, { r, j }); ws.send(JSON.stringify({ id: i, method, params, sessionId })); });
  const targets = (await send('Target.getTargets')).targetInfos;
  let page = targets.find((t) => t.type === 'page');
  if (!page) page = { targetId: (await send('Target.createTarget', { url: 'about:blank' })).targetId };
  const { sessionId } = await send('Target.attachToTarget', { targetId: page.targetId, flatten: true });
  const ps = (method, params) => send(method, params, sessionId);
  const evaluate = async (expression, userGesture = false) => {
    const r = await ps('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true, userGesture });
    if (r.exceptionDetails) throw new Error(r.exceptionDetails.exception?.description || r.exceptionDetails.text);
    return r.result.value;
  };
  const { windowId } = await send('Browser.getWindowForTarget', { targetId: page.targetId });
  return { ws, send, ps, evaluate, windowId, targetId: page.targetId, on: (h) => handlers.push(h), close: () => ws.close() };
}
