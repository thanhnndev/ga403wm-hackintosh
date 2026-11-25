// print the video decoder Chromium picked for the YouTube player (CDP Media domain) + YouTube stats
const l = await (await fetch('http://127.0.0.1:9333/json')).json(); const t = l.find(t => t.type==='page' && /youtube/.test(t.url));
const ws = new WebSocket(t.webSocketDebuggerUrl); let id=0; const out=[];
ws.onmessage = m => { const d=JSON.parse(m.data); if (d.method?.startsWith('Media.')) out.push(JSON.stringify(d.params)); if (d.id===2) console.log('stats', JSON.stringify(d.result?.result?.value)); };
await new Promise(r=>ws.onopen=r);
ws.send(JSON.stringify({id:++id, method:'Media.enable'}));
ws.send(JSON.stringify({id:++id, method:'Runtime.evaluate', params:{expression:"(()=>{const s=document.getElementById('movie_player').getStatsForNerds(); return {codecs:s.codecs, res:s.resolution, buf:s.buffer_health_seconds}})()", returnByValue:true}}));
await new Promise(r=>setTimeout(r,3000));
const all = out.join('\n'); console.log((all.match(/(Selected|Cannot select) [A-Za-z0-9]*VideoDecoder[^"\\]{0,80}/g)||[]).join('\n'));
console.log((all.match(/kVideoDecoderName[^}]*\}/g)||[]).join('\n')); console.log((all.match(/kIsPlatformVideoDecoder[^}]*\}/g)||[]).join('\n'));
process.exit(0);
