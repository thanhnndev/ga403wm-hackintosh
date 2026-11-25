#!/bin/bash
# out31-verify.sh [seconds=30] [dir]: post-install check of out-31 rows 1-3 (docs/FRAME-PATH.md 9.1-9.3).
# Read-only: reads sysctls and the two frame-path rings, writes nothing to the drivers, needs no root.
# Run it under the normal daily load (video playing + Claude + Docker); it samples the counters at the start and the end of
# the interval, snapshots both rings at the end, runs the aggregate, and prints PASS / FAIL / INFO per verify item.
# A/B: run it once as is, then once after the matching "A/B" command printed at the end (main runs those), same load.
set -u
secs=${1:-30}; dir=${2:-$HOME/ga403-logs/out31-verify-$(date +%Y%m%d-%H%M%S)}
here=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$dir" || exit 1

C="debug.nmx_flip_kfence debug.nmx_flip_irq debug.nmx_vbl_irq
debug.nmx_flip_fenced debug.nmx_flip_nofence debug.nmx_surf_fence_set debug.nmx_flip_notified debug.nmx_vbl_delivered
debug.nmxaccel_flip debug.nmxaccel_flip_kfence debug.nmxaccel_flip_notify debug.nmxaccel_flip_ts debug.nmxaccel_flip_tripped
debug.nmxaccel_flip_submitted debug.nmxaccel_flip_latched debug.nmxaccel_flip_timeouts debug.nmxaccel_flip_fallback
debug.nmxaccel_flip_drop debug.nmxaccel_flip_generation
debug.nmxaccel_kfence_flips debug.nmxaccel_kfence_not_submitted debug.nmxaccel_kfence_refused debug.nmxaccel_kfence_slow
debug.nmxaccel_flip_busy_drop debug.nmxaccel_flip_notified debug.nmxaccel_flip_ts_set debug.nmxaccel_flip_rearm
debug.nmxaccel_flip_redo debug.nmxaccel_flip_stuck_landed"

snap() {   # name=value per line; a missing sysctl is left out (older build)
    for k in $C; do v=$(sysctl -n "$k" 2>/dev/null) && echo "$k=$v"; done
    sysctl -n debug.nmx_frametrace 2>/dev/null | sed -n '1,12p' | grep -E '^(flips|vbl_timer|ips|psr|out31) ' | sed 's/^/head: /'
}

[ -n "${OUT31_VERIFY_FORCE:-}" ] || sysctl -n debug.nmx_flip_kfence >/dev/null 2>&1 || { echo "FAIL  build: debug.nmx_flip_kfence missing -- out-31 NMXGPU is not loaded"; exit 1; }
[ -n "${OUT31_VERIFY_FORCE:-}" ] || sysctl -n debug.nmxaccel_flip_kfence >/dev/null 2>&1 || { echo "FAIL  build: debug.nmxaccel_flip_kfence missing -- out-31 NMXAccel is not loaded"; exit 1; }

echo "sampling ${secs}s under the current load (keep the video playing) -> $dir"
snap > "$dir/a.txt"
perl -e "select(undef, undef, undef, $secs)"
snap > "$dir/b.txt"
t=$(date +%H%M%S)
sysctl -n debug.nmxaccel_frametrace > "$dir/accel-$t.txt" 2>/dev/null
sysctl -n debug.nmx_frametrace > "$dir/gpu-$t.txt" 2>/dev/null
sysctl -n debug.nmx_gtt > "$dir/gtt-$t.txt" 2>/dev/null
python3 -I "$here/frame-path-aggregate.py" "$here/frame-path-report.py" "$dir" > "$dir/aggregate.txt" 2>&1

python3 -I - "$dir" "$secs" <<'EOF' | tee "$dir/verify.txt"
import sys, re
d, secs = sys.argv[1], float(sys.argv[2])
def load(p):
    kv, head = {}, {}
    for l in open(p):
        l = l.rstrip("\n")
        if l.startswith("head: "):
            w = l[6:].split(); head[w[0]] = w
        elif "=" in l:
            k, v = l.split("=", 1); kv[k] = v
    return kv, head
A, ha = load(d + "/a.txt"); B, hb = load(d + "/b.txt")
def has(k): return ("debug." + k) in B
def val(k, S=B):
    try: return int(S["debug." + k])
    except (KeyError, ValueError): return None
def dl(k):
    a, b = val(k, A), val(k, B)
    return None if a is None or b is None else b - a
def hnum(h, line, key):
    w = h.get(line)
    if not w or key not in w: return None
    try: return int(w[w.index(key) + 1])
    except (ValueError, IndexError): return None
agg = open(d + "/aggregate.txt").read()
def aggre(pat, cast=float):
    m = re.search(pat, agg)
    return cast(m.group(1)) if m else None

res = {"PASS": 0, "FAIL": 0}
def row(ok, name, detail):
    tag = "INFO" if ok is None else ("PASS" if ok else "FAIL")
    if tag in res: res[tag] += 1
    print(f"{tag:5} {name:44} {detail}")
def ratio(n, m): return (n / m) if (n is not None and m) else None
def fr(x): return "n/a" if x is None else f"{x:.2f}"

lat, sub = dl("nmxaccel_flip_latched"), dl("nmxaccel_flip_submitted")
print(f"interval {secs:.0f}s: flips submitted {sub}, latched {lat} ({fr((lat or 0)/secs)} /s)")
if not lat:
    print("FAIL  no flips latched in the interval: play a video (zero-copy flips) and run again; nothing below is meaningful")
active = bool(lat)
row(val("nmxaccel_flip") == 1, "zero-copy flips on (nmxaccel_flip 1)", f"nmxaccel_flip={val('nmxaccel_flip')}")
row(val("nmxaccel_flip_tripped") == 0, "flips not tripped", f"tripped={val('nmxaccel_flip_tripped')} (see log 'iop: flip: OFF')")
row(dl("nmxaccel_flip_timeouts") == 0, "no 50 ms latch timeouts", f"+{dl('nmxaccel_flip_timeouts')}")

print("-- 9.1 row 1: render fence in the kernel commit")
row(val("nmx_flip_kfence") == 1 and val("nmxaccel_flip_kfence") == 1, "switches on (nmx_flip_kfence, nmxaccel_flip_kfence)",
    f"{val('nmx_flip_kfence')} / {val('nmxaccel_flip_kfence')}")
kf, fen = dl("nmxaccel_kfence_flips"), dl("nmx_flip_fenced")
r1 = ratio(kf, sub)
row(active and kf is not None and kf > 0 and r1 is not None and r1 >= 0.5, "kernel-fenced flips grow with flips",
    f"nmxaccel_kfence_flips +{kf} = {fr(r1)} of submitted (PASS >= 0.50)")
row(active and fen is not None and kf is not None and abs(fen - kf) <= max(2, 0.05 * kf), "NMXGPU agrees (nmx_flip_fenced ~ kfence_flips)",
    f"nmx_flip_fenced +{fen} vs +{kf}")
ns, rf = dl("nmxaccel_kfence_not_submitted"), dl("nmxaccel_kfence_refused")
r = ratio((ns or 0) + (rf or 0), sub)
row(active and r is not None and r < 0.10, "old-wait fallbacks small", f"not_submitted +{ns} refused +{rf} nofence +{dl('nmx_flip_nofence')} = {fr(r)} of submitted (PASS < 0.10)")
row(None, "surface fences recorded", f"nmx_surf_fence_set +{dl('nmx_surf_fence_set')}")
sl, bd = dl("nmxaccel_kfence_slow"), dl("nmxaccel_flip_busy_drop")
row(active and (sl or 0) == 0 and ratio(bd or 0, sub) is not None and ratio(bd or 0, sub) < 0.01, "no slow fenced flips / BUSY drops",
    f"kfence_slow +{sl} busy_drop +{bd} (PASS: slow 0, drops < 1% of submitted)")
if has("nmxaccel_flip_redo"):
    row(None, "round 2: stuck flips landed / redo frames", f"stuck_landed +{dl('nmxaccel_flip_stuck_landed')} redo +{dl('nmxaccel_flip_redo')} (redo should equal the stuck count with BUSY drops)")
k2 = re.search(r"kernel-fence frames \(waited 2\) (\d+) of (\d+)", agg)
if k2:
    a2, n2 = int(k2.group(1)), int(k2.group(2))
    row(n2 > 0 and a2 / n2 >= 0.5, "trace: frames with waited = 2", f"{a2} of {n2} joined frames (PASS >= 50%)")
else:
    row(False, "trace: frames with waited = 2", "aggregate did not run (see aggregate.txt)")
ho = aggre(r"handoff>4ms (\d+)", int)
wk = aggre(r"wake>4ms (\d+)", int)
row(None if ho is None else ho <= 5, "trace: handoff > 4 ms (first run: 138/300 s)", f"handoff>4ms {ho} wake>4ms {wk} in this ring (~512 frames)")
tp = re.search(r"total\s+p50\s+([\d.]+)\s+p90\s+([\d.]+)\s+p99\s+([\d.]+)", agg)
row(None, "trace: total (commit -> pflip) ms", f"p50 {tp.group(1)} p90 {tp.group(2)} p99 {tp.group(3)}" if tp else "n/a")
row(None, "on screen", "owner: no torn, stale or stuck frames during the run (a static screen must show the last frame)")

print("-- 9.2 row 3: completion from the pageflip IRQ")
row(val("nmx_flip_irq") == 1 and val("nmxaccel_flip_notify") == 1 and val("nmxaccel_flip_ts") == 1,
    "switches on (nmx_flip_irq, flip_notify, flip_ts)", f"{val('nmx_flip_irq')} / {val('nmxaccel_flip_notify')} / {val('nmxaccel_flip_ts')}")
gn, an = dl("nmx_flip_notified"), dl("nmxaccel_flip_notified")
row(active and ratio(gn, lat) is not None and ratio(gn, lat) >= 0.9, "NMXGPU notified ~ flips", f"nmx_flip_notified +{gn} = {fr(ratio(gn, lat))} of latched (PASS >= 0.90)")
row(active and ratio(an, lat) is not None and ratio(an, lat) >= 0.9, "NMXAccel notified ~ flips", f"nmxaccel_flip_notified +{an} = {fr(ratio(an, lat))} of latched (PASS >= 0.90)")
rr = dl("nmxaccel_flip_rearm")
# few flips (login, a still screen) land at random points of the frame and the learned net looks early more often: the
# ratio is judged only from 300 latched flips up (2026-11-23 13:18: 73 flips, +11 = 0.15; a minute later 0.08, then 0.02)
row((active and ratio(rr or 0, lat) is not None and ratio(rr or 0, lat) < 0.10) if (lat or 0) >= 300 else None, "re-arms small",
    f"flip_rearm +{rr} = {fr(ratio(rr or 0, lat))} of latched (PASS < 0.10{'' if (lat or 0) >= 300 else '; INFO: under 300 latched flips'})")
ts = dl("nmxaccel_flip_ts_set")
row(active and ratio(ts, lat) is not None and ratio(ts, lat) >= 0.5, "presentation time stamped (tx+0x170)", f"flip_ts_set +{ts} = {fr(ratio(ts, lat))} of latched (PASS >= 0.50)")
nt = re.search(r"notify\s+p50\s+([\d.]+)\s+p90\s+([\d.]+)\s+p99\s+([\d.]+)", agg)
row(None if not nt else float(nt.group(1)) < 1.0, "trace: notify (pflip -> latch seen) p50 < 1 ms",
    f"p50 {nt.group(1)} p90 {nt.group(2)} p99 {nt.group(3)} ms" if nt else "n/a")
row(None, "WindowServer pipe-thread CPU", "needs root: main runs  sudo spindump WindowServer 10 -file /tmp/ws-out31.txt  and compares with an A/B run")

print("-- 9.3 row 2: IOFramebuffer VBL from the CRTC vblank")
row(val("nmx_vbl_irq") == 1, "switch on (nmx_vbl_irq)", f"{val('nmx_vbl_irq')}")
vd = dl("nmx_vbl_delivered")
hz = (vd or 0) / secs
row(None, "VBL delivered from the CRTC vblank", f"nmx_vbl_delivered +{vd} = {hz:.1f} /s (out-34+: only while a registration is on; up to out-33 it counted every CRTC vblank)")
tf_a, tf_b = hnum(ha, "vbl_timer", "fires"), hnum(hb, "vbl_timer", "fires")
st_a, st_b = hnum(ha, "vbl_timer", "stale"), hnum(hb, "vbl_timer", "stale")
if tf_a is not None and tf_b is not None:
    th = (tf_b - tf_a) / secs
    row(th <= 15, "VBL timer only the watchdog (<= ~10 /s)", f"vbl_timer fires +{tf_b - tf_a} = {th:.1f} /s, stale +{(st_b or 0) - (st_a or 0)} (was ~120 /s)")
else:
    row(False, "VBL timer only the watchdog", "vbl_timer line missing from debug.nmx_frametrace")
vh, vw = hnum(hb, "out31", "vbl_held"), hnum(hb, "out31", "vbl_wanted")
vs = (hnum(hb, "out31", "vbl_sink") or 0) - (hnum(ha, "out31", "vbl_sink") or 0) if hnum(hb, "out31", "vbl_sink") is not None else None
if vw is None:   # out-33 and older: no vbl_wanted; vbl_delivered counted every CRTC vblank, wanted or not
    row(None, "vblank reference vs registrations", f"out31 vbl_held {vh} (build before out-34: cannot tell whether a 'vbl ' registration is on)")
else:
    row(vh == vw, "vblank reference held iff a 'vbl ' registration is on", f"vbl_held {vh} vbl_wanted {vw}; CRTC vblanks seen by the sink +{vs} = {(vs or 0)/secs:.1f} /s")
ps = hb.get("psr")
row(None, "psr / active_vblank_irq_count", " ".join(ps[1:]) if ps else "psr line missing")
ia, ib = ha.get("ips"), hb.get("ips")
row(None, "ips counters (move only on a static screen)", (" ".join(ia[1:]) + "  ->  " + " ".join(ib[1:])) if ia and ib else "ips line missing")
print(f"-- {res['PASS']} PASS, {res['FAIL']} FAIL (INFO rows are for the reader); files in {d}")
EOF

cat <<'EOF'
-- A/B switches (main runs these as root; each turns one row back to the out-30 path at runtime, =1 restores):
row 1 (kernel fence):      sudo sysctl debug.nmxaccel_flip_kfence=0     # NMXAccel waits NMXFenceDone again
                           sudo sysctl debug.nmx_flip_kfence=0          # NMXGPU side (fence-only submits then refused -> old wait)
row 3 (pageflip notify):   sudo sysctl debug.nmxaccel_flip_notify=0     # 200 us poll completion
                           sudo sysctl debug.nmx_flip_irq=0             # NMXGPU stops calling the notify
                           sudo sysctl debug.nmxaccel_flip_ts=0         # no tx+0x170 presentation time
row 2 (VBL from vblank):   sudo sysctl debug.nmx_vbl_irq=0              # 120 Hz timer again
boot-time (next boot only, via boot-args): nmxkfence=0 nmxflipirq=0 nmxvblirq=0
A/B run: tools/890m/out31-verify.sh 30 ~/ga403-logs/out31-B-<row>   (same load), then compare verify.txt / aggregate.txt
EOF
