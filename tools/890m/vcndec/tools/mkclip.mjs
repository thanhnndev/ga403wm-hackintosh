// make a 1920x1080 60 fps VP9 (or AV1) IVF clip with WebCodecs in the probe Edge; args: codec frames out
import fs from 'fs';
const [codec='vp09.00.41.08', frames='300', out='clip.ivf'] = process.argv.slice(2);
const l = await (await fetch('http://127.0.0.1:9333/json')).json(); const t = l.find(t => t.type==='page');
const ws = new WebSocket(t.webSocketDebuggerUrl); let id=0; const pend=new Map();
ws.onmessage = m => { const d=JSON.parse(m.data); if (d.id && pend.has(d.id)) { pend.get(d.id)(d); pend.delete(d.id);} };
await new Promise(r=>ws.onopen=r);
const ev = e => new Promise(r=>{const i=++id; pend.set(i,r); ws.send(JSON.stringify({id:i,method:'Runtime.evaluate',params:{expression:e,awaitPromise:true,returnByValue:true}}));});
const r = await ev(`(async()=>{
 const W=1920,H=1080,N=${frames}; const cv=new OffscreenCanvas(W,H); const g=cv.getContext('2d'); const chunks=[];
 const enc=new VideoEncoder({output:c=>{const b=new Uint8Array(c.byteLength); c.copyTo(b); chunks.push([c.timestamp,b])}, error:e=>{throw e}});
 enc.configure({codec:'${codec}', width:W, height:H, framerate:60, bitrate:12e6, latencyMode:'quality'});
 for(let i=0;i<N;i++){ const gr=g.createLinearGradient(0,0,W,H); gr.addColorStop(0,'hsl('+(i*3)+',80%,50%)'); gr.addColorStop(1,'hsl('+(i*3+180)+',80%,40%)');
  g.fillStyle=gr; g.fillRect(0,0,W,H); for(let k=0;k<60;k++){g.fillStyle='hsl('+(k*37+i)+',90%,60%)'; g.beginPath(); g.arc((k*331+i*(k%7+2)*4)%W,(k*197+i*(k%5+1)*3)%H,40+k%30,0,7); g.fill()}
  g.fillStyle='#fff'; g.font='120px sans-serif'; g.fillText('frame '+i,100,200);
  const f=new VideoFrame(cv,{timestamp:i*16667}); enc.encode(f,{keyFrame:i%120==0}); f.close(); if(enc.encodeQueueSize>8) await new Promise(r=>setTimeout(r,5)); }
 await enc.flush();
 let s=''; const parts=chunks.map(([ts,b])=>{let x=''; for(let j=0;j<b.length;j+=8192) x+=String.fromCharCode.apply(null,b.subarray(j,j+8192)); return [ts,btoa(x)]});
 return JSON.stringify(parts)})()`);
const v = r.result?.result?.value; if (!v) { console.log(JSON.stringify(r).slice(0,600)); process.exit(1); }
const parts = JSON.parse(v); const fourcc = codec.startsWith('av01') ? 'AV01' : 'VP90';
const hdr = Buffer.alloc(32); hdr.write('DKIF',0); hdr.writeUInt16LE(0,4); hdr.writeUInt16LE(32,6); hdr.write(fourcc,8); hdr.writeUInt16LE(1920,12); hdr.writeUInt16LE(1080,14); hdr.writeUInt32LE(60,16); hdr.writeUInt32LE(1,20); hdr.writeUInt32LE(parts.length,24);
const bufs=[hdr]; parts.forEach(([ts,b],i)=>{const d=Buffer.from(b,'base64'); const h=Buffer.alloc(12); h.writeUInt32LE(d.length,0); h.writeBigUInt64LE(BigInt(i),4); bufs.push(h,d)});
fs.writeFileSync(out, Buffer.concat(bufs)); console.log('wrote', out, parts.length, 'frames', Buffer.concat(bufs).length, 'bytes'); process.exit(0);
