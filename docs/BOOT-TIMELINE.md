# Boot timeline, power button to usable desktop (2026-11-19)

Machine: GA403WM, macOS 26.7.2 (25G332), OpenCore, 890M on NMXGPU, RTX 5060 behind StrixDgpuGate.
Sources: unified log of six boots (`/usr/bin/log show`), live registry, `machdep.tsc.nanotime.tsc_base`, OpenCore logs on
the ESP root (October, debug builds), the ESP `config.plist`, decoded shutdown-stall reports, and disassembly of
`AppleGPUWrangler.kext` (carved from the SystemKC) and `GPUWrangler.framework` (pulled out of the dyld cache).
REA has no decompiler provider configured on this machine (no Ghidra, Hopper or IDA), so the reverse engineering used
`llvm-objdump` on the carved binaries. The extractors are in `tools/re/`.

## 1. The whole boot in one table

Times are seconds after the kernel's `=== system boot` record (T0), unless marked. "Eco" means the gate held the RTX and
powered it off; "RTX on" means NVRM drove it.

| Stage | 11-19 11:54 (Eco, slow) | 11-18 20:01 (Eco, slow) | 11-18 10:41 (Eco, slow) | 11-18 15:54 (RTX on, fast) | 11-16 18:39 (RTX on, fast) |
|---|---|---|---|---|---|
| CPU reset -> kernel (firmware + OpenCore + boot.efi) | **8.0 s** (tsc_base) | n/a | n/a | n/a | n/a |
| T0 -> BSD root (`disk1s4`) | 0.50 | 0.48 | 0.50 | 0.48 | - |
| APFS boot trim on disk1 (spaceman scan) | **4.36 s** (171 835 extents) | 3.84 s | 3.56 s | 3.70 s | - |
| T0 -> launchd `hello` | 5.19 | 4.55 | 4.38 | 4.50 | - |
| launchd -> WindowServer "Server is starting up" | 2.65 | 3.86 | 4.78 | 8.11 | - |
| T0 -> WindowServer start | 7.84 | 8.42 | 9.16 | 12.61 | 8.26 |
| AuxKC activation (kernelmanagerd) | 8.66 | - | - | - | - |
| NMXGPU first log -> NMXAMDFB published (890M framebuffer) | 10.10 -> 11.49 | -> 12.94 | -> 12.47 | -> 15.86 | - |
| WindowServer start -> "Creating FB 1 of 1" | **63.4 s** (timeout) | **65.3 s** (timeout) | **63.5 s** (timeout) | 7.6 s (waits for the RTX to publish) | 7.9 s |
| T0 -> login window shown (`LoginwindowUIShown`) | 77.0 | 79.1 | 77.5 | 25.4 | 21.6 |
| password typed (user) | 12.6 s | 14.4 s | 170.7 s | 16.6 s | 23.3 s |
| login -> Finder/Dock launched | 0.86 | - | - | - | 0.96 |
| Finder/Dock -> `ContinueAfterDesktopReady` | 5.0 s (timeout) | - | - | - | 5.0 s (timeout) |
| -> `ContinueAfterTALCheckin` (apps reopened) | **43.5 s** | - | - | - | 3.6 s |
| -> `LoginComplete` | 0.18 | - | - | - | 0.13 |

The 11-18 08:54 boot also took 61.3 s from WindowServer start to the framebuffer (08:54:43.661 -> 08:55:44.918). The kernel
log of that boot is gone, so it cannot be confirmed as Eco, but nothing else in this report explains a 61 s gap there.

Expected after the fixes in section 3 (Eco boot): the framebuffer comes as soon as NMXAMDFB is published, about 11.8 s after
T0 instead of 71 s. The login window shows at about 17.5 s instead of 77 s; with the trim and picker changes, about 6 s
earlier again. That is roughly **60-66 s saved** before the password prompt.

## 2. Ranked avoidable waits

| # | Wait | Cost | Cause | Confidence | Fix | Risk |
|---|---|---|---|---|---|---|
| 1 | `GPUWranglerWaitForPublish: timed out; status=0xe00002d6` | 60 s, every Eco boot | The held, powered-off RTX is still a display-class `IOPCIDevice`, so AppleGPUWrangler keeps a GPU record for it that is never published (2.1) | High (disassembly plus live `debug-gpus`, 4/4 slow boots Eco, 2/2 fast boots RTX on) | StrixDgpuGate 0.2.1 takes the powered-off card off the bus (2.2) | Medium: new teardown path, see 4 |
| 2 | TAL (reopen windows) relaunch | 43.5 s on 11-19 (2.6-3.6 s on the other boots) | loginwindow waits for every restored app to check in: Xcode, Simulator, Chrome, Edge, Claude, Safari, Notes, Activity Monitor (9 apps) | High (loginwindow TAL log) | Owner's choice: untick "Reopen windows when logging back in" at shutdown, or quit Xcode and Simulator first. Note: macOS itself relaunched **Microsoft Edge** here (TAL), nothing of ours did | None |
| 3 | APFS boot-time trim | 3.5-4.4 s, critical path | apfs.kext trims all free space of disk1 at mount (about 150-170 k extents at 23 us each); launchd's `hello` comes 0.16-0.25 s after the trim ends on all four boots | High | OpenCore `Kernel/Quirks/SetApfsTrimTimeout` = `0`. On macOS 12+ only 0 has an effect; it disables the boot-time trim only. The OpenCore docs say normal running is not affected | Low-medium: the SSD gets no boot-time deallocation; undo = `-1` |
| 4 | OpenCore picker | 2.0 s per boot | `ShowPicker` true, `Timeout` 2 | High | `Misc/Boot/ShowPicker` = false. The picker is still reachable by holding Option/Esc at power-on (`PollAppleHotKeys` true). Check that the hotkey works on the built-in keyboard before relying on it; otherwise `Timeout` = 1 | Low |
| 5 | loginwindow desktop-ready timeout | 5.0 s, every boot | loginwindow waits for the desktop-ready registration; Dock is ready 1.7 s after login, but Finder registers its desktop only 9.3 s after login (11:55:42.76) | Medium | Gone with #2 (Finder competes with the TAL relaunch). Part of Finder's delay is our Metal stack: 0.9 s between "GPU wait budget" and "driver opened directly: libvulkan_radeon.dylib" in Finder | Follow-up, not done |
| 6 | 890M framebuffer publication | about 3.7 s after WindowServer start | The AuxKC is activated only after launchd starts kernelmanagerd (T0+8.7 s); NMXGPU then needs 1.4 s ("boot hold released: NMXAMDFB published after 1393 ms") | High | None proposed. Moving NMXGPU into the boot KC is a large change for about 4 s | - |
| 7 | launchd -> WindowServer | 2.6-8.1 s | Varies; the slowest boots (15:54 8.1 s, 10:41 4.8 s) were the first boots after an AuxKC rebuild (AuxKC "marked as loadable" at 14:18 and 09:53 the same day) | Low (hypothesis) | None now | - |

Firmware alone (CPU reset to OpenCore start) cannot be split out of the 8.0 s without an OpenCore log of a current boot.
The October debug logs give OpenCore start -> menu 1.66 s (driver connect, entry scan), menu 2-4 s (Timeout/user), menu ->
ExitBootServices 1.3 s (kernel and kext injection). File logging slows those runs, so they are upper bounds. The rest of
the 8.0 s (about 3 s) is firmware POST. `ScanPolicy` 0 and `ConnectDrivers` true cost little (45 ms for "Connecting
drivers" in the October log). Enabled kexts are 37; the 43 MB on disk is mostly `NVRM.kext` (16 MB, not enabled in
OpenCore: it is in the AuxKC) and `StrixAmp.kext`'s Resources (12 MB, never read by OpenCore). So kext count and size are
not a measurable cost.

To get an OpenCore log for one boot (main, ESP write): set `Misc/Debug/Target` = `65` (0x41: logging on, write to file),
boot once, read `/Volumes/ESP/opencore-<date>.txt`, then set `Target` back to `0`. File logging slows that boot, so read
the deltas (second column), not the total.

### 2.1 What `GPUWranglerWaitForPublish` waits for (Apple's contract)

All addresses are in the carved `AppleGPUWrangler` (SystemKC fileset entry `com.apple.AppleGPUWrangler`, 3.15.24,
vmaddr 0x13d34000) or in `GPUWrangler.framework` (dyld cache, `__TEXT` 0x7ff8159a1000).

- `GPUWranglerWaitForPublish(wrangler, timeout)` (framework 0x7ff8159a41d4) turns the timeout into a mach-time deadline
  and calls `IOConnectCallMethod(connect, 0xa0000004, [deadline])` on `AppleGPUWranglerClient`. The wait is in the kernel.
- The kernel wait loop (0x13d359ea) walks every GPU record. A record is done when
  `flags & 0xC100000D` (published, terminated, unsupported, or one of the eject bits) or `(flags & 0x08000002) == 2`
  (an external GPU whose drivers never started). Otherwise it sleeps on the wrangler lock with the deadline and returns
  `0xe00002d6` (kIOReturnTimeout) at the deadline.
- Flag bits, decoded from the framework's flag printer (0x7ff8159a3c14..3dc6): eject 0x1, XG 0x2, ejectFinalizing 0x4,
  ejectFinalized 0x8, IG 0x10, DG 0x20, NG 0x40, unsupported 0x01000000, **pubArmed 0x02000000**, hasGPUC 0x04000000,
  driversStarted 0x08000000, **pubSched 0x10000000**, **quiet 0x20000000**, terminated 0x40000000, published 0x80000000.
- Records are created by the `IOPCIDevice` match handler (0x13d38e46) for every device whose `class-code` property has
  base class 03 (display). The RTX gets one whether or not anything drives it.
- **pubArmed** is set by 0x13d37758, which the match handlers call when an AGDC (`AppleGraphicsDeviceControl`) or an
  accelerator registers under the GPU (callers 0x13d3902d, 0x13d39121, 0x13d3970e). Right after arming it calls
  0x13d354b0 with the PCI device's busy state.
- **quiet** (0x13d354b0) means the GPU's PCI subtree is not busy. When a GPU is quiet and armed but not yet scheduled, the
  wrangler sets **pubSched** and queues a post-start work item. displaypolicyd then receives `GpuAdded` and publishes the
  GPU through the user client (0x13d35fc0, op 1 sets 0x80000000).
- **terminated**: when the record's PCI component is terminated, 0x13d34a70 sets 0x40000000, posts `GpuRemoved` (event 2)
  and wakes the waiters (0x13d34c48 -> 0x13d35b0a -> thread_wakeup). That is the eGPU unplug path, and the only exit open to
  a driver: `unsupported` is set only by a privileged client call (0x13d368ac).

Live registry on the 11-19 Eco boot (`ioreg -l -r -c AppleGPUWrangler`, `debug-gpus`):
`{"id"=64206 (0xface),"acc"=0,"fbs"=(),"pci"=0x100000294 (PEGP),"flags"=0x20000020 (DG|quiet)}` and
`{"id"=54616 (0xd558),"acc"=...,"fbs"=(NMXAMDFB),"flags"=0xb2000020 (published|quiet|pubSched|pubArmed)}`.
The RTX is quiet but never armed, because in Eco no AGDC or accelerator ever registers under it (StrixDgpuAccelHold holds
the IOAccelerator category without registering, NVRMFBClaim holds the IOFramebuffer category, and NVRMAGDC idles). So it
is never published, and WindowServer waits the full 60 s on every Eco boot.

On RTX-on boots NVAccel and NVRM's framebuffer register, the RTX is armed at registration (`flags 0x2000020 (DG,pubArmed)`
at 15:54:52.573), quiet once NVRM's display is up, and published at 15:54:57.819. The framebuffer is created 0.4 s later.
That is why RTX-on boots wait only about 7.6 s: they wait for NVRM's bring-up, not for a timeout. The `quiet` versus
`(DG)` difference between 11-19 and 11-18 20:01 is only whether the subtree was busy when displaypolicyd looked. It does
not matter, because pubArmed is missing in both.

### 2.2 The fix (patch on a branch, compile-checked, not installed)

`rog-control-macos`, branch **`fix/eco-offbus`** @ **83b35e0** (0.2.1, review fixes on top of ad5a90c 0.2.0, from
`feat/gpu-mode` @ 2cf905e), worktree `~/develop/projects/rog-control-macos-ecooffbus`. Built at
`~/develop/projects/rog-control-macos-ecooffbus/build/StrixDgpuGate.kext` (binary md5 f68953bf94ab0036c90f4659af77c434).
No errors; only the three old warnings. New imports beyond 0.1.x are `IOService::terminate`, the `IOPCIBridge` and
`IOUserClient` metaclasses, `IORegistryIterator::iterateOver`, `IOLock*` and `thread_call_cancel(_wait)/free`, all covered by
the kpi.iokit / kpi.mach / IOPCIFamily libraries already declared.

- **Power-off pass** (`powerOff()`, serialised by a lock): walks GPP9's IOService-plane `IOPCIDevice` children (the bridge
  attaches every nub before it registers any, so the audio function is seen even while it is still matching). Refuses if
  any RTX function has a foreign driver. With the card powered it relearns each function's address and PM capability,
  runs NVOP `_DSM` 0 and 0x1A, PMCSR -> D3hot (skipped when PMCSR reads 0xffff), then `_PS3`.
- **Off the bus** (`takeOffBus()`): when GPP9.GSTA is 0 **and** the display function reads vendor 0xffff, every RTX
  function still registered is terminated (`terminate(kIOServiceRequired)`). The wrangler marks the record terminated and
  wakes WindowServer, or never makes one when the gate gets there first. This is not one-shot: it runs on every pass,
  including the "already off" branch (one fresh vendor read there, only when nubs exist).
- **When a pass runs:** Claim start + 3 s; wake + 3 s (`kIOMessageSystemHasPoweredOn`); a second Claim start in the same
  boot + 3 s (a hot-plug re-scan after GPP9 returns to D0 re-created the nubs; GPP9 has `IOPCIHotPlug`, `_PR0 = {PG00}`);
  and the 90 s / 5 min re-check + 1 s when GSTA reads 1 again or RTX nubs are back.
- Terminating the nub stops `StrixDgpuClaim`, so everything that outlives it is file-level state with parameterless thread
  calls (loop-guard clears, power-off passes, heartbeat). `StrixDgpuGate::stop` (unload) removes the notifiers, cancels,
  waits for and frees the thread calls, and releases what it retained.
- Config space goes through the parent bridge (`IOPCIBridge::configRead16/configWrite16`) with the saved
  `IOPCIAddressSpace`, which stays valid after the nub is gone.
- New properties on the `StrixDgpuGate` IOResources service: `gate-off-bus` (no RTX nub left after the last pass),
  `gate-offbus-terminations`, `gate-offbus-passes`, `gsta-recheck`, `gate-keepbus`, `gate-ws-seen`.
- Way back without a reinstall: boot-arg `strixgate_keepbus=1` or NVRAM `strix-gpu-keepbus=1` (`sudo nvram
  strix-gpu-keepbus=1`; `sudo nvram -d strix-gpu-keepbus` to undo): card off, nubs kept, 60 s at login. Both names checked
  against the AuxKC, BootKC, SystemKC, ESP kexts and /Library/Extensions: no other match.
- Loop-guard evidence (review point 4): the guard still only covers the first 90 s of kernel life. Cheap extension done:
  `strix-gpu-eco-cleared` is now `<counter>:<awake s>:ws0|ws1`, where ws1 means a user client created by WindowServer existed
  at the clear (one registry walk at 90 s and 5 min), so the next boot can tell "kernel lived 90 s" from "the desktop came
  up". Not done: arming the guard across sleep (try=1 on WillSleep, cleared after wake) would also catch a hang at wake, but
  it changes when the guard trips, so it is the owner's call.

AsusWmi and RogControl (review point 7, checked in source): with the nubs gone, AsusWmi's `rtxForeignDriver()` finds no
RTX, so `ASUS_GPF_LIVE_OK` stays clear and `ASUS_GPU_SET_DGPU` (live WMI eject) answers NotPermitted. RogControl never calls
it. Its GPU-mode page reads `supported` (WMI DGPU DSTS), `gate` / `held` / `poweredOff` / `tripped` (gate properties) and
`boot` (`gate-effective`), and stores the next-boot mode with `ASUS_GPU_SET_MODE`, which is always allowed. So Eco still
shows correctly and Standard can still be requested for the next boot.

Open risks for main to weigh:

- Resume: IOPCIFamily no longer restores the RTX's config space (it has no nub). If the platform powers PG00 on at wake,
  the hot-plug re-scan re-creates the nubs, the second Claim holds them away from NVRM, and the wake/claim pass powers the
  card off and terminates them again. Watch list below.
- Termination runs about 3 s after Claim start. If the wrangler already made a record, the waiter is woken at once.
- System Information no longer lists the RTX in Eco.

## 3. What main must install or change, and how to verify each

1. **StrixDgpuGate 0.2.1** @ 83b35e0 (ESP `EFI/OC/Kexts/StrixDgpuGate.kext`, replaces 3FB90B94; owner's OK and one
   reboot). First Eco boot watch list:
   - `ioreg -r -c StrixDgpuGate -l | grep -E 'gate-off-bus|gate-offbus|gate-state|gsta|gate-ws-seen'` ->
     `gate-off-bus = Yes`, `gate-offbus-terminations` 2 (display + audio), state `eco: dsm0 ... gsta 1->0 ... vid 0xffff`.
   - `ioreg -r -n GPP9` -> no `PEGP` and no `HDAU` under it. Note GPP9's `IOPowerManagement` `CurrentPowerState`
     (whether IOPCIFamily idles the empty bridge).
   - `ioreg -l -r -c AppleGPUWrangler | grep debug-gpus` -> only the 890M, or the RTX with 0x40000000 (terminated).
   - `/usr/bin/log show --last boot --predicate 'eventMessage CONTAINS "GPUWranglerWaitForPublish" OR eventMessage CONTAINS "Server is starting up" OR eventMessage CONTAINS "Creating FB"'`
     -> no timeout line; "Server is starting up" -> "Creating FB" about 4 s (was 63-65 s).
   - After 5 min: `gsta-recheck = 0`, `gate-ws-seen = Yes`, `nvram strix-gpu-eco-cleared` ends in `:ws1`.
   - After 5 min, unplug and plug the charger once: `hb-events` grows and every `hb-ring` entry keeps `g0` (GSTA stays 0).
   First sleep/wake (owner starts it; no sleep test from a side session):
   - Right after wake: does `ioreg -r -n GPP9` show PEGP/HDAU again? Does `gate-claim-starts` go to 2?
   - 30 s after wake: `gsta-recheck` / `gsta-after` 0, `gate-off-bus = Yes`, `gate-offbus-passes` +1 (or +2 with a re-claim).
   - Log out and back in: WindowServer start -> "Creating FB" stays about 4 s (no new wrangler wait).
   - Undo: `sudo nvram strix-gpu-keepbus=1` or boot-arg `strixgate_keepbus=1` (no reinstall), or put 3FB90B94 back.
2. **`Kernel/Quirks/SetApfsTrimTimeout` = 0** (ESP config.plist). Verify: no `spaceman_scan_free_blocks: ... trims took`
   line, and launchd `hello` at about T0+1.0 s instead of T0+4.5-5.2 s. Undo: `-1`.
3. **`Misc/Boot/ShowPicker` = false** (or `Timeout` = 1). First check that holding Option/Esc at power-on still brings up
   the picker. Verify: `machdep.tsc.nanotime.tsc_base` / `machdep.tsc.frequency` drops from 8.0 s to about 6 s.
4. Owner, no install: turn off "Reopen windows when logging back in", or quit Xcode and Simulator before shutting down
   (43.5 s on 11-19).

Batch 1-3 into one reboot. Expected Eco boot to the login window: about 13-14 s after T0 (was 77 s), and the pre-kernel
part about 2 s shorter.

## 4. Shutdown stalls (item 3)

Decoded with `spindump -i`: `shutdown_stall_2026-11-16-204205`, `2026-11-18-174716` and `2026-11-18-213534`. Each is a
1 s stackshot taken 2 s into the final process teardown, listing who was still alive:

- In all three: **`com.docker.hyperkit`** (Docker Desktop's VM, 8 vCPU threads still in `xh_vm_run` / `hv_vmx_vcpu_run`)
  and `docker-agent`. Also user apps: `chrome_crashpad_handler`, `msedge_crashpad_handler`, `claude` and its `disclaimer`
  helpers, a Gradle daemon (`java`), Simulator services and `findmydeviced`.
- No kext of ours is in any stack. The kernel frames are XNU or Hypervisor (unsymbolicated `kernel + ...`), not RyzenHV,
  StrixDgpuGate or NMXGPU.
- How long it holds: 21:35 -> confirmation 21:35:14.4, `shutdownNoReturn` 21:35:22.3, log ends 21:35:27.2 (about 5 s of
  teardown). 20:41 -> `shutdownNoReturn` 20:41:53.5, last line 20:41:54.5. 17:46 -> logout 17:46:27, log ends 17:47:05.6:
  38 s, almost all of it apps quitting in the user session, before the teardown.
- Verdict: not ours. The stall reports mean only that user processes, mostly Docker's VM, outlived SIGTERM for 2 s or more.
  Quitting Docker Desktop before shutdown removes the biggest one. There is no system-side fix to make.

## 5. Notes

- `itlmt7925WifiInterface` "republished" at T0+7.7 s is configd naming the interface (en1) after launchd started. It is
  not a kernel wait.
- `GPUWrangler` user-space and kext disassembly, the carved binaries and full logs used here are in this session's
  scratchpad and are lost on reboot. Recreate them with `tools/re/dyld-cache-extract-one.py <cache> <image path> <out>` and
  `tools/re/kc-extract-fileset-entry.py <kc> <bundle id> <out>`. Apple's `dsc_extractor.bundle` refuses this machine's
  modified shared cache ("code signature for page 67738 is incorrect"), so the first script reads the cache directly.
