#!/usr/bin/env node
// Builds the summary of a results directory (from run.sh): one row per case, and when the directory holds several
// rounds (r1, r2, ...) a spread table (min / median / max per metric across rounds).
// usage: node table.mjs <resultsdir>          -> markdown on stdout
//        import { load, row } for compare.mjs
import fs from 'node:fs';
import path from 'node:path';

export function loadRound(dir) {
  const out = {};
  for (const f of fs.readdirSync(dir).filter((f) => f.endsWith('.json')).sort()) {
    const s = JSON.parse(fs.readFileSync(path.join(dir, f))); out[s.case] = s;
  }
  return out;
}
export function load(dir) {
  const rounds = fs.readdirSync(dir).filter((d) => /^r\d+$/.test(d) && fs.statSync(path.join(dir, d)).isDirectory()).sort((a, b) => +a.slice(1) - +b.slice(1));
  return rounds.length ? rounds.map((r) => ({ name: r, cases: loadRound(path.join(dir, r)) })) : [{ name: '-', cases: loadRound(dir) }];
}
// flat metrics of one case summary, idle watts of the same round for the "above idle" column
export function row(s, idleW) {
  if (s.window) { const w = s.window; return { case: s.case, W: w.watts, dW: 0, tctl: w.tctl, ws: w.cpu.windowserver, kt: w.cpu.kernel_task, docker: w.cpu.docker, claude: w.cpu.claude, total: w.cpu.total, fps: w.nmx.frames_per_s }; }
  const m = s.phases?.measure || {}; const r = s.phases?.resume5 || {}; const p = s.phases?.pause || {};
  return { case: s.case, dec: (s.decoder || '-').replace('VideoDecoder', '') + (s.hwDecoder ? '' : ' (SW)'), secs: m.secs,
    decoded: m.decoded, dropped: m.dropped, skipped: m.skipped, late: m.late, p95: m.ivP95, p99: m.ivP99, max: m.ivMax,
    hidden: m.hiddenSecs, input: m.inputSecs, swapin: m.mem?.swapins, wiredGB: m.mem?.wiredGB, unfocused: m.unfocusedSecs, fsSecs: m.fsSecs, view: m.viewport,
    W: m.watts, preW: s.preIdle?.watts ?? null, dW: m.wattsOverPre ?? (m.watts != null && idleW != null ? +(m.watts - idleW).toFixed(2) : null), tctl: m.tctl,
    gpu: m.cpu?.gpu, rend: m.cpu?.renderer, ws: m.cpu?.windowserver, kt: m.cpu?.kernel_task, vtd: m.cpu?.vtdecoder,
    docker: m.cpu?.docker, claude: m.cpu?.claude, total: m.cpu?.total, fps: m.nmx?.frames_per_s,
    chunks: m.nmx ? `${m.nmx.chunks_filled}/${m.nmx.chunks_inline}/${m.nmx.chunks_freed}` : null,
    parks: m.nmx ? `${m.nmx.parks}/${m.nmx.unparks}` : null, fails: m.nmx ? (m.nmx.unpark_fail || 0) + (m.nmx.park_fail || 0) + (m.nmx.restore_fail || 0) + (m.nmx.timeouts || 0) + (m.nmx.fence_timeouts || 0) : null,
    freeMin: m.nmx?.page_free_min,
    r5drop: s.phases?.resume5 ? `${r.dropped}/${r.skipped}/${r.late}` : null,
    pauseW: p.watts ?? null, pauseParks: s.phases?.pause ? `${p.nmx?.parks}/${p.nmx?.unparks}` : null,
    resumeUnparks: s.phases?.resume5 ? r.nmx?.unparks : null, timedOut: s.timedOut, dist: s.disturbed ? 'DISTURBED' : '' };
}
const COLS = [['case', 'case'], ['dec', 'decoder'], ['decoded', 'decoded'], ['dropped', 'dropped'], ['skipped', 'skipped'], ['late', 'late'],
  ['p95', 'iv p95 ms'], ['p99', 'iv p99'], ['max', 'iv max'], ['W', 'pkg W'], ['preW', 'pre-idle W'], ['dW', 'W over pre-idle'], ['tctl', 'Tctl'],
  ['gpu', 'GPU-proc %'], ['rend', 'renderer %'], ['ws', 'WS %'], ['kt', 'kernel_task %'], ['vtd', 'VTDec %'], ['docker', 'Docker %'], ['total', 'all CPU %'],
  ['fps', 'NMX frames/s'], ['chunks', 'chunks fill/inl/free'], ['parks', 'parks/unparks'], ['fails', 'fails'], ['hidden', 'hidden s'], ['unfocused', 'unfocused s'], ['input', 'input s'], ['swapin', 'swapins'], ['wiredGB', 'wired GB'], ['dist', 'note']];
const fmt = (v) => (v == null ? '-' : String(v));
function idleOf(cases) { return cases.idle?.window?.watts ?? null; }
export function roundTable(cases) {
  const idle = idleOf(cases);
  const rs = Object.values(cases).map((s) => row(s, idle));
  const L = ['| ' + COLS.map((c) => c[1]).join(' | ') + ' |', '|' + COLS.map(() => '---').join('|') + '|'];
  for (const r of rs) L.push('| ' + COLS.map(([k]) => fmt(r[k])).join(' | ') + ' |');
  const sp = rs.filter((r) => r.r5drop);
  if (sp.length) {
    L.push('', 'seek + pause case: drops/skipped/late in the 5 s after resume, power while paused, parks/unparks while paused, unparks in the 5 s after resume', '');
    L.push('| case | resume 5 s drop/skip/late | pause W | pause parks/unparks | resume unparks |', '|---|---|---|---|---|');
    for (const r of sp) L.push(`| ${r.case} | ${r.r5drop} | ${fmt(r.pauseW)} | ${fmt(r.pauseParks)} | ${fmt(r.resumeUnparks)} |`);
  }
  return L.join('\n');
}
const SPREAD = [['dropped', 'dropped'], ['skipped', 'skipped'], ['late', 'late'], ['p95', 'iv p95 ms'], ['W', 'pkg W'], ['dW', 'W over pre-idle'], ['gpu', 'GPU-proc %'], ['ws', 'WS %'], ['kt', 'kernel_task %'], ['docker', 'Docker %']];
export const med = (a) => { const s = a.filter((x) => x != null).sort((x, y) => x - y); return s.length ? s[Math.floor((s.length - 1) / 2)] : null; };
export function spreadTable(rounds) {
  const names = [...new Set(rounds.flatMap((r) => Object.keys(r.cases)))];
  const L = ['| case | ' + SPREAD.map((c) => c[1] + ' min/med/max').join(' | ') + ' |', '|---|' + SPREAD.map(() => '---').join('|') + '|'];
  for (const n of names) {
    const rs = rounds.filter((r) => r.cases[n]).map((r) => row(r.cases[n], idleOf(r.cases)));
    L.push(`| ${n} | ` + SPREAD.map(([k]) => { const v = rs.map((r) => r[k]).filter((x) => x != null); return v.length ? `${Math.min(...v)} / ${med(v)} / ${Math.max(...v)}` : '-'; }).join(' | ') + ' |');
  }
  return L.join('\n');
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const dir = process.argv[2]; const rounds = load(dir);
  const ctx = path.join(dir, 'context.txt');
  console.log(`# video-suite results: ${path.basename(dir)}\n`);
  if (fs.existsSync(ctx)) console.log('```\n' + fs.readFileSync(ctx, 'utf8').split('\n').filter((l) => !l.startsWith('  ')).slice(0, 18).join('\n') + '\n```\n');
  if (rounds.length > 1) console.log(`## Spread over ${rounds.length} rounds\n\n${spreadTable(rounds)}\n`);
  for (const r of rounds) console.log(`## ${rounds.length > 1 ? 'Round ' + r.name : 'Cases'}\n\n${roundTable(r.cases)}\n`);
}
