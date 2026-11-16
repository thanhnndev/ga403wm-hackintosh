// Checks WebCodecs encode support (VP9/AV1/H.264 at 1080p60 and 4K60) and MSE type support in a scratch Chrome.
// The page must be a localhost http page (secure context); about:blank has no VideoEncoder. See checks/README in docs/VIDEO-SUITE-PLAN.md.
// usage: start Chrome --headless=new --user-data-dir=<scratch> --remote-debugging-port=9334 http://127.0.0.1:8765/ then node enccheck.mjs
const t=(await (await fetch('http://127.0.0.1:9334/json')).json()).find(x=>x.type==='page');
const ws=new WebSocket(t.webSocketDebuggerUrl); await new Promise(r=>ws.onopen=r);
const expr=`(async()=>{const o={};for(const [c,w,h,f] of [['vp09.00.51.08',1920,1080,60],['vp09.00.51.08',3840,2160,60],['av01.0.12M.08',1920,1080,60],['av01.0.13M.08',3840,2160,60],['avc1.640033',1920,1080,60]]){try{const s=await VideoEncoder.isConfigSupported({codec:c,width:w,height:h,framerate:f,bitrate:8e6});o[c+' '+w]=s.supported}catch(e){o[c+' '+w]='err '+e.message}} o.mse_vp9=MediaSource.isTypeSupported('video/webm; codecs="vp09.00.51.08"'); o.mse_av1=MediaSource.isTypeSupported('video/mp4; codecs="av01.0.08M.08"'); o.mse_av1webm=MediaSource.isTypeSupported('video/webm; codecs="av01.0.08M.08"'); return JSON.stringify(o)})()`;
ws.send(JSON.stringify({id:1,method:'Runtime.evaluate',params:{expression:expr,awaitPromise:true,returnByValue:true}}));
ws.onmessage=m=>{const d=JSON.parse(m.data); if(d.id===1){console.log(d.result.result.value||JSON.stringify(d)); process.exit(0)}};
