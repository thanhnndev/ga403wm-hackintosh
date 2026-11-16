#!/usr/bin/env node
// Per-case diff of two results directories (medians across rounds when a directory has several).
// usage: node compare.mjs <A> <B>   (compare.sh wraps it)
import path from 'node:path';
import { load, row, med } from './table.mjs';

const [A, B] = process.argv.slice(2).map((d) => ({ dir: d, rounds: load(d) }));
const KEYS = [['dropped', 'drops'], ['skipped', 'skipped'], ['late', 'late'], ['p95', 'iv p95'], ['W', 'pkg W'], ['dW', 'W>idle'], ['gpu', 'GPU %'], ['ws', 'WS %'], ['kt', 'kt %'], ['docker', 'Docker %']];
const agg = (X, n) => { const rs = X.rounds.filter((r) => r.cases[n]).map((r) => row(r.cases[n], r.cases.idle?.window?.watts ?? null));
  return Object.fromEntries(KEYS.map(([k]) => [k, med(rs.map((r) => r[k]))])); };
const names = [...new Set([...A.rounds, ...B.rounds].flatMap((r) => Object.keys(r.cases)))];
console.log(`A = ${path.basename(A.dir)} (${A.rounds.length} round(s))   B = ${path.basename(B.dir)} (${B.rounds.length} round(s)); values A -> B (B-A)\n`);
const w = 20;
console.log('case'.padEnd(18) + KEYS.map(([, h]) => h.padStart(w)).join(''));
for (const n of names) {
  const a = agg(A, n), b = agg(B, n);
  console.log(n.padEnd(18) + KEYS.map(([k]) => {
    if (a[k] == null && b[k] == null) return '-'.padStart(w);
    const d = a[k] != null && b[k] != null ? b[k] - a[k] : null;
    return `${a[k] ?? '-'}->${b[k] ?? '-'}${d != null ? ` (${d > 0 ? '+' : ''}${+d.toFixed(2)})` : ''}`.padStart(w);
  }).join(''));
}
