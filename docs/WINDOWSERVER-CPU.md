# WindowServer CPU investigation — 2026-10-11

Machine: GA403WM, macOS 15.8.1 (24H32), NullMoth 1.14.0. The owner reports high CPU even without scrolling or dragging.

## Measured result

WindowServer's CPU load follows visible application content. Temporarily hiding the ChatGPT application (which hosts
Codex here) reduces the measured load almost to idle. This is the strongest lead, rather than a driver busy loop that
continues with all windows hidden. The driver still contributes substantial work when that content changes.

CPU below is the change in cumulative WindowServer process CPU time divided by elapsed wall time, expressed as a
percentage of **one logical CPU**. These are separate short measurements, not a simultaneous benchmark.

| State | Duration | CPU | Primary flips/s |
|---|---:|---:|---:|
| Visible windows | 10.11 s | 78.9% | 29.8 |
| Previously visible regular applications hidden | 10.12 s | 12.3% | 3.8 |
| Same applications restored | 10.11 s | 73.7% | 35.4 |
| Only ChatGPT hidden | 8.57 s | 1.5% | 1.2 |
| Only Microsoft Edge hidden | 8.58 s | 53.0% | 34.2 |
| Only Zalo hidden | 8.57 s | 65.9% | 34.4 |

The hide-all test affected Zalo, Microsoft Edge, ChatGPT and Finder; Claude was already hidden. Every application
hidden by the test was unhidden afterward. Tests ran during an active Codex conversation, so streaming responses/tool
activity can contribute. This establishes dependence on that visible window, but does not identify a particular
animation or prove that the same repaint rate persists after the conversation finishes. Repeat with no active turn
before calling it a persistent application defect.

During the visible/hidden/restored test, most updates were on driver head 1 (296/301, 32/38 and 352/358 respectively).
Head counters are driver indices; they have not been mapped to a physical display here. No new `iop_fail` or
`iop_async_drop` occurred during these measurements.

## Original sample and driver source

Original data was collected at 21:03 local, WindowServer PID 158, then preserved at
`~/efi-audit/ws-cpu-20261011/` (`ws-sample.txt`, both vmmap summaries and `ab.json`).

The main thread has 2,485 observations. Its dominant update path is:

`CGXUpdateDisplay → CompositorMetal → QuartzCore → NVMTLTexture nvmtlSurfaceIn → nvmtl_vk_image_write`

The large upload branch contains 410 observations in `longcopy` and 91 in upload submission/wait. Other threads
show `nvmtlSurfaceOut → nvmtl_vk_image_read` and IOSurface release. These are observations of elapsed execution/wait
states, **not CPU percentages**; parent and child counts overlap and must not be summed. Sleeping syscall counts
across all threads do not indicate CPU consumed in those syscalls.

Source checked at tag `v1.14.0`, commit `56ae15f4e91a8ef0bf7a9db6f6980a0a49a0bf8f`:

* [NVMTLObjects.m](https://github.com/nullmoth/nvidia-macos-driver/blob/v1.14.0/plugin/NVMTLObjects.m):
  `nvmtlSurfaceIn` skips an already synchronized, unchanged IOSurface seed/generation. Actual uploads can result from
  changed or newly created surfaces; this sample cannot distinguish those cases. `commitAndWaitUntilSubmitted` waits
  for completion in WindowServer deliberately so scanout cannot precede rendering.
* [nvmtl_vk.c](https://github.com/nullmoth/nvidia-macos-driver/blob/v1.14.0/plugin/nvmtl_vk.c):
  `nvmtl_vk_image_write` copies pixels into staging memory and submits/waits for a Vulkan transfer. The readback path
  also copies pixels. The sample proves these paths were used, but does not establish why VRAM sharing did not avoid
  each individual transfer.

Memory footprint went from 680 to 692 MB across 13.2 seconds; peak stayed 868.4 MB. IOKit grew by 11.8 MB, IOSurface
dirty memory stayed 195.4 MB, malloc dirty stayed about 161 MB. This short interval is insufficient evidence of a
memory leak. Large framebuffer virtual reservations are not equivalent to allocated RAM.

## Practical mitigation and follow-up

Hide/minimize the ChatGPT/Codex window when it is not in use: this directly reduced WindowServer load in the test.
No driver removal, boot arguments, refresh-rate changes, or WindowServer restart are required for this mitigation.

For a clean repeat, launch the following from Terminal while no Codex response is running. Keep the pointer still,
leave the same displays connected, and take each measurement once with the app visible and once minimized:

```sh
python3 scripts/macos-ws-cpu.py --seconds 20 --label visible-static
python3 scripts/macos-ws-cpu.py --seconds 20 --label chatgpt-minimized
```

The collector needs no sudo, changes no settings, and saves JSON under `~/efi-audit/ws-cpu-<timestamp>/`.
It checks that WindowServer did not restart, measures CPU from process-time deltas, and records per-head updates,
flip/error/drop and allocation counter deltas. Allocation counters are cumulative driver-wide totals, not solely
WindowServer allocations. Do not interpret a decreasing live-allocation count or cumulative byte total as a leak.

If the load remains high with ChatGPT minimized in a quiet repeat, collect a new WindowServer sample in that state
with `scripts/macos-ws-frame-sample.sh` (sudo needed). Further driver changes need that evidence. Removing the completion
wait or forcing a sharing knob without checking synchronization risks stale/black frames and is not a justified fix.

The initial visibility investigation above was followed by the system/driver investigation below.

## System-wide follow-up and upstream candidate

Source checkout: `/Users/thanhnndev/develop/projects/nvidia-macos-driver-ws`, base
`de9b33aa98dcb0ba6d5bf624fc3817e4a2d8bd66`; candidate commit
`68b4ce209a32135385ec4b27221fc8c2cecfc484`.
[Draft PR #139](https://github.com/nullmoth/nvidia-macos-driver/pull/139) proposes an upload-copy optimization.
It does not claim to fix every source of desktop CPU load.

The new root-authorized system spindump is in `~/efi-audit/ws-system-20261012-114755/`:

* WindowServer: 5.759 s CPU over 8.00 s (72% of one logical CPU), main thread 4.476 s.
* Kernel task: 1.373 s; its named NVRM thread used 0.246 s. NVRM is not spinning continuously in this capture.
  Kernel work executing on a client thread can be charged to that client, so kernel_task time alone does not
  exclude driver overhead in WindowServer.
* The spindump collector itself used 10.230 s CPU. Exclude that instrumentation cost when discussing normal
  system utilization; do not treat its work as a background-system problem.
* Main-thread stacks contain the IOSurface staging-copy path, QuartzCore composition and synchronous Metal
  completion. The source deliberately keeps those completion waits to protect rendering and image lifetime.
* RAM pressure was low, swap was zero. The displays are 1920x1080 at 144 Hz and 2880x1800 at 120 Hz (1440x900 HiDPI).
* On AC power, CPPC was off; busy Zen 5 cores measured about 2.03 GHz and Zen 5c about 1.64–1.80 GHz in this capture.
  The earlier clock snapshot had Zen 5c at 1.42 GHz. CPU power management is a separate performance limitation;
  no MSRs, CPPC settings or CPU kexts were changed by this investigation.

Synthetic static/animation/move runs were also saved under `~/efi-audit/ws-system-20261012/`. Their background
isolation was not reliable: the on-screen window inventory still included ChatGPT and a full-screen Screenshot
overlay after requesting application hiding. Do not use those runs as a clean idle baseline or to assign driver
head indices to physical monitors.

Direct GPU tests independently exercised a 2880x1800 texture and a shared IOSurface on the installed NVK/kexts.
Shared-VRAM import and buffer/image alias creation both succeeded, and readback matched the input. This rules out
a universally broken shared-import path on this machine, but does not prove every compositor surface uses it.

An attempted tight-pitch readback memcpy optimization produced correct pixels but no consistent performance gain
and was discarded. The deferred-upload approach in PR #96 was cherry-picked and then made synchronous upstream
in commit `77e4c9839f5925a7087357d552790a7edcc978fa`: freeing the destination image could race the GPU copy. That
approach was not reapplied. macOS Reduce transparency also did not reduce the measured load (steady repeat 83%).

### What PR #139 changes and what is verified

Large GPU-consumed staging uploads use AVX2 streaming stores when the destination and tight row size are aligned
to 32 bytes. A CPU SFENCE completes those stores before the existing Vulkan transfer/submission. Small/unaligned
uploads and CPUs without AVX2 keep libc memcpy. GPU completion waits and resource lifetimes are unchanged.

On the RTX 5060/HX 370, three interleaved warmed process runs per variant/pitch gave these medians for 2880x1800:

| Source pitch | Original upload CPU | Candidate upload CPU | Original wall | Candidate wall |
|---|---:|---:|---:|---:|
| 11520 (tight) | 2.347 ms | 1.920 ms | 3.384 ms | 2.979 ms |
| 11584 (+64 padding) | 2.367 ms | 1.926 ms | 3.311 ms | 2.914 ms |

This is about 18% less CPU per upload and 12% lower upload wall time. Individual runs varied. These are isolated
transfer numbers, **not a measured reduction of WindowServer CPU**. Pixel checks changed the first/last pixel on
each iteration, compared every output row and checked output padding. ASan/UBSan helper tests, full plugin builds,
release GPU roundtrips and an ARM64 fallback compile check passed. Other GPUs/older CPUs remain unmeasured.

Raw measurements: `~/efi-audit/ws-cpu-20261011/final-upload-ab.json`. The release candidate is
`~/efi-audit/ws-upload-candidate/NVMTLDriver` (SHA256
`5975192f1d5cc8ed8b6c2bcb53a1fe0ac55b301806e232cd0c49f0981b576d6a`).

### Install and desktop validation

`scripts/macos-ws-upload-install.sh` validates the exact collected 1.14.0 executable and candidate hashes, stages
the bundle, and atomically exchanges it with the installed bundle. The full original bundle is retained in
`/Library/NullMoth/ws-upload-test/previous.bundle`. The signed candidate bytes were verified standalone; vendor
package assets/signatures are otherwise preserved. The original vendor bundle already fails whole-bundle resource
seal verification, so that check is not used to assert candidate compatibility. A copied candidate bundle loads
through NSBundle in an isolated process. This still does not replace WindowServer activation testing.

```sh
sudo bash scripts/macos-ws-upload-install.sh
# Reboot after saving work. Then reproduce the same workload:
bash scripts/macos-ws-system-collect.sh
```

Undo (then reboot): `sudo bash scripts/macos-ws-upload-install.sh --undo`.
The installer never restarts WindowServer itself. A disk replacement does not change code already mapped by the
running WindowServer. Verify the next boot's sample driver UUID against the candidate, compare CPU time/flips under
the same workload, and check rendering, app launches, display sleep and both displays before promoting the draft.

## Follow-up 2026-10-12: the upload candidate was the wrong layer; the lead is `vramGrant`

* Codex's candidate (PR #139, streaming-store copy in `nvmtl_vk_image_write`) was evaluated and dropped: the copy is a
  small part of the WindowServer cost and the kernel side (system time >= user time, 46-63k page faults/s) is where the
  time goes. The installed `NVMTLDriver.bundle` is upstream's again (the candidate is in
  `/Library/NullMoth/ws-upload-test/previous.bundle` and in the upgrade backup). `scripts/macos-ws-upload-install.sh`
  must not be run on 1.14.2.
* Measured instead: every IOSurface grant in `vramGrant` clears through BAR1 at ~110 MB/s while holding the global
  `NVRMDisplayGate`, 26 % of wall time and ~70 ms stalls for 7.6 MB, with flips and cursor updates queued behind it.
  Evidence, candidate fix and the A/B to run: [VRAM-GRANT-STALL.md](VRAM-GRANT-STALL.md).
* Still open: the page faults in WindowServer (a plain IOSurface read-back in user space faults 0 times, DTrace is blocked by
  SIP), and whether the `movnti` clear is actually faster on this BAR (needs the reboot and the A/B).

## Reboot follow-up (2026-10-12 17:11–17:15)

AmdCppc 0.2.0 + autonomous CPPC policy is active; the new NVRMFB clear path is loaded.
Visible-desktop WindowServer measurements: 30.2% of one logical CPU / 32.2 flips/s over 10.95 s;
later 24.57% / 26.47 flips/s over 12.09 s. The historical 70–80% measurements used other workloads
and CPU clocks, so this is not a controlled before/after claim.

A 6-second root-authorized sample still shows CGXUpdateDisplay → CompositorMetal → QuartzCore →
NVMTLTexture nvmtlSurfaceIn → nvmtl_vk_image_write, with upload copies and Vulkan submission waits.
2914 of 3641 main-thread observations were in the message-receive branch. These sample counts are
elapsed stack observations, not CPU percentages, and are not evidence of a continuously spinning
main thread. CPU includes all WindowServer threads and kernel work on those threads.

Kitty briefly showed 87.6% in ps, but its separate sample mostly found event/poll waits, so that
snapshot is insufficient to call Kitty the sustained cause. NSRunningApplication.hide returned
false for Kitty (0 successfully hidden instances); the output labeled kitty-hidden (68.4%) is an
invalid isolation result and must not be used to infer causality. Kitty subsequently was no longer
running, without this investigation terminating it.

Driver clear A/B: mode 0 78–82 MB/s vs mode 1 109–113 MB/s. The optimization helps, but slow clears
still hold the global display gate. In the later desktop interval, clears occupied 4.69% of wall
time (driver-wide, not attributable entirely to WindowServer). See VRAM-GRANT-STALL.md. No new
iop_fail or iop_async_drop; clear_mode restored to 1. Driver and desktop both contribute; this
inspection does not isolate a particular app's repaint source or prove a driver busy loop.

Artifacts: build/ws-reboot-audit/{windowserver.sample.txt,kitty.sample.txt,clear-ab.txt,steady.json};
visible measurement ~/efi-audit/ws-cpu-20261012-171154-021688/measurement.json. No driver replacement,
WindowServer restart or persistent refresh-rate change was performed.

Research continuation: WINDOWSERVER-RESEARCH.md identifies a concrete mismatch between
the configured AMD PAT table and XNU's write-combining slot. PA6-only correction is
staged in EFI; next boot's actual PAT read and clear throughput will validate it.

Post-reboot PAT validation (2026-10-12 17:43): AmdCppc 0.2.1 loaded, PA6 WC read
on all 24 CPUs; VRAM clear now 1043–1094 MB/s (~9–10x prior movnti throughput).
WindowServer measured 33.4% of one CPU / 34.5 flips/s; zero failures/drops.
This confirms the clear bottleneck fix, not a measured reduction in compositor CPU
under an identical workload. Full record: WINDOWSERVER-RESEARCH.md.
