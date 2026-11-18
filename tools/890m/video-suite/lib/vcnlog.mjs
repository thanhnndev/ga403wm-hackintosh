// VCNDec sessions in a time window, from the unified log (subsystem com.ga403wm.vcndec). This is the hardware verdict
// for the codec matrix: "platform decoder" in Chrome only means VideoToolbox, and VideoToolbox also has Apple's own
// software decoders (HEVC, H.264, AV1) that run in the same VTDecoderXPCService. A cell is on the 890M VCN only if
// VCNDec logged "StartSession <codec> ... on the 890M VCN" during it, and its "close" line shows frames out, 0 errors.
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const sh = promisify(execFile);
const ts = (d) => { const p = (n) => String(n).padStart(2, '0'); return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`; };

export async function vcnSessions(t0, t1) {
  const { stdout } = await sh('/usr/bin/log', ['show', '--style', 'compact', '--start', ts(new Date(t0 - 1000)), '--end', ts(new Date(t1 + 2000)),
    '--predicate', 'subsystem == "com.ga403wm.vcndec"'], { maxBuffer: 32 << 20 }).catch((e) => ({ stdout: e.stdout || '' }));
  const byPid = new Map(), get = (pid, proc) => { if (!byPid.has(pid)) byPid.set(pid, { pid, proc, codec: null, started: false, refused: null, errors: [], close: null }); return byPid.get(pid); };
  for (const l of stdout.split('\n')) {
    const m = /\s(\S+)\[(\d+):[0-9a-f]+\] \[com\.ga403wm\.vcndec:decoder\] (VCNDEC .*)$/.exec(l); if (!m) continue;
    const s = get(+m[2], m[1]), msg = m[3];
    let x;
    if ((x = /^VCNDEC CreateInstance (\S{4})/.exec(msg))) s.codec = x[1];
    if ((x = /^VCNDEC StartSession (\S{4}) (\d+x\d+)(?: (\d+)-bit)?.* on the 890M VCN/.exec(msg))) { s.codec = x[1]; s.started = true; s.size = x[2]; s.depth = x[3] ? +x[3] : null; }
    if (/^VCNDEC StartSession .*refused/.test(msg)) s.refused = msg.slice(7);
    if (/^VCNDEC (StartSession|decode #)/.test(msg) && !/on the 890M VCN|refused/.test(msg)) s.errors.push(msg.slice(7, 160));
    if ((x = /^VCNDEC close: in (\d+) out (\d+) dropped (\d+) errors (\d+)/.exec(msg))) s.close = { in: +x[1], out: +x[2], dropped: +x[3], errors: +x[4] };
  }
  return [...byPid.values()];
}

// verdict for one cell: fourcc(s) the clip uses -> 'vcn' (VCNDec decoded it), 'refused' (VCNDec said no -> VT fell back),
// 'error' (VCNDec failed), or 'none' (VCNDec never asked)
export function vcnVerdict(sessions, fourccs) {
  const mine = sessions.filter((s) => fourccs.includes(s.codec));
  if (mine.some((s) => s.started && (!s.close || (s.close.out > 0 && !s.close.errors)) && !s.errors.length)) return { v: 'vcn', s: mine };
  if (mine.some((s) => s.refused)) return { v: 'refused', s: mine };
  if (mine.length) return { v: 'error', s: mine };
  return { v: 'none', s: [] };
}
export const FOURCC = { H264: ['avc1'], HEVC: ['hvc1', 'hev1'], VP9: ['vp09'], AV1: ['av01'] };
