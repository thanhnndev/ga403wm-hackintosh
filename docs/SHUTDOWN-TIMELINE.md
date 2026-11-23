# Shut down and boot-time faults (2026-11-23)

The owner's daily cycle: boot, work, shut down. This file covers two things: where the time goes from "Shut Down" to
power off, and the `bluetoothd` fault reported at every boot.

**Sources**
- The unified log (`/usr/bin/log show`, loginwindow / launchd / sessionlogoutd / kernel).
- All 10 `*.shutdownStall` reports in `/Library/Logs/DiagnosticReports`, decoded with `spindump -i`.
- All 10 `ExcUserFault_bluetoothd` reports.
- The `MtkBtFw` registry log.
- The `machdep.tsc` sysctls.
- The `/usr/sbin/bluetoothd` and kernel binaries (llvm-objdump).

Everything was read only. Nothing was installed and nothing was written to the ESP or NVRAM.

## 0. Findings, ranked by seconds saved

| # | What | Cost | Whose | Status |
|---|---|---|---|---|
| 1 | 11-23 13:11 restart: **3 min 50 s** with no log between the kernel's WillRestart (gate stamp 13:11:21) and the next CPU reset (13:15:12) | 230 s, once in two logged restarts | unknown: kernel driver shutdown, platform reset or firmware | trace added: StrixDgpuGate 0.2.9 `strix-gpu-sd` (section 1.3) |
| 2 | Bluetooth comes up about 15 s late on 9 of 10 boots: `bluetoothd` races MtkBtFw's firmware download, falls back to a UART that does not exist, waits 15 s, faults, restarts | BT ready at about T0+23 s instead of about T0+8 s; one ReportCrash run per boot | **ours** (MtkBtFw holds the USB interface for 5.2 s) | root cause proven (section 2); fix plan below, needs a bluetoothd-side decision |
| 3 | Apps quitting: 4.7-18.6 s per shutdown, last app is usually **Claude.app** (9.9 s on 11-23, 18.4 s on 11-22 10:08), then Notes and Edge | 5-18 s per shutdown | third-party | owner: quit Claude.app (Cmd-Q) before Shut Down, or accept |
| 4 | Userspace teardown after `shutdown -h/-r now`: 4-11 s. Survivors at +2 s: crashpad handlers (Claude, Chrome, Edge), Claude Code CLI + `disclaimer`, Simulator services, Docker's hyperkit | 4-11 s | third-party (Docker VM is the largest when it runs) | owner: quit Docker Desktop and Simulator before Shut Down |
| 5 | 11-19 14:42: `VTDecoderXPCService` hung in `amdgpu_vm_fini` -> `dma_fence_wait` (2 h 14 min) | one occurrence, not seen since | **ours** (NMXGPU) | BOOT-TIMELINE section 4; owner = NMXGPU / video side |
| 6 | 11-18 17:46: WebKit.GPU and VTDecoderXPCService in `ttm_pool_shrink` contending for the pool lock at exit | seconds, once | **ours** (NMXGPU) | BOOT-TIMELINE section 4 |

Not ours in any stall report: RyzenHV, StrixDgpuGate, AsusWmi, rogaudiod and RogControl appear in no process stack.
NMXGPU, RyzenHV, SimpleHDA and itlmt7925 appear only as `kernel_task` worker threads, which is normal. The gate's shutdown
NVRAM clear (0.2.4+) completed on 11-23 (`8:2902:ws1` persisted). Whether it plays a part in finding 1 is exactly what the
0.2.9 trace answers.

## 1. Shut down, step by step

### 1.1 Measured (loginwindow KeyMilestone, sessionlogoutd, launchd)

| Shut down | dialog -> confirmed | GUI apps quit | last app (s after start) | -> `shutdown` called | after that |
|---|---|---|---|---|---|
| 11-16 20:41 (restart) | 1.3 s | 4.7 s | - | 0.7 s | stall report; log to 20:41:54.5 |
| 11-18 21:35 | 1.8 s | 5.9 s | Docker 6.4 s, Claude.app 5.8 s | 0.7 s | log to 21:35:27.2 (4.4 s) |
| 11-19 14:42 | 1.4 s | 10.9 s | Edge 10.9 s, Notes 8.3 s, Safari 5.3 s | 0.7 s | **hung 2 h 14 min** (finding 5) |
| 11-22 10:08 | 1.6 s | **18.6 s** | **Claude.app 18.4 s** | 0.3 s | stall report |
| 11-22 16:15 | 1.4 s | 8.4 s | Edge 8.4 s, Notes 7.5 s, Claude.app 4.8 s | 0.8 s | stall report |
| 11-23 13:11 (restart) | 1.5 s | 10.0 s | **Claude.app 9.9 s**, Edge 3.0 s, Notes 2.4 s | 0.5 s | WillRestart at +11 s, then **3 min 50 s** to CPU reset |

The phases:
- **Dialog to confirmed** is the owner clicking.
- **GUI apps quit**: loginwindow `StartGUIAppsQuit` -> `AllGUIAppsQuit` waits for every app to exit. Claude.app (Electron)
  is the slowest app on 3 of the 5 shutdowns where the exits were logged.
- **UI elements, Finder, Dock, point of no return, sessionlogoutd**: 0.3-0.8 s.
- **`shutdown -h/-r now`, then launchd's system teardown**: logd is killed early in it, so the log ends about 1 s in.

### 1.2 What the 10 stall reports show

macOS writes a `shutdownStall` report when processes are still alive 2 s into the final teardown. It is a 1 s stackshot:
who was still there, not how long they took. In all 10 reports, launchd is blocked only on `wait4` of `spindump` (the
report itself). The exception is 11-19 14:42, where it was also blocked on the hung `VTDecoderXPCService` (finding 5).

Survivors by report:
- **Every report**: `chrome_crashpad_handler` (from Claude.app and Chrome) and `msedge_crashpad_handler`.
- **When running**: Claude Code (`claude` + `disclaimer`), the CoreSimulator services (`SimAudioProcessorService`,
  `SimStreamProcessorService`, `SimRenderServer`, `launchd_sim`), `com.docker.hyperkit` + `docker-agent` (5.3 GB footprint
  on 11-16), and a Gradle daemon.
- **Apple daemons** that are normally last: `securityd`, `duetexpertd`, `logd`, `diskarbitrationd`, `photolibraryd`.

In 11-23 13:11 the `claude` CLI turned zombie inside the sample (it was exiting, not stuck).

| Report | Uptime | Ours in a process stack | Notes |
|---|---|---|---|
| 11-16 20:42 | 7375 s | - | Docker hyperkit, Simulator |
| 11-18 17:47 | 6748 s | NMXGPU (WebKit.GPU, VTDecoderXPCService exiting in `ttm_pool_shrink`) | finding 6 |
| 11-18 21:35 | 5616 s | - | Docker hyperkit, ReportCrash busy |
| 11-19 14:42 | 10116 s | **NMXGPU** (`amdgpu_vm_fini` fence wait) | finding 5 |
| 11-19 17:16 | 5087 s | - | Simulator |
| 11-19 18:07 | 3005 s | - | - |
| 11-20 11:07 | 37 s | - | shutdown at T+35 s |
| 11-22 10:08 | 3340 s | - | - |
| 11-22 16:15 | 7213 s | - | `launchd_sim` on CPU |
| 11-23 13:11 | 2893 s | - | Claude Code exiting |

### 1.3 The 13:11 restart gap (finding 1)

- **13:10:58.1**: `kAEShowRestartDialog` (from Claude.app, pid 567). Confirmed at 13:10:59.6.
- **13:11:09.6**: all apps quit. `shutdown -r now` at 13:11:10.1. The log ends at 13:11:11.
- **13:11:21**: StrixDgpuGate 0.2.6 got WillRestart at awake uptime 2902 s. Boot at 12:22:59.6 + 2902 s gives this time,
  and the next boot read `strix-gpu-eco-cleared` = `8:2902:ws1`. So the userspace teardown took about 11 s.
- **13:15:12**: CPU reset. `kern.boottime` is 13:15:23.0, minus `machdep.tsc.nanotime.tsc_base` / `machdep.tsc.frequency`
  = 15 755 551 320 / 1 996 247 234 = 7.89 s before the kernel.

That leaves **3 min 51 s** between the kernel's restart message and the next CPU reset. No log covers it.

| Restart | WillRestart | Next CPU reset | Gap |
|---|---|---|---|
| 11-19 17:16 (from an Eco boot, gate 0.2.1) | - | - | about 7 s from the stall report to the next kernel |
| 11-23 13:11 (first gate 0.2.6 shutdown) | 13:11:21 | 13:15:12 | 3 min 51 s |

On 11-19 17:16 the gate had no shutdown hook, so it was not stamped. On 11-23 13:11 the gate wrote two forced NVRAM syncs
at WillRestart, and both persisted.

Candidates, in order:
1. A driver's shutdown path (systemWillShutdown / PM teardown of NMXGPU, RyzenHV, the audio stack, itlmt7925).
2. The ACPI reset not taking (`_PTS` / SSDT-PTS5, the open "reset bit 23" note), so the owner powered it on again.
3. Firmware POST on a warm reset with the RTX in D3cold (unlikely: the 11-19 17:16 Eco restart was fast).

**StrixDgpuGate 0.2.9** (`fix/eco-offbus` b0a00cb, md5 e8b0303a0dfc174aac23d2d7331273b1, not installed) splits the gap:
- **Record**: NVRAM `strix-gpu-sd` = `<boot>|A<wall s>.<ms>:<awake s>|B<wall s>.<ms>:<awake s>`.
- **Stamp A** is written at the priority WillPowerOff / WillRestart message, in every mode, not only Eco.
- **Stamp B** is written at `systemWillShutdown`. The status service joins the PM tree with one power state for this.
- **Next boot**: `gate-prev-shutdown` publishes the record. Compare it with the CPU reset time from `kern.boottime` and
  `tsc_base`:
  - before A = userspace;
  - A -> B = priority clients and driver shutdown up to the gate's turn;
  - after B = the rest of the driver tree, the platform halt and firmware.

If B is missing, the NVRAM sync at that point did not reach flash. That is itself the answer for the stall's position.

**0.2.10** (`fix/eco-offbus` 1f4db9d, md5 993f27c43e563278065532bbf05eede0, not installed) carries the same trace and adds
main's 0.2.8 review fixes: from WillPowerOff / WillRestart no power-off, slow or re-check pass runs (queued ones cancelled,
a running one waited out, then stamp A), a 200 s heal timer at WillSleep, no action on an unreadable GSTA. Cost at shutdown:
two forced NVRAM syncs of an 80-byte variable (A, B), in addition to the two `clearNow` already does at A. Install it, not
0.2.9, for the instrumentation boot.

### 1.4 What the owner can change (third-party, one line each)

- **Claude.app**: quit it (Cmd-Q) before Shut Down. It took 4.8-18.4 s to exit on 3 of 5 shutdowns.
- **Docker Desktop**: quit it first. Its hyperkit VM (5.3 GB) outlived SIGTERM in 3 reports.
- **Simulator**: quit Simulator / Xcode first. Its services were alive in 6 reports.
- **Notes**: 2.4-8.3 s to quit on every shutdown, which is likely iCloud sync. Nothing to change unless it grows.
- **Crashpad handlers** (Chrome, Edge, Electron): always survive SIGTERM briefly. Harmless (under 1 s).

## 2. bluetoothd ExcUserFault at every boot (finding 2)

### 2.1 What the report is

All 10 reports (11-18 to 11-23) are the same:
- **Exception**: `"is_simulated":1`, `EXC_GUARD` / `GUARD_TYPE_USER`, namespace 18 (LIBSYSTEM), "Application Triggered
  Fault".
- **Stack**: `os_fault_with_payload` from a dispatch queue in `bluetoothd`.
- **Timing**: taken 15-20 s after bluetoothd launched.

It is bluetoothd's own CBCrash: it logs `UART open(/dev/cu.BLTH) port failed to appear after 15 seconds`, then
`Transport layer initialization failed`. The kernel takes a corpse, launchd relaunches bluetoothd, and the new instance
opens the USB controller and works (`STACK_READY/StackStarted` within 0.3 s). **Bluetooth works after it**; it is late, not
broken.

### 2.2 Root cause: a race with MtkBtFw's firmware download

The 11-23 13:15 boot, from the log:

| Time | Event |
|---|---|
| 13:15:22.76 | bluetoothd [167] launched |
| 13:15:25.66 | USB interface `BT_ACL_If` published, MtkBtFw matched, opens it exclusively, starts the firmware download |
| 13:15:27.08 | bluetoothd `FindTransportType -- UART Transport` (board-id of MacBookPro16,2), `HCI Transport is set to H4BC` |
| 13:15:27.23 | `[bm3_usb][Found_USB_Dongle]` finds 0489:E11E; kernel: `AppleUSBHostUserClient::openGated: failed to open BT_ACL_If@0: provider is already opened for exclusive access by MtkBtFw`; `FoundBluetoothInterfaces() ... returned false` -> UART |
| ~13:15:30.8 | MtkBtFw done: `ready in 5159 ms` (sections 0-2, 448 KB in 1792 blocks, HCI Reset status 0) |
| 13:15:42.60 | `UART open(/dev/cu.BLTH) port failed to appear after 15 seconds` -> CBCrash, corpse, ReportCrash |
| 13:15:42.76 | bluetoothd [517] spawned; 42.90 `HCI Transport is set to USB`; 43.04 STACK_READY, then started |

Every boot since 11-18 in the log:

| Boot | Interface published -> bluetoothd's USB open | MtkBtFw holds it | Result |
|---|---|---|---|
| 11-18 20:01 | 2.5 s | yes | UART, 15 s, restart |
| 11-19 11:54 | 1.5 s | yes | UART, 15 s, restart |
| 11-19 15:52 | 1.5 s | yes | UART, 15 s, restart |
| 11-19 17:17 | 1.6 s | yes | UART, 15 s, restart |
| 11-20 11:07 | 1.5 s | yes | UART, 15 s, restart |
| 11-22 09:12 | **5.7 s** | no (download done) | USB at once, no fault |
| 11-22 14:15 | 2.6 s | yes | UART, 15 s, restart |
| 11-23 12:23 | 1.7 s | yes | UART, 15 s, restart |
| 11-23 13:15 | 1.6 s | yes | UART, 15 s, restart |

The download takes 5.2 s on a cold boot. bluetoothd reaches its USB scan 1.5-2.6 s after the interface appears, so it loses
on 9 of 10 boots and Bluetooth is ready about 15 s later than it could be.

**Not a regression.** The race has existed since MtkBtFw 0.1.0, and the 10-11 doc already measured "ready after 5.2 s".
The 11-08 warm-reboot loop was a different failure: a dead firmware made bluetoothd write `bluetoothExternalDongleFailed`
= 01 and loop for the whole boot. Here NVRAM stays 00, and the second instance always works.

### 2.3 How bluetoothd picks the transport (25G332 binary)

- **Transport**: `BT_HCI_TRANSPORT` is read with `getenv` (0x1001d16f7 -> `_getenv`). If it is unset, the transport comes
  from `board-id` in `IODeviceTree:/`; Mac-5F9802EFE386AA28 gives UART (H4BC).
- **USB tried first**: if a USB dongle opens (`Found_USB_Dongle` / `FoundBluetoothInterfaces`), bluetoothd uses it and
  sets `gUseInternalController` FALSE. Otherwise it stays on H4BC and waits 15 s for `/dev/cu.BLTH`.
- **Dongle preference**: NVRAM `bluetoothHostControllerSwitchBehavior` (`always` / `never`) only sets that preference. It
  does not make bluetoothd wait.
- **USB-transport wait**: the USB transport has its own wait (`[bm3_usb] Waiting for bluetooth devices...` / `Timed out
  waiting for bluetooth devices`). Only a USB transport (by board-id or `BT_HCI_TRANSPORT`) reaches it.

### 2.4 Fix plan (ours, MtkBtFw + a bluetoothd-side choice; not written yet)

The download cannot finish in the 1.5 s bluetoothd leaves. Hiding the device alone does not help either: with no USB
dongle at that moment, bluetoothd goes straight to the 15 s UART wait. A fix needs both halves:
1. **MtkBtFw**: load the firmware before the interface is visible. Match the `IOUSBHostDevice` (0489:e11e) above the
   composite driver, `setConfiguration(1, false)` (interfaces created but not matched), open interface 0, download, close.
   Then `setConfiguration(1, true)` or register the interfaces so that bluetoothd (and BlueToolFixup) find a ready
   controller. bluetoothd then never sees a busy interface.
2. **bluetoothd waits for USB** instead of falling to UART. Two candidates:
   - **(a)** run bluetoothd with `BT_HCI_TRANSPORT` set to its USB value. It is an env var of a system daemon, so this
     needs a launchd override. Check first whether `launchctl setenv` in the system domain reaches bluetoothd at boot.
   - **(b)** a BtLeDlFix patch of `FindTransportType` for this board-id.

   Then the `bm3_usb` wait covers the 5 s download.

Step 1 alone already saves the 15 s on boots where bluetoothd starts late (like 11-22 09:12), but not on the usual ones.
Expected result with both: Bluetooth ready about 8 s after T0, no fault, no ReportCrash. The download time itself (5.2 s,
about 2.9 ms per 250-byte block with 0.5 ms polling) could also shrink with tighter WMT event polling. Linux reports a
few seconds for the same chip family; this was not measured here.

Owner of the code: `mt7925-macos` (`kexts/MtkBtFw`, `kexts/BtLeDlFix`). Needs a reboot to test (main installs).

## 3. Other answers from this pass

**Does `mach_absolute_time` stop in sleep?** For the gate's 180 s self-heal: `machdep.tsc.deep_idle_rebase` reads **1** on
this machine. So `acpi_idle_kernel` re-bases the clock after `pmCPUHalt` (kernel 0xffffff80003fc585), as found in
BOOT-TIMELINE 0.1. The measuring tool for the owner's sleep test is still `tools/sleep-clock`.
