#!/usr/bin/env node
// Where did dropped frames land? For every measured, visible second: drop seconds vs clean seconds, averaged
// (presentation gap max, CPU, swap-ins, input, NMX park/unpark/chunk deltas) plus the list of drop seconds.
// usage: node where.mjs results/<run>/**/*.tsv

import fs from 'node:fs'; import path from 'node:path';
const files = process.argv.slice(2);
const D = ['userwire_parks','userwire_unparks','page_chunks_filled','page_chunks_freed','page_chunks_inline'];
const agg = {drop:{n:0}, clean:{n:0}}; const events = [];
for (const f of files) {
  const L = fs.readFileSync(f,'utf8').trim().split('\n'); const h = L[0].split('\t'); const ix = Object.fromEntries(h.map((k,i)=>[k,i]));
  if (ix.dropped == null) continue;
  let prev = null;
  for (const l of L.slice(1)) {
    const c = l.split('\t'); const g = (k) => ix[k] == null ? null : (c[ix[k]] === '-' || c[ix[k]] === '' ? null : +c[ix[k]]);
    if (c[ix.phase] !== 'measure' && !['pre','seek','resume5','post'].includes(c[ix.phase])) { prev = c; continue; }
    if (c[ix.vis] !== 'visible') { prev = c; continue; }
    const row = { f: path.basename(path.dirname(f))+'/'+path.basename(f,'.tsv'), t: c[0], dropped: g('dropped'), skipped: g('skipped'), ivmax: g('iv_max'), input: g('input'), swapin: g('swapin'),
      ws: g('cpu_windowserver'), gpu: g('cpu_gpu'), total: g('cpu_total'), kt: g('cpu_kernel_task'), watts: g('watts') };
    for (const k of D) row[k] = prev && ix[k] != null && prev[ix[k]] !== '-' && c[ix[k]] !== '-' ? +c[ix[k]] - +prev[ix[k]] : null;
    const b = row.dropped > 0 || row.skipped > 0 ? 'drop' : 'clean'; const a = agg[b]; a.n++;
    for (const k of ['ivmax','ws','gpu','total','kt','input','swapin',...D]) if (row[k] != null) { a[k] = (a[k]||0) + row[k]; a[k+'_n'] = (a[k+'_n']||0) + 1; if (k !== 'ivmax' && k !== 'ws' && k!=='gpu' && k!=='total' && k!=='kt' && row[k] > 0) a[k+'_nz'] = (a[k+'_nz']||0)+1; }
    if (b === 'drop') events.push(row);
    prev = c;
  }
}
for (const [b,a] of Object.entries(agg)) {
  const out = {secs: a.n};
  for (const k of ['ivmax','ws','gpu','total','kt','input','swapin',...D]) if (a[k+'_n']) { out[k+'_avg'] = +(a[k]/a[k+'_n']).toFixed(1); if (a[k+'_nz'] != null || ['input','swapin',...D].includes(k)) out[k+'_secs>0'] = `${a[k+'_nz']||0}/${a[k+'_n']}`; }
  console.log(b, JSON.stringify(out));
}
console.log('\ndrop seconds:');
for (const e of events) console.log([e.f, e.t, 'drop', e.dropped, 'skip', e.skipped, 'ivmax', e.ivmax, 'in', e.input, 'swapin', e.swapin, 'parks', e.userwire_parks, 'unparks', e.userwire_unparks, 'fill', e.page_chunks_filled, 'freed', e.page_chunks_freed, 'WS', e.ws, 'all', e.total].join(' '));
