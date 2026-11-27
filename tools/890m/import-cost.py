#!/usr/bin/env python3
"""import-cost.py: per-stage cost of userptr imports, GEM_VA map/unmap and userptr BO frees from debug.nmx_import_cost
(NMXGPU out-55+, import trace = WS-CPU item 2). Read-only: it never writes the gate.

  import-cost.py [seconds]          two snapshots `seconds` apart (default 10), then the report
  import-cost.py A.txt B.txt [sec]  the same from two saved snapshots (`sysctl -n debug.nmx_import_cost > A.txt`);
                                    sec = wall time between them, for the per-second columns (default: from the ring)
  options: --row ws|other|none (row to fit and rank, default ws), --all (print every row's ranking)

The trace has to be on first (root, once; the write resets every sum): sysctl -w debug.nmx_import_trace=1

What it prints, for the window between the snapshots:
 1. Ranking of the stages of one row (default ws = WindowServer) by time spent in the window, in ms per second of wall
    time (= the share of one CPU), with calls/s, mean and max (max is since the gate write, not the window), and the
    histogram of the window (<0.1 ms, <1, <10, <100, <1000, more).
 2. A fit time = a + b * pages per (side, stage) over the ring records of that row taken in the window: a in us (fixed
    cost per call), b in us per 1000 pages, R^2, and the pages range it saw. pages = the record's pages (whole import /
    whole mapping), not the stage's own units. The ring keeps the last 256 records, so the fit is over a sample of the
    window when more than 256 records closed in it (the "fit n" column says how many).
 3. Counter deltas (all BOs, every process), per second and per row import.

Stages with no open record on the thread (row "none") come from parked-BO restores in CS and delayed frees on a worker;
C9a_dmalock there also counts TTM pool maps. Waits use select(), not sleep(1)/timeout(1).
"""
import select
import subprocess
import sys

HIST = ["<0.1", "<1", "<10", "<100", "<1k", ">=1k"]


def parse(text):
    """-> dict: head (header fields), stage {(name,row): [n, sum_us, max_us, units, h0..h5]}, count {name: n},
    rec [(side, t0, pid, row, pages, nents, total_us, {stage: (us, units)})], truncated"""
    d = {"head": {}, "stage": {}, "count": {}, "rec": [], "truncated": False}
    lines = text.splitlines()
    if any(l.strip() == "TRUNCATED" for l in lines):
        d["truncated"] = True
        cut = max(i for i, l in enumerate(lines) if l.strip() == "TRUNCATED")
        lines = lines[:cut]
        while lines and not lines[-1].strip():
            lines.pop()
        if lines:
            lines.pop()             # the line the cut went through is partial
    for line in lines:
        f = line.split()
        if not f or f[0].startswith("#"):
            continue
        try:
            parse_line(d, f)
        except ValueError:
            pass                    # a malformed line: skip it, never guess
    return d


def parse_line(d, f):
    if f[0] == "import_trace":
        d["head"] = {"on": int(f[1])}
        for i in range(2, len(f) - 1, 2):
            d["head"][f[i]] = int(f[i + 1])
    elif f[0] == "stage" and len(f) == 13:
        d["stage"][(f[1], f[2])] = [int(x) for x in f[3:]]
    elif f[0] == "count" and len(f) == 3:
        d["count"][f[1]] = int(f[2])
    elif f[0] == "rec" and len(f) >= 8:
        st = {}
        for kv in f[8:]:
            k, _, v = kv.partition("=")
            us, _, u = v.partition(",")
            st[k] = (int(us), int(u or 0))
        d["rec"].append((f[1], int(f[2]), int(f[3]), f[4], int(f[5]), int(f[6]), int(f[7]), st))



def read_live():
    out = subprocess.run(["/usr/sbin/sysctl", "-n", "debug.nmx_import_cost"], capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit("debug.nmx_import_cost not readable (NMXGPU without the import trace, out-55+?): " + out.stderr.strip())
    return out.stdout


TOTAL = {"import": "C0_total", "map": "V0_total", "unmap": "V0_total", "free": "D0_total"}


def fit(pts):
    """least squares y = a + b x; -> (a, b, r2) or None"""
    n = len(pts)
    if n < 3:
        return None
    sx = sum(p[0] for p in pts)
    sy = sum(p[1] for p in pts)
    mx, my = sx / n, sy / n
    sxx = sum((p[0] - mx) ** 2 for p in pts)
    sxy = sum((p[0] - mx) * (p[1] - my) for p in pts)
    syy = sum((p[1] - my) ** 2 for p in pts)
    if sxx == 0:        # every record the same size: only a mean
        return (my, 0.0, 0.0)
    b = sxy / sxx
    a = my - b * mx
    r2 = (sxy * sxy) / (sxx * syy) if syy else 1.0
    return (a, b, r2)


def report(A, B, secs, row, all_rows):
    if B["head"].get("records", 0) < A["head"].get("records", 0) or B["head"].get("opened", 0) < A["head"].get("opened", 0):
        sys.exit("the second snapshot has fewer records than the first: the gate was written (reset) in between")
    if not B["head"].get("on"):
        print("note: debug.nmx_import_trace is 0 in the second snapshot (nothing new is recorded)")
    for name, s in (("first", A), ("second", B)):
        if s["truncated"]:
            print(f"note: the {name} snapshot was TRUNCATED (stage sums are complete; part of the ring is missing)")
    # ring records new in B (key: side, t0, pid)
    seen = {(r[0], r[1], r[2]) for r in A["rec"]}
    new = [r for r in B["rec"] if (r[0], r[1], r[2]) not in seen]
    nrec = B["head"].get("records", 0) - A["head"].get("records", 0)
    if secs is None:
        # t0 is mach_absolute_time (ns on x86: timebase 1/1). Only usable when the ring still holds every new record.
        if nrec > len(new) or len(new) < 2:
            sys.exit(f"give the seconds between the snapshots: {nrec} records closed but only {len(new)} are in the ring")
        ts = [r[1] for r in new]
        secs = (max(ts) - min(ts)) / 1e9
        print(f"window: not given, {secs:.2f} s from the first and last record's start (a lower bound)")
    secs = secs or 1e-9
    h = B["head"]
    print(f"window {secs:.1f} s: {nrec} records closed ({nrec / secs:.1f}/s), {len(new)} of them still in the ring; "
          f"dropped +{h.get('dropped', 0) - A['head'].get('dropped', 0)}, busy (no free slot) "
          f"+{h.get('busy', 0) - A['head'].get('busy', 0)}")

    def delta(key):
        b = B["stage"].get(key)
        if b is None:
            return None
        a = A["stage"].get(key, [0] * 10)
        return [b[0] - a[0], b[1] - a[1], b[2], b[3] - a[3]] + [b[4 + i] - a[4 + i] for i in range(6)]

    rows = ["ws", "other", "none"] if all_rows else [row]
    imports = {}
    for r in ("ws", "other", "none"):
        d = delta(("C0_total", r))
        imports[r] = d[0] if d else 0
    for r in rows:
        lines = []
        for (name, rr) in B["stage"]:
            if rr != r:
                continue
            d = delta((name, rr))
            if d and d[0] > 0:
                lines.append((name, d))
        lines.sort(key=lambda x: -x[1][1])
        print(f"\nrow {r}: stages ranked by time in the window (ms/s = share of one CPU, x1000)")
        print(f"  {'stage':14} {'ms/s':>8} {'calls/s':>9} {'mean us':>9} {'max us':>8} {'units/call':>10}  hist ms "
              + " ".join(f"{x:>6}" for x in HIST))
        for name, d in lines:
            n, s_us, mx, units = d[0], d[1], d[2], d[3]
            tag = "  (total)" if name.endswith("_total") else ""
            print(f"  {name:14} {s_us / 1000 / secs:8.2f} {n / secs:9.1f} {s_us / n:9.1f} {mx:8d} {units / n:10.1f}  "
                  f"        " + " ".join(f"{x:6d}" for x in d[4:]) + tag)
        if not lines:
            print("  (nothing in this row in the window)")

    print(f"\nrow {row}: fit time = a + b * pages over the ring records of the window (side, stage)")
    print(f"  {'side':6} {'stage':14} {'fit n':>6} {'a us':>9} {'b us/1k pages':>14} {'R^2':>6} {'pages min..max':>16}")
    groups = {}
    for side, _t0, _pid, rr, pages, _nents, total, st in new:
        if rr != row:
            continue
        groups.setdefault((side, TOTAL.get(side, "total")), []).append((pages, total))
        for k, (us, _u) in st.items():
            groups.setdefault((side, k), []).append((pages, us))
    fits = []
    for (side, stage), pts in groups.items():
        f = fit(pts)
        if f is None:
            continue
        a, b, r2 = f
        mean_pages = sum(p[0] for p in pts) / len(pts)
        fits.append((side, stage, len(pts), a, b * 1000, r2, min(p[0] for p in pts), max(p[0] for p in pts),
                     a + b * mean_pages))
    fits.sort(key=lambda x: (x[0], -x[8]))
    for side, stage, n, a, b1k, r2, lo, hi, _ in fits:
        print(f"  {side:6} {stage:14} {n:6d} {a:9.1f} {b1k:14.1f} {r2:6.2f} {lo:>7}..{hi:<8}")
    if not fits:
        print("  (fewer than 3 new ring records per stage in this row)")

    print("\ncounters (all BOs, all processes): per second, and per row-" + row + " import")
    per = imports.get(row, 0)
    for k in B["count"]:
        dv = B["count"][k] - A["count"].get(k, 0)
        print(f"  {k:16} {dv:10d} {dv / secs:10.1f}/s " + (f"{dv / per:8.2f}/import" if per else ""))


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    opts = [a for a in sys.argv[1:] if a.startswith("--")]
    row = "ws"
    all_rows = "--all" in opts
    for o in opts:
        if o.startswith("--row"):
            row = o.split("=", 1)[1] if "=" in o else None
    if "--row" in sys.argv:
        i = sys.argv.index("--row")
        row = sys.argv[i + 1]
        args = [a for a in args if a != row]
    if row not in ("ws", "other", "none"):
        sys.exit("--row ws|other|none")
    if len(args) >= 2:
        A = parse(open(args[0]).read())
        B = parse(open(args[1]).read())
        secs = float(args[2]) if len(args) > 2 else None
    else:
        secs = float(args[0]) if args else 10.0
        A = parse(read_live())
        if not A["head"].get("on"):
            print("note: debug.nmx_import_trace is 0; turn it on first (root): sysctl -w debug.nmx_import_trace=1")
        select.select([], [], [], secs)
        B = parse(read_live())
    report(A, B, secs, row, all_rows)


if __name__ == "__main__":
    main()
