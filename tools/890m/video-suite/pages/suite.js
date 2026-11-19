// Page side of the suite. Plays ?clip= and POSTs one row per second to /report, so any browser works (Safari too:
// no CDP needed). The page also runs the scenario itself (?scenario=plain|seekpause) and labels each row's phase.
//
// Per row: decoded/dropped deltas from getVideoPlaybackQuality(); rVFC callbacks, frames skipped (gaps in the
// presented mediaTime, i.e. frames the viewer never saw), backwards steps, and every presented-frame interval in ms
// (from rVFC expectedDisplayTime); waiting/stalled events, readyState, buffered-ahead; visibility, focus, fullscreen,
// viewport. The runner aligns rows with its own power/CPU/driver samples by wall time.
const P = new URLSearchParams(location.search);
const clip = P.get('clip'), fps = +(P.get('fps') || 60), scenario = P.get('scenario') || 'plain';
const caseName = P.get('case') || clip, run = P.get('run') || '';
const WARM = +(P.get('warm') || 10), MEASURE = +(P.get('measure') || 60);
const v = document.getElementById('v');

const post = (o) => fetch('/report', { method: 'POST', body: JSON.stringify({ case: caseName, run, ...o }), keepalive: true }).catch(() => {});
const ev = { waiting: 0, stalled: 0, seeking: 0, error: 0 };
for (const k of Object.keys(ev)) v.addEventListener(k, () => ev[k]++);
v.addEventListener('error', () => post({ type: 'error', msg: v.error && v.error.message, code: v.error && v.error.code }));

// presented-frame bookkeeping (rVFC)
let rv = 0, skipped = 0, back = 0, intervals = [], prevIdx = null, prevEdt = null, prevPf = null, missedCb = 0;
const resetChain = () => { prevIdx = null; prevEdt = null; prevPf = null; };
v.addEventListener('seeked', resetChain); v.addEventListener('play', resetChain); v.addEventListener('pause', resetChain);
const cb = (now, md) => {
  rv++;
  const idx = Math.round(md.mediaTime * fps);
  if (prevIdx !== null) {
    const gap = idx - prevIdx;
    if (gap > 1) skipped += gap - 1; else if (gap <= 0) back++;
    intervals.push(+(md.expectedDisplayTime - prevEdt).toFixed(2));
    if (md.presentedFrames - prevPf > 1) missedCb += md.presentedFrames - prevPf - 1;   // presented, but no callback
  }
  prevIdx = idx; prevEdt = md.expectedDisplayTime; prevPf = md.presentedFrames;
  v.requestVideoFrameCallback(cb);
};
v.requestVideoFrameCallback(cb);

const ahead = () => { for (let i = 0; i < v.buffered.length; i++) if (v.buffered.start(i) <= v.currentTime + 0.1 && v.buffered.end(i) >= v.currentTime) return +(v.buffered.end(i) - v.currentTime).toFixed(1); return 0; };

// scenario: list of [phase, seconds, action at phase start]
const SCEN = {
  plain: [['warm', WARM], ['measure', MEASURE]],
  // seek, then a 70 s pause (longer than the 60 s IOSurface park in NMXGPU Step142b), then resume
  seekpause: [['warm', WARM], ['pre', 10], ['seek', 5, () => { v.currentTime = 40; }], ['pause', 70, () => v.pause()],
    ['resume5', 5, () => v.play()], ['post', 15]],
};
const plan = SCEN[scenario]; let pi = 0, phaseLeft = plan[0][1];
let started = false, sec = 0, q0 = null, wallStart = 0;

function tick() {
  const q = v.getVideoPlaybackQuality();
  const row = { type: 'row', sec, phase: started ? plan[pi][0] : 'load', wall: Date.now(),
    decoded: q0 ? q.totalVideoFrames - q0.totalVideoFrames : 0, dropped: q0 ? q.droppedVideoFrames - q0.droppedVideoFrames : 0,
    rvfc: rv, skipped, back, missedCb, intervals, ...ev, readyState: v.readyState, ahead: ahead(), ct: +v.currentTime.toFixed(3),
    paused: v.paused, vis: document.visibilityState, focus: document.hasFocus(), fs: !!document.fullscreenElement,
    vw: innerWidth, vh: innerHeight, dpr: devicePixelRatio, vidW: v.videoWidth, vidH: v.videoHeight };
  q0 = q; rv = 0; skipped = 0; back = 0; missedCb = 0; intervals = []; for (const k in ev) ev[k] = 0;
  post(row);
  if (!started) return;
  sec++;
  if (--phaseLeft <= 0) {
    pi++;
    if (pi >= plan.length) { post({ type: 'done', sec }); v.pause(); return 'done'; }
    phaseLeft = plan[pi][1]; if (plan[pi][2]) plan[pi][2]();
  }
}
// self-correcting 1 s clock (setInterval drifts)
function schedule() {
  const next = wallStart + (sec + 1) * 1000;
  setTimeout(() => { if (tick() !== 'done') schedule(); }, Math.max(0, next - performance.now()));
}
v.addEventListener('playing', () => {
  if (started) return;
  started = true; q0 = v.getVideoPlaybackQuality(); wallStart = performance.now(); sec = 0;
  post({ type: 'start', wall: Date.now(), vidW: v.videoWidth, vidH: v.videoHeight, clip, fps, scenario });
  schedule();
}, { once: false });
window.__vs = { v, fullscreen: () => v.requestFullscreen(), state: () => ({ started, sec, phase: plan[pi] && plan[pi][0] }) };
if (window.vsSource) window.vsSource(v); else v.src = '/clips/' + clip;
v.play().catch((e) => post({ type: 'error', msg: 'play(): ' + e.message }));
