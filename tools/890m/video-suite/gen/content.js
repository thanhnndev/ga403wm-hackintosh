// ds-allow-hardcode: test-pattern colours, not UI
// Deterministic test content for the clips. Same frame index -> same pixels. Motion everywhere (gradient, moving
// shapes, scrolling text), two-layer grain so the encoder has to spend its bitrate like on real footage, and a large
// frame counter plus a 16-bit binary strip (bottom left) so a screen capture shows lost or repeated frames.
// The Swift generator (genmp4.swift) draws the same layout for H.264/HEVC.
function makeContent(W, H, fps, label) {
  const s = H / 1080;
  // seeded PRNG (mulberry32)
  let seed = 0x9e3779b9;
  const rnd = () => { seed |= 0; seed = (seed + 0x6D2B79F5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
  const tile = (n) => {
    const c = new OffscreenCanvas(n, n); const x = c.getContext('2d'); const d = x.createImageData(n, n);
    for (let p = 0; p < n * n; p++) { const v = rnd() * 255; d.data[p * 4] = d.data[p * 4 + 1] = d.data[p * 4 + 2] = v; d.data[p * 4 + 3] = 255; }
    x.putImageData(d, 0, 0); return c;
  };
  const g1 = tile(256), g2 = tile(193);    // co-prime sizes: the sum of two shifted layers is not one global motion
  const shapes = Array.from({ length: 24 }, (_, k) => ({ sp: (1.5 + rnd() * 6) * s, ph: rnd() * 6.28, sz: (40 + rnd() * 120) * s, hue: rnd() * 360, rs: (rnd() - 0.5) * 0.15, kind: k % 3 }));
  const words = 'the quick brown fox jumps over the lazy dog while frames tick by at a steady pace and every pixel moves'.split(' ');
  const lines = Array.from({ length: 64 }, () => Array.from({ length: 9 }, () => words[Math.floor(rnd() * words.length)]).join(' '));
  const hash = (i, k) => { let x = (i * 374761393 + k * 668265263) | 0; x = Math.imul(x ^ (x >>> 13), 1274126177); return ((x ^ (x >>> 16)) >>> 0); };
  return {
    draw(ctx, i) {
      const t = i / fps;
      const h0 = (i * 0.6) % 360;
      const gr = ctx.createLinearGradient(0, 0, W, H);
      gr.addColorStop(0, `hsl(${h0},60%,35%)`); gr.addColorStop(0.5, `hsl(${(h0 + 120) % 360},55%,30%)`); gr.addColorStop(1, `hsl(${(h0 + 240) % 360},60%,35%)`);
      ctx.globalAlpha = 1; ctx.globalCompositeOperation = 'source-over';
      ctx.fillStyle = gr; ctx.fillRect(0, 0, W, H);
      for (const [k, sh] of shapes.entries()) {
        const x = ((k * W / 24 + i * sh.sp) % (W + 2 * sh.sz)) - sh.sz;
        const y = H * 0.12 + H * 0.62 * (0.5 + 0.5 * Math.sin(t * 0.9 + sh.ph + k));
        ctx.save(); ctx.translate(x, y); ctx.rotate(i * sh.rs);
        ctx.fillStyle = `hsl(${(sh.hue + i) % 360},70%,55%)`;
        if (sh.kind === 0) ctx.fillRect(-sh.sz / 2, -sh.sz / 2, sh.sz, sh.sz);
        else if (sh.kind === 1) { ctx.beginPath(); ctx.arc(0, 0, sh.sz / 2, 0, 6.283); ctx.fill(); }
        else { ctx.beginPath(); ctx.moveTo(0, -sh.sz / 2); ctx.lineTo(sh.sz / 2, sh.sz / 2); ctx.lineTo(-sh.sz / 2, sh.sz / 2); ctx.fill(); }
        ctx.restore();
      }
      // scrolling text panel (right third)
      ctx.fillStyle = 'rgba(0,0,0,0.45)'; ctx.fillRect(W * 0.64, H * 0.08, W * 0.33, H * 0.78);
      ctx.save(); ctx.beginPath(); ctx.rect(W * 0.64, H * 0.08, W * 0.33, H * 0.78); ctx.clip();
      ctx.fillStyle = '#e8e8e8'; ctx.font = `${Math.round(24 * s)}px monospace`;
      const lh = 34 * s, off = (i * 3 * s) % (lines.length * lh);
      for (let L = 0; L < lines.length * 2; L++) { const y = H * 0.1 + L * lh - off; if (y > H * 0.06 && y < H * 0.9) ctx.fillText(lines[L % lines.length], W * 0.65, y); }
      ctx.restore();
      // grain: two co-prime tiles at per-frame pseudo-random offsets
      for (const [g, a, k] of [[g1, 0.10, 1], [g2, 0.08, 2]]) {
        const n = g.width, ox = hash(i, k) % n, oy = hash(i, k + 7) % n;
        ctx.globalAlpha = a; ctx.globalCompositeOperation = k === 1 ? 'overlay' : 'soft-light';
        for (let y = -oy; y < H; y += n) for (let x = -ox; x < W; x += n) ctx.drawImage(g, x, y);
      }
      ctx.globalAlpha = 1; ctx.globalCompositeOperation = 'source-over';
      // frame counter box (top left)
      ctx.fillStyle = 'rgba(0,0,0,0.75)'; ctx.fillRect(30 * s, 30 * s, 760 * s, 210 * s);
      ctx.fillStyle = '#ffffff'; ctx.font = `bold ${Math.round(120 * s)}px monospace`;
      ctx.fillText(String(i).padStart(5, '0'), 50 * s, 150 * s);
      ctx.font = `${Math.round(36 * s)}px monospace`;
      ctx.fillText(`t=${t.toFixed(3)}s ${label}`, 50 * s, 210 * s);
      // 16-bit frame index strip (bottom left), black/white cells, framed by a white border
      const c = Math.round(28 * s), x0 = 30 * s, y0 = H - 30 * s - c;
      ctx.fillStyle = '#ffffff'; ctx.fillRect(x0 - 4 * s, y0 - 4 * s, 16 * c + 8 * s, c + 8 * s);
      for (let b = 0; b < 16; b++) { ctx.fillStyle = (i >> (15 - b)) & 1 ? '#ffffff' : '#000000'; ctx.fillRect(x0 + b * c, y0, c, c); }
    },
  };
}
