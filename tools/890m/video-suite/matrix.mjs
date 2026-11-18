#!/usr/bin/env node
// Codec matrix: every clip in the cache's manifest that the matrix covers, played in scratch Chrome (small 800x480 window) as a
// plain file and, where it has an MSE type, through Media Source Extensions. Per cell: plays or not (and the error),
// decoder (platform = VCNDec / VideoToolbox, or the software decoder Chrome fell back to), drops, frame-counter check
// (pages/check.js), CPU and package watts over an 8 s idle taken right before the cell.
//
// usage: node matrix.mjs [label=build] [filter-substring]   -> results/matrix-<label>-<date>/{<cell>.json, matrix.md}
// Safari / QuickTime columns stay "waiting for owner permission" until main relays it.
import fs from 'node:fs';
import path from 'node:path';
import { startServer, CLIPS, SUITE } from './lib/server.mjs';
import { launch, killScratch, wait } from './lib/cdp.mjs';
import { startSampler, windowStats, pageStats, hidIdle } from './drive.mjs';

const label = process.argv[2] || 'build', filter = process.argv[3] || '';
const manifest = JSON.parse(fs.readFileSync(path.join(CLIPS, 'manifest.json')));
const WARM = 3, MEASURE = 12, PRE = +(process.env.VS_PREIDLE ?? 0);

// what a clip is, from its name: codec, profile/bit depth, size, fps, container
function describe(name, m) {
  const base = name.replace(/^mx-/, '');
  const [cod] = base.split('-');
  const codec = { h264: 'H.264', hevc: 'HEVC', hevc10: 'HEVC', vp9: 'VP9', vp9p2: 'VP9', av1: 'AV1', av110: 'AV1' }[cod] || cod;
  const depth = { hevc10: 'Main10 10-bit', vp9p2: 'profile 2 10-bit', av110: 'main 10-bit', hevc: 'Main 8-bit', h264: 'High 8-bit', vp9: 'profile 0 8-bit', av1: 'main 8-bit' }[cod] || '';
  const mime = m.mime || (name.endsWith('.webm') ? `video/webm; codecs="${m.codec}"` : null);
  return { codec, depth, size: `${m.height}p${m.fps}`, container: name.endsWith('.webm') ? 'WebM' : m.frag ? 'fMP4' : 'MP4', mime, fps: m.fps };
}
const cells = [];
for (const [name, m] of Object.entries(manifest)) {
  if (!name.startsWith('mx-') && !['vp9-1080p60.webm', 'av1-1080p60.webm', 'h264-1080p30.mp4', 'vp9-2160p60.webm'].includes(name)) continue;
  if (filter && !name.includes(filter)) continue;
  if (m.unsupported) { cells.push({ id: name.replace(/\.\w+$/, '') + '-file', clip: name, notMade: m.unsupported, d: describe(name, { ...m, height: '?', fps: '?' }) }); continue; }
  const d = describe(name, m);
  if (!m.frag) cells.push({ id: name.replace(/\.\w+$/, '') + '-file', clip: name, d, mode: 'file' });
  if (d.mime && (name.endsWith('.webm') || m.frag)) cells.push({ id: name.replace(/\.\w+$/, '') + '-mse', clip: name, d, mode: 'mse' });
}

const out = path.join(SUITE, 'results', `matrix-${label}-${new Date().toISOString().slice(0, 16).replace(/[-:]/g, '').replace('T', '-')}`);
fs.mkdirSync(out, { recursive: true });
const profile = path.join(CLIPS, '..', 'chrome-run');
const port = 8792;
let onReport = () => {};
const srv = await startServer(port, { onReport: (o) => onReport(o) });

async function runCell(cell) {
  const r = { id: cell.id, clip: cell.clip, ...cell.d, mode: cell.mode, started: new Date().toISOString() };
  if (cell.notMade) return { ...r, plays: 'no clip', error: 'could not make the clip on this machine: ' + cell.notMade };
  // correctness run: no wait for an idle machine; an optional idle reference (VS_PREIDLE seconds) without Chrome
  killScratch(profile);
  const smp = startSampler(profile);
  if (PRE) { await wait((PRE + 1.5) * 1000); const tp = Date.now(); r.preIdle = windowStats(smp.samples, tp - PRE * 1000, tp).watts; }
  const rows = [], checks = [], errors = []; let startWall = null, done = false;
  onReport = (o) => { if (o.case !== cell.id) return; if (o.type === 'row') rows.push(o); else if (o.type === 'check') checks.push(o); else if (o.type === 'start') startWall = o.wall; else if (o.type === 'done') done = true; else if (o.type === 'error') errors.push(o.msg || JSON.stringify(o)); };
  const media = {}; const mediaErr = []; let b;
  try {
    b = await launch(profile, 9342, { extra: ['--window-size=800,480', '--window-position=40,40', '--disable-backgrounding-occluded-windows', '--disable-renderer-backgrounding', '--disable-background-media-suspend', '--disable-background-timer-throttling'] });
    b.on((m) => {
      if (m.method === 'Media.playerPropertiesChanged') for (const p of m.params.properties) media[p.name] = p.value;
      if (m.method === 'Media.playerErrorsRaised') mediaErr.push(...m.params.errors.map((e) => `${e.errorType}:${e.code}`));
      if (m.method === 'Media.playerMessagesLogged') for (const x of m.params.messages) if (x.level === 'error') mediaErr.push(x.message.slice(0, 160));
    });
    await b.ps('Media.enable'); await b.ps('Page.enable');
    const q = new URLSearchParams({ clip: cell.clip, fps: cell.d.fps, case: cell.id, run: path.basename(out), warm: WARM, measure: MEASURE, ...(cell.mode === 'mse' ? { mse: cell.d.mime } : {}) });
    await b.ps('Page.navigate', { url: `http://127.0.0.1:${port}/pages/matrix.html?${q}` });
    for (let i = 0; i < 60 && !startWall && !errors.length; i++) await wait(250);
    if (startWall) { const lim = Date.now() + (WARM + MEASURE + 15) * 1000; while (!done && Date.now() < lim) await wait(250); }
    await wait(800);
  } finally { smp.stop(); try { b?.close(); } catch {} killScratch(profile); }
  r.decoder = media.kVideoDecoderName || null;
  r.platform = String(media.kIsPlatformVideoDecoder) === 'true';
  r.errors = [...errors, ...mediaErr];
  const mr = rows.filter((x) => x.phase === 'measure');
  r.plays = startWall && mr.length && mr.reduce((a, x) => a + x.decoded, 0) > 0 ? 'yes' : 'no';
  if (mr.length) {
    Object.assign(r, pageStats(mr, cell.d.fps), windowStats(smp.samples, mr[0].wall - 1000, mr.at(-1).wall));
    r.wattsOverPre = r.watts != null && r.preIdle != null ? +(r.watts - r.preIdle).toFixed(2) : null;
  }
  const ck = checks.filter((c) => !mr.length || (c.wall >= mr[0].wall - 1000 && c.wall <= mr.at(-1).wall + 1000));
  r.check = { ok: ck.reduce((a, c) => a + c.ok, 0), near: ck.reduce((a, c) => a + (c.near || 0), 0), bad: ck.reduce((a, c) => a + c.bad, 0), unreadable: ck.reduce((a, c) => a + c.unreadable, 0), first: ck.flatMap((c) => c.mism).slice(0, 5) };
  return r;
}

const results = [];
for (const c of cells) {
  const r = await runCell(c);
  fs.writeFileSync(path.join(out, c.id + '.json'), JSON.stringify(r, null, 1));
  results.push(r);
  console.log(`${c.id}: plays ${r.plays} ${r.decoder ?? '-'}${r.platform ? ' (platform)' : ''} dropped ${r.dropped ?? '-'} check ${r.check?.ok ?? '-'}/${r.check?.bad ?? '-'}/${r.check?.unreadable ?? '-'} ${r.wattsOverPre ?? '-'} W ${r.errors?.length ? 'ERR ' + r.errors[0] : ''}`);
  await wait(2000);
}
srv.close();
fs.writeFileSync(path.join(out, 'matrix.md'), matrixTable(results));
console.log('results: ' + out);

export function matrixTable(rs) {
  const pass = (r) => (r.plays === 'yes' && r.platform && r.check?.ok > 0 && !r.check.bad && !r.check.unreadable ? 'PASS' : 'FAIL');
  const hw = (r) => (r.plays !== 'yes' ? '-' : r.platform ? (/VideoToolbox/.test(r.decoder) ? 'HW (VideoToolbox)' : 'HW') : `**SW** (${(r.decoder || '?').replace('VideoDecoder', '')})`);
  const L = ['| codec | profile / depth | size | container | plays | decoder | dropped / decoded | late | frame check ok / near / bad / unreadable | GPU-proc % | renderer % | WS % | W over pre-idle | pass | note |',
    '|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|'];
  for (const r of rs) {
    const note = r.errors?.length ? r.errors[0].replace(/\|/g, '/').slice(0, 120) : '';
    L.push(`| ${r.codec} | ${r.depth} | ${r.size} | ${r.mode === 'mse' ? 'MSE ' + r.container : r.container} | ${r.plays} | ${hw(r)} | ${r.dropped ?? '-'} / ${r.decoded ?? '-'} | ${r.late ?? '-'} | ${r.check ? `${r.check.ok} / ${r.check.near ?? 0} / ${r.check.bad} / ${r.check.unreadable}` : '-'} | ${r.cpu?.gpu ?? '-'} | ${r.cpu?.renderer ?? '-'} | ${r.cpu?.windowserver ?? '-'} | ${r.wattsOverPre ?? '-'} | ${pass(r)} | ${note} |`);
  }
  return L.join('\n') + '\n';
}
