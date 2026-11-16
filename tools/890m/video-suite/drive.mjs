#!/usr/bin/env node
// Runs one case of the suite and writes <out>/<case>.tsv (one row per second) and <out>/<case>.json (summary).
// usage: node drive.mjs <case> <outdir>
// Called by run.sh; see README.md for the cases and the metrics.
import fs from 'node:fs';
import path from 'node:path';
import { execFile, spawn } from 'node:child_process';
import { promisify } from 'node:util';
import { startServer, CLIPS } from './lib/server.mjs';
import { launch, killScratch, wait } from './lib/cdp.mjs';
const sh = promisify(execFile);

// mode: windowed (1280x800 window), maximized, fullscreen (element fullscreen of the <video>, like a player button)
export const CASES = {
  'idle':             { kind: 'idle', secs: 30, note: 'desktop reference: no scratch Chrome' },
  'vp9-1080p60-win':  { clip: 'vp9-1080p60.webm', mode: 'windowed' },
  'vp9-1080p60-max':  { clip: 'vp9-1080p60.webm', mode: 'maximized' },
  'vp9-1080p60-fs':   { clip: 'vp9-1080p60.webm', mode: 'fullscreen' },
  'av1-1080p60-max':  { clip: 'av1-1080p60.webm', mode: 'maximized' },
  'h264-1080p30-win': { clip: 'h264-1080p30.mp4', mode: 'windowed', fps: 30 },
  'vp9-seekpause':    { clip: 'vp9-1080p60.webm', mode: 'maximized', scenario: 'seekpause' },
  'vp9-2160p60-max':  { clip: 'vp9-2160p60.webm', mode: 'maximized' },
  // TODO (plan cases not built yet): PiP, AV1 4K60, H.264 1080p60, HEVC 1080p60, MSE + quality switch, scroll,
  // two videos, Safari, QuickTime. Listed so `run.sh <name>` says so instead of failing silently.
  'vp9-1080p60-pip':  { todo: 'PiP via requestPictureInPicture with userGesture' },
  'av1-2160p60-max':  { todo: 'needs av1-2160p60.webm (slow software encode)' },
  'h264-1080p60-max': { todo: 'clip defined in gen.mjs' },
  'hevc-1080p60-max': { todo: 'Chrome HEVC playback path not checked' },
  'vp9-mse-switch':   { todo: 'mse.html: Cues-driven segment appends, 1080 -> 1440 -> 1080' },
  'vp9-scroll':       { todo: 'scroll.html + CDP mouseWheel at 60 Hz' },
  'two-videos':       { todo: 'two.html: VP9 + AV1 side by side' },
  'safari':           { todo: 'needs the owner OK for Safari' },
  'quicktime':        { todo: 'needs the owner OK for AppleScript' },
};
export const CORE = ['idle', 'vp9-1080p60-win', 'vp9-1080p60-max', 'vp9-1080p60-fs', 'av1-1080p60-max', 'h264-1080p30-win', 'vp9-seekpause', 'vp9-2160p60-max'];

// driver counters (handoff 5.2) + NMXAccel frames; '-' when the running kext lacks one
export const NMX = ['nmx_pages_live', 'nmx_page_chunks', 'nmx_page_free', 'nmx_page_chunks_freed', 'nmx_page_chunks_filled',
  'nmx_page_chunks_inline', 'nmx_page_hwm', 'nmx_userwire_pages', 'nmx_surfwire_pages', 'nmx_userwire_parked_pages',
  'nmx_userwire_parks', 'nmx_userwire_unparks', 'nmx_userwire_unpark_fail', 'nmx_upin_restore_fail', 'nmx_park_skip_busy',
  'nmx_park_fail', 'nmx_userrec_live', 'nmx_userrec_made', 'nmx_timeouts', 'nmxaccel_pipe_perform', 'nmxaccel_fence_timeouts'];
const GROUPS = ['gpu', 'renderer', 'browser', 'chrome_other', 'windowserver', 'vtdecoder', 'docker', 'claude', 'owner_apps', 'total'];

// ---------- sampler: power, temperature, CPU per group, driver counters, once a second ----------
function classify(args, profile) {
  if (profile && args.includes(`--user-data-dir=${profile}`)) {
    if (args.includes('--type=gpu-process')) return 'gpu';
    if (args.includes('--type=renderer')) return 'renderer';
    if (args.includes('--type=')) return 'chrome_other';
    return 'browser';
  }
  if (args.includes('SkyLight.framework/Resources/WindowServer')) return 'windowserver';
  if (args.includes('VTDecoderXPCService')) return 'vtdecoder';
  if (/Docker\.app|com\.docker|vpnkit|qemu|vfkit|ryzenhv/i.test(args)) return 'docker';
  if (/Claude\.app|\/claude( |$)|claude-code|\.claude\//i.test(args)) return 'claude';
  return 'owner_apps';
}
const cpuSecs = (t) => { const p = t.split(':').map(Number); return p.length === 3 ? p[0] * 3600 + p[1] * 60 + p[2] : p[0] * 60 + p[1]; };

export function startSampler(profile) {
  const samples = []; let prev = null; let ktask = null; let stop = false;
  const top = spawn('top', ['-l', '0', '-s', '1', '-pid', '0', '-stats', 'pid,cpu']);   // kernel_task CPU (ps can't see pid 0)
  let tbuf = '';
  top.stdout.on('data', (d) => { tbuf += d; const ls = tbuf.split('\n'); tbuf = ls.pop(); for (const l of ls) { const m = /^0\s+([\d.]+)/.exec(l); if (m) ktask = +m[1]; } });
  const one = async () => {
    const t = Date.now();
    const [sens, ps, ctl] = await Promise.all([
      sh('sysctl', ['-n', 'debug.amdcppc.sensors']).then((r) => r.stdout, () => ''),
      sh('ps', ['-A', '-o', 'pid=,time=,args='], { maxBuffer: 16 << 20 }).then((r) => r.stdout, () => ''),
      sh('sysctl', NMX.map((n) => 'debug.' + n)).then((r) => r.stdout, (e) => e.stdout || ''),
    ]);
    const rm = /rapl=([0-9a-f]+)\/([0-9a-f]+)/.exec(sens), tm = /tctl=(\d+)/.exec(sens);
    const esu = rm ? (parseInt(rm[1], 16) >> 8) & 31 : 16, energy = rm ? parseInt(rm[2], 16) : null;
    const procs = new Map();
    for (const l of ps.split('\n')) { const m = /^\s*(\d+)\s+(\S+)\s+(.*)$/.exec(l); if (m) procs.set(+m[1], { cpu: cpuSecs(m[2]), g: classify(m[3], profile) }); }
    const nmx = {}; for (const l of ctl.split('\n')) { const m = /^debug\.(\S+): (.*)$/.exec(l); if (m) nmx[m[1]] = +m[2]; }
    const s = { t, tctl: tm ? +tm[1] / 1000 : null, ktask, nmx };
    if (prev) {
      const dt = (t - prev.t) / 1000;
      s.watts = energy != null && prev.energy != null ? (((energy - prev.energy) >>> 0) / 2 ** esu) / dt : null;
      const g = Object.fromEntries(GROUPS.map((k) => [k, 0]));
      for (const [pid, p] of procs) { const o = prev.procs.get(pid); if (!o) continue; const d = Math.max(0, p.cpu - o.cpu) / dt * 100; g[p.g] += d; g.total += d; }
      for (const k of GROUPS) g[k] = +g[k].toFixed(1);
      s.cpu = g; samples.push(s);
    }
    prev = { t, energy, procs };
  };
  (async () => { while (!stop) { const t0 = Date.now(); await one().catch((e) => console.error('sample', e.message)); await wait(Math.max(0, 1000 - (Date.now() - t0))); } })();
  return { samples, stop: () => { stop = true; top.kill(); } };
}

// ---------- statistics ----------
const pct = (a, p) => { if (!a.length) return null; const s = [...a].sort((x, y) => x - y); return s[Math.min(s.length - 1, Math.floor(p / 100 * s.length))]; };
const avg = (a) => (a.length ? a.reduce((x, y) => x + y, 0) / a.length : null);
const r1 = (x) => (x == null ? null : +x.toFixed(1)), r2 = (x) => (x == null ? null : +x.toFixed(2));
const nearest = (samples, t) => { let b = null; for (const s of samples) if (!b || Math.abs(s.t - t) < Math.abs(b.t - t)) b = s; return b && Math.abs(b.t - t) < 700 ? b : null; };

export function windowStats(samples, t0, t1) {
  const w = samples.filter((s) => s.t > t0 && s.t <= t1 + 300);
  if (!w.length) return {};
  const first = w[0].nmx, last = w[w.length - 1].nmx;
  const d = (k) => (first[k] == null || last[k] == null ? null : last[k] - first[k]);
  const cpu = {}; for (const k of GROUPS) cpu[k] = r1(avg(w.map((s) => s.cpu[k])));
  return {
    n: w.length, watts: r2(avg(w.map((s) => s.watts).filter((x) => x != null))), tctl: r1(avg(w.map((s) => s.tctl))), tctlMax: r1(Math.max(...w.map((s) => s.tctl))),
    cpu: { ...cpu, kernel_task: r1(avg(w.map((s) => s.ktask).filter((x) => x != null))) },
    nmx: { chunks_filled: d('nmx_page_chunks_filled'), chunks_inline: d('nmx_page_chunks_inline'), chunks_freed: d('nmx_page_chunks_freed'),
      parks: d('nmx_userwire_parks'), unparks: d('nmx_userwire_unparks'), unpark_fail: d('nmx_userwire_unpark_fail'), park_fail: d('nmx_park_fail'),
      restore_fail: d('nmx_upin_restore_fail'), timeouts: d('nmx_timeouts'), fence_timeouts: d('nmxaccel_fence_timeouts'),
      frames_per_s: d('nmxaccel_pipe_perform') == null ? null : r1(d('nmxaccel_pipe_perform') / ((w[w.length - 1].t - w[0].t) / 1000 || 1)),
      page_free_min: Math.min(...w.map((s) => s.nmx.nmx_page_free ?? Infinity)), pages_live_max: Math.max(...w.map((s) => s.nmx.nmx_pages_live ?? 0)),
      userwire_max: Math.max(...w.map((s) => s.nmx.nmx_userwire_pages ?? 0)), parked_pages_end: last.nmx_userwire_parked_pages ?? null },
  };
}
export function pageStats(rows, fps) {
  const iv = rows.flatMap((r) => r.intervals); const period = 1000 / fps;
  const sum = (k) => rows.reduce((a, r) => a + (r[k] || 0), 0);
  return { secs: rows.length, decoded: sum('decoded'), dropped: sum('dropped'), skipped: sum('skipped'), presented: sum('rvfc'), back: sum('back'),
    missedCb: sum('missedCb'), waiting: sum('waiting'), stalled: sum('stalled'),
    ivP50: r2(pct(iv, 50)), ivP95: r2(pct(iv, 95)), ivP99: r2(pct(iv, 99)), ivMax: r2(iv.length ? Math.max(...iv) : null),
    late: iv.filter((x) => x > period * 1.5).length,       // a frame stayed on screen at least half a frame too long
    hiddenSecs: rows.filter((r) => r.vis !== 'visible').length, unfocusedSecs: rows.filter((r) => !r.focus).length,
    fsSecs: rows.filter((r) => r.fs).length, viewport: rows.length ? `${rows.at(-1).vw}x${rows.at(-1).vh}@${rows.at(-1).dpr}` : null };
}

// power-relevant state at the start of each case (other sessions may change profile/EPP between cases)
async function machineCtx() {
  const o = (c, a) => sh(c, a).then((r) => r.stdout, () => '');
  const [st, rep, batt, dock] = await Promise.all([o('sysctl', ['-n', 'debug.asuswmi.status']), o('sysctl', ['-n', 'debug.amdcppc.report']), o('pmset', ['-g', 'batt']), o('pgrep', ['-f', 'com.docker.backend'])]);
  const f = (k) => (new RegExp(' ' + k + '=(\\d+)').exec(' ' + st) || [])[1] ?? null;
  const epp = {}; for (const m of rep.matchAll(/epp (\d+)/g)) epp[m[1]] = (epp[m[1]] || 0) + 1;
  return { profile: f('profile'), set_profile: f('set_profile'), dgpu_disable: f('dgpu_disable'), epp, ac: /AC Power/.test(batt), docker: !!dock.trim() };
}

// ---------- one case ----------
async function runCase(name, out) {
  const c = CASES[name]; if (!c) throw new Error('unknown case ' + name);
  if (c.todo) { console.log(`${name}: TODO (${c.todo}), skipped`); return; }
  const profile = path.join(process.env.VS_PROFILE_ROOT || path.join(CLIPS, '..'), 'chrome-run');
  const summary = { case: name, ...c, started: new Date().toISOString() };
  summary.ctx = await machineCtx();
  if (c.kind === 'idle') {
    killScratch(profile);
    const smp = startSampler(null); await wait((c.secs + 5) * 1000); smp.stop();
    const t1 = smp.samples.at(-1).t, t0 = t1 - c.secs * 1000;
    Object.assign(summary, { window: windowStats(smp.samples, t0, t1) });
    writeTsv(out, name, smp.samples.filter((s) => s.t > t0).map((s) => ({ s })));
    fs.writeFileSync(path.join(out, name + '.json'), JSON.stringify(summary, null, 1));
    return summary;
  }
  const meta = JSON.parse(fs.readFileSync(path.join(CLIPS, 'manifest.json')))[c.clip];
  if (!meta) throw new Error(`clip ${c.clip} missing: run node gen.mjs ${c.clip}`);
  const fps = c.fps || meta.fps; summary.clipSha = meta.sha256.slice(0, 12);
  const port = 8791; const rows = []; const events = []; let done = false, startWall = null;
  const srv = await startServer(port, { onReport: (o) => { if (o.type === 'row') rows.push(o); else { events.push(o); if (o.type === 'done') done = true; if (o.type === 'start') startWall = o.wall; } } });
  const smp = startSampler(profile);
  let b;
  try {
    b = await launch(profile, 9341, { extra: c.mode === 'windowed' ? ['--window-size=1280,800', '--window-position=80,60'] : ['--start-maximized'] });
    const media = {}; const mediaErr = [];
    b.on((m) => {
      if (m.method === 'Media.playerPropertiesChanged') for (const p of m.params.properties) media[p.name] = p.value;
      if (m.method === 'Media.playerErrorsRaised') mediaErr.push(...m.params.errors.map((e) => e.errorType + ':' + e.code));
    });
    await b.ps('Media.enable'); await b.ps('Page.enable');
    if (c.mode === 'windowed') { await b.send('Browser.setWindowBounds', { windowId: b.windowId, bounds: { windowState: 'normal' } }); await b.send('Browser.setWindowBounds', { windowId: b.windowId, bounds: { left: 80, top: 60, width: 1280, height: 800 } }); }
    else await b.send('Browser.setWindowBounds', { windowId: b.windowId, bounds: { windowState: 'maximized' } });
    await b.ps('Page.bringToFront');
    const q = new URLSearchParams({ clip: c.clip, fps, ...(process.env.VS_MEASURE ? { warm: process.env.VS_WARM || 1, measure: process.env.VS_MEASURE } : {}), scenario: c.scenario || 'plain', case: name, run: path.basename(out) });
    await b.ps('Page.navigate', { url: `http://127.0.0.1:${port}/pages/play.html?${q}` });
    for (let i = 0; i < 80 && !startWall; i++) await wait(250);
    if (!startWall) throw new Error('playback did not start: ' + JSON.stringify(events));
    if (c.mode === 'fullscreen') { await wait(500); await b.evaluate('window.__vs.fullscreen()', true); }
    const limit = Date.now() + 200e3;
    while (!done && Date.now() < limit) await wait(500);
    await wait(1200);
    summary.decoder = media.kVideoDecoderName || null; summary.platformDecoder = media.kIsPlatformVideoDecoder ?? null;
    summary.hwDecoder = String(media.kIsPlatformVideoDecoder) === 'true' || /VideoToolbox|VTVideo|Platform|Mojo/i.test(media.kVideoDecoderName || '');
    summary.mediaErrors = mediaErr; summary.chromeVersion = (await b.send('Browser.getVersion')).product;
  } finally { smp.stop(); try { b?.close(); } catch {} killScratch(profile); srv.close(); }
  summary.events = events.filter((e) => e.type !== 'start');
  summary.timedOut = !done;
  const phases = [...new Set(rows.map((r) => r.phase))];
  summary.phases = {};
  for (const ph of phases) {
    if (ph === 'load' || ph === 'warm') continue;
    const pr = rows.filter((r) => r.phase === ph);
    summary.phases[ph] = { ...pageStats(pr, fps), ...windowStats(smp.samples, pr[0].wall - 1000, pr.at(-1).wall) };
  }
  if (c.scenario === 'seekpause') {
    const pr = rows.filter((r) => ['pre', 'seek', 'resume5', 'post'].includes(r.phase));
    summary.phases.measure = { ...pageStats(pr, fps), note: 'playing phases pre+seek+resume5+post (35 s); pause excluded' };
  }
  // the page was hidden (window covered, other Space, screen locked): Chrome stops decoding, the case measured nothing real
  summary.disturbed = Object.entries(summary.phases).filter(([k, p]) => k !== 'pause' && p.hiddenSecs > 0).map(([k, p]) => `${k}: hidden ${p.hiddenSecs} s`).join(', ') || null;
  writeTsv(out, name, rows.map((r) => ({ r, s: nearest(smp.samples, r.wall) })), 1000 / fps);
  fs.writeFileSync(path.join(out, name + '.json'), JSON.stringify(summary, null, 1));
  return summary;
}

function writeTsv(out, name, rs, period = 1000 / 60) {
  const hdr = ['time', 'sec', 'phase', 'decoded', 'dropped', 'skipped', 'rvfc', 'iv_max', 'late', 'vis', 'focus', 'fs', 'ready', 'ahead', 'waiting',
    'watts', 'tctl', ...GROUPS.map((g) => 'cpu_' + g), 'cpu_kernel_task', ...NMX.map((n) => n.replace(/^nmx(accel)?_/, (m) => (m === 'nmxaccel_' ? 'acc_' : ''))) ];
  const lines = [hdr.join('\t')];
  for (const { r, s } of rs) {
    const iv = r?.intervals || [];
    lines.push([new Date(r?.wall ?? s.t).toTimeString().slice(0, 8), r?.sec ?? '', r?.phase ?? 'idle', r?.decoded ?? '', r?.dropped ?? '', r?.skipped ?? '', r?.rvfc ?? '',
      iv.length ? Math.max(...iv).toFixed(1) : '', r ? iv.filter((x) => x > period * 1.5).length : '', r?.vis ?? '', r ? +r.focus : '', r ? +r.fs : '', r?.readyState ?? '', r?.ahead ?? '', r?.waiting ?? '',
      s?.watts?.toFixed(2) ?? '-', s?.tctl ?? '-', ...GROUPS.map((g) => s?.cpu?.[g] ?? '-'), s?.ktask ?? '-', ...NMX.map((n) => s?.nmx?.[n] ?? '-')].join('\t'));
  }
  fs.writeFileSync(path.join(out, name + '.tsv'), lines.join('\n') + '\n');
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const [name, out] = process.argv.slice(2);
  if (!name || !out) { console.error('usage: node drive.mjs <case> <outdir>'); process.exit(2); }
  fs.mkdirSync(out, { recursive: true });
  const s = await runCase(name, out).catch((e) => { console.error(`${name}: FAILED ${e.stack}`); process.exit(1); });
  if (s) { const m = s.phases?.measure; console.log(`${name}: ${m ? `dropped ${m.dropped} skipped ${m.skipped} late ${m.late} ivP95 ${m.ivP95} hidden ${m.hiddenSecs}s ${m.watts ?? ''} W` : `${s.window?.watts} W`} decoder ${s.decoder ?? '-'}`); }
  if (s?.disturbed) { console.log(`${name}: DISTURBED (${s.disturbed})`); process.exit(4); }
  process.exit(0);
}
