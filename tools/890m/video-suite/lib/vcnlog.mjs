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
  // one record per decoder session: a VTDecoderXPCService (or WebKit GPU process) hosts many sessions in a row, and
  // probes (CreateInstance of another codec) must not relabel the running one. A session's StartSession, decode and
  // close lines come from the same thread, so key the open session by pid:tid.
  const all = [], open = new Map(), pending = new Map();
  for (const l of stdout.split('\n')) {
    const m = /\s(\S+)\[(\d+):([0-9a-f]+)\] \[com\.ga403wm\.vcndec:decoder\] (VCNDEC .*)$/.exec(l); if (!m) continue;
    const pid = +m[2], key = `${pid}:${m[3]}`, msg = m[4];
    const fresh = (codec) => { const s = { pid, proc: m[1], codec, started: false, refused: null, errors: [], close: null }; all.push(s); open.set(key, s); return s; };
    let x;
    if ((x = /^VCNDEC CreateInstance (\S{4})/.exec(msg))) { pending.set(pid, x[1]); continue; }
    if ((x = /^VCNDEC StartSession (\S{4}) (\d+x\d+)(?: (\d+)-bit)?.* on the 890M VCN/.exec(msg))) {
      const s = fresh(x[1]); s.started = true; s.size = x[2]; s.depth = x[3] ? +x[3] : null; continue; }
    if ((x = /^VCNDEC StartSession (\S{4})/.exec(msg))) {
      const s = fresh(x[1]); if (/refused/.test(msg)) s.refused = msg.slice(7); else s.errors.push(msg.slice(7, 160)); continue; }
    const s = open.get(key) || fresh(pending.get(pid) || null);
    if (/^VCNDEC decode #/.test(msg)) s.errors.push(msg.slice(7, 160));
    if ((x = /^VCNDEC close: in (\d+) out (\d+) dropped (\d+) errors (\d+)/.exec(msg))) { s.close = { in: +x[1], out: +x[2], dropped: +x[3], errors: +x[4] }; open.delete(key); }
  }
  return all;
}

// verdict for one cell: fourcc(s) the clip uses -> 'vcn' (VCNDec decoded it), 'refused' (VCNDec said no -> VT fell back),
// 'error' (VCNDec failed), or 'none' (VCNDec never asked)
export function vcnVerdict(sessions, fourccs) {
  // sessions of the VCNDec test tools (vt_check, vt_test, vcndec_test) running at the same time are not the app's
  const mine = sessions.filter((s) => fourccs.includes(s.codec) && !/^(vt_check|vt_test|vcndec_test)$/.test(s.proc));
  if (mine.some((s) => s.started && (!s.close || (s.close.out > 0 && !s.close.errors)) && !s.errors.length)) return { v: 'vcn', s: mine };
  if (mine.some((s) => s.refused)) return { v: 'refused', s: mine };
  if (mine.length) return { v: 'error', s: mine };
  return { v: 'none', s: [] };
}
export const FOURCC = { H264: ['avc1'], HEVC: ['hvc1', 'hev1'], VP9: ['vp09'], AV1: ['av01'] };
