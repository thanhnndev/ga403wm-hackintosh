# First load of the native Wi-Fi kext (`itlmt7925Native`)

Status: nothing in the native path has ever run. Stage 1 (controller) and stage 2 (interface + queues) are verified only up to
build, link check and vtable slots (HANDOFF-NATIVE-WIFI.md). Treat this as an experiment with a way back, not as an update.

## 0. Before you start

* Have a stick with a working copy of the current EFI (or `scripts/native-wifi-test.sh backup` output copied to it) and know how
  to boot from it (OpenCore picker, F8/Esc on the ASUS). A panic with `debug=0x100` in the boot-args halts instead of rebooting.
* Know that the box is offline for Wi-Fi if the experiment fails: keep the USB Ethernet / phone tether nearby.
* `nvram boot-args` shows what NVRAM overrides; if it is non-empty it wins over `config.plist` (the helper stores it in the backup).

## 1. Build

On the Mac, in the worktree: `bash scripts/build.sh itlmt7925 itlmt7925Native` (build/ contains both kexts), then
`KC=<path to the .kc> python3 tools/check_kext_links.py build/itlmt7925Native.kext build/itlmt7925.kext` must exit 0 with only
the 6 baseline-missing `IONetworkController` symbols. The native kext must be the build from the same commit as the core kext.

## 2. Backup (done automatically by install, can be run alone)

    scripts/esp-automount.sh          # mounts the ESP at /Volumes/ESP (password box)
    scripts/native-wifi-test.sh backup

Creates `~/itlmt-backup/EFI-<time>/` (+ `.tar.gz`, + `.nvram-boot-args.txt`). Copy the `.tar.gz` to the stick too.

## 3. Stage A: controller only (lowest risk)

    scripts/native-wifi-test.sh install build/itlmt7925Native.kext

This backs up again, copies the kext, adds it to `Kernel/Add` right after `itlmt7925.kext` and sets `itlmt_native=1` (stage A is
the default; `--stage b` and `--exclusive` are described in section 4). Reboot.

Expected: boots; the Ethernet-style Wi-Fi from the core kext is replaced by the native controller, no Wi-Fi in System Settings
yet (no interface). Collect: `scripts/native-wifi-test.sh logs`. Fail = panic or hang on boot, or the core kext lost its network.

## 4. Stage B: controller + interface

One path at a time: stage A ran next to the old Wi-Fi (the core joined and gave the Ethernet-style link). For stage B use the helper's
options instead of editing `config.plist` by hand:

    scripts/native-wifi-test.sh install build/itlmt7925Native.kext --stage b --exclusive

`--stage b` adds `itlmt_native_if=1` (default `--stage a` removes it); `--exclusive` removes `itlmt_m2`, `itlmt_m3` and `itlmt_fast`
from the boot-args, so the core loads (and with `itlmt_m1` brings the firmware up) but never scans/joins and creates no Ethernet
interface; the only network device left from this driver is the native one. No Wi-Fi at all then: use the phone tether. Going back =
`restore` (it puts the whole EFI, including the old boot-args, back). Without the core's `IOMACAddress` (no Ethernet front end) the
native interface uses a placeholder locally-administered MAC (`02:00:79:25:00:01`), which is expected in this mode.

Add `itlmt_native_if=1` back to `boot-args` (`itlmt_native_unit=N` is optional; default 9) and reboot. Look for:

* `kextstat | grep itlmt` shows both kexts;
* `ioreg -l | grep -i itlmt7925Wifi` shows the controller with a child interface (class `itlmt7925WifiInterface`);
* `ifconfig -a` has a new `en9`; System Settings > Network may list a Wi-Fi service (it will not connect: every handler answers
  unsupported, the radio is not driven yet).

A clean failure is also useful: the log line says which step of `makeInterface`/`startWithInfo` returned false.

## 5. Sleep / unload (only if B loaded)

Sleep and wake once; then reboot normally (do not unload by hand). Report whether either panics: teardown order is the least
verified part.

## 6. Go back

    scripts/native-wifi-test.sh restore            # newest backup; or: restore ~/itlmt-backup/EFI-<time>

Reboot. If the native boot-args stick: OpenCore picker > Reset NVRAM, or boot from the stick. By hand: remove
`itlmt7925Native.kext` from `EFI/OC/Kexts` and its `Kernel/Add` entry, and delete `itlmt_native=1 itlmt_native_if=1`.
A missing `boot-args` token alone makes the native kext inert (its `start` returns false), the core driver then works as before.

## 7. What to send back

`scripts/native-wifi-test.sh logs` output (kextstat, ioreg, `log show --last boot`, dmesg; remove SSIDs/MACs), the stage reached
(A/B/5), and for a panic the first 30 lines of the panic text (photo is fine). The ItlDiag `ITLLOG.BIN` on the ESP also has the
early log (`scripts/usblog.ps1 -Esp -Read` on Windows).

## Result log

* 2026-10-12, stage A, commit 5dca5d5: native kext did not load. Kernel: `library kext com.itlmt7925.kext not compatible with
  requested version 0.1.0` (0xdc00800e), because the core Info.plist had no `OSBundleCompatibleVersion`, so it was not a library
  kext. Native `start` was never reached; the Wi-Fi loss in that boot was **not** caused by the native code (cause not established;
  `itlmt_fast=6` and `nvrmacpibl=1` were also new in boot-args). Fix: core Info.plist now has `OSBundleCompatibleVersion`; `install`
  patches the ESP copy of the core Info.plist in place (credentials stay), no need to replace the core kext.
* Same boot, the Wi-Fi loss itself (core driver, native never loaded): scan works, then every join dies with
  `efuse hw type failed rc=-5` -> `hw-prep-fail` (`itlmt7925_pwr.cpp` efuseRead, the power-table code of a45e8c1 had never run on
  hardware). Fix: power tables are best effort (failure is logged and the join continues), and the rejected efuse event is logged
  (`efuse event rejected: len= tag= addr= want= valid=`) so the parser can be corrected from a real event. This needs a rebuilt
  **core** kext (replace it on the ESP, then re-inject the credentials with `scripts/inject-creds.ps1`).
* 2026-10-12, stage A, commit 9339299 (native kext now links): **kernel panic at 0.47 s uptime**, before the filesystem is up
  (decoded from `AAPL,PanicInfo0000..0007`, 7-bit unpacking, in the user's tarball). Page fault CR2=RSI=RDI=0x648 (RBX=0) in
  `IOLockLock+0x3`, called from `IONetworkController::start+0x1d4` <- `IO80211Controller::start+0x41` (the `call [rax+0x5d0]`
  to the IONetworkController start) <- `itlmt7925Wifi::start+0x8c` (our `super::start`). So the work queue, CoreCapture logger and
  fault reporter built before it did not fault; `IONetworkController::start` locks a lock inside an object it holds as NULL
  (`lock = NULL + 0x648`). Which pointer is NULL is **chưa xác định** (candidates: a field `IONetworkController::init` fills, the
  provider being the core driver and not a PCI device, a global of IONetworkingFamily not ready at 0.47 s). Rolled back by the
  user (native `Enabled=False`, `itlmt_native*` removed). **Cause found from the round-6 dump** (`abi/native-wifi/24H32/round6/`):
  the `IOLockLock` is inside `ml_thread_policy(thread, 1, 0x10000001)`, and `thread` is NULL. `IONetworkController::start`
  (+0x1a0..0x1d4) compares `this->getWorkLoop()` with `provider->getWorkLoop()`; when they differ it calls
  `ml_thread_policy(workLoop->getThread(), ...)`. Our `getWorkLoop()` was `IO80211Controller`'s, which returns something other than
  the provider's loop, and `IO80211WorkQueue::getThread` (0xffffff80022591fa, 8 bytes between two method addresses) is a stub that
  returns NULL, so the call faulted at `thread+0x648`. Round 7 (`abi/native-wifi/24H32/round7/`): `IO80211Controller::getWorkLoop` is a pure tail call to virtual
  `getWorkQueue` (slot 399; Family default returns NULL, BCM returns `ivars+0x7898`), and `IO80211WorkQueue::getThread` is
  `xor eax,eax`. So Apple's BCM also returns an `IO80211WorkQueue` from `getWorkLoop`; it avoids the policy call only if its provider
  (the bus layer, which supplies that queue by default, see `createWorkQueue`) returns the *same* queue from `getWorkLoop`, so the
  compare matches. That is an inference (the bus class was not dumped): **chưa xác định**. Our provider is the core `itlmt7925`
  (plain `IOService::getWorkLoop` = the PCI device's loop), so the equal-loops condition is met by returning the provider's loop. Fix (commit after 4435061): `itlmt7925Wifi::getWorkLoop()` returns the
  provider's work loop (fallback: an own `IOWorkLoop`), so the compare matches and `ml_thread_policy` is skipped. Slots 20/0 and
  compile check pass. **Not run on hardware.** Residual risk: code in the IO80211 family that casts `getWorkLoop()` to an
  `IO80211WorkQueue` (none seen in the dumps read so far) and any further fault later in `IONetworkController::start` (after the policy call it creates an
  `IOCommandGate` and `addEventSource`s it to the loop returned by `getWorkLoop()`, i.e. now the provider's loop, which must stay
  enabled/running for the life of the controller).
* 2026-10-12, stage A, commit b6693cb (`docs/native-wifi-results/20261012-stage-a-b6693cb/`): **PASS, no panic.** `com.itlmt7925.native`
  loaded, `itlmt7925Wifi` registered/matched/active, `kern.bootargs` had `itlmt_native=1` only. Confirms the `getWorkLoop()` fix
  (`ml_thread_policy` path skipped, command gate on the provider's loop did not fault). The `controller started` IOLog line was not seen
  (registry entry is the evidence). Not tested: stage B (interface), sleep/wake, unload. The core joined and got DHCP (`RESULT rc=0
  link up`) without power tables: `efuse event rejected: len=124 tag=0002 addr=00000a70 want=00000a70 valid=00000001`. The event is the
  expected shape (address and valid match) but its tag is **2**, the parser demanded 1. Fix: `efuseRead` accepts tag 1 or 2 and logs
  the first 8 bytes of the block (`efuse a71 tag= block=`). First run of the CLC and tx-power commands on hardware follows from this,
  still best effort (failure is logged, join continues). Whether tag 2 puts the 16-byte block at the same offset is **chưa xác định**
  until the logged block is checked against the known encapsulation byte. Needs a rebuilt core kext.
* 2026-10-12, phase 2, stage B exclusive, commit 7428c5e (`docs/native-wifi-results/20261012-phase2-7428c5e/`): booted without
  panic; both kexts loaded and controller registered/matched/active. Child `itlmt7925WifiInterface` exists but is not
  registered/matched; no en9 and no service named Wi-Fi in networksetup. Native start/failure IOLog messages were absent from
  collected logs, so the precise publication/failure step is unknown. Sleep/wake not tested. Phase 1 power-table test was
  skipped at the user's direction; exclusive mode disables core scan/join. Persistent per-step logging is needed before retry.

* 2026-10-12, analysis of the phase-2 result (cloud, from `abi/native-wifi/24H32/round3|4`, no new hardware data): the interface child has
  only `IO80211InterfaceRole` in the registry. `IOSkywalkNetworkInterface::registerNetworkInterface` (round4 `-a`/`-b`) sets
  `IOInterfaceNamePrefix` (via `getBSDNamePrefix`, slot 318) and `IOInterfaceUnit` on the interface before anything is published, and
  neither is present, so the registration either was not reached or failed before that point. `IOService::attach(core)` keeps the
  child in the registry even after `detachInterface(ifc, false)` and `release()` (retain 4 fits both a failed and a successful
  start), so the object's presence says nothing about the outcome. The earlier "unverified" item is the strongest suspect:
  `registerNetworkInterface` builds a queue set with `IOSkywalkQueueSet::isWMMSchedModelCapable` (type 0xb if capable, else 3)
  and `createWithQueues`, failing with `0xe00002c2`; our four Tx queues all have service class 0, Apple's have
  {0, 0x00100080, 0x00380100, 0x00400180}. Not proven: `isWMMSchedModelCapable`/`createWithQueues` are not in the dumps yet
  (round 8 tool: `tools/dump_native_wifi_round8.py`). Role 2 is `IO80211InterfaceRole = LowLatency` in the registry; whether that is
  the intended role for the primary Wi-Fi interface is **chưa xác định**.
* Next build (commit after 7428c5e) records every step of `makeInterface`/`startWithInfo` in the registry property
  `itlmt_native_trace` of the controller (IOLog output was not found in any collected log, stage A or B). Read it with
  `ioreg -l | grep itlmt_native_trace` or `scripts/native-wifi-test.sh logs` (`native-trace.txt`). Expected last entry on success:
  `sw:registerInfraEthernetInterface=0; mk:startWithInfo ok`.
* 2026-10-12, correction after round 8 (`abi/native-wifi/24H32/round8/`): (1) the phase-2 registry extracts are filtered (the JSON keeps a fixed
  key set, the text file a grep window), so the absence of `IOInterfaceNamePrefix`/`IOMACAddress` there is **not** evidence that
  registration failed. (2) `isWMMSchedModelCapable` counts Tx queues per service class against {0x100080, 0, 0x380100, 0x400180} and
  needs each exactly once, so our four class-0 queues make it false, but `registerNetworkInterface` then uses queue-set type 3 and
  `IOSkywalkQueueSet::initWithQueues` only rejects a false result when info bit 0x8 is set (type 0xb). Service classes are therefore
  not the established blocker; no code change was made for them. (3) `copyRegistrationInfo` publishes `IOMACAddress` and the
  registration sets `IOInterfaceNamePrefix`/`IOInterfaceUnit` on the interface: the next log collection reads the full interface node
  (`native-interface-full.txt`) instead of a filtered one. One reboot of the already installed a8c7ae2 build is the cheapest next datum.

* 2026-10-12, Stage B exclusive trace build cf1bd62 (`docs/native-wifi-results/20261012-stageb-trace-cf1bd62/`): boot completed, no new panic reported. Persistent trace: `mk:withController=ok; mk:attachInterface=1; sw:IO80211InfraInterface::start=0; mk:startWithInfo failed`. Base interface start returns false before getWorkQueue, pool/queue creation or registration. WMM/service class is not the failing step in this boot. Controller active, interface child unregistered/unmatched, no en9. Sleep/wake not tested.

* 2026-10-12, analysis of the stage-B trace (static, `abi/native-wifi/24H32/IO80211SkywalkInterface-start.asm.txt`, `round4/AppleBCMWLANCore-createSkywalkInterface.asm.txt`, `round4/AppleBCMWLANSkywalkInterface-start-full.asm.txt`): `IO80211InfraInterface::start` runs `IO80211SkywalkInterface::start` first, and for `ivars->role == 2` that function needs `ivars->parentInterface` (`ivars+0x68`); with a NULL parent it logs a failure from `IO80211SkywalkInterface.cpp` line 0x1f8 (label 0xffffff8002261e4b) and returns false. Our interface was created with role 2 and no parent, which matches the trace exactly. In `createSkywalkInterface` the role comes from the creation parameters (`[params+0x18]`): role 2 builds `AppleBCMWLANLowLatencyInterface` (only when a bus flag is set) and receives the parent as the 4th argument; every other role builds `AppleBCMWLANSkywalkInterface`. So role 2 / "LowLatency" is a secondary interface; the primary station interface is role 1 (the role 1 and `ivars+0x58 == 1` branches exist in `IO80211InfraInterface::start`/`IO80211SkywalkInterface::start`: `IO80211Glue`, ScanManager). Which exact value Apple passes for the primary interface in `[params+0x18]` is **chưa xác định** from a caller; role 1 is inferred from those branches and from `AppleBCMWLANSkywalkInterface::start` (`getInterfaceRole() == 1` then `deferBSDAttach(true)`, vtable column 0xa08).
* Role 1 differences from the role-2 path (all from the same disassembly): `[info+0x10] = 1`; no BSD prefix/unit in the RegistrationInfo (`[info+0x30]/[+0x38]/[+0x40]` are only filled in the role-2 branch, `+0x40 |= 4`); the interface is created by `AppleBCMWLANSkywalkInterface::withProvider(core, id, role, ...)`. Code change (this commit): `makeInterface` uses role 1 by default (`itlmt_native_role=2` keeps the old path for comparison), `startWithInfo` calls `deferBSDAttach(true)` for role 1 before the base start (traced as `sw:deferBSDAttach=`), the BSD name is left to the family unless `itlmt_native_unit=N` is given. Not hardware-tested. The remaining failure points of `IO80211SkywalkInterface::start` that apply to role 1 are `createPeerManager` (vtable col 0xb10, not overridden by Apple's subclass) returning NULL, `IO80211FlowQueueDatabase::initialize`, `IO80211Glue::withOptions`, `IO80211MacAddressAgent::withOptions`; the trace will show only `sw:IO80211InfraInterface::start=0` again if one of them fails, then the next step is a finer split.
* Test for this build: the same exclusive stage-B install as before; read `native-trace.txt`. Expected on success: `mk:start role=1 ...; sw:deferBSDAttach=0; sw:IO80211InfraInterface::start=1; sw:getWorkQueue=ok; sw:pool+queues=1; ...; sw:registerInfraEthernetInterface=0; mk:startWithInfo ok`.

* 2026-10-12, Stage B exclusive role-1 build 4bd0819 (`docs/native-wifi-results/20261012-stageb-role1-4bd0819/`): reboot completed, no new panic reported. Trace confirms base start=1, pool/queues=1, addEventSource x6 ok, registerInfraEthernetInterface=0 and startWithInfo ok. Child role Infrastructure, IODeferBSDAttach=Yes; still unregistered/unmatched and no BSD unit/new en interface. Next: determine primary-interface BSD publication after deferral. Sleep/wake and teardown not tested.

* 2026-10-12, Stage B role 1 (`docs/native-wifi-results/20261012-stageb-role1-4bd0819/`): trace complete, `mk:startWithInfo ok`; base start, pool/queues (class-0 Tx queues accepted), six event sources and `registerInfraEthernetInterface=0` all succeed. Interface child: `IOInterfaceNamePrefix=en`, `IOMACAddress` present, `IODeferBSDAttach=Yes`, !registered/!matched, no `IOInterfaceUnit`, no new en. Static reading (round3/4 dumps): `IOSkywalkNetworkInterface`'s `start` is plain `IOService::start` (vtable col 0x5d0), and the only caller of `deferBSDAttach` (col 0xa08) found so far is `AppleBCMWLANSkywalkInterface::start` with `true` for role 1. Who passes `false`, who calls `registerService` on the interface and what `deferBSDAttach` does exactly are **chưa xác định**; the dumps do not contain them. Next: `tools/dump_native_wifi_round9.py` on the Mac (read-only, no reboot) dumps `deferBSDAttach`, `prepare/finalizeBSDInterface`, the functions that reference the string `IODeferBSDAttach`, and every `call [vptr+0x9f8]` / `registerService`-slot call site in the IO80211/AppleBCMWLAN/IOSkywalk code.

* 2026-10-12, round 9 analysis (`abi/native-wifi/24H32/round9/`) and publication build: (1) `deferBSDAttach(true)` = `setProperty("IODeferBSDAttach", true)`; `deferBSDAttach(false)` = `removeProperty("IODeferBSDAttach")` + `registerService(0)`; `AppleBCMWLANCore::setupDriver` calls the latter on the object at `[core ivars+0x2c20]`. (2) `IOSkywalkNetworkBSDClient::start` needs the property not true **and** an `IOInterfaceUnit` OSNumber; it then builds "%s%u" (prefix col 0x9e0, unit col 0x9e8) and sets `BSD Name`/`IOInterfaceName`. (3) `registerNetworkInterface` sets `IOInterfaceUnit` only when `info+0x38 >= 0`, and `initRegistrationInfo` leaves it 0xFFFFFFFF; role 1 never fills it, so unit has to come from us. (4) `AppleBCMWLANSkywalkInterface::start` ends, on `registerInfraEthernetInterface == 0`, with `registerService(8)` and `setRunningState(false)`. Code change: role 1 now sets `info+0x38 = unit` (default 9, `itlmt_native_unit`), calls `registerService(kIOServiceAsynchronous)` + `setRunningState(false)` after a successful registration (traced `sw:registerService(8) done`, `sw:setRunningState(false) done`) and then `deferBSDAttach(false)` (traced `mk:deferBSDAttach(false)=%x`). Boot-arg `itlmt_native_publish`: 0 = none of these, 1 = registerService + setRunningState only, 2 (default) = also deferBSDAttach(false). Not hardware-tested.
* Test (one reboot, stage B exclusive, same install): read `native-trace.txt`; expected tail `sw:registerInfraEthernetInterface=0; sw:registerService(8) done; sw:setRunningState(false) done; mk:startWithInfo ok; mk:deferBSDAttach(false)=0`. Success signs: `IOInterfaceUnit=9` and no `IODeferBSDAttach` on the interface node, `en9` in `ifconfig`, a BSD client child. Risks (chưa xác định): a panic when the BSD client attaches/enables with our queues (no queue callbacks implemented yet), and no "Wi-Fi" service in System Settings (needs userland IO80211 integration). Fallback if it panics: boot with `itlmt_native_publish=1` to see whether registerService alone is safe.

* 2026-10-12, Stage B exclusive publish build 06840d9 (`docs/native-wifi-results/20261012-stageb-publish-06840d9/panic-decoded.txt`): **kernel panic** at 0.47 s of uptime, `"trying to send on thread panic \n" @IO80211Glue.cpp:417`, thread = IOConfigThread (`IOService::doServiceMatch`). Backtrace: `IOSkywalkNetworkBSDClient::start -> kern_nexus_controller_alloc_net_provider_instance -> prepareNexusCallback -> IOCommandGate::runAction -> gatedPrepareNexus -> IO80211InfraInterface::prepareBSDInterface -> updateStaticProperties+0x8e -> IO80211Glue::sendIOUCToWcl+0x2bd -> panic`. So the publication worked: the interface was registered, `IODeferBSDAttach` was cleared, `IOInterfaceUnit` was present and the BSD client got as far as `prepareBSDInterface`.
* Analysis of the panic (`round3/IO80211Glue-sendIOUCToWcl.asm.txt`): the function takes `W = [[glue+0x18]+0x38]` (an IOWorkLoop-derived object, vptr+0x130 = `IOWorkLoop::onThread`, vptr+0x138 = `IOWorkLoop::inGate` after the +0x10 column shift), and only proceeds when `W->inGate() == true && W->onThread() == false`; otherwise it logs "[wcl] sendIOUCToWcl: Trying to send iouc msg<%d> on thread=<%d> inGate=<%d>" (only when the CCLogStream accepts level 1) and panics. `prepareBSDInterface` runs inside the BSD client's `IOCommandGate::runAction`, so the check passes exactly when that gate belongs to the same loop W. W is most likely the `IO80211WorkQueue` we return from `getWorkQueue()`. Our controller's `getWorkLoop()` returns the provider's real IOWorkLoop (stage-A fix), a different object, so the gate the BSD client uses (if it follows `getWorkLoop()` through the registry) is not W's, `inGate()` is false. This is a hypothesis: **chưa xác định** which loop the BSD client's gate is attached to and what is stored at glue ivars+0x38 (`IO80211Glue::initWithOptions` and `IOSkywalkBSDClient` init are not in any dump yet).
* Build after 06840d9: default `itlmt_native_publish` is now 1 (registerService + setRunningState only, no `deferBSDAttach(false)`), so the BSD client does not attach and the panic path is not reached; installing it over the current Stage B setup is safe to boot. New trace line `mk:loops wq=.. provider=.. ctl=.. iface=.. wq.inGate=.. wq.onThread=..` records which work loop each layer returns. Experiment knobs, both opt-in: `itlmt_native_publish=2` (also `deferBSDAttach(false)`, panics unless the loop problem is solved) and `itlmt_native_wl=1` (after `IO80211Controller::start` returned, `getWorkLoop()` answers with the `IO80211WorkQueue` like Apple's controller; the early answer stays the provider's loop so the stage-A `ml_thread_policy(NULL)` panic does not return). Do not combine them until the round-10 dumps back the hypothesis.
* Round 10 (read-only, no reboot): `KC=<BootKernelExtensions.kc> python3 tools/dump_native_wifi_round10.py abi/native-wifi/24H32/round10` dumps `updateStaticProperties`, `IO80211InfraInterface::prepare/finalizeBSDInterface`, `IO80211Glue::initWithOptions/withOptions/runActionBlockOnSerial`, all `IOSkywalkNetworkBSDClient`/`IOSkywalkBSDClient` functions and every `getWorkLoop` of the IO80211/IOSkywalk/AppleBCMWLAN classes. It answers: which loop the BSD client's gate uses, what the Glue keeps at +0x38, and which ioctls `updateStaticProperties` sends (our `isCommandProhibited` refuses all of them for now).

* 2026-10-12, post-panic diagnostics (`docs/native-wifi-results/20261012-stageb-loops-2220380/`): current trace includes new loop diagnostics; wq differs from provider, ctl equals provider. The line is truncated at iface, so inGate/onThread are unavailable (96-byte per-entry trace buffer). Interface remains BSD-deferred, consistent with safe publish=1 default; no experimental wl=1/publish=2 retry. Round 10 and supplementary Glue dumps collected for cloud analysis.

* 2026-10-12, round 10 analysis (`abi/native-wifi/24H32/round10/`, static, high confidence) and the all-in build: (1) `sendIOUCToWcl` needs `W = glue+0x38 = interface ivars+0x38 = controller->getWorkQueue()` to satisfy `W->inGate() && !W->onThread()`. (2) The BSD client's `IOCommandGate` (`client+0x90`) is attached to the loop the `IOService::getWorkLoop` chain returns (interface -> controller -> `controller->getWorkLoop()`). (3) Apple's `IO80211Controller::getWorkLoop` tail-calls the `getWorkQueue` slot, so both are the same object; our `getWorkLoop()` returned the provider's loop (the stage-A `ml_thread_policy(NULL)` fix), so the gate belonged to a different loop and `inGate()` was false. Hardware trace (2220380) agrees: wq != provider, ctl == provider. (4) `IO80211WorkQueue` is an `IOWorkLoop` subclass whose `workQueue()` runs the virtual `init` (real gate lock and thread), so a command gate can be attached to it. (5) `updateStaticProperties` sends ioctl 0x2c (HARDWARE_VERSION) and 0x2b (DRIVER_VERSION) through `sendIOUCToWcl`, skips the property when the result is nonzero, and falls back to the controller getter only for result 0xe082280f, then calls `updateCountryCodeProperty(false)`.
* Code changes in this build: `getWorkLoop()` returns the `IO80211WorkQueue` once `start()` has finished (`itlmt_native_wl`, default 1; 0 = old provider-loop answer); the early answer stays the provider loop. `itlmt_native_publish` default is back to 2 (registerService + setRunningState + `deferBSDAttach(false)`). `isCommandProhibited` allows ioctl 0x2b/0x2c, `getDRIVER_VERSION`/`getHARDWARE_VERSION` return real strings. The trace buffer is 1536 bytes and the loop diagnostics are split into `lp:wq/prov`, `lp:ctl/if`, `lp:inGate/onThread/wl`.
* Test (one reboot, stage B exclusive, install the CI build over the current EFI without restoring): read `native-trace.txt`. Expected tail: `lp:wq=X prov=Y`, `lp:ctl=X if=..`, `lp:inGate=.. onThread=.. wl=1`, `sw:registerService(8) done; sw:setRunningState(false) done; mk:startWithInfo ok; mk:deferBSDAttach(false)=0`. Success signs: `en9` in `ifconfig`, no `IODeferBSDAttach` on the interface node, a BSD client child, no panic. Fallbacks: `itlmt_native_wl=0` (old loop answer) and/or `itlmt_native_publish=1` (no BSD attach). If it panics again the backtrace (not the trace) is the evidence. Likely next blockers (chưa xác định): queue callbacks on enable, `setInterfaceEnable`, `finalizeBSDInterface`, whether configd/airportd touch en9; `tools/dump_native_wifi_round11.py` (read-only, run with `KC=...`) dumps those paths and the ioctl routing.

* 2026-10-12, round 11 analysis (`abi/native-wifi/24H32/round11/`, static, build 24H32; CI build of 5e3afae is green, run 38269276468): **ioctl path** — `sendIOUCToWcl` (gate check `inGate() && !onThread()` on W, satisfied if `getWorkLoop()` == `getWorkQueue()`) -> `runActionBlockOnSerial` -> in Glue dqMode 2 (default) the caller queues the block and `commandSleep`s on the Glue gate (`ivars+0x70`, 50 s deadline) while the Glue's own `IO80211WorkQueue` (`ivars+0x58`) thread runs `processPendingIoucQueue` -> `receiveMessageInternal` -> `apple80211RouteInternal` -> `apple80211getXXX` -> interface `isCommandProhibited(type)` -> controller. A nonzero `isCommandProhibited` is returned as the ioctl result and `updateStaticProperties`/`updateCountryCodeProperty`/`updateLocaleProperty` just skip that property. So 0x2b/0x2c (version strings) succeed, 0x33 (country code), locale and the rest are refused with 0x3a harmlessly. **Finalize** — `finalizeBSDInterface` is teardown only (calls disable), it is not on the attach path. **Enable** — `IOSkywalkNetworkBSDClient::enableInterface/adjustInterfaceEnable` need the client's gate loop `inGate()`, then call interface col 0x860 (`IO80211SkywalkInterface::enable`), presumably -> `setInterfaceEnable(true)` (col 0x938; not verified) -> `IO80211MacAddressAgent::setInterfaceEnable`, `createIOReporters` (if none and `IOInterfaceName` exists) and, for role 1, an `IO80211AssociationJoinSnapshot` allocation.
* Main risk of the test (chưa xác định, cannot be settled statically): the first ioctl in dqMode 2 depends on `commandSleep`/`commandWakeup` and on the Glue's second `IO80211WorkQueue` thread really running; failure panics in `IO80211Glue.cpp:0x20c` ("IO80211 Sleep failed -> proably deadlock") after up to 50 s. Boot-arg `wlan.wclDqMode` (value other than 2) makes the Glue invoke blocks directly; untested, use only if that panic shows up. Other unknowns: body of `IO80211SkywalkInterface::enable/disable`, who calls `enableDatapath` (our stub returns `kIOReturnUnsupported`; no call site in any dump so far), `createIOReporters`, `IO80211MacAddressAgent::setInterfaceEnable`, `IO80211AssociationJoinSnapshot::withInterfaceAndOptions`, `commandSleep/commandWakeup`, `apple80211getHARDWARE_VERSION/COUNTRY_CODE`. Verdict: the 5e3afae build is fit to test as is; no code change from round 11.

* 2026-10-13, Stage B exclusive build 5e3afae (`docs/native-wifi-results/20261013-stageb-bsd-5e3afae/`): boot completed, no new panic reported; wq=controller=interface loop, deferBSDAttach(false)=0, en9 and active BSD client present, no deferral property. Static version properties populated. Native link remains down; ifconfig en9 reports SIOCGIFXMEDIA I/O error; no Wi-Fi service in networksetup. Trace sample inGate=0 is before publication, not a measurement inside the BSD gate. Sleep/wake and teardown not tested.

* 2026-10-13, Stage B exclusive build 5e3afae (`docs/native-wifi-results/20261013-stageb-bsd-5e3afae/`): **BSD attach works**, no panic. Trace reaches `mk:deferBSDAttach(false)=0`; `wq == ctl == iface`, provider loop differs; interface has `IOInterfaceUnit=9`, `BSD Name=en9`, no `IODeferBSDAttach`, an active `IOSkywalkNetworkBSDClient` child (with the full queue/pool reporter legend), and `ifconfig -l` lists en9. `IO80211DriverVersion` / `IO80211HardwareVersion` are populated on the interface node, which proves the whole ioctl chain of round 11 (`sendIOUCToWcl` -> Glue serial queue/`commandSleep` -> `apple80211RouteInternal` -> our `getDRIVER_VERSION/getHARDWARE_VERSION`) ran to completion on real hardware; so the dqMode-2 sleep/wake risk and the gate check did not bite. (`lp:inGate=0` in the trace is a sample taken outside any gate and says nothing about the BSD client's gate.) Not working yet: `ifconfig en9` shows `flags=8822<BROADCAST,SMART,SIMPLEX,MULTICAST>` (no UP/RUNNING), `options=400<CHANNEL_IO>` and fails with `SIOCGIFXMEDIA: Input/output error`; controller `IOLinkStatus=0`, `IOLinkSpeed=0`, `IOSelectedMedium=""`, `IOActiveMedium=""`; `networksetup -listallnetworkservices` has no Wi-Fi service.
* Static reading for the media error (round 3 + 11 dumps): `IO80211InfraInterface::processBSDCommand` first calls `IO80211SkywalkInterface::processBSDCommand`, which for non-802.11 ioctls tail-calls the super slot (asm vptr+0x920 = `IOSkywalkEthernetInterface/IOSkywalkNetworkInterface::processBSDCommand`), and only afterwards, for `0xc02c6938` (SIOCGIFXMEDIA), runs `IO80211InfraInterface::updateMediumStatus`. The latter returns void: it reads `IOSelectedMedium`/`IOActiveMedium` names from the controller's properties and looks them up in the controller's medium dictionary (controller vptr+0x890), skipping everything when the dictionary or the names are missing. So the EIO is returned by the base class (`IOSkywalkNetworkInterface::ioctl_gifmedia` at 0xffffff80029825d6 is the likely site; it is **not dumped yet**, as are `getSupportedMediaArray`, `getInitialMedia`, `handleChosenMedia`, `IOSkywalkEthernetInterface::processBSDCommand`/`enable`). Our interface overrides none of those media virtuals, and our controller publishes no medium dictionary (`IOSelectedMedium=""`). Whether the fix is a medium dictionary on the controller, an override on the interface, or a different property is **chưa xác định** until the dump. Enable: nothing has enabled the interface (flags have no UP); `IO80211SkywalkInterface::enable`, `AppleBCMWLANSkywalkInterface::enable/enableDatapath` and the userland (configd/airportd/CoreWLAN) expectations are **chưa xác định**. The existing Wi-Fi front end (core Ethernet path) is not involved.
* Next (read-only, no reboot): `KC=<BootKernelExtensions.kc> python3 tools/dump_native_wifi_round12.py abi/native-wifi/24H32/round12` dumps `IOSkywalkNetworkInterface` and `IOSkywalkEthernetInterface` (all functions, incl. `processBSDCommand`, `ioctl_gifmedia/sifmedia/sifflags`, `enable`, `getSupportedMediaArray`, `getInitialMedia`), `IO80211SkywalkInterface::enable/disable/createIOReporters/enableDatapath`, the BCM equivalents, `IO80211MacAddressAgent`, `IO80211AssociationJoinSnapshot`, `IO80211CommandGate::commandSleep/commandWakeup`, the HARDWARE_VERSION/COUNTRY_CODE getters and link-state/postMessage functions.

* 2026-10-13, local round 12 collection: 204 entries, zero missing; 12 supplemental executable media/datapath functions. Media EIO path identified: inherited IO80211 supported-media getter needs controller medium dictionary; ioctl_gifmedia converts getter failure to errno 5. Local fix publishes/selects one IEEE80211Auto medium, no active-link claim. Build/link check passed (six reserved baseline missing only); controller slots 21 correct, zero wrong. Not installed or hardware-tested. Details in abi/native-wifi/24H32/round12/README.md. Enable/datapath and userland integration remain unresolved.

## Local datapath experiment (2026-10-13, not hardware-tested)

The next build includes the medium dictionary fix, a TX/RX bridge to the existing core radio engine, and lifecycle/queue/packet-ownership traces. Build **both** kexts; old core does not implement the internal bridge. `itlmt_native_dp=1` enables core scan/auth/join with installed credentials but prevents legacy Ethernet creation. `itlmt_native_nvtrace=1` opts into bounded best-effort NVRAM checkpoint writes; kernel log and registry traces/counters are also collected. No native CoreWLAN scan/join or radio-power support is claimed.

Datapath ABI evidence: `abi/native-wifi/24H32/round13/`. Build and link check passed with only the six reserved baseline missing symbols; controller slots 21 correct/0 wrong, interface 213 correct/0 wrong. New tracing includes the first 32 distinct ioctl IDs without payloads. The logs command collects native checkpoints and panic chunks plus a private full core registry; sanitize before sharing.

After the next boot, first collect baseline logs and media/discovery, then enable en9 explicitly and inspect TX/RX/completion/link counters. A read-only live query already confirms explicit BSD lookup identifies en9 as IEEE80211; a service can be created with `build/native_wifi_service create <absolute-private-preferences-backup.plist>` under administrator privileges. It preserves existing services and refuses duplicate en9 creation. Do not run sleep/wake/unload tests before the new datapath has been assessed. If panic occurs, stop and collect backtrace plus NVRAM checkpoints; checkpoint persistence is not guaranteed.

* 2026-10-13, datapath c2e21ce boot: no panic; core join/efuse/CLC succeed, en9 media EIO fixed, explicit enable succeeds, IEEE80211 service created. DHCP remains INACTIVE and traffic counters zero; delivery unverified. Follow-up stable station identity/linkState/software checksum changes prepared. See docs/native-wifi-results/20261013-datapath-c2e21ce/README.md.

* 2026-10-13, c78492b boot: no panic, native auto-enable/core link up; DHCP still blocked by inactive BSD media, traffic counters zero. Follow-up corrects ifmediareq status after Family handling, applies station address and clears BSD offloads during prepare. Interface slots 217 correct/0 wrong; only six baseline symbols missing. See docs/native-wifi-results/20261013-datapath-c78492b/.

* 2026-10-13, 78852cc boot: no panic; en9 media active, DHCP transmits, TX/completion work. No lease; RX reaches bridge but first frame drops during allocation/validation/enqueue (substep not traced). Live MAC correction succeeded after prepare returned ENXIO. See docs/native-wifi-results/20261013-datapath-78852cc/.

## RX root investigation — 2026-10-13

Round14 identifies omitted packet preparation, missing Family station seed and missing Infra link-state transition. The next build replaces the earlier BSD media/MAC patches with proper lifecycle calls, supplies RX Ethernet metadata, and includes step-specific RX failure tracing. Build **both** core and native: link callback bridge ABI is now v2. Slots: controller 22/interface 214 correct, zero wrong; all generated interface headers have zero slot mismatches; link check permits only six reserved baseline symbols. Hardware outcome remains pending.

Expected next boot: fixed station identity without shell repair; `dp:Family link=1 begin gate=1 thread=0` followed by result=1/state=2; real media active without patched ifmediareq; `dp:RX prepare=0 buffers=0->1`, `dp:first RX delivered`, and a DHCP lease. Different before-count can occur for recycled objects; preparation return and after-count matter. If RX fails, send step/rc/packet/len trace plus counters. No CoreWLAN scan/join implementation or end-to-end networking success is claimed yet.

Legacy ItlWiFi login agent is disabled for this experiment; its prior plist and launchctl state are under `~/itlmt-backup/legacy-ui-20261013`. On returning to legacy mode after EFI restore, re-enable with `launchctl enable gui/$(id -u)/com.itlmt7925.ItlWiFi` and bootstrap its saved/current LaunchAgents plist if it is not loaded. No legacy Ethernet driver object was present; required core firmware/radio engine stays enabled.

## CARD_CAPABILITIES (ioctl 12) — 2026-10-13, build after 3b4ff24 (not hardware-tested)

* Live evidence on the 3b4ff24 boot (`itlmt_native=1 itlmt_native_if=1 itlmt_native_dp=1`): en9 `UP,RUNNING`, `status: inactive`; registry
  trace `ioctl:cmd=c prohibited` (also 0x216, 0x33, 0x1c) and `itlmt_ioctl_rejected` = 1409. CoreWLAN lists no interface and
  `SCNetworkInterfaceCopyAll()` does not return en9, although a direct BSD lookup of en9 reports IEEE80211. Apple's client library
  asks DRIVER_VERSION (0x2b) and then CARD_CAPABILITIES (0xc) when it binds an interface; the controller refused 0xc with 0x3a and
  `getCARD_CAPABILITIES` returned unsupported, so the bind can stop there. That the refusal is *the* reason Settings sees no Wi-Fi is
  **a hypothesis**: it is the only ioctl in the trace that the bind step needs and that we refuse; the next boot decides.
* Change (`itlmt7925_wifi.cpp`): `isCommandProhibited` also allows 0xc; `getCARD_CAPABILITIES` writes the 0x18-byte extent that
  `AppleBCMWLANCore::getCARD_CAPABILITIES` (0xffffff80015f16ca) writes, reporting only the bits Apple sets without consulting chip state
  (constants, two unconditional ORs, and the two bits set when BCM feature flags 1 and 7 are absent). Bits Apple derives from firmware
  features / chip revision / radio state stay clear. Which bit is which capability is **chưa xác định** (names live in userland).
* Build + link check: `bash scripts/build.sh itlmt7925Native` ok; `check_kext_links.py` exit 0, only the 6 baseline-missing symbols.
  No virtual signature changed (slots unaffected).
* Next boot, read: `ioctl:cmd=c allowed`, `ioctl:CARD_CAPABILITIES answered`; then which *new* ioctl IDs appear in the trace
  (first 32 distinct are recorded: the library's next requests after the bind are the next handlers to implement), and whether
  `networksetup -listallhardwareports` / CoreWLAN list en9. If still absent, the matching/user-client path airportd uses is the
  next thing to dump (not done).

## Full-flow call recorder (`itlmt_native_calls`) — 2026-10-13, build after 19e4999 (not hardware-tested)

Reason: a reboot is expensive and the old trace kept only the first 32 distinct ioctl IDs, nothing about GET/SET handlers or
callers, no counters. The recorder keeps one table (160 entries, ~8 KiB text) published as the registry property
`itlmt_native_calls` on the controller whenever an entry is new or its count reaches a power of two (so it is current at a panic-free
shutdown and loses at most a doubling of a count). `native-wifi-test.sh logs` already greps `itlmt_native_` into `native-trace.txt`.

Format: `<kind>:<hex id>[@<ra0>/<ra1>/<ra2>]x<count>;` ...

| kind | what | id |
|---|---|---|
| `I` | controller `isCommandProhibited(cmd)`, every request, allowed or refused | ioctl number (0xc CARD_CAPABILITIES, 0x13 POWER, 0xd STATE, 0xe PHY_MODE, 0xf OP_MODE, 0x1b SUPPORTED_CHANNELS, 0x1c LOCALE, 0x2b DRIVER_VERSION, 0x2c HARDWARE_VERSION, 0x33 COUNTRY_CODE) |
| `C` | controller handler actually reached (`getCARD_CAPABILITIES`, `getDRIVER_VERSION`, ...) | ioctl number; `0x8000000N` = set |
| `H` | `handleCardSpecific` | cmd, `0x80000000` set bit = set |
| `S` | interface protocol stub (one of the 191 unimplemented get/set handlers, all return unsupported) | vtable slot (467..656, see `round3/AppleBCMWLANSkywalkInterface.vtable.txt`) with 3 return addresses |
| `U` / `u` | controller `newUserClient` entry / result | type (0x57694669 = 'WiFi' firmware loader); `u` id = `type << 16 | result & 0xffff` |
| `W` / `w` | interface `newUserClient` entry / result | same as `U`/`u` |
| `B` | `processBSDCommand` | ioctl command word |
| `E` | interface `enable` / `disable` | 1 / 0 |

`ra0/ra1/ra2` are the three return addresses above the recording function (for `I` the Family function that called
`isCommandProhibited`, then its callers; for `S` the dispatcher above the stub), already corrected by the KASLR slide (runtime
address of the exported `IO80211WorkQueue::workQueue` minus its static 0xffffff8002258fcc) and truncated to the low 32 bits: prefix
`0xffffff80` is implied (`021f65a4` = `0xffffff80021f65a4`). Look them up with `tools/kc.py` (`kc.syms` nearest lower symbol) against
the same KC hash. A zero means the frame walk stopped (bounded: 3 hops, 0x400 per hop, kernel addresses only).

What it still cannot tell: payload contents or what userland did with an answer; that needs the userland log (`logs` now also
collects `userland-wifi.log`, `airport-profile.txt`, `hardwareports.txt`).

## IOSkywalkLegacyEthernet shim + first real ioctl handlers — 2026-10-13, build after ef42853 (not hardware-tested)

### What the ef42853 boot established

* The recorder (see above) showed userland reaching the interface: `0x2c/0x2b` (versions), `0xc` (x37, answered), then `0x13` POWER (x71,
  polled), `0x33` COUNTRY_CODE, `0x1c` LOCALE, `0x5` POWERSAVE, `0xf` OP_MODE (x20), `0x4` CHANNEL, `0x10` RSSI, `0x1b`
  SUPPORTED_CHANNELS (x12), `0xcf` CHANNELS_INFO, `0xd8` ROAM_PROFILE, `0x103` MAX_NSS_FOR_APP, set `0x16b` USB_HOST_NOTIFICATION,
  `0x1d5` OS_FEATURE_FLAGS, `0x200` INFRA_ENUMERATED, and `0x216` (not identified). All but 0xc/0x2b/0x2c were still refused.
* `SCNetworkInterfaceCopyAll()` and configd's InterfaceNamer enumerate only `IONetworkInterface` objects (via IONetworkStack). Our
  interface is an `IOSkywalkEthernetInterface` (not an `IONetworkInterface`), so en9 existed as a BSD interface but not for
  SystemConfiguration.

### Mechanism (from Apple's own 24H32 disassembly, read-only)

`IOSkywalkFamily` carries a personality `IOSkywalkLegacyEthernet` (`IOProviderClass` = `IOSkywalkEthernetInterface`,
`IOMatchCategory` = `IOSkywalkLegacyEthernet`): an `IOEthernetController` shim whose `createInterface()` builds an
`IOSkywalkLegacyEthernetInterface` (an `IOEthernetInterface`, i.e. an `IONetworkInterface`, with `IOClassNameOverride`). Its
`probe()` refuses a provider that already has `IOInterfaceUnit`. Our controller pre-assigned the unit (RegistrationInfo +0x38 = 9) so
the shim never matched. Apple's own role-1 interface leaves +0x38 = 0xFFFFFFFF; the unit is assigned later by IONetworkStack /
configd through the shim's `attachToDataLinkLayer`, which sets `IOInterfaceUnit` on the provider and re-registers it, after which
`IOSkywalkNetworkBSDClient::start` names the BSD interface.

### Change

* `makeInterface`: role 1 no longer writes the unit; `itlmt_native_unit=N` (explicit mode) and role 2 are unchanged.
* Watcher (own IOWorkLoop + IOTimerEventSource, 5 s ticks, `unit:*` trace lines, overwritten property `itlmt_native_shim`): records every
  `IONetworkInterface` in the registry (class / `BSD Name` / unit) and the registry children of our interface. If no `IOInterfaceUnit`
  appears within `itlmt_native_unit_wait` seconds (default 45; 0 disables the fallback) it applies the previous behaviour
  (`IOInterfaceUnit` = `itlmt_native_unit_fb`, default 9, then `registerService`) so the BSD interface still comes up. Trace line
  `unit:none after ...` means the fallback fired, i.e. the shim did not match.
* Handlers with layouts taken from Apple's `AppleBCMWLANCore` (addresses in the source): controller `getPOWER` ([+4]=1, [+8]=state, the
  state is what userland set, initially 0), `setPOWER` (recorded only: no firmware), `getCOUNTRY_CODE` / `setCOUNTRY_CODE` (3 bytes at
  +4, initially Apple's "XZ" = unknown); interface `getCHANNEL` (0xe0822801 while the link is down), `getPOWERSAVE` ([+4]=0), `getRATE` /
  `getRSSI` (0xe0822403 = not associated), `getOP_MODE` ({1, 0}), `setUSB_HOST_NOTIFICATION`, `setOS_FEATURE_FLAGS` (qword stored),
  `setINFRA_ENUMERATED` (0). While the core reports its link up the value getters return unsupported rather than an invented answer.
* Allowed commands: 0x4, 0x5, 0x8, 0xc, 0xf, 0x10, 0x13, 0x2b, 0x2c, 0x33, 0x16b, 0x1d5, 0x200. Still refused (data comes from firmware
  tables this driver has not): 0x1b, 0xcf, 0xd8, 0x103, 0x1c, 0x216.
* `itlmtTrace`: once the 1500-byte prefix is full, entries now append to `itlmt_native_trace_tail` instead of replacing it.

### Checks (host-only)

`scripts/build.sh itlmt7925Native` ok; `check_kext_links.py` only the 6 baseline-missing symbols; `check_native_slots.py`:
interface 215/0, controller 23/0; `gen_native_iface.py --check` ok.

### One reboot, read in this order

1. `ioreg -l | grep itlmt_native_shim` — an `IOSkywalkLegacyEthernetInterface`/`IOEthernetInterface` entry with a `BSD Name`
   and `u=` is the shim worked (then `networksetup -listallhardwareports`, CoreWLAN, System Settings should list it as Wi-Fi).
2. `unit:assigned t=..s fb=0` (shim) / `unit:none after 45s` + `fb=1` (shim did not match; send the `first` snapshot).
3. `itlmt_native_calls`: which `I:` ids remain refused, which `S:` slots (467+) are reached next.
4. `ifconfig` for the BSD name chosen by IONetworkStack (not necessarily en9).

### Result of the f6b7162 boot (user report)

The shim matched: the interface came up as `en4` (Wi-Fi hardware port) and the Wi-Fi switch in System Settings turns on and off.
Scan and join were still refused at that point; the section below is the next build.

## Scan + WPA2-PSK join through the native path — 2026-10-13, build after f6b7162 (not hardware-tested)

### What is new

Core (`itlmt7925`, `itl_native_bridge.h`): platform functions `itlmt-native-scan-v1`, `-nets-v1`, `-join-v1`, `-leave-v1`,
`-status-v1` (only answered in native mode; they only touch a mailbox and snapshots, nothing blocks on the chip).
The AP table now keeps probe/beacon flag, capability, beacon interval and up to 512 bytes of whole information elements.
`Net` gained a PMK: when userland supplies the 32-byte PMK the core's M3 handshake uses it directly (`itl_wpa_pmk` is skipped).
A failed native attempt is reported once (state FAILED, fail stage) and the network is dropped instead of being retried forever.

Interface (`itlmt7925Native`): handlers for ioctl 0x1b / 0xfe (supported channels: the 12 channels the core scans), 0x1b9
(SCAN_REQ), 0x1b3 (SCAN_ABORT), 0x1ba (ASSOCIATE: needs a raw 32-byte PMK, cipher type 6 or 9, otherwise Unsupported), 0x1b6
(JOIN_ABORT), 0x1a9 (LEAVE_NETWORK), 0x1b1 (WCL_BSS_INFO). `getCHANNEL/RATE/RSSI/OP_MODE` answer from the core status while linked.
`pollControl()` (100 ms inside the datapath tick) delivers results: scan table as one 0xc9 event per AP (beacon message 0x44 + IE
length) followed by 0xed (scan done); join as 0x4e, 0xd3 and, on success, 0xd5, posted with
`IO80211Controller::postMessage`. Scan timeout 25 s, join timeout 45 s (then LEAVE and a failure result).

### Not determined (chưa xác định)

`apple80211_channels_info` layout; Apple's numeric failure codes (ieee status 1 / status1 1 are placeholders); the 0xd3 flag byte and
the words at +0xc/+0x10; whether the Family needs a current-BSS object / SSID property update before Settings shows the joined name;
directed scans (the SSID is only a report filter); open, SAE and enterprise joins (refused with Unsupported); ROAM_PROFILE,
BTCOEX_PROFILE, LOCALE layouts. The station address is still the placeholder shared by core and controller (core firmware setup uses
the same value in native mode).

### Checks (host-only)

Both kexts build; `check_kext_links.py` only the 6 baseline-missing symbols (postMessage resolves in IO80211Family);
`check_native_slots.py` 215 on the right slot, 0 wrong; `gen_native_iface.py --check` ok.

### One reboot, read in this order

1. Settings → Wi-Fi: does the list of networks appear? `bash scripts/native-wifi-test.sh logs`.
2. `itlmt_native_calls`: `S:594` (SCAN_REQ), `P:201`/`P:237` (0xc9/0xed posted), then `S:595` (ASSOCIATE), `P:78`/`P:211`/`P:213`
   (0x4e/0xd3/0xd5).
3. `itlmt_native_trace`: `scan:` and `assoc:` lines (fail stage when a join fails), `wifi-events` in the core log.
4. Join a WPA2-PSK network from Settings; `ifconfig` for the BSD interface and DHCP.

## Join sequence fix (round 16)

### Result of the 4b9273b boot (user report + log)

Settings listed the scanned networks; joining failed immediately. `setAssociateRequest` returned 58 (`kProhibited`): the family's
`WCLJoinManager::handleJoinRequest` (0xffffff800220ac36) begins every join with an internal GET of ioctl 0x1ab
`WCL_LOW_LATENCY_INFO` and aborts when it fails or returns a nonzero dword. `isCommandProhibited` refused 0x1ab (not in
`commandAllowed()`), so the join never reached 0x1ba ASSOCIATE.

### What changed (itlmt7925Native only; core kext unchanged)

* `commandAllowed()`: + 0x170 SET_MAC_ADDRESS, 0x1ab LOW_LATENCY_INFO, 0x1be SET_SCAN_HOME_AWAY_TIME, 0x1b7 TRIGGER_CC.
  The recorded-ioctl list holds 96 distinct ids (was 32).
* Handlers: `getWCL_LOW_LATENCY_INFO` (one zero dword), `setWCL_SET_SCAN_HOME_AWAY_TIME` (accepted, first two words traced),
  `setWCL_WNM_OPS`, `setWCL_TRIGGER_CC`, `setWCL_LINK_UP_DONE` (accepted), `setWCL_LINK_STATE_UPDATE` (accepted; bssid/up/flags/reason
  traced as `wcl:link state ...`). `setMacAddress` answers `kIOReturnNotPermitted` for a different address (the join manager
  tolerates 0 and 0xe00002e2 only).
* Event 0xd4 (first beacon, exactly 0x14 bytes: u16 status 0, u16 ieee status 0, +4 bssid, +0xc u64 zero) is posted between 0xd3
  and 0xd5 (`WCLJoinManager::firstBeaconEventHandler`, `WCLJoinRequest::updateFirstBeaconEvent`).
* `getCHANNEL/RATE/RSSI/WCL_BSS_INFO` use the core's association state only (no longer also the family-visible radio link, which
  can lag by one tick when WCLNetManager::linkUp asks for BSS info right after 0xd5).

### Not needed from the driver (read from the disassembly)

The family's `WCLNetManager::linkUp` -> `updateBss` -> `WCLBssManager::setCurrentBSS(WCLBSSBeacon*)` sets the current BSS, so
SSID/BSSID/CHANNEL are answered by the family; the driver does not build a `IO80211BSSBeacon`. `linkUp` also issues a GET 0x1b2
TRAFFIC_COUNTERS (0x38 bytes) whose result it does not check; 0x1b2 is still refused (layout not determined).

**Correction (round 19):** "once 0xd3/0xd4/0xd5 arrive" was wrong. `linkUp` is only reached from the net-manager FSM's LINK_UP
event, which comes from event 0xd8 (see round 19 below); 0xd3/0xd4/0xd5 alone leave the current BSS null.

### Checks (host-only)

Both kexts build; `check_kext_links.py` only the 6 baseline-missing symbols; `check_native_slots.py` interface 215/0;
`gen_native_iface.py --check` ok.

### One reboot, read in this order

1. Join a WPA2-PSK network from Settings. `bash scripts/native-wifi-test.sh logs`.
2. `itlmt_native_trace`: `ioctl:cmd=1ab/170/1ba allowed`, `assoc:request`, `assoc:result ok=1`, `wcl:link state up=...`,
   `wcl:link up done`, `if:setMacAddress ...`.
3. `itlmt_native_calls`: `S:595` ASSOCIATE, `P:78/211/212/213` posted events, `S:600` LINK_STATE_UPDATE, `S:597` LINK_UP_DONE,
   which `I:` ids appear next (SSID/BSSID are family-answered; look for 0x1b2, 0x1b8 and any still-refused id).
4. `ifconfig` for the BSD interface and DHCP; System Settings shows the joined name.

### Result of the round-16 boot (2026-10-13)

* The password prompt in Settings no longer reports an error (round 15: `setAssociateRequest` = 58 right after the prompt).
* The captured window (boot 16:26 to 16:51, `log show` + ioreg) contains **no join request at all**: no `APPLE80211_IOC_WCL_ASSOCIATE`,
  no GET 0x1ab / SET 0x170 / 0x1ba, no `assoc:request` in `itlmt_native_trace`; airportd logged only auto-join scans (known
  networks all "unused for 72 weeks", so auto-join never targets one). So the join attempt was not inside the capture; no verdict on
  the join FSM or on data yet.
* Still failing on every cycle, all family-visible: GET SSID/BSSID/RSSI/RATE/NOISE `0xe0822403` (no association, expected), CHANNEL
  `0xe0822801`, CHANNELS_INFO (0xcf) `0xe00002c7` (about 500 calls), MCS and NSS `0x3a` (prohibited, not in `commandAllowed()`),
  BTCOEX_PROFILE `0xe00002c7` x35, ROAM_PROFILE `0xe0822403`, SET IE (0x55) `0x3a`, POWERSAVE `0xe00002c7`.
* `itlmt_tx_*` / `itlmt_rx_*` counters are 0 (no association, so no datapath yet).

### Next capture (no reboot needed: the kext is loaded)

1. Join from Settings, then within a minute: `bash scripts/native-wifi-test.sh logs` (from the worktree path, not the main checkout)
   or just read `ioreg -l -w0 | grep itlmt_native_trace_tail` and
   `log show --last 3m --info --debug --predicate 'process == "kernel" AND eventMessage CONTAINS "IOC DEBUG"'`.
2. Expect `INTERNAL: Set type=<APPLE80211_IOC_WCL_ASSOCIATE>` and the 0x1ab/0x170 GET/SET before it.

### Result of the join capture (2026-10-13, round-16 build still loaded)

* **Join works.** Trace: GET 0x1ab, SET 0x170 (setMacAddress answered "change refused", tolerated), 0x1ba `WCL_ASSOCIATE`,
  `assoc:request ssidLen=8 cipher=6 keyLen=32`, `assoc:result ok=1`, family link up, DHCP lease obtained (ACK from the gateway).
  Counters at the time: TX 66 / RX 20 frames, no drops.
* **No internet: every unicast IPv4 frame was dropped after BPF.** `tcpdump -i en4` (root) showed ICMP echo replies, TCP SYN-ACK and
  DNS answers arriving with the correct destination MAC, yet `netstat -s -p icmp` never counted an echo reply and TCP kept
  retransmitting the SYN. ARP (including unicast requests) and broadcast DHCP worked, so the destination MAC match was not the
  problem; only IPv4/IPv6 unicast was.
* **Root cause:** `IOSkywalkNetworkPacket::setIsLinkBroadcast(bool)` (24H32 `0xffffff800297f262`) and `setIsLinkMulticast(bool)`
  (`0xffffff800297f290`) ignore their argument: both call `kern_packet_set_link_broadcast` / `_multicast` unconditionally. The RX
  path called both for every frame, so each frame was marked link-broadcast **and** link-multicast; the IP stack discards a
  unicast IP packet that arrived as a link-layer broadcast/multicast (ICMP echo, TCP), ARP and DHCP do not care.
* **Fix (round 17):** call `setIsLinkBroadcast(true)` only for the all-ones destination and `setIsLinkMulticast(true)` only for
  other group addresses; never call them otherwise (the call itself is the flag).
* Expected next boot: `ping` to the gateway answers, DNS/TCP work. The default route may still prefer the en1 tether service;
  if browsing keeps using en1, reorder Network service order (not a driver problem).

## Result of round 17 (2026-10-13): unicast works, firmware stops answering ~50 s after link-up

Round 17 (`595561c`) booted. Unicast IPv4 reaches the stack (ping to the gateway, DNS). New failure: about 35 s after
link-up the radio goes silent (no beacons, no data), 15 s later the core logs `link lost: no beacon or data from the AP for
15 s`, and every MCU command after that returns `rc=-110` (`bss_info(add)`, `edca`), scans find nothing. The chip stays dead
until reboot. Cause: chưa xác định (candidates: firmware power management, a specific TX/RX frame, DMA / MCU queue stall,
PCIe link state).

Round 18 adds diagnostics and recovery in the core (`itlmt7925`), so one boot gives a verdict:

- `wifi-frames` (ioreg property of the core): last 24 Ethernet frames, oldest first, `<ms ago><t|r> <ethertype>/<ip proto> <a>><b> <len>`
  (ports for UDP/TCP, ICMP type or ARP op in `a`).
- `wifi-postmortem`: chip id, LPCTL / MISC / DUMMY / GLO_CFG / HOST_INT status+enable, PCI command / status / link control /
  link status, CPU/DMA indices of every ring, count of descriptors marked done. Written at 4 s without beacon ("silent 4s"),
  again after a `driverOwn()` wake attempt ("after driverOwn") and when the link is declared lost ("lost").
- Recovery: after a lost link the supervisor redoes the cold start (`wfsys` reset, rings, firmware, interface, scan) via
  `chipRecover()` (at most 8 times per boot) and rejoins. `wifi-events` shows `chip not answering: reset and firmware reload #n`
  and `recover #n rc=...`.

Read after the reboot (no root needed): `ioreg -l -w0 | grep -E "wifi-postmortem|wifi-frames|wifi-events"`.

## Result of round 18 (2026-10-13): link stable, internet over en4

After the reboot the link stayed up through the point where round 17 died (about 35 s after link-up) and for more than
5 minutes of use: 3 x 20 MB HTTP downloads over en4 (about 1.7 MB/s each, legacy level 0 / 6 Mb/s path), DNS to the
gateway, ping 0 % loss. The post-mortem and recovery code never triggered (`wifi-postmortem` absent). The round-17 hang did
not repeat; its cause stays chưa xác định (the previous boot had a root tcpdump + dig run on en4 at the time).
Open: `itlmt_fast` is not set, so the link runs at `lvl 0 bw 0`; en1 (tether) is still the primary default route.

## Round 19 (2026-10-13): the family never saw a link — event 0xd8 (not hardware-tested)

### Symptom (user report after round 18)

Internet works over en4, but System Settings > Wi-Fi and the quick-settings Wi-Fi item do not show the joined network.
airportd/WiFiAgent: GET SSID/BSSID answered `0xe0822403` (no association) although the core is associated.

### Root cause (read-only from the 24H32 IO80211Family disassembly)

* `WCLConfigManager::getSSID` fails with `0xe0822403` while `WCLBssManager`'s current BSS is null.
* The current BSS is set only by `WCLNetManager::updateBss` (GET 0x1b1 WCL_BSS_INFO into a 0x840-byte buffer, then
  `setCurrentBSS`), called from `linkUp`, `wake` and `assocTimerAction`.
* `linkUp` is reached from the net-manager FSM (states LINK_DOWN, WAITING_FOR_CONNECT_COMPLETE, WAITING_FOR_IP, LINK_UP,
  DEAUTH, SLEEP, SLEEP_DEAUTH): LINK_DOWN --LINK_UP--> `firstLinkUp` -> WAITING_FOR_CONNECT_COMPLETE; CONNECT_COMPLETE (from the
  join manager's 0xc0003 "join done") -> WAITING_FOR_IP; IPV4_STATUS -> LINK_UP.
* The FSM's LINK_UP / LINK_DOWN_IND events come from `WCLNetManager::linkStatusInd`, a bulletin-board subscriber for the driver
  event **0xd8**: `processEvent(byte[data+6] == 0 ? LINK_DOWN_IND : LINK_UP)`. The driver never posted 0xd8, so the FSM stayed in
  LINK_DOWN, no `0x1b1`/`0x1bc`/`0x1c6` ever came (the call recorder shows none of them), and the current BSS stayed null.
* Event routing: `postMessage(code)` -> `IO80211Glue::routeEventToWcl` -> `CommonGlue::sendMessage` ->
  `WCLGlue::receiveMessageInternal`, bulletin id `(code << 16) | 2`; `WCLGlue::isMsgNeeded` drops events nobody subscribed to.
* Pointer decode used for the KC data/vtables: `target = 0xffffff8000100000 + (raw & 0xffffffff)`.

### Change (`itlmt7925Native` only; core unchanged)

* `finishJoin(ok)` posts **0xd8** (0x10 bytes: `+0` BSSID, `+6` = 1) first, before 0x4e / 0xd3 / 0xd4 / 0xd5, so LINK_UP precedes
  CONNECT_COMPLETE and the join manager is still busy when `firstLinkUp` checks it.
* A core link loss (`linkFromCore(up=false)` while the family was told "up") makes `pollControl` post 0xd8 with `+6` = 0 and
  reason `+8` = 1. `WCLNetManager::linkDownInd` treats reasons 1 and 3 as the plain path: no debounce, no recreate; it issues
  `leaveNetworkCommand`, which reaches the driver's existing 0x1a9 handler (a core leave on an already-lost link).
* Trace lines: `wcl:link status posted up=<0|1> reason=<n>`, `wcl:bss info answered ch= ssidLen= ie=`; the existing
  `wcl:link up done` (0x1bc) and `wcl:link state ...` (0x1c6) now show whether the family reached `linkUp`.
* Still refused (result not checked by `linkUp`): 0x1b2 TRAFFIC_COUNTERS.

### One reboot, read in this order

1. `ioreg -l -w0 | grep -E "itlmt_native_calls|itlmt_native_trace"`: expect `P:d8` before `P:4e P:d3 P:d4 P:d5`, then
   `I:1b1`, `S:522`, `S:597` (0x1bc), `S:600` (0x1c6), and the trace `wcl:bss info answered`.
2. Settings > Wi-Fi shows the network as connected; `log show --last 2m --predicate 'process == "airportd"'` has no
   `0xe0822403` for SSID/BSSID.
3. If `P:d8` is there but no `I:1b1`: the FSM rejected LINK_UP (read the `wifi` log of WCLNetManager for the state), or the
   subscription table has no 0xd8 entry in the live build — then dump `gNET_MANAGERCallBackArray` again.
4. Link loss: force one (move the AP out of range); expect `wcl:link status posted up=0 reason=1` then `assoc:leave=...`.


## Handshake correction after the 36e0da6 boot — 2026-10-13

Settings scan works, but two native joins failed at M1 -> M2 -> no M3 (stage 6), before the new link-status event.
Corrected discarded M1 retransmissions and single-frame EAPOL RX mailbox; added replay/ANonce/MIC checks, AP-leave reasons,
optional PMKID equality and a persistent `wifi-handshake` summary. Both kexts built, link/slot/OC checks passed and executables
were staged on ESP with credentials/config preserved. Hardware result pending; the old logs cannot prove the exact failure cause.
See [result and next observations](native-wifi-results/20261013-handshake-36e0da6/README.md).

## Round 19 result and round 20 (2026-10-13): the family reached `linkUp`, then left because GET 0x1cc was refused

### Result of the 36e0da6 + 370bf8e boot

Call recorder / trace: `P:d8 P:4e P:d3 P:d4 P:d5`, then `I:1b1` (answered, `ch=149 ssidLen=18 ie=245`), `I:1cc` (stub:
Unsupported), `I:1a9` (the family's own LEAVE_NETWORK, `assoc:leave=0`), `I:1c6 up=0`, `I:188`, `I:1b5`, then our `0xd8 up=0
reason=1`. So 0xd8 works: the net-manager FSM reached `linkUp` -> `updateBss`. Core side the join itself was clean (PMKID
match, M1..M4, `hs-ok`); the 36 `eapol rx dropped depth=8` lines are the AP retransmitting M3 after the family-ordered leave.

### Cause (24H32 disassembly)

`WCLNetManager::setCurrentBSS` (after `WCLBssManager::setCurrentBSS`) runs, each step aborting the function (and `updateBss`
then issues `leaveNetworkCommand`) when it fails:

1. GET 0x1cc WCL_EXTENDED_BSS_INFO, 0x1e0 bytes. Layout from `AppleBCMWLANNetAdapter::getExtendedBssInfo`: +0 rate set
   (0xbc), +0xbc MCS index set (16), +0xcc VHT MCS set (8), +0xd4 HE MCS set (8), +0xdc u8 MLO, +0xdd 0x101 bytes of the
   associated WPA/RSN IEs.
2. `updateLinkState(1,1,1)` -> SET 0x1c6 (already handled).
3. SET 0x1f6 WCL_UPDATE_FAST_LANE (2 bytes).

Afterwards `linkUp` sends GET 0x1b2 TRAFFIC_COUNTERS (0x38 bytes, result ignored) and `startProtectIp` SET 0x1bb QOS_PARAMS
(result ignored); the 5 s protect-IP timer posts the FSM's IPV4_STATUS event, so LINK_UP is reached even before an address is
reported. `set4wayHsTimeout` only arms for EAP joins.

### Change (`itlmt7925Native` only; core is the Codex build 370bf8e, unchanged)

* 0x1cc answers success with the whole 0x1e0 buffer zeroed (the rate / MCS structure layouts and the IE blob format are chưa
  xác định, so nothing is invented: no rates, no MCS, no MLO, no IEs).
* 0x1f6, 0x188 PM_MODE, 0x1b5 ARP_MODE, 0x1bb QOS_PARAMS, 0x1ac SET_ROAM_LOCK: accepted and recorded; 0x1b2 answers zeros.
  The allow-list gained 0x1f6 / 0x1b2 / 0x188 / 0x1b5 / 0x1bb / 0x1ac.
* New trace lines: `wcl:extended bss info answered (empty)`, `wcl:fast lane <2 bytes>`.
* Still refused: 0x55 SET IE, 0xbf/0xc0 OFFLOAD_ARP/NDP, 0x22d DRBG_ENTROPY, 0x3a, CHANNELS_INFO details.

### One reboot, read in this order

1. `ioreg -l -w0 | grep -E "itlmt_native_calls|itlmt_native_trace_tail"`: expect `I:1b1`, `I:1cc`, `I:1f6`, `S:20a`,
   `S:212`, then `I:1c6 up=1`, `I:1bc`, `I:1b2`, and no `I:1a9` from the family (only on a real disconnect).
2. Settings > Wi-Fi shows the network connected; `airportd` no longer logs `0xe0822403` for SSID.
3. If the link is still left, the recorder's next `I:` after `I:1cc` names the new blocker.

## Round 20 result and round 21 (speed, duplicates, op mode, `itlmt_fast=6`)

### Round 20 result (boot with native bdef5ce0, core 71256f98, user joined from Settings)

* The whole family chain ran and stayed: `P:d8`, `I:1b1`, `I:1cc`, `I:1c6`, `I:1f6`, `I:1b2`, `I:1bb`, `I:1bc`; no `I:1a9` from the
  family. Core `wifi-state` = connected, en4 active with a DHCP address, `system_profiler SPAirPortDataType` reports
  Status Connected, channel 44, WPA2 Personal, 802.11ac, rate 54.
* `networksetup -getairportnetwork en4` still prints "not associated": the macOS 14+ redaction without Location permission, not a
  driver state (the profiler and the core agree).
* Defect found: "Network Type: Computer to Computer Network". `getOP_MODE` answered mode 2 and `APPLE80211_M_STA` is 1 (2 is
  IBSS, `apple80211_var.h`); the earlier comment that 2 = station was wrong. Fixed in round 21.
* Still prohibited and seen: 0x39 (x11), 0x161, 0x22d, 0x55, 0xc0, 0xbf, 0x1a8 - none stopped the join.

### Speed (round 20, legacy 6 Mb/s TX path, single run, not a LAN iperf)

Cloudflare WARP was running, and its policy refuses any TCP socket bound to en4 locally (zero packets on en4, refused in 2 ms), so
curl `--interface en4` cannot measure it. Apple's `networkQuality -I en4` does work:

| | round 20 baseline |
|---|---|
| uplink / downlink capacity | 15.4 / 8.8 Mb/s |
| idle latency | 62 ms (gateway ping 2.3-11 ms, 0 % loss) |
| responsiveness under load | 530 ms up / 810 ms down (poor: queueing + retries) |
| duplicates | +8 duplicate ICMP replies in 30 (AP retries delivered twice) |

### Round 21 change

* Core (`itlmt7925_m3.cpp`): 802.11 duplicate drop for unicast data outside a Block Ack window: Retry bit set and the sequence
  number equals the previous frame of that TID (index 8 = non-QoS) -> dropped, counted in `stRxDupL`. Frames without the Retry bit
  are never dropped, so an AP restart cannot be mistaken for a duplicate. A-MSDU subframes and the reorder path are untouched.
* Native: `getOP_MODE` answers `APPLE80211_M_STA` (1). A link the core restores by itself (fast-mode ladder step, AP drop and
  supervisor rejoin) is announced to the family again with the join sequence (`wcl:link restored by core, announcing again`),
  because the family had been told the link went down and would stay LINK_DOWN while data flowed.
* Boot-arg `itlmt_fast=6` added to `config.plist` (backup `config.plist.round21-pre`): HT/VHT rates, Block Ack, A-MSDU RX,
  160 MHz, HE; the core steps down by itself on failure down to the legacy path (verified earlier on this machine on the
  non-native path: 1.5-1.7 MB/s up, about 5.4 MB/s down over the internet, [WIFI.md](WIFI.md)).
* Undo: `occonfig.py args del itlmt_fast` (or restore `config.plist.round21-pre`);
  `build/esp-backup-native-round20-pre.kext` (bdef5ce0...) and `build/esp-backup-core-round20-pre.kext` (71256f98...).

### One reboot, read in this order

1. `ioreg -l -w0 | grep -E '"m3-log"|wifi-state|wifi-events'`: want `fast: on lvl=6` (or the highest level the ladder keeps),
   `lvl N bw M` in `wifi-events`.
2. `system_profiler SPAirPortDataType`: Network Type Infrastructure, PHY mode / rate higher than 54.
3. `networkQuality -I en4` against the round-20 baseline above (turn the USB tether and WARP off for a TCP test with curl).
4. `ioreg ... itlmt_native_calls`: a `P:d8` pair after a ladder step-down means the re-announce path ran.

## Round 22 (2026-10-13): firmware MAC, rate / MCS / IE content in GET 0x1cc

### Change

* Core (`itlmt7925_m2.cpp`): in native mode the firmware MAC is published as `IOMACAddress` when it is usable (read, not all zero,
  unicast); otherwise the previous locally-administered placeholder is kept. `itlmt_mac_source` = `firmware` | `placeholder` says which.
  The MAC value is not written to this repository.
* Native (`itlmt7925_wifi.cpp` `findMac`): reads the provider's `IOMACAddress` first, then falls back to the old registry scan.
* Bridge (`itl_native_bridge.h`, `ItlNativeStatus`): negotiated rate plan appended: `fastActive`, `fastNss`, `fastHe`, `fastBw`,
  `htMcs[10]`, `vhtMcs`, `heMcs` (IEEE 2-bit-per-stream maps, 0xffff = none), filled from the core `apCaps` in `itlmt7925_uc.cpp`.
* Native `getWCL_EXTENDED_BSS_INFO` (slot 530, GET 0x1cc, 0x1e0 bytes) no longer answers empty. Layout from
  `AppleBCMWLANNetAdapter::getExtendedBssInfo` and its helpers (24H32): rate set at +0 (count u16 at +4, entries of 12 bytes from
  +8: version, Mb/s = (byte>>1)&0x3f, basic = byte>>7), HT MCS bytes at +0xc0, VHT map u16 at +0xd0, HE map u16 at +0xd8,
  MLO flag +0xdc = 0, raw RSN (else WPA) element at +0xdd up to 0x101 bytes. Rates come from the AP Supported / Extended Supported
  Rates, MCS maps from the core plan; on the legacy 6 Mb/s path the VHT/HE maps are 0xffff. The version dwords the caller set
  are preserved. Trace line: `wcl:extended bss info rates=N rsn=N fast=N nss=N ht=.. vht=.. he=..` (first 4 calls).
* Not changed: default route / service order is a system setting (Settings > Network > ... > Set Service Order), not the driver.

### Install (ESP, verified byte for byte)

* Backups first: `build/esp-backup-native-round21-pre.kext` (e272ed83...) and `build/esp-backup-core-round21-pre.kext` (29527e9a...).
* Installed: native 45841ffb..., core de80ffa7..., boot-args unchanged (`itlmt_fast=6`, `itlmt_native_nvtrace=1`).
* Undo: copy the two backup kexts back over `/Volumes/ESP/EFI/OC/Kexts/itlmt7925Native.kext` and `itlmt7925.kext`.

### One reboot, read in this order

1. `ioreg -l -w0 | grep -E "itlmt_mac_source|IOMACAddress"`: `firmware` expected; if `placeholder`, `m2-log` says why the read was unusable.
2. `ioreg -l -w0 | grep -E "itlmt_native_trace_tail"`: the `wcl:extended bss info rates=` line, rsn nonzero for a WPA2 network.
3. `system_profiler SPAirPortDataType`: the interface address is the firmware MAC, rate / PHY higher than 54 if `fast: on`.
4. `networkQuality -I en4` against the round-20 baseline (15.4 / 8.8 Mb/s); `m3-log` for `fast: on lvl=` and `stRxDupL`.
5. `route -n get default`: still `en1` until the service order is changed by the user.

## Round 23 (2026-10-14): station address regression, ladder memory, wider scan

Report after the round 22 reboot: scans list too few networks, joins fail, and a join that succeeds has no internet.

### Causes found

* **Address mismatch (the regression of round 22, "joined but no internet").** Round 22 made the radio use the firmware MAC on
  air, but the native interface was registered before M2 had read it, so the interface kept the placeholder address. DHCP /
  ARP replies were addressed to a station the AP never heard of (`itlmt_rx_received` stayed 0). The two must be the same.
* **Ladder restarts at the top on every retry.** The cap that remembers a given-up level was reset on every failed join, so each
  retry from the Family walked `itlmt_fast=6 -> 5 -> 4 -> ... ` again (30+ s each).
* **Scan list short.** Only channels 1 / 6 / 11 were probed on 2.4 GHz (60 / 120 ms dwell); a router on 2..10 was never seen.

### Change

* Core `start()`: in native mode (`itlmt_native_dp=1` and `itlmt_m1`) `registerService()` is deferred (`regPending`);
  `publishService()` runs as soon as M2 has set `IOMACAddress`, or when M1 / M2 gave up, so the interface always reads the address
  the radio uses. Note line: `registerService (native: address known|not read)`.
* Ladder: RX-BA-only level (2) is skipped (`3 -> 1`); the cap (`lvlCap`) is kept per SSID and band (`capSsid`, `capBand`,
  `capMs`) across disconnects and failed joins, and expires after 10 min or when another network / band is joined
  (event `band changed (cap learned on ...)`).
* Watchdog "no unicast frame received" fires after 15 s instead of 25 s and logs tx / fail / fwfail / free / rxd / eapol / eth.
* Event ring (`evbuf`) 1500 -> 6000 bytes; `handshake failed: m1= m2= m3= rx= ...` is also an event now.
* Legacy association advertises the 2.4 GHz CCK + OFDM rate set (as the fast path did) so an AP whose basic rates are CCK accepts it.
* Scan list: 2.4 GHz channels 1..11 (was 1 / 6 / 11), plus the 5 GHz set as before.
* Native trace line `mk:mac from core|placeholder` (no address value).

### Install

* Backups: `build/esp-backup-{native,core}-round22-pre.kext` (byte-for-byte verified before the replace).
* Installed: native 932c4dbe..., core 4013ec79..., boot-args unchanged. Undo: copy the two backups over
  `/Volumes/ESP/EFI/OC/Kexts/itlmt7925Native.kext` and `itlmt7925.kext`.

### One reboot, read in this order

1. `ioreg -l -w0 | grep -E "itlmt_mac_source|IOMACAddress"` (core) and `ifconfig en4 | grep ether`: same address.
   `itlmt_native_trace_tail` must contain `mk:mac from core`.
2. `wifi-networks` (networks listed; more than before) and `wifi-events` (`level N -> M`, `no unicast frame ... tx= fail=`,
   `handshake failed: ...`).
3. After a join: `itlmt_rx_received` > 0, `ipconfig getifaddr en4`, `networkQuality -I en4`.
4. Leave and join the same network again: `m3-log` shows the start level is the cap, not 6.
5. Default route is a user setting: `networksetup -ordernetworkservices "Wi-Fi" "<tether name>"` (WARP refuses `curl --interface en4`).

### Round 23 result and round 23b (2026-10-14)

Boot with round 23 installed: the Wi-Fi interface came up as `en2` (firmware address, `itlmt_mac_source` = firmware), join and
4-way handshake complete at every level, but no data ever came back (`itlmt_rx_received` 0, only the two EAPOL frames received,
DHCP answered nowhere, `no unicast frame received in 15s` at levels 6, 5, 3, 1 and 0 alike).

* **Cause:** `ifconfig en2` showed `de:..` while the radio used `dc:..` (same bytes, locally administered bit set). The Family
  applies that bit to the interface address itself (private-address step; `setMacAddress` is refused, so the radio keeps the
  original). The DHCP server answers to the client hardware address in the request (the interface one), which is not a station
  on the AP. The earlier placeholder address (`02:..`) already had the bit set, which is why rounds 18-21 were not affected.
* **Change (core, `itlmt7925_m2.cpp`):** the address used on air and published as `IOMACAddress` has bit 1 of byte 0 set
  (`itlmt_mac_source` = `firmware+LA`). Interface address and on-air address are now the same value.
* **Install:** backups `build/esp-backup-{native,core}-round23-pre.kext` (the round 23 binaries, native 932c4dbe..., core 4013ec79...);
  installed core b8c1ea53..., native b8b7fdfe.... Undo: copy the backups back.
* **One reboot, read:** `ifconfig <wifi>` ether equals `ioreg IOMACAddress` of the core; `itlmt_mac_source` = `firmware+LA`;
  `itlmt_rx_received` > 0; `ipconfig getifaddr <wifi>`; `wifi-events` shows `up lvl 6` and no `no unicast frame`.
* **Noted, not changed:** the first join after boot can fail with `auth-fail` (4 authentication frames unanswered although frames
  were received) and succeed on the retry; the interface BSD name is now `en2` (was `en4`) because the service order changed.

## Speed measurements (2026-10-14, round 23b, core b8c1ea53..., native b8b7fdfe...)

Reference numbers, same machine, same boot. `itlmt_fast=6`, the link came up at level 6 on a 5 GHz channel (ch 40); RSSI about
-37 / -38 dBm (very close to the AP); `wifi-rate` 2402 Mb/s and one `up lvl 6 ch 40 bw 3` (160 MHz) event in `wifi-events`.
Measured by `curl` of a 20 MB object from a public speed-test host, `ping`, and the driver counters in `ioreg`.

| Condition | Result |
|---|---|
| Cloudflare WARP on, 1 flow | about 20 Mb/s (ping 41-66 ms) |
| Cloudflare WARP on, 4 flows | about 23 Mb/s aggregate |
| Cloudflare WARP on, upload | about 21 Mb/s |
| WARP off, `curl` download (20 MB / 30 s, 15 s) | 61 KB/s and 56 KB/s, about 0.45-0.5 Mb/s |
| WARP off, the user's own browser test | about 270 Kb/s |
| Phone on the same network (fast.com) | 180 Mb/s |
| Ping to the gateway, 1400 B, WARP off | 4-24 ms, average 12 ms, 0 % loss |
| Ping 1.1.1.1, WARP off | 31-41 ms, 0 % loss |

The WARP-on and WARP-off runs were on different subnets (different AP or network), so they are not comparable with each other;
only the WARP-off row and the phone share a network.

Driver counters at the WARP-off run (core `stat-log` `up=295s`):

* `itlmt_rx_received` 585211, `itlmt_rx_delivered` 585211, **`itlmt_rx_drop` 63981** (9.8 % of all RX frames offered), no
  `dp:RX failed` line: every drop was the 64-frame ring in `receiveFromCore` being full.
* `itlmt_tx_sent` 461937, `itlmt_tx_stall` 6357, `itlmt_tx_drop` 0.
* `stat-log`: `reo=13969/11135/1902/91/815/791/791/26` (reorder timeouts 791 of 13969, 5.7 %), `txf=460267/0/4954/942/420427`
  (about 0.9 firmware retries per frame).

Reading: ping with 1400 B packets is clean, bulk TCP is not. A 10 % loss rate on a 30 ms path limits one TCP flow to about
1 Mb/s, which is the order of magnitude seen. The loss is inside the driver, not on air.

### Round 24: RX ring and drain (native kext only)

* **Cause:** `datapathTick` ran every 10 ms, delivered at most 32 frames per tick (a ceiling of 3200 frames/s) and the ring between
  the core worker and the tick held 64. A burst (a block-ack reorder flush or an A-MSDU unpack gives tens of frames at once)
  overflowed it.
* **Change (`itlmt7925_iface.cpp/.h`):** ring 512 frames, up to 128 per tick, tick 2 ms. `pollControl()` still runs every 10 ms
  because the scan / join timeouts count in 10 ms polls. Properties are published once a second now.
* **New properties on the interface node:** `itlmt_rx_ringfull` (ring-full drops), `itlmt_rx_oversize` (bad length),
  `itlmt_rx_ringpeak` (deepest backlog). `itlmt_rx_drop` stays the sum plus delivery failures.
* **Install:** native only; backup `build/esp-backup-native-round24-pre.kext` (the round 23b binary, b8b7fdfe...), installed
  2e9345b7.... Core unchanged. Undo: copy the backup over `/Volumes/ESP/EFI/OC/Kexts/itlmt7925Native.kext`.
* **One reboot, read:** `itlmt_rx_ringfull` must be 0 or tiny and `itlmt_rx_ringpeak` below 512; then `curl` a large object with
  WARP off and compare with the table above and with the phone. If the speed is still low with no ring drops, the next
  suspects are (in this order): 160 MHz (`itlmt_fast=4` boot-arg removes level 5/6 and 160 MHz for an A/B), reorder timeouts
  (5.7 %), firmware retries (0.9 per frame), repeated RX block-ack renegotiation (`ba-log`: ssn 1, 2, 3 and `rx ba stopped`).

### Round 24 result and round 25 (2026-10-14)

Boot with round 24 (native only), same network, WARP off, `itlmt_fast=6`, level 6, ch 40, `bw 3` (160 MHz), RSSI -38 dBm.

| Counter / measurement | Round 23b | Round 24 |
|---|---|---|
| `itlmt_rx_drop` / `itlmt_rx_ringfull` | 63981 of about 649000 (9.8 %) | **0 / 0** (`itlmt_rx_ringpeak` 502 of 512) |
| `curl` download, several hosts | 56-61 KB/s | **23-66 KB/s: unchanged** |
| ping 1400 B to the gateway | 4-24 ms | 2.5-20 ms, 0 % loss |
| frames received in the first 94 s | n/a | 321878 unicast (a burst of about 3000 frames/s, ~35 Mb/s) |
| frames received afterwards | n/a | about 50 frames/s while `curl` ran |

The ring fix removed the host-side loss but did not change the speed, so it was not the limit. A burst at boot proves the link
can carry tens of Mb/s; later it does not. Counters during a 10 s `curl` (about 450 received MPDUs):

* reorder: 278 direct, 134 buffered (30 % out of order), 29 old (6 %), 82 timeouts, 4 late. Totals at 300 s:
  `reo=227975/151875/51394/3270/21323/5788/5717/113` = 9.4 % old (the AP re-sent MPDUs already delivered), 2.5 % timeouts that
  were never filled (late 113 of 5717).
* TX: 0.7 firmware retries per frame (`txf=.../116619`), `fwfail` 265, `noslot` 1289.
* `netstat -s`: 0 bad checksums, 0 TCP retransmits on the host side, no fragments: nothing is lost after the driver.
* `itlmt_rx_oversize` 0. Rx data ring 1536 entries (not an overrun). Group-addressed frames already bypass the reorder buffer.

Reading: the AP keeps re-sending frames we already acknowledged in hardware (our Block Acks / ACKs do not reach it) and
our own frames need 1.7 attempts each: an uplink / control-response problem, which on a 160 MHz HE link at -38 dBm points
at the 160 MHz configuration (control-response bandwidth or rate, or the channel config sent to the firmware). The 30 ms
reorder timeout turns every hole that is never filled into a 30 ms stall of the whole TID.

**Round 25 (installed, reboot pending):**

* New boot-arg `itlmt_no160=1`: `itl_caps_channel` is asked for at most 80 MHz at levels 5 and 6 (HE stays on).
  Boot-args now: `itlmt_fast=6 itlmt_no160=1 itlmt_reo=10` (reorder timeout 10 ms instead of 30 ms).
* `stat-log` gets `rty=<retry-bit MPDUs>/<all unicast QoS MPDUs>` (the AP resend ratio measured directly) and `bw=<fastBw>`.
* Install: core `283a29ea...`, native `a7c3d255...`; backups `build/esp-backup-{core,native}-round25-pre.kext` (core b8c1ea53...,
  native 2e9345b7...) and `build/config.plist.round25-pre`. Undo: copy the backups back, `occonfig.py ... args del itlmt_no160 itlmt_reo`.
* **One reboot, read:** `stat-log` shows `bw=2`; `rty=` ratio; `old` / `timeout` shares of `reo=`; `curl` speed; then A/B by
  removing `itlmt_no160` (160 MHz back) and `itlmt_reo` (30 ms) one at a time only if 80 MHz is also slow.

### Round 26: legacy comparison and the A/B matrix in one boot (2026-10-14)

Round 25 was never booted: the evidence changed what to test, and one boot should answer all of it.

**What the legacy driver did (same core, same radio engine, same 160 MHz HE AP, 2026-10-11, `HANDOFF.md` 10b/10)**: 4.3-8 MB/s
down, 0.9-6 MB/s up, with the same "old ~8 %, TX retry 30 %" signature (`rty` 13269 of 44055). So that signature is **not** the
cause of the collapse to 23-66 KB/s. Core changes after that benchmark, in order: `a45e8c1` (CLC + ACPI SAR power tables, RX
rings 1536, cached frame DMA buffers, batched `inputPacket`), `94e9814` (power tables finally accepted: before it the efuse query
failed on every join, so the tables were *never sent* in the legacy benchmark), then rounds 21-25 (RX duplicate drop,
firmware MAC + locally administered bit, native bridge). Of those, the power tables are the only change that alters what the
radio transmits.

**New evidence (round 24 build, WARP off, 1319 s uptime, -40 dBm):**

| Probe | Result |
|---|---|
| ping 1400 B to the gateway (the AP itself) | 0 % loss, 2-16 ms |
| ping 1400 B to 1.1.1.1 | 41-70 % loss; 10 % at 1 s interval |
| ping to 1.1.1.1 by size (56 / 500 / 1000 / 1400 B) | 2 / 4 / 14 / 40 % |
| ping 1400 B to other LAN clients (.2 / .5 / .12 / .82) | 22 / 100 / 7 / 0 % (peer dependent) |
| `netstat -s` ip / icmp / tcp | 0 bad checksums, 0 fragments, 0 TCP retransmits |
| `stat-log` | am=718674/718674/0/0: every A-MSDU carries one subframe; txf fwretry 1.6 per frame (0.7 earlier) |

Reading: the loss follows the *size* of frames forwarded by the AP (A-MSDU path, one subframe each) and not the gateway's own
replies (plain MPDUs), and no corrupted frame ever reaches the stack (cached DMA coherence is excluded: it would show bad
checksums). Candidates left: power tables (uplink power / control responses), the A-MSDU receive path, 160 MHz.

**Round 26 build (core `8effa037...`, native `a9ec3650...`, installed, reboot pending):**

* `itlmt_nopwr=1`: no CLC / SAR tables at join = the radio as in the legacy benchmark. `itlmt_stat=1`: `stat-log` every second.
* Run-time control without a reboot (`itlmt7925_ctl.cpp`, `tools/itlctl.c`, administrator only, applied by the link loop):
  `itl_lvl=1..6` reconnects at exactly that level (cap for the network untouched), `itl_no160`, `itl_reo=<ms>`,
  `itl_pwr=<ceiling in 0.5 dBm>` sends the CLC + SKU tables on the live link.
* New `rx-log` (size classes `<128 <512 <1024 <1280 <1400 >=1400` at the RX ring, after A-MSDU parsing, at delivery, parse
  rejects; big ICMP echoes at each stage and on TX) and `ts-log` (per second: eth, ring, tx, fwretry, noslot, old, timeouts).
  If a 1400 B echo reply is counted at `parsed` and not at `deliv` the loss is the reorder buffer; if it is not counted at the
  ring the radio / firmware never handed it over.
* `tools/itl-ab.sh` runs the matrix as root and writes one text file: A L6 160 MHz no tables (boot state), B L6 80 MHz,
  C L5 VHT160, D L4 VHT80+A-MSDU, E L3 no A-MSDU, F L1 no Block Ack, G back to A, H tables sent live (20 dBm ceiling), I 80 MHz +
  tables, J SAR ceiling, K reorder 10 ms. Each: gateway / WAN pings at 1400 B and 56 B, 10 s download, counters before / after.
* Install: backups `build/esp-backup-{core,native}-round26-pre.kext`, `build/config.plist.round26-pre`; boot-args
  `itlmt_no160` and `itlmt_reo` removed, `itlmt_nopwr=1 itlmt_stat=1` added. Tools in `build/itl-ab/` (survive the reboot).

### Round 26 first boot (2026-10-14): link lost at 839 s, never rejoined; matrix measured the wrong path

* **Wi-Fi 2 service.** macOS keys interface units by MAC address (`NetworkInterfaces.plist`). The MAC changed across rounds
  (placeholder `02:00:79:25:00:01` = en4, firmware MAC = en2, firmware + locally administered bit = en5), so every change created
  a new unit and a new service ("Wi-Fi", "Wi-Fi 2"). The MAC is final now: en5 stays en5. The stale entries (en2, en4, ...) and
  the stale "Wi-Fi" service can be removed by hand; nothing in the driver needs to change for it.
* **Link loss.** `wifi-events`: `843s silent for 4 s: driverOwn=1`, `854s lost after 839s at lvl 6: no beacon or data from the AP
  for 15 s`, `855s chip not answering: reset and firmware reload #1`, `858s recover #1 rc=0`, then `native join failed: network
  not found` (x2) and `the access point refused authentication` (x2); the supervisor then stopped. The postmortem registers
  (`lp=0`, `misc=3` where the boot value was 1, no interrupts pending) say the chip stopped answering; why it stopped is
  chưa xác định.
* **Bug found in the recovery path.** `chipRecover()` reloads the firmware but `m3hw` stayed true, so `fw_log`,
  `eeprom(efuse)` and `rts_thresh` (the cold-start one-time setup) were not sent again, and the CLC / SKU power tables were not
  either. The `m3-log` after `recover: M2` shows `set_domain` and nothing else. `chipRecover()` now clears `m3hw` and `clcCc[0]`.
  Whether this is why scans found nothing after the reset is not measured yet.
* **The first matrix run measured the phone tether.** The default route was the tether (en1): the "gateway" was the phone, the
  11.6 MB/s download and the unchanged counters were not Wi-Fi at all. `itl-ab.sh` now binds every ping / download to the
  Wi-Fi interface (`ping -b`, `curl --interface`), takes the gateway from that interface and stops if it has no router.

### Round 26 result: A-MSDU in the Block Ack agreement is what collapses the throughput (2026-10-14)

Matrix run inside one boot (core with the recovery fix, boot-args `itlmt_fast=6 itlmt_nopwr=1 itlmt_stat=1`, WARP off, all
traffic bound to the Wi-Fi interface, 10 s Apple CDN download; same AP, same radio):

| Config | Download | GW 1400 B loss | WAN 1400 B loss | WAN 56 B loss |
|---|---|---|---|---|
| A  L6 HE 160 MHz | 23 KB/s | 0 % | 70 % | 0 % |
| B  L6 HE 80 MHz | 59 KB/s | 0 % | 69 % | 3 % |
| C  L5 VHT 160 MHz | 66 KB/s | 0 % | 69 % | 1 % |
| D  L4 VHT 80 MHz + A-MSDU RX | 39 KB/s | 2 % | 71 % | 0 % |
| **E  L3 VHT 80 MHz, no A-MSDU** | **5 587 KB/s** | 5 % | 70 % | 1 % |
| F  L1 no Block Ack | 333 KB/s | 37 % | 82 % | 6 % |
| G  L6 160 MHz again | 170 KB/s | 10 % | 70 % | 2 % |
| H  L6 160 MHz + CLC/SKU tables 20 dBm | 46 KB/s | 1 % | 70 % | 2 % |
| I  L6 80 MHz + tables | 49 KB/s | 0 % | 69 % | 3 % |
| J  L6 80 MHz + tables, SAR ceiling | 48 KB/s | 100 % | 72 % | 5 % |
| K  L6 160 MHz, reorder 10 ms | 61 KB/s | 1 % | 71 % | 0 % |

* Power tables (H, I, J), 160 vs 80 MHz (A vs B), HE vs VHT (C) and the reorder timeout (K) change nothing. Only the step
  from level 3 to level 4 (the Block Ack agreement now accepts A-MSDU) costs a factor of ~100; level 3 has the whole
  Block Ack / TX-pool path and does 5.6 MB/s.
* The 70 % loss of 1400 B pings to 1.1.1.1 is the same at level 3, so it is not what stalls TCP (it is outside this driver or
  its cause is unknown; chưa xác định).
* Why A-MSDU hurts is not known yet: the hardware splits A-MSDUs into one packet per subframe, `stat-log` `am=` says
  packets == subframes, `drop=0`. Round 26d adds `rx-log` `ai=` (RXD4 payload format seen), `subs=` (subframes per packet,
  0..4+), `ovf=` (bundle full) and `bigdrop=` for the diagnosis.

**Round 26d change.** A-MSDU is off by default: `noAmsdu = true`, so levels 4..6 keep HE and 160 MHz but the agreement does not
accept A-MSDU. Boot-arg `itlmt_amsdu=1` or run time `itl_amsdu=1` (with the next reconnect) turn it back on. `tools/itl-ab.sh`
matrix: A-MSDU off at L6/160, L6/80, L5, L4, L3, then A-MSDU on at L6 and L4 for comparison, tables, reorder 10 / 100 ms.

### Round 26d result (2026-10-14): A-MSDU off = 33-41 MB/s

Same matrix, same AP / radio, traffic bound to the Wi-Fi interface, 10 s Apple CDN download:

| Config | Download |
|---|---|
| A  L6 HE 160 MHz, A-MSDU off (boot state) | 33.1 MB/s |
| B  L6 HE 80 MHz | 11.0 MB/s |
| C  L5 VHT 160 MHz | 19.5 MB/s |
| D  L4 VHT 80 MHz | 13.9 MB/s |
| E  L3 VHT 80 MHz | 31.6 MB/s |
| **F  L6 HE 160 MHz, A-MSDU ON** | **0.057 MB/s** |
| G  L4 VHT 80 MHz, A-MSDU ON | 0.048 MB/s |
| H  L6 HE 160 MHz, A-MSDU off again | 41.2 MB/s |
| I  H + CLC/SKU tables (20 dBm) | 23.6 MB/s |
| J  reorder 10 ms | 38.2 MB/s |
| K  reorder 100 ms | 26.7 MB/s |

* Phone on the same network: 180 Mb/s (~22 MB/s). The driver now does ~260-330 Mb/s on one TCP stream.
* The speed differences between the A-MSDU-off rows are run-to-run variance of one 10 s transfer on a shared channel; power
  tables, reorder timeout and 80 vs 160 MHz give no consistent effect. Defaults stay: no tables sent at join is still the
  boot-arg `itlmt_nopwr`; recommended boot-args `itlmt_fast=6` (A-MSDU off is the default now).
* With A-MSDU on the RXD4 payload format shows the expected first / middle / last mix (`ai=0/375/290/366`) but every packet
  carries exactly one subframe (`subs=0/1031/0/0/0`), bundles never overflow (`ovf=0`) and nothing is "bigdrop". The loss is
  not in the unpack; why TCP collapses with A-MSDU is chưa xác định and is left off. 1400 B pings to 1.1.1.1 still lose 70 %
  at every level (chưa xác định, not a driver symptom: TCP runs at 33 MB/s).

### Speed test of the shipped defaults (2026-10-14, core 322f7c94..., native 6d0e43df..., boot state, WARP off)

Interface = the native Wi-Fi port, default route on it, same AP as above, traffic bound to the interface.

| Test | Result |
|---|---|
| `networkQuality -s` downlink capacity | 293 Mb/s |
| `networkQuality -s` uplink capacity | 45 Mb/s |
| idle latency | 46 ms |
| downlink / uplink responsiveness | Medium (154 ms) / Low (675 ms) |
| 10 s Apple CDN download, 3 runs | 35.8, 33.6, 28.8 MB/s |

* The download is stable at ~29-36 MB/s (one TCP stream, ~230-290 Mb/s), above the phone's 180 Mb/s on the same network.
* Uplink is about 6 times lower than downlink and has high loaded latency: the TX path (rate selection is the firmware's, TX
  aggregation, `retry-ratio` in `stat-log`) has not been investigated yet. Next measurement: an upload run with `stat-log` on.

## Tahoe (25G241) first load

Everything above describes the 24H32 (Sequoia) rounds. The branch now carries the 25G241 (macOS 26.7.1) port: headers
regenerated from `abi/native-wifi/25G241`, the code deltas applied (`setMacAddress` takes an `mloAddrArray`, 5-argument
`setLinkState`, 13 new protocol handlers), all checks green (see
[IO80211-ABI.md](IO80211-ABI.md#tahoe-port-of-itlmt7925native-mac-2026-10-16)). **Nothing has been loaded on Tahoe yet**;
this is the first-load checklist.

Build and checks (Mac, in the worktree):

```sh
bash scripts/build.sh itlmt7925 itlmt7925Native
KC=/System/Library/KernelCollections/BootKernelExtensions.kc python3 tools/check_kext_links.py \
    build/itlmt7925Native.kext build/itlmt7925.kext      # exit 0, only the 6 baseline-missing symbols
python3 tools/gen_native_iface.py --check                 # generated stubs match the headers
```

Install (same helper as always; it backs up the EFI including NVRAM boot-args first):

```sh
scripts/esp-automount.sh
scripts/native-wifi-test.sh install build/itlmt7925Native.kext --stage b --exclusive
```

`install` now also **clears `MaxKernel`** on the ESP's `itlmt7925Native.kext` entry: the Tahoe migration had capped it at
24.99.99, and with the cap the kext silently does not load. Stage b adds `itlmt_native=1 itlmt_native_if=1 itlmt_native_dp=1`;
`itlmt_native_dp=1` is what makes the core scan/auth/join for the native front end (and suppresses the legacy Ethernet
front end / user clients). `--exclusive` additionally drops `itlmt_m2`/`itlmt_m3`/`itlmt_fast`, so the native path is the
only network device this driver produces - keep the phone tether ready until the native path works. Going back:
`scripts/native-wifi-test.sh restore`.

After the reboot (stage b), same signs as the 24H32 rounds plus the new ones:

* `kextstat | grep itlmt` shows both kexts; `ioreg -l | grep itlmt_native_trace` shows the `mk:`/`sw:`/`lp:` steps, ending in
  `mk:startWithInfo ok` and (publish >= 2) `mk:deferBSDAttach(false)=0`.
* `ioreg -l | grep itlmt7925WifiInterface` shows the interface node (role Infrastructure, `IOInterfaceNamePrefix`).
* A Wi-Fi service/interface appears (`networksetup -listallhardwareports`, System Settings > Network); the shim's unit
  assignment and scan/join are the parts to watch. The 13 new Tahoe handlers answer `kIOReturnUnsupported` until a feature
  needs them.
* Failures to send back: `scripts/native-wifi-test.sh logs` (kextstat, ioreg, `log show --last boot`, dmesg; SSIDs/MACs
  removed), the stage reached, and for a panic the first 30 lines of the panic text. Sleep/wake once only after the load
  is confirmed safe.

### First load result (2026-10-16): Wi-Fi came up, the scan list was garbled

Stage b did load on Tahoe: `itlmt7925Wifi` init against `IO80211_kexts-1566.5`, role 1, `mk:startWithInfo ok`, service
registered, `ifnet_attach` gave **en5** (`IOSkywalkLegacyEthernetInterface`, MAC `de:56:7b:34:81:d5`), and the radio path
worked - `APPLE80211_IOC_CARD_CAPABILITIES` GOOD, radio power from System Settings accepted (GET POWER / GET OP MODE on
en5), the core scanned at boot (`scan finished done=1@2410ms rx=85 bcn=83 aps=48`) and every one of airportd's 84
`APPLE80211_IOC_SCAN_REQ` calls answered GOOD (13 live core scans, the rest from airportd's cache; `scan:delivered 48 of
48` each time). The core's own AP table is clean (`m2-res` in the NVRAM checkpoints lists real names). The **list the Wi-Fi
menu built was garbled**.

Collection, driver trace, NVRAM checkpoints and the layout evidence:
[`docs/native-wifi-results/20261016-tahoe-first-load-73fe4ce4/`](../native-wifi-results/20261016-tahoe-first-load-73fe4ce4/README.md).

Cause: the `0xc9` beacon message header is **0x44**, not 0x40. From the 25G241 `BootKernelExtensions.kc` (verified
2026-10-16 on the mounted System volume):

* `AppleBCMWLANBSSBeacon::getBeaconMsgFromWLBSSInfo` writes ssid at +6, ssid_len at +0x26, primary channel at +0x27,
  bssid at +0x29, rssi at +0x30, noise at +0x34, a word at +0x36, beacon interval at +0x38, capability at +0x3a,
  **flags at +0x40**, and the caller passes the IE destination separately.
* `AppleBCMWLANScanAdapter::processScanResults` sets `ieBuf = meta + 0x44`, allocates the meta buffer as `0x844`
  (= 0x44 + 0x800) and posts the event with `len = ie_len + 0x44`.
* `AppleBCMWLANCore::getWCL_BSS_INFO`'s block does `lea rsi, [beacon_msg + 0x44]` for the same struct.
* Nothing writes +0x3c in either builder (left zero).

With the header at 0x40 the IE area sat four bytes early, so every element was read from the middle of its predecessor
(the SSID element included) and the consumer also read four bytes past the end of the buffer. Fixed in
`kexts/itlmt7925Native/itlmt7925_iface.cpp`: `kBeaconHeader = 0x44` and the flags dword moved to +0x40. Not rebuilt or
re-tested yet - next Mac boot: rebuild both kexts, `native-wifi-test.sh install ... --stage b --exclusive`, and check that
System Settings lists the networks with their real names.

Installed 2026-10-16 18:19 (Linux, no reboot yet): the `build-kexts` workflow run
[38892788373](https://github.com/thanhnndev/ga403wm-hackintosh/actions/runs/38892788373) on `163ec60` was downloaded and
`scripts/linux-install-kext.sh itlmt7925Native` put its `build/itlmt7925Native.kext` into the ESP
(`/boot/EFI/OC/Kexts/itlmt7925Native.kext`, sha256 `14c6af9a…`, previous one kept as
`Kexts-backup/itlmt7925Native.kext.20261016-181944`; `Info.plist` unchanged). The installed binary carries the fix -
`movl %eax, 0x40(%rbx)` then `addq $0x44, %rbx` before the IE `memcpy`, where the old one had `0x3c`/`0x40`. The ESP
boot-args already carry stage b (`itlmt_native=1 itlmt_native_if=1 itlmt_native_dp=1 itlmt_native_nvtrace=1 itlmt_fast=6
itlmt_stat=1 itlmt_nopwr=1`) and both itlmt entries have no Min/MaxKernel cap, so the next macOS boot is the check. The
core kext was left as installed (2026-10-14): this fix is native-side only.

### 2026-10-17: Wi-Fi worked, then a hard panic — the scan cache read past the queued beacon message

The 0x44 build did what it was meant to do: the Wi-Fi menu listed the networks with their real names and the machine
connected. 216 s in it went down hard (`Kernel-2026-10-17-093407.panic`): GZAlloc `data.kalloc.512`, a **read 1 byte past**
a 512-byte element, `IO80211BSSBeacon::setBeaconDataFromMsg + 0x2c` → `_memmove + 0x12` (the `rep movsb` in `__HIB`),
`RCX = 4`.

What the registers decode to (full walk-through in
[`docs/native-wifi-results/20261017-panic-kalloc512/`](../native-wifi-results/20261017-panic-kalloc512/README.md)):

* The element is the family's queue entry for one 0xc9 scan result: 0x20 header + 0x1e0 payload
  (`IO80211Glue::addEventToPendingQueue` allocates `length + 0x20` and copies the payload).
* `R13/R15 = payload + 0x44` = the IE pointer (`WCLMngFrameRouter::scanResultEventHandler` checks only `length >= 0x44`
  and hands `meta = payload`, `ies = payload + 0x44` on), `RDX/RBX = 0x1a0` = `ie_len` = the `+0` field of our header.
* `setBeaconDataFromMsg` takes `size = *(u32*)meta` and `allocateIEListBufferAndCopy` does `memmove(beacon->ieBuffer,
  payload + 0x44, size)` — **without validating `0x44 + ie_len` against the message**.
* The message needed 0x44 + 416 = 484 bytes but was stored (per the 512-byte element) as 480: 412 = 0x19c bytes of IEs.
  The copy spent its last 4 bytes one past the element, on a GZAlloc guard page.

So the family's contract is one `apple80211_beacon_msg`: 0x44 header + at most **0x19c = 412** bytes of IEs. The driver was
reporting up to `ITL_NATIVE_IE_MAX = 512`. Fixed in `kexts/itlmt7925Native/itlmt7925_iface.cpp`: `kEventIeMax = 0x190`
(400) with `ieTrim` (whole-IE prefix) in both beacon-message paths (`deliverScanResults`, `getWCL_BSS_INFO`), plus a
`scan:trim <bssid> ch=<n> ie=<reported>-><trimmed>` trace line (first 6 per boot) so the offending AP is identifiable.
Not built or re-tested yet. Next boot: use Wi-Fi >=5 minutes incl. repeated `wdutil scan`; no panic, and the trace shows
the trim for the AP that used to overflow (the 09:34 message had `ie = 416` → `416->400`).

Installed 2026-10-17 10:18 (Linux, no reboot yet): the `build-kexts` workflow run
[38998145267](https://github.com/thanhnndev/ga403wm-hackintosh/actions/runs/38998145267) on `6a73548` was downloaded and
`scripts/linux-install-kext.sh itlmt7925Native` put its `build/itlmt7925Native.kext` into the ESP
(`/boot/EFI/OC/Kexts/itlmt7925Native.kext`, sha256 `88499c27…`; the 0x44 build it replaces is kept as
`Kexts-backup/itlmt7925Native.kext.20261017-101843`, sha256 `14c6af9a…`; `Info.plist` unchanged, no Min/MaxKernel cap,
boot-args still stage b). Verified in the installed binary: both `ieTrim` loops with their `cmpl $0x190` bound (one in the
`getWCL_BSS_INFO` path, one in the `deliverScanResults` loop). The core kext is unchanged (native-side fix only).

### 2026-10-17 (later): the IE fix held, panic #2 — the fault pipe was never started

The 10:26 boot was the first with a working cap: the log store holds `scan:trim 00c896036939 ch=1 ie=473->347` (an AP
with 473 bytes of IEs — the old build's over-read territory) and the machine joined, got a DHCP lease and was usable.
Then, idle, it went down twice (10:30 after 229 s, 10:37 after 77 s) with a signature that has nothing to do with the
scan cache:

* `com.apple.driver.corecapture`, `CCDataPipe::enqueueBlob + 0x128`, NULL deref (`RDI = 0`) while
  `CCFaultReporter::completeReport` (a deferred fault report, timer-driven) writes a core capture.
* The capture is requested by the family's link-recovery path: `IO80211LinkRecovery::recordBSSBlacklistEvent` →
  `IO80211LinkRecovery::triggerFaultReporter` → the fault reporter this driver handed to the family at start.

Root cause: the `CCPipe::withOwnerNameCapacity` / `CCStream::withPipeAndName` factories only *init* a pipe. On 25G241 the
notify timer a data pipe needs is created by `CCDataPipe::start` (stored at pipe ivars +0x90 → +0x38, handler
`CCDataPipe::notifyTimeout`), which also publishes resource "CCPipe" and registers the service; the factories never call
it, and `CCDataPipe::enqueueBlob` dereferences that timer without a null check. Apple's
`AppleBCMWLANBusInterfacePCIe::createCrashTracerLogger` ends its setup with exactly the missing call —
`CCPipe::startPipe`, virtual at vtable slot +0x868. Fixed in `kexts/itlmt7925Native`: `ccPipeStartPipe()` (raw slot call,
documented in `corecapture_min.h`) now runs on both pipes right where Apple runs it, plus a `ctl:faultPipe=<0|1>` start
trace. Full walk-through with the 25G241 disassembly:
[`docs/native-wifi-results/20261017-panic-corecapture/`](../native-wifi-results/20261017-panic-corecapture/README.md).
Installed 2026-10-17 11:03 (Linux, no reboot yet): `build-kexts` run 39000943950 on `bff6b30` →
`/boot/EFI/OC/Kexts/itlmt7925Native.kext`, sha256 `7ddc713b…` (the IE-cap build it replaces is kept as
`Kexts-backup/itlmt7925Native.kext.20261017-110334`, sha256 `88499c27…`). Next boot: `ioreg -l | grep itlmt_native_trace`
must show `ctl:faultPipe=1`, and ≥5 minutes of Wi-Fi (incl. scans) must pass without a panic.

### 2026-10-17 (round 27): the pipe fix held, the link died 60 s in — the missed-beacon monitor needed event 0x27

The pipe-start boot (11:55) did not panic at the pipe; instead the link came up, worked, and **dropped ~60 s after every
join** (`link_off`, `WiFiAgent: link recovery started`) with the family's `missed beacons timeout` fault report — and the
fault report's core capture made `corecaptured` segfault, so every boot had a `corecaptured-*.ips` ~80 s in. Root cause:
`WCLNetManager::assocTimerAction` declares the beacons missed when two timestamps (`ctx+0x150`/`ctx+0x158`) are both
older than 60 s, and `ctx+0x158` is only refreshed by `WCLNetManager::handleLqmUpdate` — the handler for **driver event
0x27** (`apple80211_lqm_event_data`, 0x1dc bytes, exactly what `AppleBCMWLANCore::postLQMEvent` sends). This driver never
posted it. Full walk-through with the 25G241 disassembly (dispatch table, gates, fault path):
[`docs/native-wifi-results/20261017-lqm-beacon-monitor/`](../native-wifi-results/20261017-lqm-beacon-monitor/README.md).

Fixed in this build (both kexts rebuilt):

* core: `tgtBcnCount` (beacons heard from the connected BSS) in `ItlNativeStatus.beaconCount`;
* native: `postLqmUpdate()` posts event 0x27 once a second while the link is up, carrying the real beacon counter in the
  fields the handler gates on (`+0x14/+0x1c/+0x24/+0x28`, flags `+0x1d8/+0x1d9/+0x30`); trace `wcl:lqm post beacons=N delta=D`;
* core: the **scan list now covers 2.4 GHz 1–13 and the full 5 GHz set incl. DFS 52–64 / 100–144** (the domain always
  allowed them, the scan never visited them — APs on a DFS channel, e.g. a 5 GHz >400 Mb/s network whose phone sees it
  and this Mac never did, could not appear). `itlmt7925Native`'s reported supported-channel list mirrors it.

Test checklist for the next boot (stage b):

1. `ioreg -l | grep itlmt_native_trace` — `wcl:lqm post beacons=N delta=D` with N growing; `ctl:faultPipe=1` still there.
2. Idle ≥2 minutes on the link: no `link_off` / `link recovery` in `log show --last boot` (previously guaranteed at ~60 s),
   no `missed beacons` fault, no new `corecaptured-*.ips`.
3. Wi-Fi menu: a network on a DFS channel (the "Kefoff Coffee" 5 GHz case) should now be listed; `wdutil scan` welcome.
4. Still no panic; the usual trace lines (`scan:delivered`, `dp:` counters) unchanged.
