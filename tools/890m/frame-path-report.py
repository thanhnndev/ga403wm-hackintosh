#!/usr/bin/env python3
"""Join the frame-path rings and say where late frames lost their time (docs/FRAME-PATH.md section 7).

Usage:  frame-path-report.py accel.txt gpu.txt
        (accel.txt = `sysctl -n debug.nmxaccel_frametrace`, gpu.txt = `sysctl -n debug.nmx_frametrace`,
         taken back to back right after the run; both rings hold the last 512 frames)

Per frame (all times mach_absolute_time ns, joined by NMXGPU flip seq):
  gpu       WindowServer commit -> GPU end            (plugin NMXFencePendingT -> NMXFenceGpuEndT)
  wake      GPU end -> plugin completion thread saw it (IRQ thread + syncobj + user-space scheduling)
  handoff   plugin saw it -> display pipe saw it      (IOSurface IPC + 100 us poll)
  queue     WindowServer commit -> performTransaction entry (overlaps gpu/wake)
  pipe      pipe saw fence -> flip submitted
  worker    submit -> flip armed in amdgpu_dm_commit_planes (commit worker, vblank-window wait, IPS exit)
  scanout   armed -> pageflip IRQ                     (waiting for the vblank; > 1 period = missed one)
  notify    pageflip IRQ -> NMXAccel saw the latch    (200 us poll + thread call)
Memory stalls (NMXGPU "stall"/"stallev" lines): Step142 re-wire (restore), inline 2 MB chunk (inline), fill thread
chunk (fill), new userptr/surface wire (wire); each late frame lists the stalls >= 1 ms that overlap it.
A frame is late when pageflip IRQ - commit > 2 refresh periods or it latched more than one vblank after it was armed.
"""
import statistics
import sys


def read_accel(path):
    recs = {}
    for line in open(path):
        f = line.split()
        if len(f) != 11 or not f[0].isdigit():
            continue
        seq = int(f[0])
        if not seq:
            continue
        entry = int(f[2])
        rel = [int(x) for x in f[3:10]]          # us relative to entry, -999999 = missing
        names = ["cpend", "gend", "pdone", "fence", "sub", "latch", "sig"]
        r = {"entry": entry, "sid": f[1], "waited": int(f[10])}
        for n, v in zip(names, rel):
            r[n] = None if v == -999999 else entry + v * 1000
        recs[seq] = r
    return recs


def read_gpu(path):
    recs, head, stalls = {}, {}, []
    for line in open(path):
        f = line.split()
        if not f:
            continue
        if f[0] == "stall":
            head.setdefault("stall", []).append(line.strip())
            continue
        if f[0] == "stallev" and len(f) == 6:
            t0 = int(f[2])
            stalls.append({"kind": f[1], "t0": t0, "t1": t0 + int(f[3]) * 1000, "ms": int(f[3]) / 1000,
                           "pages": int(f[4]), "pid": int(f[5])})
            continue
        if f[0] in ("flips", "vbl_timer", "ips", "psr", "out31"):
            head[f[0]] = line.strip()
            continue
        if len(f) != 10 or not f[0].isdigit():
            continue
        seq = int(f[0])
        if not seq:
            continue
        sub0 = int(f[2])
        rel = [int(x) for x in f[3:7]]           # us relative to sub0, -1 = missing
        r = {"sub0": sub0, "handle": int(f[1]), "vbl_armed": int(f[7]), "vbl_pflip": int(f[8]), "idle": int(f[9])}
        for n, v in zip(["sub1", "armed", "pflip", "seen"], rel):
            r[n] = None if v < 0 else sub0 + v * 1000
        recs[seq] = r
    return recs, head, stalls


def d(a, b):
    return (b - a) / 1e6 if a is not None and b is not None and b >= a else None


def pct(xs, p):
    xs = sorted(xs)
    return xs[min(len(xs) - 1, int(p * len(xs)))] if xs else float("nan")


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    acc = read_accel(sys.argv[1])
    gpu, head, stalls = read_gpu(sys.argv[2])
    for k in ("flips", "vbl_timer", "ips", "psr", "out31"):
        if k in head:
            print(head[k])
    for line in head.get("stall", []):
        print(line)
    period = None
    if "vbl_timer" in head:
        for i, w in enumerate(head["vbl_timer"].split()):
            if w == "frame_ns":
                period = int(head["vbl_timer"].split()[i + 1]) / 1e6
    period = period or 1000 / 120.0
    stages = ["gpu", "wake", "handoff", "queue", "pipe", "worker", "scanout", "notify"]
    rows = []
    for seq in sorted(set(acc) & set(gpu)):
        a, g = acc[seq], gpu[seq]
        row = {
            "seq": seq,
            "gpu": d(a["cpend"], a["gend"]),
            "wake": d(a["gend"], a["pdone"]),
            "handoff": d(a["pdone"], a["fence"]),
            "queue": d(a["cpend"], a["entry"]),
            "pipe": d(a["fence"], g["sub0"]),
            "worker": d(g["sub0"], g["armed"]),
            "scanout": d(g["armed"], g["pflip"]),
            "notify": d(g["pflip"], a["latch"]),
            "total": d(a["cpend"], g["pflip"]),
            "missed": (g["vbl_pflip"] - g["vbl_armed"] - 1) if g["pflip"] and g["armed"] else None,
            "idle": g["idle"],
            "t0": a["cpend"] or a["entry"],
            "t1": g["pflip"] or g["seen"] or a["latch"],
        }
        rows.append(row)
    print(f"joined frames: {len(rows)} (accel {len(acc)}, gpu {len(gpu)}), refresh period {period:.3f} ms")
    if not rows:
        return
    print(f"{'stage':<9}{'n':>6}{'p50':>9}{'p90':>9}{'p99':>9}{'max':>9}  (ms)")
    for s in stages + ["total"]:
        xs = [r[s] for r in rows if r[s] is not None]
        if xs:
            print(f"{s:<9}{len(xs):>6}{pct(xs, .5):>9.3f}{pct(xs, .9):>9.3f}{pct(xs, .99):>9.3f}{max(xs):>9.3f}")
    late = [r for r in rows if (r["total"] is not None and r["total"] > 2 * period) or (r["missed"] or 0) > 0]
    print(f"late frames: {len(late)} of {len(rows)}")
    blame = {s: 0 for s in stages}
    for r in late:
        cand = {s: r[s] for s in stages if r[s] is not None and s != "queue"}
        if cand:
            blame[max(cand, key=cand.get)] += 1
    print("largest stage in late frames: " + ", ".join(f"{s} {n}" for s, n in sorted(blame.items(), key=lambda x: -x[1]) if n))
    idle = [r for r in rows if r["idle"] == 1]
    if idle:
        print(f"flips armed with DC idle optimisations allowed (IPS path): {len(idle)}; their worker p50 "
              f"{pct([r['worker'] for r in idle if r['worker'] is not None], .5):.3f} ms vs "
              f"{pct([r['worker'] for r in rows if r['idle'] == 0 and r['worker'] is not None], .5):.3f} ms")
    if stalls:
        hit = 0
        for r in late:
            r["stalls"] = [x for x in stalls if r["t0"] and r["t1"] and x["t0"] < r["t1"] and x["t1"] > r["t0"]]
            hit += bool(r["stalls"])
        print(f"memory stalls >= 1 ms in the ring: {len(stalls)}; late frames overlapping one: {hit} of {len(late)}")
    print("worst 10:")
    for r in sorted(late, key=lambda r: -(r["total"] or 0))[:10]:
        print("  seq %d total %s missed %s | " % (r["seq"], f"{r['total']:.2f}" if r["total"] else "-", r["missed"]) +
              " ".join(f"{s} {r[s]:.2f}" for s in stages if r[s] is not None) +
              "".join(f" | {x['kind']} {x['ms']:.1f} ms pid {x['pid']}" for x in r.get("stalls", [])))


if __name__ == "__main__":
    main()
