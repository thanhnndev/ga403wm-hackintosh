#!/usr/bin/python3 -I
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 thanhnndev and contributors
"""Generate the RogControl speaker test set (no dependencies; voice labels use macOS `say` when available).

Writes 48 kHz / 16 bit / stereo WAV files into the output directory (default build/audio-test) and an index.json that
RogControl reads. Everything is synthesized, so the files are free of third party rights.

  full.wav           ~70 s all-round check: spoken sections, music with kick/snare/hat/bass/chords/pluck, sweeps, noise
  music.wav          ~26 s stereo mix (full range, transients, bass line, chords, stereo spread)
  voice.wav          spoken sentences (intelligibility / sibilance), left, right, centre
  sweep-left/right   20 Hz -> 20 kHz log sweep on one channel
  bass-left/right    stepped sine tones 31..125 Hz on one channel (woofer)
  treble-left/right  pink-noise bursts high-passed at 3 kHz plus 4/6/8/10/12/16 kHz tones (tweeter)
  noise-left/right   pink noise per channel (frequency response by ear, rattles)
  transients         kick/snare/click train (driver speed, enclosure rattle)
  imaging            moving pluck left -> right -> left (pan law, channel balance)
  polarity           200 Hz and 1 kHz in phase, then L/R out of phase (wiring/phase check)
"""
import array, json, math, os, random, struct, subprocess, sys, wave

SR = 48000
OUT = sys.argv[1] if len(sys.argv) > 1 else "build/audio-test"
os.makedirs(OUT, exist_ok=True)
random.seed(7)
TAU = 2 * math.pi


def n(sec): return int(round(sec * SR))


class Buf:
    def __init__(self, sec):
        self.L = [0.0] * n(sec); self.R = [0.0] * n(sec)

    def add(self, sig, t, l=1.0, r=1.0):
        i = n(t)
        if i >= len(self.L): return
        m = min(len(sig), len(self.L) - i)
        if l:
            L = self.L
            for k in range(m): L[i + k] += sig[k] * l
        if r:
            R = self.R
            for k in range(m): R[i + k] += sig[k] * r

    def extend_to(self, sec):
        k = n(sec) - len(self.L)
        if k > 0: self.L += [0.0] * k; self.R += [0.0] * k


def env(sig, a=0.005, rel=0.02):
    na, nr = n(a), n(rel)
    out = list(sig)
    for i in range(min(na, len(out))): out[i] *= i / na
    for i in range(min(nr, len(out))): out[-1 - i] *= i / nr
    return out


def tone(f, dur, amp=0.5, fade=0.02):
    return env([amp * math.sin(TAU * f * i / SR) for i in range(n(dur))], fade, fade)


def sweep(f0, f1, dur, amp=0.5):
    k = math.log(f1 / f0) / dur
    out = []
    for i in range(n(dur)):
        t = i / SR
        out.append(amp * math.sin(TAU * f0 * (math.exp(k * t) - 1) / k))
    return env(out, 0.05, 0.05)


def pink(dur, amp=0.4):
    rows = [0.0] * 7; out = []; s = 0.0
    for i in range(n(dur)):
        for r in range(7):
            if i % (1 << r) == 0:
                s -= rows[r]; rows[r] = random.uniform(-1, 1); s += rows[r]
        out.append(amp * (s + random.uniform(-1, 1)) / 8.0)
    return out


def highpass(sig, fc):
    a = math.exp(-TAU * fc / SR); y = 0.0; x1 = 0.0; out = []
    for x in sig:
        y = a * (y + x - x1); x1 = x; out.append(y)
    return out


def lowpass(sig, fc):
    a = 1 - math.exp(-TAU * fc / SR); y = 0.0; out = []
    for x in sig:
        y += a * (x - y); out.append(y)
    return out


def kick(amp=0.9):
    out = []; ph = 0.0
    for i in range(n(0.28)):
        t = i / SR
        f = 45 + 110 * math.exp(-t * 28)
        ph += TAU * f / SR
        out.append(amp * math.sin(ph) * math.exp(-t * 9))
    return env(out, 0.001, 0.01)


def snare(amp=0.5):
    noise = highpass([random.uniform(-1, 1) for _ in range(n(0.2))], 1500)
    return env([amp * (0.8 * noise[i] * math.exp(-i / SR * 20) + 0.5 * math.sin(TAU * 190 * i / SR) * math.exp(-i / SR * 28))
                for i in range(n(0.2))], 0.001, 0.01)


def hat(amp=0.25, d=0.05):
    noise = highpass([random.uniform(-1, 1) for _ in range(n(d))], 6500)
    return env([amp * noise[i] * math.exp(-i / SR * 70) for i in range(n(d))], 0.0005, 0.005)


def pluck(f, dur=0.6, amp=0.35):
    out = []
    for i in range(n(dur)):
        t = i / SR
        v = sum(h_amp * math.sin(TAU * f * h * t) * math.exp(-t * (3 + h * 2.2))
                for h, h_amp in ((1, 1.0), (2, 0.5), (3, 0.33), (4, 0.2), (5, 0.12), (6, 0.08)))
        out.append(amp * v)
    return env(out, 0.002, 0.03)


def bass_note(f, dur, amp=0.55):
    out = []
    for i in range(n(dur)):
        t = i / SR
        out.append(amp * (math.sin(TAU * f * t) + 0.35 * math.sin(TAU * 2 * f * t) + 0.12 * math.sin(TAU * 3 * f * t)) * math.exp(-t * 2.2))
    return env(out, 0.004, 0.03)


def pad(freqs, dur, amp=0.12):
    out = []
    for i in range(n(dur)):
        t = i / SR
        v = 0.0
        for f in freqs:
            v += math.sin(TAU * f * t) + 0.4 * math.sin(TAU * 2.003 * f * t) + 0.2 * math.sin(TAU * 3.01 * f * t)
        out.append(amp * v / len(freqs))
    return env(out, 0.25, 0.5)


def midi(m): return 440.0 * 2 ** ((m - 69) / 12)


def music(sec_bars=12, bpm=112):
    beat = 60.0 / bpm; bar = 4 * beat
    total = sec_bars * bar + 1.0
    b = Buf(total)
    prog = [(33, [57, 60, 64]), (29, [53, 57, 60]), (36, [55, 60, 64]), (31, [55, 59, 62])]   # Am F C G
    lead_scale = [69, 72, 74, 76, 79, 76, 74, 72]
    for k in range(sec_bars):
        t0 = k * bar
        root, chord = prog[k % 4]
        if k >= 1:                                              # drums
            for q in range(4):
                b.add(kick(), t0 + q * beat, 0.9, 0.9)
                for e in range(2):
                    b.add(hat(), t0 + q * beat + e * beat / 2, 0.55 if e == 0 else 0.9, 0.9 if e == 0 else 0.55)
            b.add(snare(), t0 + beat, 0.8, 0.8); b.add(snare(), t0 + 3 * beat, 0.8, 0.8)
        for q in range(8):                                       # bass line
            b.add(bass_note(midi(root + (12 if q % 4 == 3 else 0)), beat / 2 * 0.9), t0 + q * beat / 2, 0.8, 0.8)
        b.add(pad([midi(c) for c in chord], bar * 0.98), t0, 1.0, 0.7)       # chord pad, left-leaning
        b.add(pad([midi(c + 12) for c in chord], bar * 0.98, 0.07), t0, 0.7, 1.0)
        if k >= 2:                                               # lead pluck, pan wanders
            for q in range(8):
                pan = 0.5 + 0.5 * math.sin(TAU * (k * 8 + q) / 24)
                note = lead_scale[(q + k) % len(lead_scale)] + (0 if k % 4 else 12)
                b.add(pluck(midi(note)), t0 + q * beat / 2, 1.0 - pan * 0.8, 0.2 + pan * 0.8)
    return b


def say(text, voice="Samantha"):
    path = os.path.join(OUT, "_say.aiff"); wav = os.path.join(OUT, "_say.wav")
    try:
        subprocess.run(["say", "-v", voice, "-o", path, text], check=True, capture_output=True)
        subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16@48000", "-c", "1", path, wav], check=True, capture_output=True)
        with wave.open(wav, "rb") as w:
            raw = w.readframes(w.getnframes())
        s = struct.unpack("<%dh" % (len(raw) // 2), raw)
        out = [x / 32768.0 * 0.9 for x in s]
        return out
    except Exception:
        return tone(500, 0.3, 0.2)


def silence(sec): return [0.0] * n(sec)


def soft(buf, drive):
    if drive <= 1.0: return buf
    k = 1.0 / math.tanh(drive)
    m = max(max(map(abs, buf.L), default=0), max(map(abs, buf.R), default=0), 1e-9)
    buf.L = [math.tanh(drive * x / m) * k for x in buf.L]; buf.R = [math.tanh(drive * x / m) * k for x in buf.R]
    return buf


def write_wav(name, buf, peak_db=-0.7):
    m = max(max(map(abs, buf.L), default=0), max(map(abs, buf.R), default=0), 1e-9)
    g = 10 ** (peak_db / 20) / m
    data = array.array("h")
    for l, r in zip(buf.L, buf.R):
        data.append(int(max(-1, min(1, l * g)) * 32767)); data.append(int(max(-1, min(1, r * g)) * 32767))
    with wave.open(os.path.join(OUT, name), "wb") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes(data.tobytes())
    return len(buf.L) / SR


def one(sig, left=True):
    b = Buf(len(sig) / SR + 0.1)
    b.add(sig, 0.05, 1.0 if left else 0.0, 0.0 if left else 1.0)
    return b


def seq(parts, gap=0.25):
    out = []
    for p in parts: out += p + silence(gap)
    return out


index = []


def emit(name, title, group, desc, buf, channels="stereo", drive=1.0):
    d = write_wav(name, soft(buf, drive))
    index.append({"file": name, "title": title, "group": group, "description": desc, "channels": channels, "seconds": round(d, 1)})
    print(f"{name:20s} {d:6.1f} s  {title}")


# --- individual tests ---------------------------------------------------------------------------------------------
sw = sweep(20, 20000, 14, 0.5)
emit("sweep-left.wav", "Left sweep 20 Hz-20 kHz", "Drivers", "Log sweep on the left channel only. Listen for rattles, gaps, distortion, level steps.", one(sw, True), "left")
emit("sweep-right.wav", "Right sweep 20 Hz-20 kHz", "Drivers", "Log sweep on the right channel only.", one(sw, False), "right")
bass_steps = [31.5, 40, 50, 63, 80, 100, 125]
bs = seq([tone(f, 1.6, 0.6, 0.05) for f in bass_steps], 0.3)
emit("bass-left.wav", "Left bass 31-125 Hz", "Drivers", "Stepped sine tones for the left woofer pair (31.5, 40, 50, 63, 80, 100, 125 Hz).", one(bs, True), "left")
emit("bass-right.wav", "Right bass 31-125 Hz", "Drivers", "Stepped sine tones for the right woofer pair.", one(bs, False), "right")
tw = seq([env(highpass(pink(1.5, 0.9), 3000), 0.02, 0.05)] + [tone(f, 1.2, 0.35, 0.05) for f in (4000, 6000, 8000, 10000, 12000, 16000)], 0.25)
emit("treble-left.wav", "Left treble 3-16 kHz", "Drivers", "High-passed noise and tones for the left tweeter.", one(tw, True), "left")
emit("treble-right.wav", "Right treble 3-16 kHz", "Drivers", "High-passed noise and tones for the right tweeter.", one(tw, False), "right")
pn = pink(8, 0.8)
emit("noise-left.wav", "Left pink noise", "Drivers", "Full-range pink noise, left only. Compare tone with the right channel.", one(env(pn, 0.05, 0.1), True), "left", 2.2)
emit("noise-right.wav", "Right pink noise", "Drivers", "Full-range pink noise, right only.", one(env(pn, 0.05, 0.1), False), "right", 2.2)

tr = Buf(14)
for i in range(8):
    tr.add(kick(), 0.2 + i * 0.5, 0.9, 0.9)
for i in range(8):
    tr.add(snare(), 4.4 + i * 0.4, 0.8, 0.8)
for i in range(16):
    tr.add(env([0.9] + [0.0] * 40, 0.0, 0.0), 8.0 + i * 0.25, 0.7, 0.7)       # single-sample-ish clicks
for i in range(12):
    tr.add(hat(0.7, 0.08), 12.2 + i * 0.12, 0.7, 0.7)
emit("transients.wav", "Transients", "Quality", "Kicks, snares, clicks and hats: driver speed, enclosure rattle, amp limiting.", tr, "stereo", 1.4)

im = Buf(14)
for i in range(28):
    pan = 0.5 - 0.5 * math.cos(TAU * i / 28)
    im.add(pluck(midi(69 if i % 2 else 76), 0.45, 0.5), 0.2 + i * 0.45, math.cos(pan * math.pi / 2), math.sin(pan * math.pi / 2))
emit("imaging.wav", "Stereo imaging", "Quality", "A note moves left -> right -> left. It should travel smoothly across the machine with no holes or jumps.", im, "stereo", 1.5)

pol = Buf(18)
for k, f in enumerate((200, 1000)):
    t = 0.2 + k * 8
    pol.add(tone(f, 3, 0.5, 0.05), t, 1.0, 1.0)
    pol.add(tone(f, 3, 0.5, 0.05), t + 3.5, 1.0, -1.0)
emit("polarity.wav", "Polarity", "Quality", "200 Hz and 1 kHz in phase (focused, louder in the middle) then out of phase (hollow, diffuse). "
     "If both sound alike a channel is missing or the amps are summed.", pol)

mu = music(12, 112)
emit("music.wav", "Music mix", "Quality", "Synthetic band: kick, snare, hats, bass line, chord pads and a panning lead. Judge balance, bass depth, brightness, width.", mu, "stereo", 1.8)

v = []
lines_c = ["Testing the speakers. The quick brown fox jumps over the lazy dog.",
           "She sells seashells by the seashore. Six slippery snails slid slowly seaward.",
           "Peter Piper picked a peck of pickled peppers. Zero, one, two, three, four, five, six, seven, eight, nine."]
vb = Buf(60)
t = 0.3
for i, text in enumerate(lines_c):
    s = say(text)
    side = (1.0, 0.0) if i == 0 else ((0.0, 1.0) if i == 1 else (0.8, 0.8))
    vb.add(s, t, side[0], side[1]); t += len(s) / SR + 0.8
vb.extend_to(t)
vb.L = vb.L[:n(t)]; vb.R = vb.R[:n(t)]
emit("voice.wav", "Speech", "Quality", "Spoken sentences: left, right, then centre. Check intelligibility and sibilance (s, sh, t).", vb, "stereo", 1.6)


# --- cinema / surround (stereo: interaural time + level difference, rear = darker and a bit quieter) -------------------
def reverb(sig, wet=0.3, size=1.0):
    combs = [(int(SR * d * size), g) for d, g in ((0.0297, 0.80), (0.0371, 0.78), (0.0411, 0.76), (0.0437, 0.74))]
    out = [0.0] * (len(sig) + n(1.2 * size))
    for dl, g in combs:
        buf = [0.0] * dl; idx = 0
        for i in range(len(out)):
            x = sig[i] if i < len(sig) else 0.0
            y = buf[idx]; buf[idx] = x + g * y; idx = (idx + 1) % dl
            out[i] += y * 0.25
    for dl, g in ((int(SR * 0.005), 0.7), (int(SR * 0.0017), 0.7)):
        buf = [0.0] * dl; idx = 0
        for i in range(len(out)):
            y = buf[idx]; x = out[i] + (-g) * y; buf[idx] = x; out[i] = y + g * x; idx = (idx + 1) % dl
    res = [out[i] * wet + (sig[i] if i < len(sig) else 0.0) * (1 - wet) for i in range(len(out))]
    return res


def spatial(sig, az, level=None):
    """az(t) in degrees (0 front, +90 right, 180 behind); returns (L, R)."""
    nn = len(sig)
    L = [0.0] * nn; R = [0.0] * nn
    ly = 0.0; ry = 0.0
    for i in range(nn):
        t = i / SR
        a = math.radians(az(t))
        s_ = math.sin(a); c_ = math.cos(a)
        itd = 0.00065 * s_ * SR                                   # +: right ear leads
        gl = math.sqrt(0.5 * (1 - 0.85 * s_)); gr = math.sqrt(0.5 * (1 + 0.85 * s_))
        rear = max(0.0, -c_)                                      # 0 front .. 1 behind
        fcL = (16000 - 12000 * max(0.0, s_) - 9000 * rear)        # far ear and rear are duller
        fcR = (16000 - 12000 * max(0.0, -s_) - 9000 * rear)
        aL = 1 - math.exp(-TAU * max(fcL, 1500) / SR); aR = 1 - math.exp(-TAU * max(fcR, 1500) / SR)

        def tap(d):
            j = i - d
            if j < 0: return 0.0
            j0 = int(j); fr = j - j0
            x0 = sig[j0]; x1 = sig[j0 + 1] if j0 + 1 < nn else x0
            return x0 + (x1 - x0) * fr
        xl = tap(max(0.0, itd)); xr = tap(max(0.0, -itd))
        lv = (level(t) if level else 1.0) * (1.0 - 0.3 * rear)
        ly += aL * (xl * gl * lv - ly); ry += aR * (xr * gr * lv - ry)
        L[i] = ly; R[i] = ry
    return L, R


def stereo_noise(dur, amp=0.5):
    return [[amp * random.uniform(-1, 1) for _ in range(n(dur))] for _ in range(2)]


def lfe_boom(dur=3.0, amp=0.9, f0=70.0):
    out = []; ph = 0.0
    for i in range(n(dur)):
        t = i / SR
        f = 28 + (f0 - 28) * math.exp(-t * 4)
        ph += TAU * f / SR
        out.append(amp * math.sin(ph) * math.exp(-t * 1.6) + 0.25 * amp * math.sin(2.07 * ph) * math.exp(-t * 3))
    return env(out, 0.003, 0.2)


def rumble(dur, amp=0.6, fc=90):
    return lowpass(lowpass([random.uniform(-1, 1) for _ in range(n(dur))], fc), fc * 1.3)


def wind_surround():
    return None


# 1. circle around the listener
dur = 16.0
src = [x * 0.9 for x in pink(dur, 0.9)]
Lc, Rc = spatial(src, lambda t: (t / 8.0) * 360.0)
b = Buf(dur + 0.2); b.add(env(Lc, 0.1, 0.1), 0.05, 1, 0); b.add(env(Rc, 0.1, 0.1), 0.05, 0, 1)
emit("circle.wav", "Around the head", "Cinema", "Noise circles you twice: front, right, behind, left. Behind should sound duller and "
     "wider than in front; the movement should be smooth with no jump at the sides.", b, "stereo", 2.0)

# 2. helicopter flyover
dur = 14.0
rotor = []
bn = lowpass([random.uniform(-1, 1) for _ in range(n(dur))], 900)
for i in range(n(dur)):
    t = i / SR
    chop = 0.5 * (1 + math.sin(TAU * 17 * t)) ** 2
    rotor.append(chop * (0.55 * bn[i] + 0.5 * math.sin(TAU * 52 * t) + 0.2 * math.sin(TAU * 104 * t)))
Lc, Rc = spatial(rotor, lambda t: -120 + 240 * t / dur, lambda t: 0.25 + 0.75 * math.sin(math.pi * t / dur))
b = Buf(dur + 0.2); b.add(env(Lc, 0.2, 0.3), 0.05, 1, 0); b.add(env(Rc, 0.2, 0.3), 0.05, 0, 1)
emit("helicopter.wav", "Helicopter flyover", "Cinema", "A helicopter passes from behind-left over the top to front-right "
     "(rotor chop, low thump, level rises and falls).", b, "stereo", 1.6)

# 3. rain and thunder
dur = 20.0
rain = stereo_noise(dur, 0.5)
rain = [highpass(lowpass(ch, 9000), 1200) for ch in rain]
b = Buf(dur + 1)
b.add(env(rain[0], 1.0, 1.5), 0.0, 1, 0); b.add(env(rain[1], 1.0, 1.5), 0.0, 0, 1)
for t0, side, a in ((3.0, -60, 0.8), (9.5, 70, 1.0), (15.0, 160, 0.9)):
    rb = rumble(3.5 + a)
    th = [rb[i] * 6 * math.exp(-i / SR * 0.9) * (1 + 0.5 * math.sin(TAU * 7 * i / SR)) for i in range(n(3.5 + a))]
    Lc, Rc = spatial(th, lambda t, s_=side: s_, None)
    b.add(env(Lc, 0.05, 1.0), t0, a * 2.4, 0); b.add(env(Rc, 0.05, 1.0), t0, 0, a * 2.4)
    b.add(lfe_boom(3.0, 0.5, 45.0), t0, 0.6 * a, 0.6 * a)
emit("storm.wav", "Rain and thunder", "Cinema", "Wide rain bed with three thunder claps: left-front, right, behind. "
     "Checks wide noise bed plus deep rumble together.", b, "stereo", 1.7)

# 4. explosion with debris and a reverb tail
dur = 12.0
b = Buf(dur)
for t0, az_, a in ((0.5, 0, 1.0), (5.5, -70, 0.9), (9.0, 100, 1.0)):
    boom = lfe_boom(3.5, a, 75.0)
    crack = highpass([random.uniform(-1, 1) * math.exp(-i / SR * 14) for i in range(n(0.6))], 800)
    deb = [random.uniform(-1, 1) * (1 if random.random() < 0.003 else 0) * math.exp(-i / SR * 1.2) for i in range(n(3.0))]
    mix = [0.0] * n(3.5)
    for i, v in enumerate(boom): mix[i] += v
    for i, v in enumerate(crack): mix[i] += 0.8 * v
    for i, v in enumerate(deb): mix[i] += 1.5 * v
    mix = reverb(mix, 0.35, 1.5)
    Lc, Rc = spatial(mix, lambda t, s_=az_: s_)
    b.add(Lc, t0, 1, 0); b.add(Rc, t0, 0, 1)
emit("explosion.wav", "Explosions", "Cinema", "Three blasts: ahead, left, right-rear. Sub-bass thump, crack, debris and room tail. "
     "Needs bass depth and clean transients; the laptop may clip or rattle here.", b, "stereo", 1.5)

# 5. spaceship flyby
dur = 12.0
eng = []
nz = lowpass([random.uniform(-1, 1) for _ in range(n(dur))], 400)
ph1 = ph2 = 0.0
for i in range(n(dur)):
    t = i / SR
    f = 38 + 55 * math.sin(math.pi * t / dur)
    ph1 += TAU * f / SR; ph2 += TAU * (f * 2.01) / SR
    eng.append(0.6 * math.sin(ph1) + 0.3 * math.sin(ph2) + 0.5 * nz[i] * (0.4 + math.sin(math.pi * t / dur)))
Lc, Rc = spatial(eng, lambda t: -90 + 180 * t / dur, lambda t: 0.2 + 0.8 * math.sin(math.pi * t / dur))
b = Buf(dur + 0.2); b.add(env(Lc, 0.5, 0.8), 0.05, 1, 0); b.add(env(Rc, 0.5, 0.8), 0.05, 0, 1)
emit("flyby.wav", "Starship flyby", "Cinema", "Low engine drone sweeping left to right with rising and falling pitch. "
     "Tests bass reproduction plus left-right movement.", b, "stereo", 1.8)

# 6. film-style scene: centre dialogue, wide score, ambience, footsteps, door
dur = 34.0
b = Buf(dur)
amb = stereo_noise(dur, 0.12)
amb = [lowpass(highpass(ch, 200), 3500) for ch in amb]
b.add(env(amb[0], 1.0, 2.0), 0, 1, 0); b.add(env(amb[1], 1.0, 2.0), 0, 0, 1)
for k, ch in enumerate(((57, 60, 64), (53, 57, 60), (55, 59, 62), (52, 55, 59))):       # slow score
    b.add(pad([midi(c) for c in ch], 8.5, 0.28), 1 + k * 8, 1.0, 0.85)
    b.add(pad([midi(c - 12) for c in ch], 8.5, 0.35), 1 + k * 8, 0.8, 1.0)
for i in range(10):                                                                        # footsteps walking right to left
    t0 = 4.0 + i * 0.55
    step = env([lowpass([random.uniform(-1, 1) for _ in range(n(0.12))], 700)[j] * math.exp(-j / SR * 38) for j in range(n(0.12))], 0.001, 0.02)
    Lc, Rc = spatial(step, lambda t, a=80 - i * 16: a)
    b.add(Lc, t0, 1.4, 0); b.add(Rc, t0, 0, 1.4)
door = lfe_boom(0.6, 0.8, 90.0)
b.add(door, 10.5, 1.0, 1.0)
for t0, text in ((12.5, "We have to leave. Now."), (16.5, "Where could they have gone? The door was locked from the inside."),
                 (23.0, "Listen. Can you hear that? Something is moving behind the wall.")):
    d = say(text, "Samantha")
    d = reverb(d, 0.2, 0.7)
    b.add(d, t0, 1.0, 1.0)
for t0, az_ in ((28.0, -110), (30.5, 120)):                                                # bumps behind the listener
    th = env([lowpass([random.uniform(-1, 1) for _ in range(n(0.4))], 500)[j] * math.exp(-j / SR * 10) for j in range(n(0.4))], 0.002, 0.05)
    Lc, Rc = spatial(reverb(th, 0.4, 0.8), lambda t, s_=az_: s_)
    b.add(Lc, t0, 2.0, 0); b.add(Rc, t0, 0, 2.0)
emit("scene.wav", "Film scene", "Cinema", "Dialogue in the centre, wide score and room ambience, footsteps walking across, a door, "
     "sounds behind you. A realistic mix for judging dialogue clarity against music and effects.", b, "stereo", 1.6)

# 7. trailer: braams, riser, hit, silence (dynamics)
dur = 22.0
b = Buf(dur)
def braam(f, d, amp=0.5):
    out = []
    for i in range(n(d)):
        t = i / SR
        v = 0.0
        for k, det in enumerate((0.994, 1.0, 1.006)):
            for h in (1, 2, 3, 4, 5):
                v += math.sin(TAU * f * det * h * t + k) / h
        out.append(amp * v / 6 * (min(1, t / 0.15)) * math.exp(-t * 0.7))
    return env(out, 0.01, 0.4)
b.add(braam(55, 5.0), 0.5, 1, 1)
rs = [highpass(random.uniform(-1, 1) * 1 for _ in range(1)) for _ in range(0)] if False else None
riser = [random.uniform(-1, 1) * (i / n(6.0)) ** 2 for i in range(n(6.0))]
riser = highpass(riser, 1500)
b.add(env(riser, 0.2, 0.05), 6.0, 0.7, 0.7)
b.add(lfe_boom(4.0, 1.0, 60.0), 12.0, 1, 1)
b.add(braam(41.2, 8.0, 0.7), 12.0, 1, 1)
for k in range(8):
    b.add(kick(), 12.2 + k * 0.45, 0.8, 0.8)
emit("trailer.wav", "Trailer hit", "Cinema", "Braam, riser, then a huge hit with sub-bass: dynamics and bass limits. Listen for the "
     "protection limiter pumping or the chassis buzzing.", b, "stereo", 1.5)

# --- the full test ------------------------------------------------------------------------------------------------
full = Buf(110)
t = 0.3


def put(sig, l=1.0, r=1.0, gap=0.4):
    global t
    full.add(sig, t, l, r); t += len(sig) / SR + gap


put(say("Full speaker test. Part one, left channel."), 1, 0)
put(env(highpass(pink(1.2, 0.8), 80), 0.02, 0.05), 1, 0)
put(sweep(40, 16000, 4, 0.5), 1, 0)
put(say("Part two, right channel."), 0, 1)
put(env(highpass(pink(1.2, 0.8), 80), 0.02, 0.05), 0, 1)
put(sweep(40, 16000, 4, 0.5), 0, 1)
put(say("Part three, bass."), 1, 1)
for f in (40, 50, 63, 80, 100, 125):
    put(tone(f, 1.0, 0.7, 0.05), 1, 1, 0.15)
put(say("Part four, treble."), 1, 1)
for f in (3000, 5000, 8000, 12000, 16000):
    put(tone(f, 0.8, 0.35, 0.05), 1, 1, 0.15)
put(say("Part five, stereo image."), 1, 1)
for i in range(12):
    pan = 0.5 - 0.5 * math.cos(TAU * i / 12)
    put(pluck(midi(69 if i % 2 else 76), 0.5, 0.5), math.cos(pan * math.pi / 2), math.sin(pan * math.pi / 2), 0.0)
t += 0.5
put(say("Part six, speech."), 1, 1)
put(say("The quick brown fox jumps over the lazy dog. She sells seashells by the seashore."), 0.8, 0.8)
put(say("Part seven, music."), 1, 1)
m = music(8, 112)
full.add(m.L, t, 1.0, 0.0); full.add(m.R, t, 0.0, 1.0)      # left/right of the mix go to their own channels
t += len(m.L) / SR + 0.8
put(say("Test complete."), 1, 1)
full.L = full.L[:n(t)]; full.R = full.R[:n(t)]
emit("full.wav", "Full test", "Overview", "About 70 seconds: left, right, bass, treble, stereo image, speech and music, each announced.", full, "stereo", 1.8)

for p in ("_say.aiff", "_say.wav"):
    try: os.remove(os.path.join(OUT, p))
    except OSError: pass
order = ["Overview", "Quality", "Cinema", "Drivers"]
index.sort(key=lambda e: (order.index(e["group"]), e["file"]))
json.dump(index, open(os.path.join(OUT, "index.json"), "w"), indent=1)
print("wrote", len(index), "files to", OUT)
