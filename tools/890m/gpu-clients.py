#!/usr/bin/env python3
"""gpu-clients.py [seconds] [repeats]: GPU time per process from debug.nmx_gpu_clients (NMXGPU out-54+, read-only).

Reads the sysctl, waits `seconds` (default 10), reads it again, and prints per process the GPU ring time spent in
that window, in ms per second of wall time, per hardware IP (gfx, compute, dma, vcn_dec, vcn_enc, vcn_jpeg, vpe;
uvd/vce are absent on the 890M and folded out unless non-zero). With `repeats` > 1 it keeps going, one table per
window. Unprivileged: the sysctl is CTLFLAG_RD.

What the numbers are: amdgpu_ctx_mgr_usage, i.e. Linux fdinfo's drm-engine-* (scheduled -> finished fence time of each
job). That is ring occupancy, not exclusive GPU time: jobs of two clients overlapping on a ring are both counted, so
the column sum can exceed 1000 ms/s. A process that draws on the CPU, or whose surfaces WindowServer composites,
shows up in WindowServer's line, not its own. A file that opened during the window counts from 0; one that closed
during it is dropped (its last window is lost, never negative).
Waits use select(), not sleep(1)/timeout(1).
"""
import select
import subprocess
import sys

COLS = ["gfx", "compute", "dma", "uvd", "vce", "uvd_enc", "vcn_dec", "vcn_enc", "vcn_jpeg", "vpe"]


def read():
    out = subprocess.run(["/usr/sbin/sysctl", "-n", "debug.nmx_gpu_clients"], capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit("debug.nmx_gpu_clients not readable (NMXGPU without roadmap 3 a2?): " + out.stderr.strip())
    now, files = None, {}
    for line in out.stdout.splitlines():
        f = line.split()
        if not f:
            continue
        if f[0] == "now_ns":
            now = int(f[1])
        elif f[0] in ("client", "total") or line.startswith("not ready") or "TRUNCATED" in line:
            if "TRUNCATED" in line:
                print("warning: kernel output truncated", file=sys.stderr)
            continue
        elif len(f) >= 3 + len(COLS):
            # client pid name... (process_name has no spaces in amdgpu_task_info, but be safe: name = middle fields)
            vals = [int(x) for x in f[-len(COLS):]]
            files[int(f[0])] = (int(f[1]), " ".join(f[2:-len(COLS)]), vals)
    if now is None:
        sys.exit("debug.nmx_gpu_clients: " + out.stdout.strip()[:200])
    return now, files


def window(secs):
    t0, a = read()
    select.select([], [], [], secs)
    t1, b = read()
    wall_ms = (t1 - t0) / 1e6
    per = {}
    for cid, (pid, name, vals) in b.items():
        prev = a.get(cid)
        base = prev[2] if prev else [0] * len(COLS)
        d = [max(0, v - p) for v, p in zip(vals, base)]
        k = (pid, name)
        acc = per.setdefault(k, [0] * len(COLS))
        per[k] = [x + y for x, y in zip(acc, d)]
    used = [i for i, c in enumerate(COLS) if c not in ("uvd", "vce", "uvd_enc") or any(v[i] for v in per.values())]
    rows = sorted(per.items(), key=lambda kv: -sum(kv[1]))
    print(f"window {wall_ms / 1000:.2f} s, {len(b)} DRM files open; GPU ring ms per s of wall time")
    print(f"{'pid':>7} {'process':<28}" + "".join(f"{COLS[i]:>10}" for i in used))
    tot = [0] * len(COLS)
    for (pid, name), d in rows:
        if not any(d):
            continue
        tot = [x + y for x, y in zip(tot, d)]
        print(f"{pid:>7} {name[:28]:<28}" + "".join(f"{d[i] / 1e6 / wall_ms * 1000:>10.1f}" for i in used))
    print(f"{'':>7} {'total':<28}" + "".join(f"{tot[i] / 1e6 / wall_ms * 1000:>10.1f}" for i in used))


def main():
    secs = float(sys.argv[1]) if len(sys.argv) > 1 else 10.0
    reps = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    for r in range(reps):
        if r:
            print()
        window(secs)


if __name__ == "__main__":
    main()
