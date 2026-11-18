#!/usr/bin/env node
// One codec-matrix table for a label: every results/matrix-<label>-* (Chrome) and results/apple-<label>-* (Safari,
// QuickTime) run, latest result per cell id, one row per clip x container x app, PASS/FAIL.
// usage: node matrix-report.mjs <label> [out.md]   (default results/matrix-<label>.md)
import fs from 'node:fs';
import path from 'node:path';
import { SUITE } from './lib/server.mjs';

const label = process.argv[2]; if (!label) { console.error('usage: node matrix-report.mjs <label> [out.md]'); process.exit(2); }
const R = path.join(SUITE, 'results');
const dirs = fs.readdirSync(R).filter((d) => d.startsWith(`matrix-${label}-`) || d.startsWith(`apple-${label}-`)).sort();
const cells = new Map();
for (const d of dirs) for (const f of fs.readdirSync(path.join(R, d))) {
  if (!f.endsWith('.json')) continue;
  const r = JSON.parse(fs.readFileSync(path.join(R, d, f))); r.app ??= 'Chrome'; r.run = d;
  cells.set(`${r.app}:${r.id}`, r);   // later runs (sorted by date) replace earlier ones
}
const depthOf = (r) => r.vcn?.s?.find((x) => x.started)?.depth ?? 8;
function hw(r) {
  if (r.plays !== 'yes') return '-';
  if (r.vcn?.v === 'vcn') return `HW (VCNDec ${depthOf(r)}-bit)`;
  const why = r.vcn?.v === 'refused' ? '; VCNDec refused' : r.vcn?.v === 'error' ? '; VCNDec failed' : '';
  if (r.app === 'Chrome') return r.platform ? `**SW** (VideoToolbox, Apple software${why})` : `**SW** (Chrome ${(r.decoder || '?').replace('VideoDecoder', '')}${why})`;
  return `**SW** (${(r.cpu?.vtdecoder ?? 0) > 5 ? 'VideoToolbox, Apple software' : r.app === 'Safari' ? 'WebKit' : 'QuickTime'}${why})`;
}
function check(r) {
  if (!r.check) return r.app === 'QuickTime' ? 'n/a (vt_check)' : '-';
  return `${r.check.ok} / ${r.check.near ?? 0} / ${r.check.bad} / ${r.check.unreadable}`;
}
function pass(r) {
  if (r.plays === 'no clip') return 'no clip';
  const ck = !r.check || (r.hidden ? !r.check.unreadable : r.check.ok > 0 && !r.check.bad && !r.check.unreadable);
  return r.plays === 'yes' && r.vcn?.v === 'vcn' && ck ? 'PASS' : '**FAIL**';
}
const order = ['H.264', 'HEVC', 'VP9', 'AV1'], apps = ['Chrome', 'Safari', 'QuickTime'];
const rows = [...cells.values()].sort((a, b) => order.indexOf(a.codec) - order.indexOf(b.codec) || String(a.depth).localeCompare(String(b.depth))
  || String(a.size).localeCompare(String(b.size)) || String(a.container + a.mode).localeCompare(String(b.container + b.mode)) || apps.indexOf(a.app) - apps.indexOf(b.app));
const L = [`# Codec matrix: ${label}`, '', `Runs: ${dirs.join(', ')}`, '',
  'Pass = plays, decoded by VCNDec on the 890M VCN (its unified-log StartSession/close lines during the cell), and the frame-index strip check has no wrong (more than 6 frames off) or unreadable picture. Check columns: exact / 1-6 off (late draw) / wrong / unreadable. Safari cells in a background window (Safari does not render a covered window, so the page is hidden) are judged on plays (clock advances) + VCNDec + no unreadable picture: a stale drawImage there makes the index unreliable; QuickTime frames are checked outside the app with vt_check.', '',
  '| codec | profile / depth | size | container | app | plays | decoder | frame check | dropped / decoded | VTDec % | client % | pass | note |',
  '|---|---|---|---|---|---|---|---|---|---|---|---|---|'];
for (const r of rows) {
  const client = r.app === 'Chrome' ? (r.cpu?.gpu ?? '-') : r.app === 'Safari' ? (r.cpu?.webkit_gpu ?? '-') : (r.cpu?.quicktime ?? '-');
  const note = [r.playsBy || (r.hidden ? 'background window' : ''), ...(r.errors || []).slice(0, 1).map((e) => e.replace(/\|/g, '/').slice(0, 110)), r.notMade || ''].filter(Boolean).join('; ');
  L.push(`| ${r.codec} | ${r.depth} | ${r.size} | ${r.mode === 'mse' ? 'MSE ' + r.container : r.container} | ${r.app} | ${r.plays} | ${hw(r)} | ${check(r)} | ${r.dropped ?? '-'} / ${r.decoded ?? '-'} | ${r.cpu?.vtdecoder ?? '-'} | ${client} | ${pass(r)} | ${note} |`);
}
const sum = { PASS: 0, '**FAIL**': 0, 'no clip': 0 }; for (const r of rows) sum[pass(r)]++;
L.push('', `${sum.PASS} pass, ${sum['**FAIL**']} fail, ${sum['no clip']} without a clip (no 10-bit VP9 encoder on this machine).`);
const out = process.argv[3] || path.join(R, `matrix-${label}.md`);
fs.writeFileSync(out, L.join('\n') + '\n');
console.log(`${out}: ${rows.length} cells, ${sum.PASS} pass, ${sum['**FAIL**']} fail`);
