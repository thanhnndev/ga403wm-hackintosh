# VRAM grant stall: `vramGrant` clears at ~110 MB/s while holding the display gate (2026-10-12)

Machine: GA403WM, RTX 5060 Laptop (PCIe x8), macOS 15.8.1, NullMoth 1.14.0 installed (fork checked at 1.14.2).
Complements `WINDOWSERVER-CPU.md`: that page measured where WindowServer spends CPU, this one is a serialized kernel cost
that stalls the display path.

## Evidence

* NVAccel's own log (`/Library/NullMoth/display-trace/kernel.txt`) brackets every grant: `os_map_kernel_space` (start of
  `vramGrant`) and `NVVidMemory::allocPhysical ... bytes of REAL VRAM` (end). 9204 grants in 2027 s:

  | Size | n | avg | rate |
  |---|---:|---:|---:|
  | >= 4 MB (7,667,712 B = a 1920x996 window) | 7444 | 69.8 ms | 110 MB/s |
  | 256 KB - 4 MB | 673 | 8.8 ms | 107 MB/s |
  | < 256 KB | 1087 | 1.2 ms | 98 MB/s |

  26 % of wall time is inside grants; 3.7 big grants/s on average, ~11/s at peak (the same two 8 MB blocks alternating
  every ~95 ms while a window repaints).
* The rate is the same for every size: the cost is the clear loop (`nvu_zero_wide`, `rep stosq`), not allocation.
  1.13.0's `rep stosb` ran at 11 MB/s, 1.14's `rep stosq` at ~110 MB/s: 8x per element size, i.e. one PCIe write per store.
  A combined write-combining buffer would not scale like that. `scripts/macos-vramtest.sh` on 1.14.0: 134-223 ms gross
  per 8 MB with a 75 ms sudo/sysctl baseline.
* `vramGrant` holds `NVRMDisplayGate` (one global recursive lock) for the whole clear. The pure flip
  (`nvFlipToSurfacePure`) and `cursorApply` take the same gate (nvrm-fb.cpp), so for ~70 ms nothing can be flipped or
  moved: 8-10 frames at 120/144 Hz, several times a second.

## Not established

* Whether the BAR1 mapping is truly write-combined (the request is `NV_MEMORY_WRITECOMBINED`, mode 2 in the log). The
  non-temporal clear only helps if it is.
* Which process asks for the grants (the log thread is one NVAccel thread). Sizes match the Edge window.
* The 46-63k page faults/s in WindowServer (`WINDOWSERVER-CPU.md` follow-up): a plain IOSurface read-back test in user
  space faults 0 times, so this is not ordinary IOSurface reading; DTrace is blocked by SIP.

## Candidate fix (fork `thanhnndev/nvidia-macos-driver`, branch `nvrmfb-vram-clear-nontemporal`, not installed)

`nvu_zero_stream`: eight `movnti` per 64-byte line + `sfence`, run-time switch `debug.nvrmfb_clear_mode` (1 new, 0 old)
and `debug.nvrmfb_clear_us_sum / _bytes / _us_max` so old and new can be compared in one boot with `macos-vramtest.sh`.
Helper correctness checked in user space (all alignments, 7.6 MB); throughput on the BAR is unmeasured.

Expected if the mapping is write-combined: 7.6 MB in a few ms instead of 70 ms. If the new clear is no faster, the
mapping is effectively uncached and the next option is not to clear through the CPU at all (GPU copy engine, or reuse a
freed block of the same size).

## State on the machine (2026-10-12 13:41)

* Upstream NullMoth **1.14.2** installed from the release package (`~/efi-audit/upgrade-1.14.2/pkg`, SHA-256 checked) with
  its own `install.sh`; backup `/Library/NullMoth/backup-20261012-134122.JOamKt`, undo `uninstall.sh <backup>`.
* NVRMFB replaced by the fork build (commit `49633c9`, sha256 `f3e7bff4...`; built from the unpatched 1.14.2 source the
  same way it matches the shipped binary: same 263 symbols and imports) by `scripts/macos-nvrmfb-vramclear-patch.sh`;
  `--undo` puts the upstream executable back.
* boot-args gained `nvrmacpibl=1`: 1.14.1 stopped asking the GPU firmware for backlight tables by default (some PCs hung
  there); 1.14.0 did, and the brightness slider / software dimmer rely on it. Backup `config.plist.pre-nvrmacpibl-20261012`.
* NVMTLDriver.bundle is upstream's again (Codex's upload-copy candidate was replaced; its original is in
  `/Library/NullMoth/ws-upload-test/previous.bundle` and the upgrade backup).
* After the reboot: `scripts/macos-nvrmfb-vramclear-ab.sh` (root) prints clear MB/s for mode 0 (rep stosq) and 1 (movnti) in the same boot.

## Update 2026-10-12 14:02

The installed NVRMFB is now the combined build (VRAM-clear patch + the AUX-brightness hook, sha256 `d953e018...`), so the
reboot loads both. `macos-nvrmfb-vramclear-patch.sh --undo` no longer applies (it expects the VRAM-only hash); use
`scripts/macos-edpbl-install.sh --undo` to get back the VRAM-only NVRMFB, then `macos-nvrmfb-vramclear-patch.sh --undo`
for upstream. Details: `OLED-BRIGHTNESS-DPCD.md`.

## Result after reboot (2026-10-12 17:12)

The combined patched NVRMFB is loaded and clear_mode=1. Ran the existing root-authorized A/B,
with the desktop left running (driver-wide counters include unrelated allocations):

| Mode | Bytes cleared | Clear time | Effective throughput |
| --- | ---: | ---: | ---: |
| 0, rep stosq | 54 MiB | 729 ms | 78 MB/s |
| 1, movnti | 47 MiB | 440 ms | 113 MB/s |
| 0, rep stosq | 49 MiB | 626 ms | 82 MB/s |
| 1, movnti | 62 MiB | 600 ms | 109 MB/s |

The new path is faster, but not by the order of magnitude expected from effective write combining.
It remains roughly 70–76 ms per 8 MiB clear. This suggests poor effective BAR1 write throughput;
actual PAT/MTRR/cache mapping has not been proven. Do not equate this with a measured PCIe link limit.
The source still holds NVRMDisplayGate across the clear. clear_mode was restored to 1.

A subsequent 12.09-second desktop interval recorded 363 grants, 55,705,600 bytes cleared and
567,018 microseconds in clears (4.69% of elapsed wall time), with WindowServer at 24.57% of one
logical CPU and 26.47 flips/s. Clear time is driver-wide elapsed duration, not WindowServer CPU time.
No new flip failures or async drops. This cost contributes to stalls but does not explain all CPU.

Next implementation targets are verifying the actual mapping cache attributes and clearing via
GPU or safely reusing allocations. Neither should remove zero initialization or GPU synchronization.
No new driver was installed in this investigation.

Local artifacts: build/ws-reboot-audit/clear-ab.txt, steady.json and windowserver.sample.txt.

## Deeper research: PAT slot mismatch (2026-10-12 17:29)

The enabled Sequoia Algrey boot patch encodes PA6=UC- while XNU uses PA6 for
write-combined mappings. A one-entry correction to PA6=WC is now installed in
the ESP config, with AmdCppc 0.2.1 read-only PAT diagnostics staged for reboot.
This is a source/config finding, not yet a live PAT read or measured speedup.
See WINDOWSERVER-RESEARCH.md for the source chain, alternatives and rollback.

## PAT correction verified after reboot (2026-10-12 17:43)

Live PAT PA6=WC on all 24 CPUs. The same existing A/B now measures rep stosq
1008–1048 MB/s and movnti 1043–1094 MB/s, versus 78–82 and 109–113 MB/s before
the PA6 correction. The selected clear path improved roughly 9–10x.
An 8 MiB clear is now approximately 7.7–8.0 ms at the measured throughput.
The display gate still covers clear; no GPU clear or resource-lifetime change was made.
WindowServer remains workload-dependent: 33.4% of one CPU / 34.5 flips/s in this round;
zero flip errors/drops. See WINDOWSERVER-RESEARCH.md for full results and caveats.
