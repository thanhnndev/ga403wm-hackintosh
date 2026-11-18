// Codec-matrix add-on for play: loaded before suite.js by matrix.html.
//  - ?mse=<mime>: plays the clip through Media Source Extensions (1 MB appends, like a streaming site) instead of src=.
//  - frame-counter check: on every 6th presented frame, reads the 16-bit frame index strip (bottom left, drawn by
//    gen/content.js and gen/genmp4.swift) from the video and compares it with round(mediaTime * fps). A wrong index
//    more than 6 frames off ("bad") means a wrong picture; 1-6 off ("near") is a late draw (drawImage takes the newest frame); an unreadable strip (its white border not white) means a corrupt picture.
//    Posts {type:'check'} once a second: ok / bad / unreadable and the first few mismatches.
(() => {
  const P = new URLSearchParams(location.search);
  const fps = +(P.get('fps') || 60), clip = P.get('clip'), mse = P.get('mse');
  const caseName = P.get('case') || clip, run = P.get('run') || '';
  const v = document.getElementById('v');
  const post = (o) => fetch('/report', { method: 'POST', body: JSON.stringify({ case: caseName, run, ...o }), keepalive: true }).catch(() => {});

  if (mse) {
    window.vsSource = (video) => {
      if (!window.MediaSource || !MediaSource.isTypeSupported(mse)) { post({ type: 'error', msg: `MSE: type not supported: ${mse}` }); return; }
      const ms = new MediaSource();
      video.src = URL.createObjectURL(ms);
      ms.addEventListener('sourceopen', async () => {
        let sb;
        try { sb = ms.addSourceBuffer(mse); } catch (e) { post({ type: 'error', msg: 'MSE addSourceBuffer: ' + e.message }); return; }
        const size = +(await fetch('/clips/' + clip, { method: 'HEAD' })).headers.get('content-length');
        for (let a = 0; a < size; a += 1 << 20) {
          const b = Math.min(size, a + (1 << 20)) - 1;
          const buf = await (await fetch('/clips/' + clip, { headers: { Range: `bytes=${a}-${b}` } })).arrayBuffer();
          try { sb.appendBuffer(buf); } catch (e) { post({ type: 'error', msg: 'MSE appendBuffer: ' + e.message }); return; }
          await new Promise((r) => sb.addEventListener('updateend', r, { once: true }));
        }
        try { ms.endOfStream(); } catch {}
      }, { once: true });
    };
  }

  // strip geometry, same as content.js / genmp4.swift: cell c = round(28 s), x0 = 30 s, bottom edge 30 s above the frame bottom
  let cv = null, ctx = null, geo = null;
  let ok = 0, bad = 0, near = 0, unreadable = 0, n = 0; const mism = [];
  const read = (md) => {
    const W = v.videoWidth, H = v.videoHeight; if (!W) return;
    if (!geo || geo.H !== H) {
      const s = H / 1080, c = Math.round(28 * s), x0 = 30 * s, y0 = H - 30 * s - c, m = 4 * s;
      geo = { H, s, c, sx: Math.floor(x0 - m), sy: Math.floor(y0 - m), sw: Math.ceil(16 * c + 2 * m), sh: Math.ceil(c + 2 * m), m };
      cv = new OffscreenCanvas(geo.sw, geo.sh); ctx = cv.getContext('2d', { willReadFrequently: true });
    }
    const g = geo;
    ctx.drawImage(v, g.sx, g.sy, g.sw, g.sh, 0, 0, g.sw, g.sh);
    const d = ctx.getImageData(0, 0, g.sw, g.sh).data;
    const luma = (x, y) => { x = Math.round(x); y = Math.round(y); const i = (y * g.sw + x) * 4; return 0.2126 * d[i] + 0.7152 * d[i + 1] + 0.0722 * d[i + 2]; };
    // border: the white frame around the cells, sampled left and right of the strip
    const border = Math.min(luma(g.m / 2, g.sh / 2), luma(g.sw - g.m / 2, g.sh / 2));
    if (border < 170) { unreadable++; if (mism.length < 5) mism.push({ t: +md.mediaTime.toFixed(3), border: Math.round(border) }); return; }
    let idx = 0;
    for (let b = 0; b < 16; b++) idx = (idx << 1) | (luma(g.m + b * g.c + g.c / 2, g.m + g.c / 2) > 128 ? 1 : 0);
    const want = Math.round(md.mediaTime * fps);
    if (idx === want) ok++; else if (Math.abs(idx - want) <= 6) near++; else { bad++; if (mism.length < 5) mism.push({ t: +md.mediaTime.toFixed(3), want, got: idx }); }
  };
  let lastCb = 0, timerReads = 0;
  const safe = (md) => { try { read(md); } catch (e) { unreadable++; if (mism.length < 5) mism.push({ err: e.message }); } };
  const cb = (now, md) => { lastCb = performance.now(); if (++n % 6 === 0) safe(md); v.requestVideoFrameCallback(cb); };
  v.requestVideoFrameCallback(cb);
  // Safari in a background window gives no rVFC callbacks at all: read on a timer against currentTime instead
  // (the clock, not the shown frame: only "bad" = more than 6 frames off counts as a wrong picture there)
  setInterval(() => { if (!v.paused && v.readyState >= 2 && performance.now() - lastCb > 500) { timerReads++; safe({ mediaTime: v.currentTime }); } }, 100);
  setInterval(() => { if (ok + near + bad + unreadable) post({ type: 'check', wall: Date.now(), ok, near, bad, unreadable, timerReads, mism: mism.splice(0) }); ok = near = bad = unreadable = timerReads = 0; }, 1000);
})();
