// Edge hitch probe over CDP: rVFC + rAF gaps > 25 ms, dropped frames; args: port seconds quality
const [port='9333', secs='60', q='hd1080'] = process.argv.slice(2);
const sleep = ms => new Promise(r => setTimeout(r, ms));
let tgt;
for (let i = 0; i < 60 && !tgt; i++) { try { const l = await (await fetch(`http://127.0.0.1:${port}/json`)).json(); tgt = l.find(t => t.type === 'page' && /youtube/.test(t.url)); } catch {} if (!tgt) await sleep(1000); }
if (!tgt) { console.log('no youtube page'); process.exit(2); }
const ws = new WebSocket(tgt.webSocketDebuggerUrl); let id = 0; const pend = new Map();
ws.onmessage = m => { const d = JSON.parse(m.data); if (d.id && pend.has(d.id)) { pend.get(d.id)(d); pend.delete(d.id); } };
await new Promise(r => ws.onopen = r);
const send = (method, params = {}) => new Promise(r => { const i = ++id; pend.set(i, r); ws.send(JSON.stringify({ id: i, method, params })); });
const ev = async e => { const r = await send('Runtime.evaluate', { expression: e, awaitPromise: true, returnByValue: true }); return r.result?.result?.value ?? r.result?.exceptionDetails?.text; };
for (let i = 0; i < 30; i++) { if (await ev(`!!document.querySelector('video') && document.querySelector('video').readyState >= 2`)) break; await sleep(1000); }
console.log('setup', await ev(`(async()=>{const v=document.querySelector('video'); v.muted=true; const p=document.getElementById('movie_player');
  try{p.setPlaybackQualityRange('${q}','${q}')}catch(e){} v.play(); await new Promise(r=>setTimeout(r,8000)); return (p.getPlaybackQuality?p.getPlaybackQuality():'?')+' '+v.videoWidth+'x'+v.videoHeight+' t='+v.currentTime.toFixed(1)})()`));
const res = await ev(`(async()=>{const v=document.querySelector('video'); const q0=v.getVideoPlaybackQuality(); const vf=[], af=[];
  let on=true; const f=(n,m)=>{vf.push(m.presentationTime??n); if(on) v.requestVideoFrameCallback(f)}; v.requestVideoFrameCallback(f);
  const a=t=>{af.push(t); if(on) requestAnimationFrame(a)}; requestAnimationFrame(a);
  await new Promise(r=>setTimeout(r,${secs}*1000)); on=false; const q1=v.getVideoPlaybackQuality();
  const g=x=>{const d=[]; for(let i=1;i<x.length;i++) d.push(x[i]-x[i-1]); const s=[...d].sort((a,b)=>a-b);
    return {n:d.length, over25:d.filter(y=>y>25).length, over50:d.filter(y=>y>50).length, worst:Math.round(s[s.length-1]||0), p99:+(s[Math.floor(s.length*.99)]||0).toFixed(1), med:+(s[Math.floor(s.length/2)]||0).toFixed(1)}};
  const big=[]; for(let i=1;i<af.length;i++){const d=af[i]-af[i-1]; if(d>50) big.push(Math.round(af[i]))}
  return JSON.stringify({res:v.videoWidth+'x'+v.videoHeight, decoded:q1.totalVideoFrames-q0.totalVideoFrames, dropped:q1.droppedVideoFrames-q0.droppedVideoFrames, rvfc:g(vf), raf:g(af), rafBigAt:big.slice(0,20), t0:Math.round(performance.timeOrigin)})})()`);
console.log(res); ws.close(); process.exit(0);
