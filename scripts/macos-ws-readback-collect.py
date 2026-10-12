#!/usr/bin/env python3
"""Short, read-only collection for the WindowServer readback investigation (docs/WINDOWSERVER-READBACK.md).

No sudo, no setting changes, no pixel data. It takes two snapshots of the NVAccel/NVRMFB sysctl counters and of
WindowServer's cumulative CPU time N seconds apart, reads what the driver already logs about IOSurface sharing, copies the
plugin statistics report if the instrumented plugin wrote one, and prints which branch of the decision table the numbers fall in.

  /usr/bin/python3 -I scripts/macos-ws-readback-collect.py --seconds 15 --label desktop-static

Keep the visible workload identical between runs you want to compare, and do not call a counter rate a CPU percentage.
Output: ~/efi-audit/ws-readback-<timestamp>/{counters.json,analysis.txt,logs.txt,plugin-report.*.txt}
"""
import argparse
import datetime
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import time

KERNEL_TRACE = "/Library/NullMoth/display-trace/kernel.txt"
PLUGIN_REPORTS = "/private/tmp/nullmoth-surfstat.WindowServer.*.txt"
LOG_PATTERN = "dirty refused|family VRAM import refused|buffer over the imported VRAM|image create FAILED|surface-out: readback FAILED|surface-in: upload FAILED"
DIRTY_REASONS = ["no_surface", "famlock", "no_cache", "no_res", "no_vm", "no_handle", "type", "flag", "no_valid", "plane", "pend_full", "off"]
SHARE_REASONS = ["ok", "bad_version", "off", "no_surface", "no_cache", "no_vram", "too_small", "rm"]


def run(*args, timeout=60):
    try:
        return subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True, timeout=timeout).stdout
    except (OSError, subprocess.SubprocessError) as exc:
        return "(%s failed: %s)\n" % (args[0], exc)


def cpu_seconds(pid):
    raw = run("ps", "-p", str(pid), "-o", "time=").strip()
    days, sep, clock = raw.partition("-")
    cpu = 0.0
    for field in (clock if sep else raw).split(":"):
        cpu = cpu * 60 + float(field)
    return cpu + (int(days) * 86400 if sep else 0)


def counters():
    out = {}
    for line in run("sysctl", "-a").splitlines():
        key, _, value = line.partition(": ")
        if key.startswith(("debug.nvaccel", "debug.nvrmfb")):
            try:
                out[key] = int(value)
            except ValueError:
                pass
    return out


def delta(before, after, key):
    return after.get(key, 0) - before.get(key, 0)


def analyse(before, after, seconds, ws_cpu_pct):
    """Pure function of two counter dicts: returns (lines, findings). Unit-tested in test/readback/collect_test.py."""
    d = lambda k: delta(before, after, "debug." + k)
    present = lambda k: ("debug." + k) in after
    L, F = [], []
    ok_frames, flips = d("nvaccel_iop_ok"), d("nvaccel_iop_flips")
    frames = ok_frames + flips
    L.append("window: %.1f s   WindowServer CPU: %s of one logical CPU (cumulative process time; includes kernel work on its threads)"
             % (seconds, "%.1f%%" % ws_cpu_pct if ws_cpu_pct is not None else "n/a"))
    L.append("scanout: %d frames = %d zero-copy flips + %d copied  (%.1f frames/s)" % (frames, flips, ok_frames, frames / seconds))
    stale, novram, lock, refused = d("nvaccel_iop_flip_stale"), d("nvaccel_iop_flip_novram"), d("nvaccel_iop_flip_lock"), d("nvaccel_iop_flip_refused")
    L.append("copied because: system memory newest (stale) %d | no RM VRAM %d | accelerator lock busy %d | flip refused %d | pipe-copy src: surface %d resource %d"
             % (stale, novram, lock, refused, d("nvaccel_iop_src_surf"), d("nvaccel_iop_src_res")))
    if frames and ok_frames / frames > 0.2:
        F.append("R1: %.0f%% of scanout frames were CPU copies. 'stale' (%d) means the frame's writer left the newest pixels in system memory "
                 "(a readback or a refused dirty export); 'lock' (%d) means the accelerator lock was held by someone else; 'novram'/'refused' point at the flip itself."
                 % (100.0 * ok_frames / frames, stale, lock))
    L.append("VRAM grants: alloc %d dealloc %d refused %d | resources: new %d freed %d | live alloc counters since boot: alloc %d new %d"
             % (d("nvaccel_vm_alloc"), d("nvaccel_vm_dealloc"), d("nvaccel_vm_refused"), d("nvaccel_res_new"), d("nvaccel_res_free"),
                after.get("debug.nvaccel_vm_alloc", 0), after.get("debug.nvaccel_res_new", 0)))
    if after.get("debug.nvaccel_vm_refused", 0):
        F.append("R2: VRAM grants were refused since boot (%d). A surface without RM VRAM cannot be shared (kernel status NO_VRAM) and falls back to private images + copies."
                 % after["debug.nvaccel_vm_refused"])
    if after.get("debug.nvaccel_vm_alloc", 0) > after.get("debug.nvaccel_res_new", 0) * 1.2 + 10:
        F.append("H6 (hypothesis): VRAM allocs since boot (%d) clearly exceed resources created (%d): resources are re-backed after eviction. A plugin texture that "
                 "imported the older block would keep using it (see the allocation-epoch discussion in the doc)." % (after["debug.nvaccel_vm_alloc"], after["debug.nvaccel_res_new"]))
    if not present("nvaccel_ss_dirty_ok"):
        L.append("kernel diagnostics (debug.nvaccel_ss_*) are NOT installed: dirty/share refusal reasons cannot be separated yet (stage 2).")
    else:
        dirty_ok = d("nvaccel_ss_dirty_ok")
        reasons = [(r, d("nvaccel_ss_dirty_" + r)) for r in DIRTY_REASONS]
        refused_n = sum(n for _, n in reasons)
        L.append("dirty exports: accepted %d, refused %d (%.1f%% refused)" % (dirty_ok, refused_n, 100.0 * refused_n / max(1, dirty_ok + refused_n)))
        L.append("  refused by reason: " + (", ".join("%s=%d" % (r, n) for r, n in reasons if n) or "none"))
        share = [(r, d("nvaccel_ss_share_" + r)) for r in SHARE_REASONS]
        L.append("share (SURF_VRAM): " + ", ".join("%s=%d" % (r, n) for r, n in share))
        L.append("pending table: now %d, high-water %d of 512, full-refusals %d, adds %d, page-off removals %d, removed on resource free %d"
                 % (after.get("debug.nvaccel_ss_pend_count", 0), after.get("debug.nvaccel_ss_pend_high", 0), after.get("debug.nvaccel_ss_pend_full", 0),
                    after.get("debug.nvaccel_ss_pend_add", 0), after.get("debug.nvaccel_ss_pend_del", 0), after.get("debug.nvaccel_ss_pend_release", 0)))
        L.append("page-offs: ok %d fail %d via family %d, %.1f MB, copy engine %.1f ms, staging copy %.1f ms (driver-wide elapsed, not WindowServer CPU)"
                 % (d("nvaccel_ss_pageoff_ok"), d("nvaccel_ss_pageoff_fail"), d("nvaccel_ss_pageoff_family"), d("nvaccel_ss_pageoff_bytes") / 1048576.0,
                    d("nvaccel_ss_pageoff_ce_us") / 1e3, d("nvaccel_ss_pageoff_cpu_us") / 1e3))
        L.append("accelerator lock taken by share/dirty calls: %d, waited %.2f ms, held %.2f ms" % (d("nvaccel_ss_famlock_n"),
                 d("nvaccel_ss_famlock_wait_ns") / 1e6, d("nvaccel_ss_famlock_hold_ns") / 1e6))
        top = max(reasons, key=lambda x: x[1])
        if refused_n and top[1] > 0.5 * refused_n:
            if top[0] == "pend_full":
                F.append("R3: dirty exports are refused mostly because the pending table is full (high-water %d). That is the leak patch 0003 removes (entries of freed resources)."
                         % after.get("debug.nvaccel_ss_pend_high", 0))
            else:
                F.append("R3: dirty exports are refused mostly with reason '%s' (%d of %d). Patch 0003 does NOT address this; look at the source of that check in nvAccelSurfVram/nvAccelSurfDirty." % (top[0], top[1], refused_n))
        if after.get("debug.nvaccel_ss_pend_high", 0) >= 500 and after.get("debug.nvaccel_ss_pend_count", 0) >= 450:
            F.append("R4: the pending table is nearly full right now (%d/512). If most of those are dead surfaces, patch 0003 applies; if they are live, the table is too small."
                     % after["debug.nvaccel_ss_pend_count"])
        if share[0][1] == 0 and sum(n for _, n in share) > 0:
            F.append("R5: no surface was shared in this window although SURF_VRAM was asked %d times; see the share reasons above." % sum(n for _, n in share))
        elif dirty_ok == 0 and refused_n == 0:
            F.append("R6: no dirty export happened in this window: WindowServer wrote no shared IOSurface texture, or the plugin is not using the shared path.")
    return L, F


def log_findings(text):
    counts = {}
    for line in text.splitlines():
        m = re.search(r"(dirty refused \((0x[0-9a-f]+)\)|family VRAM import refused \((-?\d+)\)|buffer over the imported VRAM|image create FAILED|readback FAILED|upload FAILED)", line)
        if m:
            counts[m.group(1)] = counts.get(m.group(1), 0) + 1
    return counts


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--seconds", type=int, default=15)
    ap.add_argument("--label", default="desktop")
    ap.add_argument("--out", default=None)
    args = ap.parse_args()
    if not 3 <= args.seconds <= 300:
        ap.error("--seconds must be between 3 and 300")
    pids = run("pgrep", "-x", "WindowServer").split()
    if not pids:
        sys.exit("STOP: WindowServer not found")
    pid = pids[0]
    out = args.out or os.path.join(os.path.expanduser("~"), "efi-audit", "ws-readback-" + datetime.datetime.now().strftime("%Y%m%d-%H%M%S"))
    os.makedirs(out)
    t0, c0, k0 = time.monotonic(), cpu_seconds(pid), counters()
    time.sleep(args.seconds)
    t1, c1, k1 = time.monotonic(), cpu_seconds(pid), counters()
    if pid not in run("pgrep", "-x", "WindowServer").split():
        sys.exit("STOP: WindowServer restarted during the window; discard this measurement")
    seconds = t1 - t0
    lines, findings = analyse(k0, k1, seconds, 100.0 * (c1 - c0) / seconds)
    # what the driver already logs (works on the stock 1.14.2 install)
    logs = ["== NVAccel kernel trace (if readable) ==\n"]
    if os.access(KERNEL_TRACE, os.R_OK):
        for key in ("surfvram dirty:", "surfvram: surface", "surfvram pageoff:"):
            hits = [l for l in open(KERNEL_TRACE, errors="replace") if key in l]
            logs.append("%s %d lines, last 4:\n%s\n" % (key, len(hits), "".join(hits[-4:])))
    else:
        logs.append("%s not readable as this user; re-run with sudo to include it\n" % KERNEL_TRACE)
    logs.append("== plugin lines in the unified log (release builds log only failures/refusals), last 3 h ==\n")
    text = run("log", "show", "--last", "3h", "--predicate", 'eventMessage CONTAINS "NullMoth:"', "--style", "compact", timeout=240)
    hits = [l for l in text.splitlines() if re.search(LOG_PATTERN, l)]
    logs.append("%d matching lines; by kind: %s\n%s\n" % (len(hits), json.dumps(log_findings(text), sort_keys=True), "\n".join(hits[-10:])))
    # plugin statistics report, if the instrumented plugin is running
    reports = glob.glob(PLUGIN_REPORTS)
    for r in reports:
        shutil.copy(r, os.path.join(out, os.path.basename(r)))
    lines.append("plugin statistics reports copied: %s" % (", ".join(os.path.basename(r) for r in reports) or "none (instrumented plugin not active, or request file missing)"))
    with open(os.path.join(out, "counters.json"), "w") as f:
        json.dump({"label": args.label, "pid": int(pid), "seconds": seconds, "before": k0, "after": k1}, f, indent=1, sort_keys=True)
    with open(os.path.join(out, "logs.txt"), "w") as f:
        f.write("".join(logs))
    report = "label: %s\n%s\n\nfindings:\n%s\n" % (args.label, "\n".join(lines), "\n".join(" - " + x for x in findings) or " - none of the decision rules fired")
    with open(os.path.join(out, "analysis.txt"), "w") as f:
        f.write(report)
    print(report)
    print("".join(logs)[:6000])
    print("Saved:", out)


if __name__ == "__main__":
    main()
