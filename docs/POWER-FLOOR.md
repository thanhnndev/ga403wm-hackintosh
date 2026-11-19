# Idle power floor: why "idle" reads 16 W, and what brings it toward 5.5 W

2026-11-16, boot 18:39 (out-29, StrixS0ix 0.1.17 idle mode 0, RTX powered because the gate stood down).
Branch `claude/power-floor-ab2a3f`. Sub-session of the main coordinator; read-only measurements, nothing installed.

Every number below is marked **measured** (taken on this machine, source given) or **estimate** (derived; how is
said). During this session the machine was **not idle**: Docker (hyperkit 100-200 %), an Xcode Swift build, the iOS
simulator, the video-suite session's `genmp4` + VTEncoder (~190 %), Edge, the Claude app and several Claude CLIs.
Package power was 28-56 W, Tctl 78-92 °C. No idle floor was measured today; the floor numbers come from earlier runs.

## 0. Summary

1. **The handoff's framing is off.** The "idle 16.4 W" sample (18:54, 15 min after boot) was not idle: Claude app
   ~33 % + 5 Claude CLIs ~11 % + WindowServer 10 % + kernel_task 12 %, at **EPP 0**. The "true idle 5.5 W" (2026-11-08,
   boot 17:33) was most likely taken **in idle mode 0 too** (HLT: the boot default is 0 and nothing records a switch on that boot; the 12:14 boot that was left in mode 1 had been replaced by then).
   So HLT alone already reached 5.5 W: **C-states are not the 11 W gap.** The gap is screen redraws plus the CPU
   work of the Claude stack, at a maximum-performance EPP.
2. **Log volume is not a cause.** All our kexts together wrote ~0.2 lines/s (2 min `log show`, 30 s kernel
   `log stream --level debug`). `diagnosticd` load comes from the iOS simulator: the Claude app's `simctl spawn … log
   stream` (orientation watcher) keeps the host diagnosticd (5-6 %) and the **simulator's own diagnosticd (10-13 %)**
   busy, and the simulator's `apsd` alone logs **~700 lines/s**. It goes away with the simulator.
3. **kernel_task ~12 % at idle with an empty compressor is most likely our polling threads**, all of which run in
   kernel_task: the Wi-Fi link loop (1 ms poll, busy `IODelay` windows after every packet), ItlXhciKick (1 kHz,
   ~2k work-loop wakeups/s), VoodooI2C touchpad polling (`-vi2c-force-polling`, ~10k IRQ/s on CPU 0 measured 11-08).
   Needs one root spindump to confirm (command in section 7).
4. **Display path keeps waking at 120 Hz forever:** NMXAMDFB's software VBL timer ignores `setInterruptState`, so it
   fires at the panel rate even when IOFramebuffer has masked VBL. Patch on this branch (not built).
5. **Outside RAPL is large.** On battery at 19:26 the battery drained **75 W** (capacity method, 60 s) while RAPL
   package read **31 W**. The ~44 W difference (RTX powered, OLED, VRM loss, SSD, Wi-Fi, fans) is invisible to every
   package number in the handoff. For battery life the RTX/platform side may matter as much as the package floor.

## 1. Measuring protocol ("steady state")

A run counts as an idle-floor sample only if all of this holds for the whole window (the probe now checks it and
prints `verdict STEADY` or `LOADED: <reasons>`):

| Condition | Threshold | Why |
|---|---|---|
| Uptime | ≥ 30 min | Spotlight, mds_stores, launch storms after boot (old numbers at 15-20 min were unclean) |
| Builds (swift-frontend, clang, xcodebuild, ld, rustc, cargo…) | ≤ 5 % total | |
| Docker (com.docker.*, hyperkit, vfkit, qemu) | ≤ 5 % | a stopped VM, not "idle containers" (idle containers still cost ~1 core, 11-08) |
| Spotlight (mds*, mdworker*, corespotlightd) | ≤ 5 % | |
| FSKit (UVFSService, fskitd) | ≤ 5 % | 85 % seen today with the NTFS volume mounted, trigger unknown |
| diagnosticd | ≤ 3 % | a `log stream` client is attached (simulator) |
| Simulator | not running | log storm + diagnosticd + AccessibilityControlsExtension bursts |
| Media (VTEncoder/VTDecoder/ffmpeg/genmp4) | ≤ 5 %, no VTDecoder process | |
| Screen | ≤ 10 frames/s (NMXAccel `pipe_perform` delta) | an animating Claude window costs ~4.5 W by itself (11-08) |
| WindowServer | ≤ 5 % | |

Also recorded every run (not gating, but must be equal between runs that are compared): EPP per CPU, ASUS profile,
`dgpu_disable`, idle mode, AC/battery, caffeinate, browsers, log lines/s and the top 4 loggers, load average,
memory/wired/compressor, top 40 processes. EPP is not constant: on battery with profile 3 it read 255 at 19:24:39 and
0 at 19:25:21, so it is sampled per run.

Procedure for a floor sample: owner closes the simulator, stops Docker Desktop, pauses builds, no video, Claude
app not streaming (or hidden), screen on and static; wait until uptime ≥ 30 min; run
`tools/health-probe.sh floor 120` detached (or with sudo for IPIs/interrupts); accept only `verdict STEADY`.
Battery discharge needs ≥ 120 s (1 mAh resolution).

`tools/health-probe.sh` changes (this branch): verdict line, uptime, load breakdown per class, frames/s over the
window, log lines/s with top loggers (10 s `log stream`, `LOGRATE=0` to skip), simulator/browsers/caffeinate, load
average, top 40 instead of top 15, the uptime regex bug fixed. `tools/idle-ab.sh`: prints EPP and profile at the
start and EPP per phase (mode comparisons are only valid at equal EPP and frames/s).

Samples taken today (no root, honest labels): `19:24 test-loaded` 28.8 W / 79 °C, `19:25 now-loaded` 31.1 W RAPL,
**75.3 W battery**, 81-90 °C, verdict `LOADED: docker 124 %, diagnosticd 19 %, media 186 %, video decoder,
WindowServer 6 %` (simulator also running; the first probe version missed it, fixed).

## 2. Idle watt budget

Reference points (all RAPL package, AC):

| State | Value | Source |
|---|---|---|
| True idle, 2-3 frames/s, WS 1 %, idle mode 0 | 5.5 W, 47 °C | measured 2026-11-08 18:00 (`idle-attrib.sh`, boot 17:33) |
| Same boot, Claude spinner → 80 frames/s, modes 0/1/2 | 9.9-10.1 W (no mode difference) | measured 2026-11-08 18:05 (`cpu-idle-ab.sh`) |
| "Idle desktop" 15 min after boot, EPP 0, Claude app + 5 CLIs | 16.4 W, 60-67 °C | measured 2026-11-16 18:54 (`tools/health/2026-11-16/185424-idle-1.txt`) |
| Light load, EPP 0 vs EPP 128 | 26 → 16 W, 37 → 22 W (−38 to −40 %) | measured 2026-11-08 A/B |

Budget of the 16.4 W sample against the 5.5 W floor:

| Row | Watts | Kind | Basis |
|---|---|---|---|
| Floor: SoC + display engine + memory, static screen, HLT | 5.5 | measured | 11-08 true idle |
| Screen redraws from the Claude app (WS composite on the 890M, scanout fetch, memory clocks up) | ~4.5 | measured | 11-08: 5.5 → ~10 W at 80 frames/s, same boot |
| EPP 0 instead of 128 on the remaining CPU work (~0.7 core: Claude stack, WS, kernel_task) | ~3.5-5 | estimate | −38 % measured ratio applied to the rest; overlaps the row above |
| kernel_task 12 % (polling threads, see 4) | ~0.5-1.5 | estimate | 0.12 core at boost clocks + the wakeups it causes |
| Claude CLIs (5 × ~1-4 %) | ~0.5-1 | estimate | top: 11 % total |
| Sum | ~14.5-17.5 | | brackets the measured 16.4 W |

Rows that are **not** in the 16.4 W and that matter elsewhere:

| Row | Watts | Kind | Basis |
|---|---|---|---|
| HLT instead of CC6 at true idle | ~0.5-2 | estimate | 0 measured at 80 frames/s; at true idle cores are >95 % idle; larger at EPP 0 because CC1 cores sit on the shared rail voltage |
| Simulator open (apsd log storm + 2 × diagnosticd ~19 % + extensions) | ~1-2 | estimate | measured CPU today, watts from 3-5 W per boosted core |
| FSKit UVFSService/fskitd burst (~110 % together) | ~3-4 while active | estimate | measured CPU 19:20, trigger unknown |
| RTX powered + platform (not in RAPL) | battery 75 W vs package 31 W under load | measured | 19:26 on battery; idle split unknown |

## 3. C-states: how idle is entered today

- `machine_idle()` (25G332 kernel) calls `pmDispatch->MachineIdle` (offset 0x10) if set, else `sti; hlt; cli`. On
  AMD no Apple kext registers it. **StrixS0ix 0.1.14+ registers it** (`kexts/StrixS0ix/StrixS0ix.cpp`,
  `s0ixMachineIdle`, line ~455): mode 0 = `sti; hlt; cli` (stock), mode 1 = per-CPU predicted idle (EWMA, 1/8) ≥ 40 µs
  → IO read of `CStateBaseAddr + 1` (`_CST` C2 = CC6), mode 2 adds `+2` (C3) for ≥ 2 ms when PM1 BM_STS is clear.
  Boot default `S0ix,IdleMode = 0` (boot-arg `s0ix_idle`, runtime `build/s0ix-set idle N`; `-s0ixidleoff` drops
  the hook). Live now: mode 0. Boot log: `CStateBaseAddr 0x413, CC6 port 0x415` (that "CC6 port" line is the
  sleep path's `s0ix_cst` depth, not runtime idle).
- So "idle mode 0 = HLT, no CC6" is **true but not new**: the fix exists and has been live-switchable since 11-08.
  It has never been compared at a true idle.
- What CC6 at idle needs: mode 1 (done in code), ARAT (present, `invariant_APIC_timer = 1`), and **long idle
  intervals**. A core only reaches CC6 when the predicted idle is ≥ 40 µs, and residency is cut by every wakeup. The
  wakeup sources in section 4 (10k/s I2C on CPU 0, 2-3k/s kick + work-loop wakeups, 1k/s Wi-Fi, 120/s VBL) decide how
  much mode 1 can give. Package-level deep idle also needs the display engine idle (PSR / IPS, section 5) and memory
  traffic low.
- **What `tools/idle-ab.sh` toggles:** only `s0ix-set idle 0/1/2` (the MachineIdle state choice), 6 × 35 s phases,
  RAPL energy over the phase, ktrace IPIs/interrupts, top, frames/s, hook stats. It is the **right test for the hook**
  but only valid at a steady true idle; at 80 frames/s it read the same 10 W in every mode (11-08). It did not record
  EPP (fixed here). Run it only after a `STEADY` probe, and expect 0.5-2 W, not 10 W.
- Small doubts in the hook (not changed, need a test first): the idle length `dt` excludes the interrupt handler, so
  the EWMA underestimates long idles slightly (conservative, fine); mode 2's BM_STS check is global, so one bus master
  (Wi-Fi polling DMA, xHCI) demotes every core.

## 4. kernel_task and wakeups: periodic sources in our code

No-root view: `top` IDLEW is always 0 on this machine; `ps`/`top` cannot split kernel threads. Source review of every
kext that is live (`kextstat`) and whose source we have:

| Source | Period / rate | Purpose | Cost | File |
|---|---|---|---|---|
| Wi-Fi link loop (`m3` RX/TX pump) | `IOSleep(1)` when quiet = ~1000 wakeups/s; after any packet `IODelay(20)` per pass and `IODelay(200)` for 50 ms | fully polled RX/TX, no interrupt | **largest suspect for kernel_task 12 %**: with streaming traffic (Claude, Docker pulls, mDNS, AWDL) the 50 ms window rearms constantly; `IODelay` either spins or, above xnu's spin threshold, becomes a 200 µs timed wait (5k wakeups/s). Either way a core never idles while traffic trickles | `~/develop/projects/mt7925-macos/kexts/itlmt7925/itlmt7925_m3.cpp:2785-2788` (live build B9E6878A, branch `dev/awdl`) |
| ItlXhciKick worker | 1 kHz (`itlz0`: `p=1000us`); controllers with devices kicked every period (c1, c3: 2.14 M kicks in 2339 s = 916/s each), empty ones every 16 | drains xHCI interrupter 1/2 events that have no MSI | 1k timer wakeups + ~1.8k work-loop wakeups/IPIs per second, forever | `kexts/ItlXhciKick/ItlXhciKick.cpp:160-232` |
| VoodooI2C touchpad polling (`-vi2c-force-polling`) | ~10k controller IRQs/s on CPU 0 (11-08 powermetrics) | touchpad GPIO interrupt not wired on AMD | keeps CPU 0 from idling at all; also the 11:19 panic link | boot-arg + VoodooI2C/VoodooGPIO (third party) |
| NMXAMDFB software VBL | panel rate, 120 Hz, never stops | VBL "interrupt" for IOFramebuffer | 120 wakeups/s + IOFramebuffer VBL work, even when masked | `nmx-build-xkpi/src/gpu-port/xkpi/xnu/nmx_fb.cpp:278-287, 531-532` |
| NMXGPU heartbeat `g_beat_call` | 1 s | liveness | negligible | `xnu/nmx_kext.cpp:459` |
| StrixDgpuGate poll/heartbeat | 1 s poll; heartbeat 250 ms for HB_TICKS after an event | gate state | small; NVRAM writes during a run | `rog-control-macos-gpumode/kexts/StrixDgpuGate/StrixDgpuGate.cpp:490, 561` |
| StrixAccel scan tick | 500 ms / 2 s, stops after 240 ticks | AGDC bring-up | none after ~8 min | `kexts/StrixAccel/StrixAccel.cpp:599-617` |
| StrixMetalGate | seconds | gate | none (and `-strixmetalgateoff` is set) | `kexts/StrixMetalGate/StrixMetalGate.cpp:86` |
| StrixS0ix evt/qCall | only after a wake | GPIO/EC | none at idle | `kexts/StrixS0ix/StrixS0ix.cpp:1299, 1308` |
| AmdCppc, AsusWmi, BtLeDlFix, MtkBtFw, RyzenHV | no periodic timers found (RyzenHV: only while a VM runs) | | | |
| linuxkpi `mi_switch` / `maybe_yield` | 1 µs timed wait per call | yield inside amdgpu loops | only under GPU load | `bsdcompat/src/nmx_kernel.c:550` |

Apple-side periodic load seen today: IO80211Family AWDL machinery ~16 log lines/s (sync frames, elections,
`peerChannelSteer` every ~1 s) because `itlmt_awdl=1` is on; that also means radio ROC windows ~1.8/s.

## 5. Display idle features (new lead, not measured)

Boot log (NMXGPU): `PSR support 1, DC PSR ver 0, sink PSR ver 1 DPCD caps 0x3a` and
`NullMoth ips: dcn35 clk_mgr … disable_ips 6`. 6 = `DMUB_IPS_RCG_IN_ACTIVE_IPS2_IN_OFF`, which is what upstream
amdgpu_dm picks for DCN 3.5.0 too (to be checked against the vendored drm-kmod), so IPS is likely at the Linux
default. **Whether PSR is ever entered is unknown:** upstream enters PSR when DRM vblank interrupts have been off for a
few frames on a static screen; in this port the IOFramebuffer side runs its own 120 Hz timer and the scanout bridge's
vblank references are not visible. With a 2880×1800 120 Hz OLED, scanout fetch from memory is ~2.5 GB/s at a static
screen without PSR; PSR lets the display engine stop fetching and the memory/fabric clocks drop. Estimate 0.5-1.5 W
at idle. Next step (main, NMXGPU): a read-only sysctl with `link->psr_settings.psr_feature_enabled`,
`psr_allow_active`, and the CRTC vblank refcount.

## 6. Ranked causes and fix proposals

Ranked by watts for "idle with the owner's normal desktop open".

1. **Screen redraws from the Claude app (~4.5 W measured).** Not a driver bug in itself; the cost per frame is the
   driver's (WindowServer ~5 ms CPU per frame, 11-08 profile). Fix: per-frame cost in the WS plugin (IOSurface import
   misses, synchronous commit; `docs/CPU-THERMALS.md` "WindowServer per frame"), owned by main. Owner side: hide the
   Claude window when not watching it.
2. **EPP 0 on AC (~3.5-5 W estimate at this load, 10-15 W at light load measured).** Owner decision, not in scope.
   Note for the owner/session B: on battery with profile 3 EPP flipped 255 → 0 within a minute today.
3. **Kernel polling threads (~0.5-1.5 W, plus they cap what CC6 can give).**
   - Wi-Fi (`itlmt7925_m3.cpp:2785-2788`, Wi-Fi session's repo): replace the 50 ms `IODelay(200)` window with
     `IOSleep(1)` once a pass found nothing (keep `IODelay(20)` only while the previous pass moved frames), and on
     the longer term use the WFDMA interrupt (MSI) to wake the loop. Throughput must be re-measured (29-36 MB/s
     baseline), so this needs the Wi-Fi session; no patch here.
   - ItlXhciKick (`ItlXhciKick.cpp` worker): before `signalInterrupt`, read interrupter 1/2's event ring state
     (IMAN.IP or the ERDP vs the ring cycle bit, read-only MMIO) and kick only when an event is pending; sleep 4-8 ms
     when nothing was pending for 1 s and return to 1 ms on the first hit. Removes ~1.8k work-loop wakeups/s at idle.
     Key-up latency must stay < 2 ms when typing; needs a test, so not patched here.
   - Touchpad: get the touchpad's `GpioInt` working (AMD GPIO; StrixS0ix already maps the AMD GPIO block for pin 0)
     and drop `-vi2c-force-polling`. Removes ~10k IRQ/s on CPU 0 and the panic link. Larger job.
4. **NMXAMDFB VBL timer at 120 Hz forever (small W, but it is a permanent wakeup and lets PSR-style idle never
   happen).** Patch: `patches/power-floor/nmx-fb-vbl-gate.patch` (applies clean to `nmx-source-port` @ 4f6825b,
   `-fsyntax-only` clean with the port's flags; **not built**). `setInterruptState`/`unregisterInterrupt` now gate
   the timer; it stops at its next fire when VBL is masked and is re-armed on enable. Default `on = true`, so if
   IOFramebuffer never masks, behaviour is unchanged. Boot-arg `nmxvblgate=0` restores the old timer (grep: no other
   kext uses that name).
5. **HLT instead of CC6 (~0.5-2 W at true idle, estimate).** Fix exists (StrixS0ix mode 1). Needs the steady A/B;
   if it gains, make mode 1 the boot default (`s0ix_idle=1` default in `start()` around line 1146). Do 3 first or
   the gain is capped.
6. **PSR not confirmed (~0.5-1.5 W, estimate).** Instrument first (section 5).
7. **Simulator log storm (~1-2 W while open).** Not ours: the simulator's apsd logs ~700 lines/s and the Claude
   app's orientation `log stream` keeps two diagnosticd busy. Owner: close the simulator when not used.
8. **FSKit NTFS (`/Volumes/Windows`, UVFSService ~85 % + fskitd ~25 % at 19:20, 2:52 CPU min in 44 min).** Trigger
   unknown (Spotlight indexing is disabled on it). Root `fs_usage` below. Owner option: unmount it when not needed.
9. **Outside RAPL (RTX powered, platform).** 75 W battery vs 31 W package under today's load. Install the built
   StrixDgpuGate 3FB90B94 (handoff 5.1) and measure battery discharge at a STEADY idle with RTX on vs off.

Rejected: our kexts' logging (~0.2 lines/s); diagnosticd as "our kexts" (it is the simulator); log rate limits are
therefore not needed and no log patch was made.

## 7. Root commands for main (run via `launchctl submit` / osascript; output to /var/tmp)

1. Steady probe with IPIs/interrupts (after the owner sets up a true idle, section 1):
   `sudo /Users/thanhnndev/develop/projects/ga403wm-hackintosh/.claude/worktrees/upbeat-colden-d050ad/tools/health-probe.sh floor 120 /var/tmp/health-floor`
2. Who is kernel_task (Wi-Fi loop, kick, I2C, VBL), 10 s at 1 ms, during the same steady idle and again with Claude
   streaming:
   `sudo spindump -noProcessingWhileSampling 0 10 1 -o /var/tmp/kt-idle.spindump` then
   `grep -A40 'Process:.*kernel_task' /var/tmp/kt-idle.spindump`
3. Per-process wakeups and interrupt rates:
   `sudo powermetrics --samplers interrupts,tasks -i 5000 -n 6 -o /var/tmp/pm-idle.txt` (the tasks sampler lists interrupt and package-idle wakeups per process)
4. FSKit trigger (while UVFSService is busy):
   `sudo fs_usage -w -f filesys -t 10 > /var/tmp/fsusage-uvfs.txt; grep -c Windows /var/tmp/fsusage-uvfs.txt`
5. The C-state A/B, only after (1) says STEADY, EPP held fixed:
   `sudo tools/idle-ab.sh /var/tmp/idle-ab-$(date +%m%d-%H%M)`

## 8. After the next reboot (if main installs anything from here)

- With the VBL patch: WindowServer up on the OLED, cursor smooth, Chrome 1080p60 video smooth (CVDisplayLink),
  no `IOPRESENTMENT` failures; health-probe STEADY run vs the previous boot: IPIs/interrupts lower, package power
  same or lower. If anything stutters: boot-arg `nmxvblgate=0`.
- In any case: one STEADY floor run (section 1) at uptime ≥ 30 min, then root commands 2 and 3, then idle-ab.
- Battery: one ≥ 120 s STEADY run on battery with RTX powered and one with the gate's RTX off.

## 9. Open questions

- Was EPP 128/191 or 0 during the 11-08 5.5 W run? (Not recorded; the probe now records it.)
- Does IOFramebuffer actually mask VBL on this path (if never, the VBL patch changes nothing and PSR needs the DRM
  side)?
- Is the Wi-Fi `IODelay(200)` a spin or a timed wait on this kernel (xnu `delay_spin_threshold`)? The spindump in
  section 7 shows which.
- Why does EPP flip between 255 and 0 within a minute on battery with profile 3?
