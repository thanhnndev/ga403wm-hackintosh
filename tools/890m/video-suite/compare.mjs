#!/usr/bin/env node
// Before/after codec matrix: one row per app x clip x mode from two labels' results (latest run per cell),
// decoder and CPU (VideoToolbox XPC + the app's decoding process) side by side.
// usage: node compare.mjs <before-label> <after-label> [out.md]   (default results/compare-<before>-<after>.md)
import fs from 'node:fs';
import path from 'node:path';
import { SUITE } from './lib/server.mjs';

const [bl, al] = process.argv.slice(2); if (!bl || !al) { console.error('usage: node compare.mjs <before> <after> [out.md]'); process.exit(2); }
const R = path.join(SUITE, 'results');
function load(label) {
  const m = new Map();
  for (const d of fs.readdirSync(R).filter((d) => d.startsWith(`matrix-${label}-`) || d.startsWith(`apple-${label}-`)).sort())
    for (const f of fs.readdirSync(path.join(R, d))) if (f.endsWith('.json')) {
      const r = JSON.parse(fs.readFileSync(path.join(R, d, f))); r.app ??= 'Chrome';
      m.set(`${r.app}:${r.clip ?? r.id}:${r.mode}`, r);
    }
  return m;
}
const B = load(bl), A = load(al);
const dec = (r) => !r ? '-' : r.plays !== 'yes' ? (r.plays === 'no clip' ? 'no clip' : 'does not play')
  : r.vcn?.v === 'vcn' ? 'VCN' : r.app === 'Chrome' && !r.platform ? `SW ${(r.decoder || '').replace('VideoDecoder', '')}` : 'SW';
const client = (r) => r.app === 'Chrome' ? r.cpu?.gpu : r.app === 'Safari' ? r.cpu?.webkit_gpu : r.cpu?.quicktime;
const cpu = (r) => { if (!r?.cpu) return '-'; const v = (r.cpu.vtdecoder ?? 0) + (client(r) ?? 0); return v.toFixed(0); };
const pass = (r) => r && r.plays === 'yes' && r.vcn?.v === 'vcn';
const order = ['H.264', 'HEVC', 'VP9', 'AV1'], apps = ['Chrome', 'Safari', 'QuickTime'];
const keys = [...new Set([...B.keys(), ...A.keys()])].map((k) => ({ k, r: A.get(k) || B.get(k) }))
  .sort((x, y) => order.indexOf(x.r.codec) - order.indexOf(y.r.codec) || String(x.r.depth).localeCompare(String(y.r.depth))
    || String(x.r.size).localeCompare(String(y.r.size)) || String(x.r.container + x.r.mode).localeCompare(String(y.r.container + y.r.mode)) || apps.indexOf(x.r.app) - apps.indexOf(y.r.app));
let fixed = 0, still = 0, was = 0;
const L = [`# Codec matrix: ${bl} -> ${al}`, '', 'CPU % = VideoToolbox XPC service + the app\'s decoding process (Chrome GPU process, WebKit GPU process, QuickTime Player) over the measured window (Safari cells: a background window).', '',
  '| codec | profile / depth | size | container | app | before | after | CPU % before | CPU % after | |', '|---|---|---|---|---|---|---|---|---|---|'];
for (const { k, r } of keys) {
  const b = B.get(k), a = A.get(k);
  const st = pass(a) && !pass(b) ? 'fixed' : pass(a) ? 'was HW' : a?.plays === 'no clip' ? 'no clip' : '**still failing**';
  if (st === 'fixed') fixed++; else if (st === 'was HW') was++; else if (st.includes('still')) still++;
  L.push(`| ${r.codec} | ${r.depth} | ${r.size} | ${r.mode === 'mse' ? 'MSE ' + r.container : r.container} | ${r.app} | ${dec(b)} | ${dec(a)} | ${cpu(b)} | ${cpu(a)} | ${st} |`);
}
L.push('', `${fixed} cells fixed, ${was} already on the VCN before, ${still} still failing.`);
const out = process.argv[4] || path.join(R, `compare-${bl}-${al}.md`);
fs.writeFileSync(out, L.join('\n') + '\n');
console.log(`${out}: ${fixed} fixed, ${was} already HW, ${still} still failing`);
