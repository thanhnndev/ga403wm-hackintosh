// YouTube playback probe over CDP, for a scratch-profile Chrome started with --remote-debugging-port.
// Prints a per-second timeline (play rate, decoded, dropped, rVFC callbacks, seconds buffered ahead) so network
// buffering, decode stalls and presentation drops can be told apart. Skips pre-roll ads before measuring.
//
// usage: node probe.mjs [port=9333] [videoId=LXb3EKWsInQ] [quality=hd1080] [seconds=40] [pauses=0]
//   pauses > 0: pause for 3 s that many times during the run (evenly spaced) and report drops in the 5 s after each
//   resume, to measure the drop burst on resume.
const [port, vid, quality, secs, pauses] = [process.argv[2] || '9333', process.argv[3] || 'LXb3EKWsInQ',
  process.argv[4] || 'hd1080', +(process.argv[5] || 40), +(process.argv[6] || 0)];
const wait = ms => new Promise(r => setTimeout(r, ms));
const tabs = await (await fetch(`http://127.0.0.1:${port}/json`)).json();
const tab = tabs.find(t => t.type === 'page');
const ws = new WebSocket(tab.webSocketDebuggerUrl);
await new Promise(r => ws.onopen = r);
let id = 0; const pend = new Map();
ws.onmessage = e => { const m = JSON.parse(e.data); if (m.id && pend.has(m.id)) { pend.get(m.id)(m); pend.delete(m.id); } };
const send = (method, params = {}) => new Promise(r => { const i = ++id; pend.set(i, r); ws.send(JSON.stringify({ id: i, method, params })); });
const ev = async (expr) => { const r = await send('Runtime.evaluate', { expression: expr, awaitPromise: true, returnByValue: true }); return r.result?.result?.value ?? r.result?.exceptionDetails?.text; };
const log = (...a) => console.log(new Date().toTimeString().slice(0, 8), ...a);

await send('Page.enable');
await send('Page.navigate', { url: `https://www.youtube.com/watch?v=${vid}` });
for (let i = 0; i < 60; i++) { await wait(1000); if (await ev(`!!(document.querySelector('video') && document.getElementById('movie_player')?.setPlaybackQualityRange)`)) break; }
await ev(`(async()=>{const v=document.querySelector('video'); v.muted=true; try{await v.play();}catch(e){} return 1;})()`);
// pre-roll ads: the player carries the ad-showing class while one plays
let adSecs = 0;
for (let i = 0; i < 180; i++) { const ad = await ev(`document.getElementById('movie_player').classList.contains('ad-showing')`); if (!ad) break; adSecs++; await wait(1000); }
if (adSecs) log('skipped ad', adSecs, 's');
await ev(`(async()=>{const p=document.getElementById('movie_player'); const v=document.querySelector('video');
  try{p.setPlaybackQualityRange('${quality}','${quality}');}catch(e){} v.muted=true; try{await v.play();}catch(e){} return 1;})()`);
for (let i = 0; i < 30; i++) { await wait(1000); if (await ev(`document.querySelector('video').videoHeight`) >= 1080) break; }
await wait(4000);   // let the quality switch settle
log('measure start', JSON.stringify(await ev(`(()=>{const p=document.getElementById('movie_player'); const v=document.querySelector('video');
  let c=''; try{c=p.getStatsForNerds().codecs;}catch(e){} return {h:v.videoHeight, codec:c};})()`)));
const r = await ev(`(async()=>{const p=document.getElementById('movie_player'); const v=document.querySelector('video');
  const evs={waiting:0,stalled:0,seeking:0}; for(const k in evs) v.addEventListener(k,()=>evs[k]++);
  const tl=[]; let rv=0, procMax=0, procSum=0;
  const cb=(now,md)=>{rv++; if(md.processingDuration!=null){procSum+=md.processingDuration; if(md.processingDuration>procMax) procMax=md.processingDuration;} v.requestVideoFrameCallback(cb);};
  v.requestVideoFrameCallback(cb);
  const ah=()=>{for(let i=0;i<v.buffered.length;i++) if(v.buffered.start(i)<=v.currentTime+0.1&&v.buffered.end(i)>=v.currentTime) return v.buffered.end(i)-v.currentTime; return 0;};
  const N=${secs}, P=${pauses}, at=new Set(); for(let k=1;k<=P;k++) at.add(Math.round(k*N/(P+1)));
  let q=v.getVideoPlaybackQuality(), ct=v.currentTime, rvl=0, t=performance.now(); const q0=q, t0=t; let playSecs=0, ct0=ct;
  const resumes=[]; let watch=null;
  for(let s=1;s<=N;s++){
    if(at.has(s)){ v.pause(); await new Promise(res=>setTimeout(res,3000)); const qa=v.getVideoPlaybackQuality(); await v.play(); watch={d:qa.droppedVideoFrames, n:qa.totalVideoFrames, left:5};
      q=v.getVideoPlaybackQuality(); ct=v.currentTime; rvl=rv; t=performance.now(); }
    await new Promise(res=>setTimeout(res,1000)); const n=performance.now(); const q1=v.getVideoPlaybackQuality();
    tl.push([s, ((v.currentTime-ct)/((n-t)/1000)).toFixed(2), q1.totalVideoFrames-q.totalVideoFrames, q1.droppedVideoFrames-q.droppedVideoFrames, rv-rvl, ah().toFixed(1), v.readyState].join(' '));
    if(watch && --watch.left==0){ resumes.push({dropped:q1.droppedVideoFrames-watch.d, decoded:q1.totalVideoFrames-watch.n}); watch=null; }
    q=q1; ct=v.currentTime; rvl=rv; t=n; }
  const q1=v.getVideoPlaybackQuality(); const dt=(performance.now()-t0)/1000;
  return {h:v.videoHeight, decoded:q1.totalVideoFrames-q0.totalVideoFrames, dropped:q1.droppedVideoFrames-q0.droppedVideoFrames, rvfc:rv,
    procAvgMs:(procSum/Math.max(rv,1)*1000).toFixed(2), procMaxMs:(procMax*1000).toFixed(1), evs, resumes,
    timeline:'sec playRate decoded dropped rvfc aheadS readyState\\n'+tl.join('\\n')};})()`);
console.log(r.timeline); delete r.timeline;
log('summary', JSON.stringify(r));
ws.close();
