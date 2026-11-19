#!/usr/bin/env node
// Codec matrix, Apple side: Safari (our localhost page in a NEW small Safari window, closed by its own id afterwards;
// no other Safari window is touched) and QuickTime Player (opens our MP4 clip as a new document, closes only that
// document). Pass/fail per cell: plays, frame-index strip correct (Safari: pages/check.js; QuickTime: not readable
// from outside, see vt_check), decoder is hardware.
//
// Safari renders nothing in a window that the owner's windows cover (visibilityState hidden: no rVFC, the clock jumps),
// and this runner never activates Safari over the owner's work, so the strip check there gets only a few reads; a
// hidden cell passes on plays + hardware + no unreadable (corrupt) picture; a wrong index is not judged there, because
// drawImage of a page that is not rendered can return a stale frame. Decoder output itself is checked frame by frame by
// vt_check and by the Chrome cells (same VCNDec).
// Hardware verdict: VCNDec's own log lines during the cell (lib/vcnlog.mjs); CPU per process is recorded as context.
//
// usage: node apple.mjs [label=build] [safari|quicktime|all=all] [filter]  -> results/apple-<label>-<date>/{<cell>.json, apple.md}
import fs from 'node:fs';
import path from 'node:path';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { startServer, CLIPS, SUITE } from './lib/server.mjs';
import { wait } from './lib/cdp.mjs';
import { vcnSessions, vcnVerdict, FOURCC } from './lib/vcnlog.mjs';

const sh = promisify(execFile);
const label = process.argv[2] || 'build', which = process.argv[3] || 'all', filter = process.argv[4] || '';
const manifest = JSON.parse(fs.readFileSync(path.join(CLIPS, 'manifest.json')));
const WARM = 3, MEASURE = 12, port = 8793;
const osa = (s) => sh('osascript', ['-e', s], { timeout: 20000 }).then((r) => r.stdout.trim());

// cputime (s) per pid for the processes that can decode: VT XPC services, Safari's GPU + WebContent, QuickTime
async function procs() {
  const { stdout } = await sh('ps', ['-A', '-o', 'pid=,time=,args='], { maxBuffer: 16 << 20 });
  const m = new Map();
  for (const l of stdout.split('\n')) {
    const x = /^\s*(\d+)\s+(\S+)\s+(.*)$/.exec(l); if (!x) continue;
    const g = /VTDecoderXPCService/.test(x[3]) ? 'vtdecoder' : /com\.apple\.WebKit\.GPU/.test(x[3]) ? 'webkit_gpu'
      : /com\.apple\.WebKit\.WebContent/.test(x[3]) ? 'webcontent' : /QuickTime Player\.app/.test(x[3]) ? 'quicktime' : null;
    if (!g) continue;
    const p = x[2].split(':').map(Number);
    m.set(+x[1], { g, cpu: p.length === 3 ? p[0] * 3600 + p[1] * 60 + p[2] : p[0] * 60 + p[1] });
  }
  return m;
}
const hasVcn = (pid) => sh('lsof', ['-p', String(pid)]).then((r) => /VCNDec\.bundle/.test(r.stdout), () => false);
async function cpuDelta(a, b, dt) {
  const g = { vtdecoder: 0, webkit_gpu: 0, webcontent: 0, quicktime: 0 }, vcn = [];
  for (const [pid, p] of b) {
    const d = Math.max(0, p.cpu - (a.get(pid)?.cpu ?? p.cpu)) / dt * 100; g[p.g] += d;
    if (p.g === 'vtdecoder' && d > 0.5) vcn.push({ pid, cpu: +d.toFixed(1), vcndec: await hasVcn(pid) });
  }
  for (const k in g) g[k] = +g[k].toFixed(1);
  return { cpu: g, vtActive: vcn };
}

function describe(name, m) {
  const cod = name.replace(/^mx-/, '').split('-')[0];
  const codec = { h264: 'H.264', hevc: 'HEVC', hevc10: 'HEVC', vp9: 'VP9', vp9p2: 'VP9', av1: 'AV1', av110: 'AV1' }[cod] || cod;
  const depth = { hevc10: 'Main10 10-bit', vp9p2: 'profile 2 10-bit', av110: 'main 10-bit', hevc: 'Main 8-bit', h264: 'High 8-bit', vp9: 'profile 0 8-bit', av1: 'main 8-bit' }[cod] || '';
  const mime = m.mime || (name.endsWith('.webm') ? `video/webm; codecs="${m.codec}"` : null);
  return { codec, depth, size: `${m.height}p${m.fps}`, container: name.endsWith('.webm') ? 'WebM' : m.frag ? 'fMP4' : 'MP4', mime, fps: m.fps };
}

const cells = [];
for (const [name, m] of Object.entries(manifest)) {
  if (m.unsupported || (!name.startsWith('mx-') && !['vp9-1080p60.webm', 'av1-1080p60.webm', 'h264-1080p30.mp4', 'vp9-2160p60.webm'].includes(name))) continue;
  if (filter && !name.includes(filter)) continue;
  const d = describe(name, m), id = name.replace(/\.mp4$/, '-mp4').replace(/\.\w+$/, '');
  if (which !== 'quicktime') {
    if (!m.frag) cells.push({ app: 'Safari', id: `safari-${id}-file`, clip: name, d, mode: 'file' });
    if (d.mime && (name.endsWith('.webm') || m.frag)) cells.push({ app: 'Safari', id: `safari-${id}-mse`, clip: name, d, mode: 'mse' });
  }
  if (which !== 'safari' && name.endsWith('.mp4')) cells.push({ app: 'QuickTime', id: `qt-${id}`, clip: name, d, mode: 'file' });
}

const out = path.join(SUITE, 'results', `apple-${label}-${new Date().toISOString().slice(0, 16).replace(/[-:]/g, '').replace('T', '-')}`);
fs.mkdirSync(out, { recursive: true });
let onReport = () => {};
const srv = await startServer(port, { onReport: (o) => onReport(o) });

async function safariCell(cell) {
  const r = { app: 'Safari', id: cell.id, clip: cell.clip, ...cell.d, mode: cell.mode };
  const rows = [], checks = [], errors = []; let startWall = null, done = false;
  onReport = (o) => { if (o.case !== cell.id) return; if (o.type === 'row') rows.push(o); else if (o.type === 'check') checks.push(o); else if (o.type === 'start') startWall = o.wall; else if (o.type === 'done') done = true; else if (o.type === 'error') errors.push(o.msg || JSON.stringify(o)); };
  const q = new URLSearchParams({ clip: cell.clip, fps: cell.d.fps, case: cell.id, run: path.basename(out), warm: WARM, measure: MEASURE, ...(cell.mode === 'mse' ? { mse: cell.d.mime } : {}) });
  const url = `http://127.0.0.1:${port}/pages/matrix.html?${q}`;
  let wid = null, a, ta;
  try {
    // a new window of our own, small, top-right; its id is the only one we ever close
    wid = await osa(`tell application "Safari"
      make new document with properties {URL:"${url}"}
      set w to front window
      set bounds of w to {760, 40, 1400, 420}
      return id of w
    end tell`);
    for (let i = 0; i < 60 && !startWall && !errors.length; i++) await wait(250);
    if (startWall) {
      // fixed timing: a covered Safari window barely runs the page's timers, so do not wait for its phases
      await wait(WARM * 1000);
      a = await procs(); ta = Date.now();
      await wait(MEASURE * 1000);
      Object.assign(r, await cpuDelta(a, await procs(), (Date.now() - ta) / 1000));
    }
  } catch (e) { errors.push('osascript: ' + e.message.split('\n')[0]); }
  finally { if (wid) await osa(`tell application "Safari" to close (every window whose id is ${+wid})`).catch((e) => errors.push('close: ' + e.message)); }
  const mr = rows.filter((x) => x.phase !== 'load');   // every reported second after the start (hidden pages report few)
  r.decoded = mr.reduce((s, x) => s + x.decoded, 0); r.dropped = mr.reduce((s, x) => s + x.dropped, 0);
  // a hidden Safari page reports no decoded-frame deltas: the clock advancing is the sign that it plays
  const ct = mr.map((x) => x.ct).filter((x) => x != null); r.advanced = ct.length > 1 ? +(Math.max(...ct) - ct[0]).toFixed(2) : 0;
  r.plays = startWall && (r.decoded > 0 || r.advanced > 2) ? 'yes' : 'no';
  r.hidden = !mr.length || mr.every((x) => x.vis === 'hidden');   // window behind the owner's: Safari does not render it
  r.check = { ok: checks.reduce((s, c) => s + c.ok, 0), near: checks.reduce((s, c) => s + (c.near || 0), 0), timerReads: checks.reduce((s, c) => s + (c.timerReads || 0), 0), bad: checks.reduce((s, c) => s + c.bad, 0), unreadable: checks.reduce((s, c) => s + c.unreadable, 0), first: checks.flatMap((c) => c.mism).slice(0, 5) };
  r.errors = errors; r.rows = mr.map((x) => ({ sec: x.sec, decoded: x.decoded, dropped: x.dropped, rvfc: x.rvfc, skipped: x.skipped, vis: x.vis, focus: x.focus, ct: x.ct, paused: x.paused, rs: x.readyState, ahead: x.ahead }));
  return r;
}

async function qtCell(cell) {
  const r = { app: 'QuickTime', id: cell.id, clip: cell.clip, ...cell.d, mode: 'file', errors: [] };
  const file = path.join(CLIPS, cell.clip);
  // QuickTime documents have no "path" (only "file"), and the reply to "open" can hang: send open without waiting for
  // the reply, then find our document by its file. Only documents whose file is this clip are ever touched.
  const mine = (body) => `tell application "QuickTime Player"
      repeat with i from (count of documents) to 1 by -1
        try
          if POSIX path of (file of document i as alias) is "${file}" then
            set d to document i
            ${body}
          end if
        end try
      end repeat
    end tell`;
  let opened = false;
  try {
    const a = await procs(); const ta = Date.now();
    await osa(`tell application "QuickTime Player"
      ignoring application responses
        open POSIX file "${file}"
      end ignoring
    end tell`);
    opened = true;
    let t0 = '';
    for (let k = 0; k < 20 && t0 === ''; k++) {
      await wait(500);
      t0 = (await osa(mine(`set bounds of (first window whose name is (name of d)) to {760, 440, 1400, 820}
            play d
            return current time of d`))).trim();
    }
    if (t0 === '') throw new Error('document did not open');
    await wait(MEASURE * 1000);
    const t1 = (await osa(mine('return current time of d'))).trim();
    Object.assign(r, await cpuDelta(a, await procs(), (Date.now() - ta) / 1000));
    r.advanced = +(+t1 - +t0).toFixed(2);
    r.plays = r.advanced > MEASURE * 0.5 ? 'yes' : 'no';
  } catch (e) { r.plays = 'no'; r.errors.push('osascript: ' + e.message.split('\n').slice(0, 2).join(' ')); }
  finally { if (opened) await osa(mine('close d saving no')).catch((e) => r.errors.push('close: ' + e.message)); }
  return r;
}

const results = [];
for (const c of cells) {
  const t0 = Date.now();
  const r = c.app === 'Safari' ? await safariCell(c) : await qtCell(c);
  r.vcn = vcnVerdict(await vcnSessions(t0, Date.now()), FOURCC[c.d.codec.replace('.', '')] || []);
  // the page of a covered Safari window may report nothing: decoding is then seen from outside the page
  if (r.app === 'Safari' && r.plays !== 'yes') {
    const vcnOut = r.vcn.s.reduce((n, x) => n + (x.close?.out || 0), 0);
    if (vcnOut > 0) { r.plays = 'yes'; r.playsBy = `VCNDec decoded ${vcnOut} frames (page hidden)`; }
    else if ((r.cpu?.webkit_gpu ?? 0) + (r.cpu?.vtdecoder ?? 0) > 20) { r.plays = 'yes'; r.playsBy = `decoding in software: WebKit GPU ${r.cpu.webkit_gpu} % + VTDecoderXPCService ${r.cpu.vtdecoder} % CPU (page hidden)`; }
  }
  fs.writeFileSync(path.join(out, c.id + '.json'), JSON.stringify(r, null, 1));
  results.push(r);
  console.log(`${c.id}: plays ${r.plays} ${hw(r)} check ${r.check ? `${r.check.ok}/${r.check.near}/${r.check.bad}/${r.check.unreadable}` : '-'} cpu ${JSON.stringify(r.cpu ?? {})} ${r.errors?.[0] ?? ''}`);
  await wait(1500);
}
srv.close();
fs.writeFileSync(path.join(out, 'apple.md'), appleTable(results));
console.log('results: ' + out);

function hw(r) {
  if (r.plays !== 'yes') return '-';
  // hardware = VCNDec decoded it (unified log); a busy VTDecoderXPCService alone may be Apple's software decoder
  if (r.vcn?.v === 'vcn') return `HW (VCNDec ${r.vcn.s.find((x) => x.started)?.depth ?? 8}-bit)`;
  const where = (r.cpu?.vtdecoder ?? 0) > 5 ? 'VideoToolbox, Apple software' : r.app === 'Safari' ? 'WebKit' : 'QuickTime';
  return `**SW** (${where}${r.vcn?.v === 'refused' ? '; VCNDec refused' : r.vcn?.v === 'error' ? '; VCNDec failed' : ''})`;
}
export function appleTable(rs) {
  const L = ['| app | codec | profile / depth | size | container | plays | decoder | frame check ok / near / bad / unreadable | VTDec % | WebKit GPU % | WebContent % | QuickTime % | pass | note |',
    '|---|---|---|---|---|---|---|---|---|---|---|---|---|---|'];
  for (const r of rs) {
    const ck = r.check ? `${r.check.ok} / ${r.check.near} / ${r.check.bad} / ${r.check.unreadable}` : 'n/a (vt_check)';
    const pass = r.plays === 'yes' && /^HW/.test(hw(r)) && (!r.check || (r.hidden ? !r.check.unreadable : r.check.ok > 0 && !r.check.bad && !r.check.unreadable)) ? 'PASS' : 'FAIL';
    L.push(`| ${r.app} | ${r.codec} | ${r.depth} | ${r.size} | ${r.mode === 'mse' ? 'MSE ' + r.container : r.container} | ${r.plays} | ${hw(r)} | ${ck} | ${r.cpu?.vtdecoder ?? '-'} | ${r.cpu?.webkit_gpu ?? '-'} | ${r.cpu?.webcontent ?? '-'} | ${r.cpu?.quicktime ?? '-'} | ${pass} | ${[r.playsBy || (r.hidden ? 'page hidden (background window): few strip reads' : ''), (r.errors?.[0] || '').replace(/\|/g, '/').slice(0, 120)].filter(Boolean).join('; ')} |`);
  }
  return L.join('\n') + '\n';
}
