# Roadmap: AWDL / AirDrop on the native MT7925 driver

Status 2026-10-17: **phase 2 code landed** (virtual interface + ioctl, behind `itlmt_awdl=1`; test tool ready). Phase 0
(research) and phase 1 (observation) completed on 2026-10-17 — see "Round 2026-10-17" at the end for the 25G241
disassembly, the Family entry points and the wifip2pd finding. This file records what was found, what is unknown (marked
"chưa xác định"), and the phase plan. Nothing here is promised. Decision taken with the user on 2026-10-14: implement real
AWDL in the driver (not the `BrowseAllInterfaces` shortcut).

Branch note (2026-10-17): the work lives on `awdl-tahoe` (worktree `.claude/worktrees/awdl`), cut from `tahoe/wifi` — main
is 15 commits behind and does not carry the Wi-Fi fixes this code builds on. Same rules as before: new files, boot-arg
gated, merged by pull request, never on the Wi-Fi test branch.

## 0. How this work stays out of the way (agreed 2026-10-14)

The native Wi-Fi front end is merged into `main` and under test. AWDL is a **separate workstream** and must not disturb it:

* AWDL work lives on its own branch cut from `main` (`awdl-*`), never on the Wi-Fi test branch, and is merged by pull request.
* New code goes into **new files** (`kexts/itlmt7925Native/itlmt7925_awdl*.cpp`, `docs/awdl/`, `tools/awdl_*`). Changes to the
  existing core / front end files are limited to a hook and are kept small, so they merge cleanly with the Wi-Fi fixes.
* Everything AWDL is behind its own boot-arg (`itlmt_awdl=1`, off by default). With the boot-arg absent the code paths are not
  entered: the verified Wi-Fi behaviour (33-41 MB/s, A-MSDU off) is unchanged.
* Phases 0 and 1 do not touch the data path at all (read-only research, then log-only observation).
* The EFI / OpenCore is not rebuilt for this: kext changes ship in a kext-only release (`kext-v*`, see
  [WIFI-DRIVERS.md](WIFI-DRIVERS.md)).

## 1. Goal and definition of done

* AirDrop between this machine and an iPhone / Mac works in both directions with the Wi-Fi connection kept.
* `awdl0` exists, has an IPv6 link-local address, and `sharingd` browses and serves `_airdrop._tcp` over it.
* Clean-room: no OWL / OpenDrop / opendrop-awdl source is copied (GPL). Protocol facts come from the published papers and from
  read-only inspection of Apple's 24H32 collection, like the rest of the native driver.

## 2. What AirDrop needs (stack, top to bottom)

| Layer | Piece | State on this machine |
|---|---|---|
| UI / daemon | `sharingd`, `NetworkBrowser`; AirDrop over Bonjour `_airdrop._tcp`, HTTPS (port 8770: /Discover /Ask /Upload) | present, idle |
| Trigger | A BLE advertisement from the sender wakes AWDL on the receiver (an iPhone only starts AWDL after it) | Bluetooth works as a controller ([BLUETOOTH.md](BLUETOOTH.md)); BLE scan filter offload `0x1812` fails; effect on AirDrop: chưa xác định |
| Link | AWDL: action frames (PSF, MIF) with Apple OUI TLVs, election, time synchronisation, availability windows, channel hopping over social channels 6 / 44 / 149 | **absent**: no `awdl0`, `getAWDL_RSDB_CAPS` answers Unsupported, no virtual interface |
| Data path | AWDL data frames carrying IPv6 (link-local) | absent |
| Radio | Two logical interfaces on one radio: infrastructure station on the AP channel plus time slices on the social channels | MT7925 firmware has no AWDL; ROC (remain on channel) is already used by the core for join |

## 3. Findings in the 24H32 collection (read-only)

* Interface name: `awdl0` appears in the family; interface is an `IO80211VirtualInterface` handed to the controller with
  `IO80211Controller::setAwdlInterface(IO80211VirtualInterface*)` / `getAwdlInterface()`.
* Host side is Apple's, not ours: `IO80211AWDLPeerManager` (945 symbols), `IO80211AWDLPeer`, `IO80211AWDLMulticastPeer`,
  `IO80211P2PSupervisor` (`requestAWDLEnable`, `setAWDLEnable/Disable`, `setConfiguredAWDLChanSequence`, `awdlReset`, NAN
  channel-sequence adoption), `IO80211VirtualInterface::createPeerManager` -> `IO80211AWDLPeerManager::withInterface(iface,
  ether_addr*)`. So the family already runs peer database, service requests, statistics and the peer-manager timers once it
  has a virtual interface with a MAC.
* Firmware side is the driver's: the family forwards about 100 `apple80211` ioctls `getAWDL_* / setAWDL_*` to the controller
  (static handlers `setAWDL_CTL`, `setAWDL_SYNC_PARAMS`, ...). Apple's reference driver (`AppleBCMWLANProximityInterface`,
  57 symbols) turns them into firmware commands: sync state and enable, election id / metric / params / counts / RSSI
  thresholds, master channel, secondary master channel, social time slots, synchronisation channel sequence
  (`buildAWDLChanSequence`, `buildChanSequenceCommand`), presence mode, availability window alignment with AP beacons, guard
  time, min rate, AF TX mode, encryption keys / type, peer traffic registration, BT-LE state / sync params, OOB requests,
  DFSP / UCSA config, statistics. Which of these a minimal peer needs: chưa xác định (Phase 1 measures it).
* Two implementation models exist in the family: Broadcom firmware executes the protocol (sync, election, hopping) and the
  host only configures it. On MT7925 the host would have to execute it: the ioctls then become configuration of our own state
  machine.
* The native driver today: `itlmt7925_iface_stubs.inc` only has `getAWDL_RSDB_CAPS` (slot 489, Unsupported); the AWDL ioctl
  numbers: the allowed set in `commandAllowed()` (`itlmt7925_wifi.cpp`) contains no AWDL command, so any that arrives is
  refused. The call recorder (`itlmt_native_calls`) logs every request including refused ones; the boot checked on 2026-10-14
  was not exercised with AirDrop open, so it holds no AWDL command yet. Interface roles in use: 1 (primary). The role /
  creation path of the virtual interface in Apple's driver (class, role value, registration call): chưa xác định.

## 4. Prior art and what it proves

* Seemoo Lab (MobiCom 2018 "One Billion Apples' Secret Sauce", USENIX Security 2019 "A Billion Open Interfaces for Eve and
  Mallory"): AWDL builds on 802.11 with election, synchronisation and channel hopping on top; IPv6 data path. These papers are
  the protocol reference (frame formats, TLV list, timing). Full text not yet read: the fetch timed out on this machine; fetching
  them is the first Phase 0 task. No numbers are quoted here until read.
* OWL (user space, Linux/macOS): static election values (slave or winner), fixed channel sequence, monitor mode + injection,
  no concurrent AP connection in its own design.
* A community project reports **MT7925 working in "shared" mode on Linux** (Wi-Fi stays connected, AP must be on channel 6,
  44 or 149, station handles ACKs, TX about 490 kB/s because injected frames leave at most about every 2.5 ms, RX about
  1.3 MB/s). That is evidence the radio can do it with host-driven frames; it also shows the throughput ceiling of a host-timed
  approach and the channel restriction.
* An Apple device only starts AWDL and the AirDrop server after a BLE advertisement from the peer; receiving from an iPhone
  that is "Everyone for 10 minutes" needs that wake-up path as well.

## 5. Constraints specific to this project

* The AP channel here is not a social channel (observed ch 40, 80 MHz). Concurrent operation means time-slicing the one radio
  between the AP channel and social channels (ROC / channel contexts in firmware): chưa xác định how much the firmware allows
  and what it does to the infrastructure link (TX stall, BA state, power save).
* Timing: AWDL windows are in TU (1024 us); host timers (IOTimerEventSource / thread sleep) jitter by milliseconds. The firmware
  TSF / ROC grant events are the only trustworthy clock available.
* Frames: the core can already build and send management and data frames through the TX path (`m3Hdr`, `m3Tx`) and parse raw
  RX; AWDL needs action frames to the broadcast address with a different BSSID and no association: chưa xác định whether the
  firmware accepts them without a station record (needs an own-MAC / BSS entry, probably a second OMAC).
* Privacy: AirDrop visibility is user-controlled (Contacts Only / Everyone). Nothing in the driver should advertise by default
  before the user enables it.
* Wi-Fi performance must not regress: slicing costs airtime; the AWDL cluster should be armed only while AirDrop is open
  (family `requestAWDLEnable`), not permanently.

## 6. Phases

Each phase ends with one reboot and a fixed list of things to read, per the one-check-per-boot rule.

### Phase 0 - complete the research (no reboot)

* [ ] Read the two Seemoo papers and record frame formats and timing here (numbers, TLV list, election rules, data header).
* [ ] From 24H32 disassembly: how the virtual interface is created and registered (class, role, who calls `setAwdlInterface`),
      what the family requires from the interface before `createPeerManager` runs, and the apple80211 structs of the ioctls that
      a minimal peer needs (layouts only from the binary, no guessing).
* [ ] Which Bluetooth events / properties wake AWDL on the Mac side and whether our BT path delivers them.
* [ ] Check what `sharingd` does when there is no `awdl0` (log lines) so Phase 1 knows what to look for.

### Phase 1 - observe (log only, one reboot)

Free first step, no reboot: open Finder > AirDrop (set "Everyone for 10 Minutes"), wait a minute, read `itlmt_native_calls` and
`itlmt_native_trace_tail` for commands that are not in the recorded set above and for `sharingd` errors. Anything new is an
AWDL-side request.

* [ ] Allow and record (`itlmt_native_calls`) every `getAWDL_* / setAWDL_*` ioctl number and size the family sends when AirDrop is
      opened in Finder; answer all with the current Unsupported / success-without-effect so nothing changes.
* [ ] Exit: a table of ioctls actually issued, in order, with payload sizes. Decides the minimal set for Phase 2.

### Phase 2 - virtual interface, no RF (one or two reboots)

* [ ] Create the AWDL virtual interface from the native kext with its own locally administered MAC; the family builds its
      peer manager; `awdl0` shows up with an IPv6 link-local address.
* [ ] Answer the minimal ioctl set with a state machine that is only bookkeeping (enable / disable, config echo).
* [ ] Exit: `ifconfig awdl0` present, no kernel panic on enable / disable cycles, Wi-Fi unaffected (`itlmt_rx_received` keeps
      growing, throughput equal to baseline).

### Phase 3 - passive receive (RF, receive only)

* [ ] Hop to a social channel with ROC while associated, capture action frames, parse headers and TLVs (read only, no
      transmission). Record whether an iPhone with AirDrop open is heard, and how long the infrastructure link is blind.
* [ ] Exit: PSF / MIF from a real device decoded in a property log; infrastructure link survives the slicing.

### Phase 4 - synchronise and announce

* [ ] Transmit PSF / MIF as a slave of a heard master (or as master with static election values), keep availability windows,
      return to the AP channel between slices.
* [ ] Exit: the peer lists this machine in its AWDL peer database / the Mac's `awdl0` neighbour table shows the peer.

### Phase 5 - data path and AirDrop

* [ ] AWDL data encapsulation both ways, IPv6 neighbour discovery, `_airdrop._tcp` over `awdl0`, TCP to the AirDrop port.
* [ ] Exit: send and receive one file with an iPhone; measure throughput (target at least the 0.5 MB/s class seen elsewhere).

### Phase 6 - hardening

* [ ] Arm AWDL only while AirDrop needs it; release the radio cleanly; sleep / wake; roam while AWDL is up; multi-peer.

## 7. Risks

| Risk | Effect | Mitigation |
|---|---|---|
| Firmware refuses frames outside an association / BSS, or slicing breaks the link | Phase 3 / 4 blocked | Phase 3 is receive-only and reversible; second OMAC / virtual BSS test before Phase 4 |
| Apple's private ABI of the AWDL interface is larger than the ioctl list suggests | Phase 2 cost grows | Phase 0 / 1 measure it before any code |
| Host timing too coarse for availability windows | Peers drop sync | Use firmware ROC / TSF events, keep our own windows slightly wider (OWL-style guard) |
| BLE wake-up does not reach the Mac side on a non-Apple controller | Receive from iPhone does not start | Test with a Mac peer first (no BLE trigger needed when AWDL is already up on the peer) |
| Reboot-per-test cost | Slow | Batch: Phase 1 logs everything in one boot |

## 8. Wi-Fi improvement backlog (measured 2026-10-14, level 6, ch 40 / 80 MHz, through Cloudflare WARP)

* [x] Remeasured without WARP: about 0.5 Mb/s against 180 Mb/s on a phone of the same network; cause found, the 64-frame RX
      ring dropped 9.8 % of frames (see "Speed measurements" and "Round 24" in [TEST-NATIVE-WIFI.md](TEST-NATIVE-WIFI.md)). Fix
      installed, result after the next reboot.
* [ ] Firmware retry ratio about 0.8 per TX header at level 6 (`txf=..` in `stat-log`): check rate adaptation (STA_REC_RA) inputs
      and whether the retries are probing or loss.
* [ ] RX reorder timeouts about 0.8 % (`reo=` timeout / late fields): holes that never fill; compare BA scoreboard handling.
* [ ] First join after boot can end `auth-fail` (4 authentication frames unanswered although frames were received).
* [ ] Wi-Fi BSD name changes between boots (`en2`, `en4`, `en5`); default route stays on the previous service until the user
      reorders services.
* [ ] Scan: more than one pass per channel at long dwell for 5 GHz DFS channels; hidden SSIDs.

## 9. Round 2026-10-17: phase 0/1 findings and the phase 2 code (all addresses 25G241)

### 9.1 The Family's virtual-interface path (disassembly)

* Userland (wifip2pd) sends `APPLE80211_IOC_VIRTUAL_IF_CREATE` (0x5e) with an `apple80211_virt_if_create_data`
  (`{u32 version; u8 mac[6]; u16 unk1; u32 role; u8 bsd_name[15]}`, 0x1f bytes packed; the request length is clamped to 0x20).
  It arrives through the IO80211 userclient at `apple80211RouteExternal` (0xffffff800236cd2e), dispatch table for code
  0x802869c8 at 0xffffff8002479060, entry `setVirtualInterfaceCreate` (0xffffff8002357f33) — which first offers the request
  to the WCL layer (`sendIOUCToWcl(0x802869c8, 0x5e, buf, 0x20, &flag)`; only `flag == 0` or the sentinel 0xe082280f falls
  through) — then calls `apple80211setVIRTUAL_IF_CREATE` (0xffffff8002268494): `iface->isCommandProhibited(0x5e)`
  (slot 0xcc8, `IO80211SkywalkInterface::isCommandProhibited` 0xffffff80022f9bce forwards to the controller's
  `isCommandProhibited`, i.e. **our gate**), then the protocol slot 558 `setVIRTUAL_IF_CREATE` (vptr + 0x1160).
* Apple's implementation (`AppleBCMWLANInfraProtocol` thunk 0xffffff80015be8fa -> core vtable +0x1328 ->
  `AppleBCMWLANCore::setVIRTUAL_IF_CREATE` 0xffffff80016788f4) dispatches by **role**: 6 = AWDL/proximity
  (`createProxInterface` 0xffffff800165dcbe), 7 = APSTA (`AppleBCMWLANIO80211APSTAInterface::withOptions`), 8/9/10 = NAN.
  For role 6 it instantiates `AppleBCMWLANProximityInterface` (an `IO80211AWDLProtocol : IO80211VirtualInterface`
  subclass; factory `withOptions` 0xffffff80017159e6, vtable `__ZTV30AppleBCMWLANProximityInterface`), fills a
  `RegistrationInfo` (0x130 bytes: +0xc = 3, +0x14 = 2, +0x24 = 0x8000000080, +0x30 = name pointer "awdl", +0x3c = 0x40
  headroom, +0x40 = 4|6, +0x108 = MAC) and calls its `start(core, &info)` (0xffffff8001729376), which registers the ifnet
  with `IOSkywalkEthernetInterface::registerEthernetInterface(info, queues, n, txPool, rxPool, flags)`
  (0xffffff8002b10a84) and wires the core's queue objects.
* The **generic** path the Family itself provides: `IO80211Controller::createVirtualInterface` (0xffffff800229612e, role 7
  only, allocates `IO80211VirtualInterface::gMetaClass` at 0xffffff800248e478), `attachVirtualInterface`
  (0xffffff80022960aa: create -> `attach(controller)` -> `registerService(0)`), `setAwdlInterface`/`getAwdlInterface`
  (0xffffff8002299c24 / 0xffffff8002293256, store/read `[this+0x120]+0x190`; **non-virtual**, added to the generated
  controller header). `IO80211VirtualInterface::createPeerManager` (slot 355) maps role 6 to
  `IO80211AWDLPeerManager::withInterface` (0xffffff80021c14bc), which creates the `IO80211P2PSupervisor`
  (0xffffff80023904ee) — the whole host-side AWDL stack. `isPeerToPeerInterface` (0xffffff800233040a) = roles 6, 8, 9, 10.
  The generic class takes the default BSD prefix ("en", `IOSkywalkEthernetInterface::getBSDNamePrefix` 0xffffff8002b1231a);
  only the Broadcom subclass returns "awdl" — hence the driver-side subclass in 9.2. Slot 490 is `___cxa_pure_virtual` in
  both `IO80211VirtualInterface` and `IO80211AWDLProtocol` (implemented by the Broadcom subclass).
* The Family builds the BSD name from the registry properties `IOInterfaceNamePrefix`/`IOInterfaceUnit`, which the
  registration path sets from `getBSDNamePrefix()` — visible on the primary interface today (`IOInterfaceNamePrefix = en`,
  `IOInterfaceUnit = 5`). A subclass returning "awdl" therefore yields `awdl0`.

### 9.2 Phase 2 code (this branch)

* `kexts/itlmt7925Native/itlmt7925_awdl.{h,cpp}`: `itlmt7925AwdlInterface : IO80211VirtualInterface` (overrides
  `getBSDNamePrefix` -> "awdl" and the pure slot 490) plus `itlmt7925WifiInterface::setVIRTUAL_IF_CREATE` (slot 558):
  alloc -> `init(ctl, mac, 6, "awdl")` -> `attach(ctl)` -> pool + [TxSubmission, TxCompletion, RxCompletion] queues ->
  `RegistrationInfo` filled like `createProxInterface` -> `registerEthernetInterface` -> `registerService` ->
  `ctl->setAwdlInterface(vif)`; answers the BSD name back. Role 6 only; 7-10 stay unsupported for now.
* Gated by the boot-arg `itlmt_awdl=1` (off by default; the ioctl is also refused at the gate without it).
* `tools/awdl/vif_create_test.m`: sends ioctl 0x5e itself (Apple80211Open/Bind/RawSet through the private framework) to
  exercise the handler without wifip2pd; see §9.5 for the 25G241 calling ABI it bakes in.
* Generated ABI additions (tools/gen_io80211_header.py + tools/io80211_abi.py): new slot-exact header
  `kexts/itlmt7925/io80211/IO80211VirtualInterface.h` (506 slots, checker-clean; the unnamed pure slot 490 gets a
  placeholder so the layout stays exact), `registerEthernetInterface` on IOSkywalkEthernetInterface, and
  `setAwdlInterface`/`getAwdlInterface` on IO80211Controller.

### 9.3 Phase 1 observation: wifip2pd never sends the ioctl (its own gate)

* On every boot wifip2pd (the P2P daemon, `/usr/libexec/wifip2pd`, imports `Apple80211RawGet/RawSet`) is asked by airportd
  (XPC, `com.apple.awdl:xpc`) for an AWDL interface and answers:
  `No AWDL interface found. Creating AWDL interface` -> `Cannot create AWDL interface because the device is missing the
  capability` -> `Failed to create interface AWDL on en5 with error <Apple80211Error Operation Not Supported>`. The ioctl
  never reaches the driver: `itlmt_native_calls` holds no 0x5e (and no AWDL-range ioctl 0x74-0xe1) on any boot.
* The capability model is built in userland (CoreP2P `WiFiDriverCapabilities`: supportsAWDL...); it is **chưa xác định**
  which query feeds it. This is why phase 2 is tested with the tool and why the driver-side handler matters: once `awdl0`
  exists, wifip2pd's "No AWDL interface found" path is not taken.

### 9.4 Next

1. Reboot with `itlmt_awdl=1` (config.plist boot-args updated 2026-10-17; NVRAM picks it up at boot through OpenCore
   WriteFlash) and run `vif_create_test`: expect `RawSet(0x5e ...) rc=0 bsd_name='awdl0'`, `ifconfig awdl0` present,
   `awdl:vif up bsd=awdl0` in `itlmt_native_trace`, no panic, Wi-Fi unaffected.
2. Then check whether wifip2pd adopts the existing interface (it should stop trying to create one) and start recording the
   AWDL ioctls it sends once the peer manager exists (phase 3 groundwork).
3. Phase 3+ per section 6: channel slicing (ROC), action frames (PSF/MIF), then the data path.

### 9.5 The 2026-10-17 panics: the virtual interface never ran `start()` (fixed 2026-10-18, HW test pending)

The first `vif_create_test` run with `itlmt_awdl=1` reached the handler, built and registered the interface, answered the
ioctl - and then the machine panicked twice on the first BSD attach
(`/Library/Logs/DiagnosticReports/Kernel-2026-10-17-163303.panic`, `…-165042.panic`):
`IO80211VirtualInterface::attachToBpf` (+0x37) dereferences `getController()->[0x120]` and the register held 0
(CR2 = 0x120). `getController()` (vtable slot 375) returns the controller stored at ivars+0x30 - and the only code that
stores it there is `IO80211SkywalkInterface::start` (0xffffff80022f5792, store at 0x22f583f). The phase 2 code went
straight from `attach` to `registerEthernetInterface`, so `attachToBpf` - which runs from the BSD client's start
(`registerNetworkInterface` -> nexus -> `prepareBSDInterface`) - found a NULL controller.

The fix mirrors what Apple's own interfaces do (all offsets 25G241; the same sequence is what the working infra
interface, `itlmt7925_iface.cpp`, already used):

1. `deferBSDAttach(true)` (slot 297): sets `IODeferBSDAttach`, so `IOSkywalkNetworkBSDClient::start` (0x2aff562, defer
   check at 0x2aff6ae) returns false and the BSD client re-probes later; this also closes the race with the config thread.
2. `start(ctl)`: stores the controller at ivars+0x30 (`IO80211VirtualInterface::start` ->
   `IO80211SkywalkInterface::start`; slot 375 = `getController` reads it back), registers the ifnet, and runs
   `IOService::start` along the way - it must be the single start call ("Calling start twice in a row" otherwise).
3. `registerAwdlInterface`: `RegistrationInfo` filled like `createProxInterface` (0x165dcbe) plus `+0x38 = 0` - the unit
   `registerNetworkInterface` turns into the `IOInterfaceUnit` property (it only sets it when the value is >= 0 and the
   BSD client needs it to build its name); unit 0 -> `awdl0`.
4. `registerService(kIOServiceAsynchronous)` + `setRunningState(false)` (slot 297's neighbours; the pattern at the tail of
   the prox interface's start, 0x1729825 / 0x1729838, and of `setupDriver`).
5. `ctl->setAwdlInterface(vif)`, then `deferBSDAttach(false)`: the BSD client re-probes now that the controller is in
   place and produces `awdl0`.
6. The BSD name is built during that asynchronous re-probe, so `getBSDName()` may still be empty when the ioctl answers;
   the handler falls back to `awdl0` (prefix "awdl", unit 0).

`tools/awdl/vif_create_test.m` (the Obj-C rewrite; 25G241 calling ABI: `Apple80211BindToInterfaceWithService` wants
(ref, service, name) and `Apple80211RawSet` takes (ref, apple80211req*), not the classic (ref, cmd, data, len)) is the
tool that exercises this. After the next boot: `rc=0 bsd_name='awdl0'`, no panic, `ifconfig awdl0` present,
`awdl:vif started` then `awdl:vif up bsd=awdl0` in `itlmt_native_trace`.

## 10. Round 2026-10-19: phase 2 verified on hardware, wifip2pd adopts the interface, the AWDL protocol class

### 10.1 The phase 2 test passed (no panic)

`./vif_create_test en5` on the boot with `itlmt_awdl=1`: `BindToInterfaceWithService(service=0x1803, en5) rc=0` +
`RawSet(0x5e VIRTUAL_IF_CREATE, role=6) rc=0 bsd_name='awdl0'`, no administrator rights needed. `ifconfig awdl0`:
`flags=8843<UP,BROADCAST,RUNNING,SIMPLEX,MULTICAST> mtu 1484`, MAC `de:56:7b:34:81:d4` (primary + locally-administered
bit + last byte flipped), `inet6 fe80::dc56:7bff:fe34:81d4%awdl0`. `itlmt_native_trace`: `awdl:vif started`,
`awdl:vif up bsd=awdl0`. No panic, Wi-Fi unaffected (ping 2.9 ms, `wifi-state=connected`). The 2026-10-17 panics are
gone.

### 10.2 wifip2pd adopts the interface and maps the rings

Right after the create (log 16:36:03): `(IO80211) Apple80211BindToInterfaceWithService: Sanity test passed` ->
`Found new interface awdl0 with role AWDL` -> `Created AWDLInterface<P2PController<AppleIO80211Driver>>[awdl0]<de:56:7b:34:81:d4>`
-> `Successfully updated awdl0 link state to Link Up` -> `(IO80211) _createMemoryMappings: ringBuffer[0x102f80000]
ringSize[0x4b000], ringState[0x102ac0000] ringSize[0x1000]` -> then the normal power/eligibility bring-up
(`Registering for Power State changes from wifid`, `OS Eligibility: 5G/160 answer eligible`). The one failure is
`APPLE80211_IOC_COMPANION_SKYWALK_IF_CREATE` (0x125, len 24) -> `return 58/0x3a` ->
`Failed to create the companion low latency interface for AWDL: <WiFiP2PError Unavailable>` - and it is **non-fatal**:
the daemon continues and the interface stays up.

### 10.3 What the AWDL ioctls and the peer manager need (25G241 disassembly)

* `apple80211setCOMPANION_SKYWALK_IF_CREATE(controller, iface, uc, req)` (0xffffff800228b4b8) first offers the request to
  the userland WCL (`IO80211Glue::sendIOUCToWcl` when `[controller+0xd8] != NULL`); on this Intel/kext path that is NULL
  and it tail-calls `apple80211setCOMPANION_SKYWALK_IF_CREATE(iface, req)` (0xffffff800226a32f), which calls slot
  `[vptr+0xcc8]` with the ioctl number, then `safeMetaCast(iface, IO80211AWDLProtocol::gMetaClass)` and calls slot 562
  (`0x1180` from the vptr = dump slot 562). So **the vif must be an `IO80211AWDLProtocol`** or every AWDL ioctl answers
  `0xe082280e` before reaching the driver.
* The `apple80211{get,set}AWDL_*` dispatchers (e.g. `getAWDL_SYNC_ENABLED` 0xffffff800227bc2f) do NOT cast the vif: they
  read the peer manager from `[iface+0x120]+0x28`, cast THAT to `IO80211AWDLPeerManager` and call its methods. The peer
  manager is created by the Family's `IO80211VirtualInterface::createPeerManager` (0xffffff80023308c2, virtual slot 355):
  for role 6 it runs `IO80211AWDLPeerManager::withInterface(vif, mac)` (role read from `[vif+0x120]+0x58`, MAC from
  `getMacAddress`). That is the Family's own code path, so it runs for this driver too once the vif exists.
* `AppleBCMWLANProximityInterface::setCOMPANION_SKYWALK_IF_CREATE` (0xffffff8001722ef2) reads `action` at req+4
  (0 = destroy, 1 = create), builds `apple80211SkywalkIfCreateParams_t {class ptr, MAC, 9, 2}`, calls
  `AppleBCMWLANCore::createSkywalkInterface(&vif->companion, params, vif)`, then
  `companion->setCompanionInterfaceId(vif->getInterfaceId())` and `strncpy(req+8, companion->getBSDName(), 0x10)`.
  `apple80211_companion_skywalk_if_create` is 24 bytes: `u32 version; u32 action; char bsd_name[16]`.
* The AWDL protocol class: `IO80211AWDLProtocol : IO80211VirtualInterface`, 571 slots, 0x130 bytes (same ivars), 63 new
  pure virtuals (slots 507..569) named from `AppleBCMWLANProximityInterface`: getSSID/CHANNEL/BSSID/STATE, the
  AWDL_SYNC_* / AWDL_ELECTION_* / AWDL_MASTER_CHANNEL / AWDL_SYNC_FRAME_TEMPLATE / PSF_DWELL / LLW_PARAMS families, and
  `setCOMPANION_SKYWALK_IF_CREATE` at slot 562. Slot 490 (pure in both classes) is the Broadcom `setMacAddress(ether_addr&)`.

### 10.4 Code in this round

* `tools/io80211_abi.py`: `IO80211AWDLProtocol` added (parent IO80211VirtualInterface, size 0x130,
  children AppleBCMWLANProximityInterface) + the IOReturn rule for its methods; dumps for 25G241
  (`IO80211AWDLProtocol`, `AppleBCMWLANProximityInterface`, MetaClass) added; `tools/kc_extract.py` extracts one fileset
  entry from the KC for disassemblers.
* `kexts/itlmt7925/io80211/IO80211AWDLProtocol.h`: generated, layout-checked (`io80211check: ok`).
* `itlmt7925AwdlInterface` now derives from `IO80211AWDLProtocol`; all 63 protocol slots are implemented as tracing stubs
  (`IOLog("itlmt7925: awdl proto %s (stub)")` + `kIOReturnUnsupported`, 48-line budget) and
  `setCOMPANION_SKYWALK_IF_CREATE` logs the action and answers unsupported (non-fatal for wifip2pd). The kernel log after
  the reboot will show which slots the Family and the peer manager actually call - that is the phase 3 to-do list.

### 10.5 Next

1. Reboot, `./vif_create_test en5`, then `log show --last 2m | grep "awdl proto"`: the calls that appear name the slots
   the peer manager drives (expect `setAWDL_SYNC_ENABLED`, `setAWDL_SYNC_PARAMS`, `setAWDL_SYNCHRONIZATION_CHANNEL_SEQUENCE`,
   `setPSF_DWELL` once AirDrop/peer discovery starts).
2. Phase 3: implement the channel sequence (ROC slicing) and the PSF/action-frame TX those slots need; the LLW companion
   interface (slot 562) afterwards.

### 10.6 Round 2026-10-19 (evening): the AWDL ioctls never left the driver - `ret=58` is this driver's own gate

AirDrop-off trace on the boot with the AWDL protocol class (`./vif_create_test en5`, then the kernel log):

* `(IO80211Family) com.apple.p2p.awdl0:` lines prove the **Family's AWDL peer manager runs for this vif**:
  `IO80211AWDLPeerManager::updateLocalRequests`, `::interfaceStateChange`, `isScanDisallowedByAwdl`,
  `IO80211PeerManager::setScanningState` (source ScanManagerFamily / DriverInternalScanDone). So
  `IO80211VirtualInterface::createPeerManager` (slot 355) did run for role 6.
* `IO80211AWDLPeerManager::getAwdlChannelSequence[28260] : unable to get AWDL channel sequence ret=58` - the peer
  manager asks the driver through `apple80211RouteInternal(0xc02869c9, 0x81, iface, out)`, which indexes the Family's
  route table at `0xffffff800247cea0` (get) / `0xffffff800247e0f0` (set) by `ioctl - 1`; entry 0x81 is
  `apple80211getAWDL_SYNCHRONIZATION_CHANNEL_SEQUENCE(iface, out)` (0xffffff8002263a45), whose first step is
  `call [vptr + 0xcc8]` = **slot 411 `IO80211SkywalkInterface::isCommandProhibited(int)`** (0xffffff80022f9bce), which
  tail-calls the **controller's** `isCommandProhibited`. Returning non-zero there returns that value to the caller -
  and `ret=58` is exactly `itlmt7925Wifi::isCommandProhibited`'s `kProhibited` (0x3a, itlmt7925_wifi.cpp:127).
* So the whole AWDL ioctl family (channel sequence, sync params, election, PSF dwell, LLW params, companion create
  0x125, OS eligibility 0x23f) was refused by this driver's own allowlist before reaching either the Family's handlers
  or the interface's `IO80211AWDLProtocol` slots. `wifip2pd`'s `Apple80211IOCTLSetWrapper ... return 58/0x0000003a`
  lines are the same gate.
* Fix in this round: `commandAllowed()` now lets the AWDL family through when `itlmt_awdl=1` (the ioctl numbers are the
  route-table indices above: 0x74-0x8b, 0x8f, 0x94-0x97, 0x9b, 0x9e, 0xa2-0xa7, 0xc9-0xe9, 0xf4-0x107, 0x125,
  0x152-0x158, 0x15f, 0x172, 0x1a0, 0x1a1, 0x1b0, 0x1d3, 0x23f). With the boot-arg absent nothing changes.
* The AWDL stub trace now goes through `itlmtTrace(getController(), ...)` (the `itlmt_native_trace` ring, mirrored to
  NVRAM): IOLog from this kext does not reach the unified log on this machine. `nvram -p | grep itlmt-native-trace`
  after the reboot shows `awdl:proto <slot>` / `awdl:companion action=<n>` - i.e. which protocol slots the peer manager
  drives once the gate is open.

### 10.7 Round 2026-10-19 late: the gate was the whole AWDL blocker - the peer manager now drives the protocol slots

Reboot with the 10.6 gate fix (`com.itlmt7925.native` UUID `56A5CD9C-0E15-3C07-8C55-BA309D3B9DA4`), AirDrop on,
`./vif_create_test en5`. The driver's own trace (`nvram -p | grep itlmt-native-trace`) now shows the whole AWDL ioctl
family **allowed** and the interface's protocol slots being called for the first time:

```
ioctl:cmd=75 allowed   ioctl:cmd=7d allowed   ioctl:cmd=97 allowed   ioctl:cmd=7e allowed
ioctl:cmd=a4 allowed   ioctl:cmd=125 allowed  ioctl:cmd=23f allowed  ioctl:cmd=81 allowed
awdl:vif started; awdl:vif up bsd=awdl0
awdl:proto getAWDL_SYNC_ENABLED
awdl:proto setAWDL_BSSID
awdl:proto setAWDL_SYNC_FRAME_TEMPLATE
awdl:proto setAWDL_ELECTION_METRIC
awdl:proto setAWDL_PEER_TRAFFIC_REGISTRATION
awdl:companion action=1 (unsupported)
awdl:proto getAWDL_SYNCHRONIZATION_CHANNEL_SEQUENCE
```

and wifip2pd brings the interface up on its own (`No AWDL interface found. Creating AWDL interface`, link up, IPv6,
mDNS agent, `OS Eligibility: 5G/160 = ENABLED`). `setCOMPANION_SKYWALK_IF_CREATE` now answers the stub's
`kIOReturnUnsupported` instead of the old gate's `0x3a` - proof the ioctl reached the driver.

**The remaining blocker is one slot.** `IO80211AWDLPeerManager`'s enable path (`doEnable` -> `configure`) aborts on the
first unsupported answer, and the first parameter it hands over is the BSSID:

```
IO80211AWDLPeerManager::enable: <awdl0> enable 1 ...
doEnable:2829 Enabling AWDL Interface because of setLinkState... configured = 0
IO80211AWDLPeerManager::configure Configuring AWDL interface
IO80211AWDLPeerManager::initParamsToDefaults RTGConcurrency:1 RTScan:1 RTGSteering:1 ...
IO80211AWDLPeerManager::configure  Unable to set BSSID ret e00002c7
IO80211AWDLPeerManager::configure configure error!! :(
doEnable:2839 ERROR: cannot configure AWDL after enabling interface!! ret=e00002c7 _enabling 1
<awdl0> disable 1 ont 0   -> AWDL DISABLE SET last state 0
```

So this round accepts the configure handshake: `awdlAccept()` (slot 540 `setAWDL_BSSID`, 541 `setAWDL_ELECTION_METRIC`,
549 `setAWDL_SYNC_FRAME_TEMPLATE`, 551 `setAWDL_PEER_TRAFFIC_REGISTRATION` and the rest of the parameter setters
536-569) answers `kIOReturnSuccess` and traces the slot, and the four AWDL structs that are public in
`IOKit/80211/apple80211_ioctl.h` are stored/printed (`apple80211_awdl_sync_enabled` {version, unk1, enabled},
`apple80211_awdl_election_metric` {version, metric}, `apple80211_awdl_sync_frame_template` {version, payload_len,
payload}, `apple80211_awdl_peer_traffic_registration` {version, addr, name_len, name[152], active} packed). The
out-of-band request slots (548/557/563) and the LLW/companion path (562/564) still answer unsupported - they expect a
response or a second interface, not just a parameter handshake. No RF work is done by these slots: the point is to let
`configure()` finish so the next missing piece (the channel sequence, then the PSF/ROC path) shows up in the trace.

### 10.8 Round 2026-10-20: the PSF frame reaches the driver - first AWDL transmit path

With the configure handshake in place the Family's AWDL state machine runs end to end: the trace shows the sync frame
template being handed to the driver over and over, and the state dump reports AWDL up with no peers because the radio
never transmits anything:

```
awdl:set SYNC_FRAME_TEMPLATE len=110
awdl:accept setAWDL_SYNC_PARAMS / setAWDL_SYNC_STATE / setAWDL_ELECTION_PARAMS
setSyncFramePeriod::Setting PSF period to 440
AWDLStateDump: AWDL up time: 29 Secs, DE:56:7B:34:81:D4 peers:0, cached:0(0), rtg(0)
AWDLStateDump: PSFDwell Support/Active: 1/0 {0ms 0ms}
IO80211AWDLPeerManager::monitorAWEvents WARNING: Did not get AW start event ...
```

`netstat -I awdl0` = 0 TX / 0 RX: nothing ever leaves the box, which is why a second Mac/iPhone with AirDrop open cannot
see it. The firmware has no AWDL channel sequencing of its own, so the driver has to provide the off-channel slot.

What this round adds (phase 3 transmit half):

* `ItlNativeAwdlSync` (`ITL_NATIVE_AWDL_SYNC`, itl_native_bridge.h) - the native interface hands one complete 802.11 frame
  plus the channel and dwell to the core. `itlmt7925::awdlSubmit()` only copies it into a mailbox under `cmdLock` and sets
  `CMD_AWDL_SYNC`; nothing blocks on the chip in the caller's context (the Family's work queue).
* `itlmt7925::awdlSyncTx()` runs on the link thread next to the scan command: `m3Roc(true, channel)` (UNI_ROC on the AWDL
  channel, bounded to 80 ms of pumping so the AP keeps being serviced), `m3Tx(frame, len, 0, 13, ...)` (management, action,
  fixed OFDM 6 Mb/s, ALT X0 queue), then `m3Roc(false, channel)` back to the infrastructure channel.
* ROC grants are now parsed after link up as well (`rocWant`, set by m3Roc and cleared by the grant or the abort). The old
  early return assumed no ROC event can arrive while associated; off-channel AWDL needs exactly that.
* `setAWDL_SYNC_FRAME_TEMPLATE` (slot 549) queues the frame the Family builds every PSF period (110 bytes on this build,
  social channel 6, 60 ms ROC window). The core service pointer is handed to the vif by the vif-create handler
  (`setNativeCore`).

What to expect on the next boot: `awdl:sync tx queued len=110 rc=0` in the interface trace and `awdl sync: tx ch=6
len=110 ok=1` in the driver log once the link is up (the AWDL TX only runs while associated - the link thread is what
services the command). A second AirDrop device should then start seeing this Mac, even though reception (peer table) still
needs the RX half: routing the AWDL action frames the firmware delivers during the ROC window up to
`IO80211AWDLPeerManager`, plus the missing "AW start event" the peer manager keeps warning about.

### 10.9 Round 2026-10-20 (same boot): the PSF leaves the radio - ROC works while associated

Test after the 10.8 build (core `b155d936`, native `618de933`), `awdl0` created with `~/vif_create_test en5`, then the
AirDrop window closed and reopened (the order matters: the vif must exist *before* the AirDrop session asks for AWDL,
otherwise wifip2pd initialises the interface but never re-runs `doEnable` - the 10:13 boot stalled exactly there, trace
ending at `getAWDL_SYNCHRONIZATION_CHANNEL_SEQUENCE` with `set SYNC_ENABLED` never called).

With that order the configure handshake completes and the new transmit path runs:

```
awdl:set SYNC_FRAME_TEMPLATE len=110
awdl:sync tx queued len=110 rc=0
awdl:accept setAWDL_SYNC_PARAMS / setAWDL_SYNC_STATE / setAWDL_ELECTION_PARAMS
```

and in `m3-log` (the core's own ring, `ioreg -l | grep m3-log`):

```
roc_acquire rc=0 st=0
roc event bss=0 tok=10 status=0
awdl sync: tx ch=6 len=110 ok=1
roc_abort rc=0 st=0
```

That answers the 10.8 open question: **the firmware grants UNI_ROC while the station is associated** (tok 10, 11, 12, ...,
status 0), so the off-channel slot works as implemented - relax-on-`rocWant` was the right change and no infra
disconnect is needed. Nine frames went out this way.

**The finding: the Family does not hand the template over once per period.** It hands it over when it changes (four
times in five minutes here), so the 10.8 note "The Family re-issues this template every sync period, so every call is one
PSF transmission" was wrong: 9 frames in ~5 minutes is nowhere near the 440 ms PSF cadence the peer manager logs
(`setSyncFramePeriod::Setting PSF period to 440`). The other device never saw the Mac because the sync frames were
essentially absent, not because they were malformed.

So the interface now owns the cadence: `setAWDL_SYNC_FRAME_TEMPLATE` copies the bytes (`awdlPsfFrame`, the Family's buffer
is not ours to keep) and `awdlPsfStart()` arms an `IOTimerEventSource` on the interface's work loop; `awdlPsfTick()` hands
one frame to the core every 440 ms with a 30 ms ROC window, and `setAWDL_SYNC_ENABLED=0` cancels the timer (AWDL off must
mean nothing leaves the radio). The immediate on-template transmit is gone: the timer's first tick is the transmit.

Still open after this round: the peer manager's `Did not get AW start event` warning (it wants
`APPLE80211_M_AWDL_AVAILABILITY_WINDOW_START` posted per window; the numeric id has not been confirmed yet - the name table
in the kernel points at 0x4f3 but the spacing of neighbouring ids makes that unverified), and the receive half - routing
received AWDL action frames up to `IO80211AWDLPeerManager` so `peers:` leaves 0 and election can run.

### 10.10 Round 2026-10-20 evening: a real root cause - the template is a TLV blob, not a frame

The 10.9 build runs (timer armed, `awdl:psf armed len=110`, ticks reaching the core), but the trace of the template's first
byte exposed a defect that is worse than the cadence one: the 110 bytes the Family hands over are **not an 802.11 frame**.

```
awdl:psf armed len=110 type=06 sub=0
```

`0x06` is not a frame-control byte - an AWDL action frame would start with `0xd0`. The kernel confirms where it comes from:
`IO80211AWDLPeerManager::updateSyncFrameTemplate` (0xffffff80021dc5b2) builds the buffer with `buildServiceParamTlv`,
`buildAWDLElectionParamsVer2`, `buildAwdlDataPathStateTlv`, `buildEnhDataRateTlv` ... and `buildServiceParamTlv`
(0xffffff80022118a6) starts with `mov byte ptr [rsi], 6` - TLV type 6, little-endian length, then the value. So the payload is
a **TLV blob**, exactly what the Family also feeds into the master indication template (`buildMasterIndicationTemplate`, no
`0xd0`/OUI anywhere in it). On Apple hardware the firmware wraps it: the driver only hands the bytes to the chip.

This driver's firmware has no AWDL support, so the wrapper has to be built by the host before `m3Tx()` - and it was not: the
raw TLV blob went out as an MPDU whose first 24 bytes (TLV types/lengths) were interpreted as addresses. That is why nothing
ever appeared on the other device's AirDrop, while the counters looked healthy (`awdl sync: tx ... ok=1` only means the
firmware accepted the descriptor).

What this round adds:

* The transmit wrapper is **not** guessed. A capture probe in the RX path (`rxParseFrame`, `itlmt7925_m2.cpp`) now looks for
  management Action frames (`fc 0xd0`) in the received buffer, notes whether the Apple OUI `00:25:00` sits at +25 (category
  at +24), and hex-dumps the first 40 bytes of the first four into `m3-log`:
  `awdl af rx len=.. cat=.. apple=1 <hex>`. The frame is only heard while the radio is on the social channel, i.e. inside the
  ROC window, so that window grew from 30 ms to 60 ms for these runs.
* Reading those bytes from a real iPhone/Mac gives the exact header (FC, DA, SA/BSSID, category, OUI, and where the TLV blob
  begins), which is also the format the receive half has to parse. Both directions need the same layout, so the probe is the
  cheapest way to obtain it: it either captures a frame (ground truth immediately) or proves the firmware does not forward
  broadcast action frames at all (then the RX filter, not the parser, is the next suspect).

Once the layout is known the transmit path becomes three lines of wrapping in `awdlSyncTx()` - 802.11 header with the AWDL MAC
(`de:56:7b:34:81:d4`) and the peer manager's BSSID (`00:25:00:ff:94:73`), category, OUI, then `awdlFrame` - and the same
parser routes received frames to the peer manager.

First capture attempt (d8a7d57, core `b614d747`, native `b14c06b4`): four dumps arrived, all `apple=0`, and none of them is
an AWDL frame - the probe accepted any `0xd0` byte inside the received buffer, and data frames (IP payloads, IPv6 multicast
DA `33:33:00:00:00:fb` in one of them) contain that byte too. It also ran with no `awdl0` at all (the vif is recreated per
boot and had not been created), i.e. on the infrastructure channel, so nothing was even looking at the social channel.

The probe is now strict: duration 0, DA broadcast or unicast, TA and BSSID unicast and non-zero (any real 802.11 header
satisfies these, data frames found at a stray `0xd0` almost never do), the dump budget is 10 frames plus every frame that
carries the Apple OUI at +25, and every 25th hit logs a one-line summary so a long run shows whether anything is arriving at
all. Core `e756604c`.

### 10.11 The transmit wrapper, from ground truth (not a guess)

Two facts settled the format, and they agree with each other:

1. The kernel. `IO80211AWDLPeerManager::actionFrameHasCorrectOUI` (0xffffff8002210200) compares three bytes of the frame
   body at fixed offsets: `0x17`, `0xf2`, then `8` - the Apple OUI and the AWDL type, exactly where a vendor-specific action
   frame puts them. `AppleBCMWLANNetAdapter::sendActionFrame` (0xffffff80015c511a) never writes an 802.11 header at all: it
   builds a descriptor (`{addr, addr, len, ...}`) and the firmware frames it. So on Apple hardware the host never sees the
   header, and no amount of kernel reading can produce it.
2. OWL (the open AWDL implementation) has the wire format: `src/frame.h` / `src/tx.c`. The action frame is
   `ieee80211_hdr{fc=0x00d0, dur=0, addr1=dst, addr2=src, addr3=AWDL_BSSID 00:25:00:ff:94:73, seq<<4}` followed by
   `awdl_action{category=0x7f, oui=00:17:f2, type=8, version=0x10 (1.0), subtype=0 (PSF) / 3 (MIF), reserved,
   phy_tx u32, target_tx u32}` and then the TLV blob. PSF is broadcast (`state->dst = ETHER_BROADCAST`), sent every 440 TU
   when following a master - the same 440 ms the Family's log reports.

That is now what the driver builds. `setAWDL_SYNC_FRAME_TEMPLATE` sees the Family's bytes for what they are (TLVs, first
byte a TLV type) and prepends the 40-byte wrapper into `awdlPsfFrame` (broadcast DA, the AWDL interface address as SA, the
AWDL BSSID - `setAWDL_BSSID`'s value when the Family provides one, the standard `00:25:00:ff:94:73` otherwise). The core
stamps the per-transmission fields just before `m3Tx()`: `seq_ctrl` at +22 (incrementing, 12 bits) and the two microsecond
timestamps at +32/+36.

The earlier trace line proves how necessary this was: `awdl:psf armed len=110 type=06` - the first byte was TLV type 6
(`buildServiceParamTlv`), so the previously transmitted MPDUs began with TLV bytes where the receiver expects addresses.
`ok=1` only ever meant "the firmware accepted the descriptor". With the wrapper the frame is 153 bytes
(24 + 16 + 113) and starts with `d0 00 00 00 ff ff ff ff ff ff de 56 7b 34 81 d4 00 25 00 ff 94 73 .. .. 7f 00 17 f2 08 10 00 00`.
The new `awdl:psf armed` line prints the first bytes of exactly that, and the RX probe now looks for `0x7f / 00:17:f2 / 8`
instead of the wrong `00:25:00` it checked before (which is the BSSID OUI, not the action OUI).

Also observed in the same run: the Family re-sends `setAWDL_SYNC_FRAME_TEMPLATE` every few seconds with updated TLVs
(110 -> 112 -> 113 bytes) - i.e. its state machine is alive and the sync parameters are changing (channel sequence, counters),
so the cadence and the content both come from it.

### 10.12 Receive half: action frames go to the Family's peer manager

The transmit half is now correct (`awdl:psf armed tlv=110 frame=150 fc=d0 cat=7f oui=0017f2 type=08 sa=de567b3481d4`,
`awdl sync: tx ch=6 len=150 ok=1`, ROC granted every time), and the other device still shows nothing. That is expected once
the discovery chain is looked at: AirDrop lists a device only after that device's **service** is learned, and services are
exchanged in AWDL action frames (service request / response, MIF). The Family builds them in `IO80211AWDLPeerManager`
(`buildServiceResponseTlvs`, `buildMasterIndicationTemplate`) in reply to frames it receives. With no receive path the peer
list stays empty, so nothing is advertised and nothing shows up - transmit alone can never be enough.

So the frames the radio hears now go where the Family expects them:

* `rxParseFrame` already recognises an AWDL action frame by its header (24-byte 802.11 action frame with `addr3` a unicast
  BSSID, then `0x7f / 00:17:f2 / 8`). Those frames are copied into a four-entry ring (`awdlRxRing`) - single producer, the RX
  thread - and nothing else in the RX path changes.
* The AWDL interface drains the ring once per PSF tick through a new platform function, `itlmt-native-awdl-rx-v1`
  (`ITL_NATIVE_AWDL_RX`), and hands each frame to `IO80211AWDLPeerManager::actionFrameInput`.
* Reaching that method needed two offsets from the KernelCollection, and both are checked at run time: the peer manager is
  `IO80211SkywalkInterface::getPeerManager()`, i.e. `[[this+0x120]+0x28]` (`0xffffff80022f5fa8`), and `actionFrameInput` is
  **virtual slot 73** - 0x238 bytes into the object's vptr once the two vtable header words are accounted for. Before the
  first call the driver verifies that slot 74 is `doEnable` by comparing the distance between the two function pointers
  (`0xffffff80021c5216 - 0xffffff800220e1ae`); a KASLR slide cancels out, and a mismatch means the table is not what this
  code assumes, in which case the frame is dropped and `awdl:rx slot check failed` is traced instead of calling an unknown
  pointer.

The trace tells the two possible outcomes apart on the next run:

* `awdl:rx af len=.. n=.. pm=.. fn=.. sub=..` - frames arrive on the social channel, the peer manager is being fed, and the
  next observable is `IO80211AWDLPeerManager` state in the unified log (peers, election, sync).
* nothing at all - the firmware is not delivering other-BSS management frames to the host while parked on the social channel.
  Then the RX filter (chip side), not the parser, is the next thing to change.

### 10.13 Why nothing was ever received: the RX filter only passed our own BSS

The receive half was wired up (10.12) and still nothing arrived - not one `awdl:rx`, not one `awdl af rx` - while the transmit
half kept running (`psf tick 200 len=153`, `awdl sync: tx ... ok=1`). That rules out the parser and the AWDL channel: the
frames were never handed to the host in the first place.

The vendor driver programs the station's RX filter explicitly. `mt7925_configure_filter` (mt7925/main.c) maps mac80211's
filter flags onto `MT7925_FILTER_ENABLE` (BIT(31)), `MT7925_FILTER_OTHER_BSS` (BIT(6)), `MT7925_FILTER_CONTROL` (BIT(5)) and
sends them with `mt7925_mcu_set_rxfilter()`, i.e. a `MCU_UNI_CMD(BAND_CONFIG)` message whose TLV is
`UNI_BAND_CONFIG_SET_MAC80211_RX_FILTER` (0x0c), value layout `{mode, rsv[3], fif, bit_map, bit_op, pad[51]}`; `mode = 0`
replaces the whole filter with `fif`. This driver never sent that message, so the firmware kept its default - our own BSS
only. Frames from another device (an AWDL action frame carries `addr3 = 00:25:00:ff:94:73`, not our AP's BSSID) were dropped
in the firmware, on the infrastructure channel as much as inside a ROC window. That is also why the probe saw four *data*
frames earlier and never a management one.

`awdlSyncTx()` now programs `fif = BIT(31) | BIT(6)` once per link, right before the first ROC window, and the trace gained a
line that separates the two possible failures from now on:

```
awdl stat: try=.. tx=.. rocfail=.. rocframes=.. bcn=.. af=..
```

`rocframes` counts every frame parsed while a ROC window is open and `bcn` the beacons among them. If `rocframes` grows but
`af` stays 0, the radio is healthy and simply no AWDL peer is on the air; if `rocframes` stays 0, the filter is still not
letting frames through and the next step is the chip-side promiscuous path, not the AWDL code.

### 10.14 The receive half works - but only on the channel we park on

With the RX filter in place (10.13) the counters finally answer the question that had been open for days:

```
rx_filter rc=0 st=0
awdl stat: try=50 tx=49 rocfail=1 rocframes=90 bcn=9 af=0
```

`rocframes` counts every frame parsed while a ROC window is open, `bcn` the beacons among them. Ninety frames in fifty
windows of 60 ms prove the radio really is listening off-channel, the RX ring is delivering, and the parser runs. `af = 0`
then means exactly one thing: **no AWDL action frame was on the air on channel 6** while we were there.

That is not a receive bug. The interface was transmitting (and therefore listening) on channel 6 unconditionally -
`ItlNativeAwdlSync req = { 1, awdlPsfFrame, awdlPsfLen, 6, kAwdlPsfRocMs }` - while `setAWDL_SYNCHRONIZATION_CHANNEL_SEQUENCE`
(slot 542) was answered by `awdlAccept()` and its contents thrown away. Apple's AWDL spreads the sync frame over a channel
sequence (2.4 GHz social channel 6, 5 GHz 44/149), and the Family's `AppleBCMWLANProximityInterface::buildAWDLChanSequence()`
builds that sequence from the struct we were ignoring. A peer whose sync tree sits on 44 or 149 is simply inaudible to a
radio that only ever parks on 6, in both directions.

The setter is now parsed (layout taken from `buildAWDLChanSequence`, 25G241, plus a raw hex trace so a wrong guess is
visible instead of silently parking the radio somewhere odd): master channel first, then the sequence entries at +0x10
(12 bytes each, channel in byte 0), then the default social set {6, 44, 149} as a union. The PSF cadence walks that list
round-robin, one channel per 440 ms period, so every channel is visited about once a second - which is what discovery
needs until the sync tree we hear tells us where the master actually is. `awdl stat` and the AF log now carry the channel,
so the next run attributes every frame to the channel it was heard on:

```
awdl:psf tick 100 len=153 ch=44 rc=0
awdl stat: try=50 tx=49 rocfail=1 rocframes=90 bcn=9 af=0 ch=149
```

Still open: `getAWDL_DEVICE_CAPABILITIES` (slot 523) answers unsupported, so the Family may keep building a 2.4 GHz-only
sequence - the union above is what makes discovery possible in the meantime, and reporting dual-band capabilities properly
is the clean fix once the struct layout is confirmed.

### 10.15 The channel sequence read-back stopped configure before the sync template

The hop change worked as far as it could - `awdl:set CHANSEQ n=8 master=255 hop=6,44,149,0,0` - but nothing followed it:
no `SYNC_FRAME_TEMPLATE`, no `SYNC_ENABLED`, no PSF tick. The trace ring held the whole boot (46 lines), and it ended on

```
awdl:proto getAWDL_SYNCHRONIZATION_CHANNEL_SEQUENCE
```

i.e. the Family sets the sequence and then *reads it back*, and `awdlProto()` answered `kIOReturnUnsupported`. That answer
aborted the configure sequence before the step that hands the driver the sync frame, so the interface had nothing to
transmit and nothing to listen for - the hop list was never used.

The read-back is not a query the driver may fail: the payloads whose layout is not public are now stored verbatim when the
Family sets them and echoed back when it reads them (`set/get AWDL_SYNCHRONIZATION_CHANNEL_SEQUENCE`, `MASTER_CHANNEL`,
`SYNC_STATE`), with a valid default sequence (version 1, one entry, 2.4 GHz ch6) when nothing has been set yet. Echoing is
also the only truthful answer: guessing a layout would hand the caller numbers the radio never used.

The entry layout is confirmed by the raw bytes of that first set - `01 00 00 00 | 00 10 00 03 | 00 ff 00 00 | 01 00 00 00`:
version 1, count 0x10, master 0xff (none), and entry 0 starting at +0x0c with `version = 1`, i.e. `apple80211_channel`
entries at +0x0c (channel in the low byte of +4, band flags at +8), exactly what `buildAWDLChanSequence` reads. The parse
now uses that offset and traces the first three entries with their flags.

### 10.16 What the firmware hands the host inside a ROC window

With the hop in place the trace shows the whole transmit half working on every channel:

```
awdl:psf tick 1 len=150 ch=6 rc=0
awdl:psf tick 2 len=150 ch=44 rc=0
awdl:psf tick 3 len=150 ch=149 rc=0
awdl sync: tx ch=6 len=150 ok=1 / ch=44 ok=1 / ch=149 ok=1
awdl stat: try=100 tx=97 rocfail=3 rocframes=86 bcn=7 af=0 ch=6
```

Still `af = 0`: over 100 periods, ~5 s of listening spread over the three social channels, not one action frame - not
even a non-AWDL one, which a busy 2.4 GHz band normally supplies (802.11v BSS transition frames are everywhere). Two
explanations remain, and they need different fixes:

* the firmware only forwards beacons and data to the host in station mode, so management frames from other devices never
  reach the RX ring at all - the AWDL code cannot fix that, the chip's RX path has to be opened up;
* the ROC grant is real but the radio never actually leaves the AP's channel, so every "off-channel" window is spent
  listening to the infrastructure channel.

`awdl stat` now separates them without another guess: `onch` counts the frames whose RXD3 channel field (p[13]) really is
the parked channel, and `fc` is a class histogram of everything heard inside a window (beacons / probe / action / other
management / data):

```
awdl stat: try=100 tx=97 rocfail=3 rocframes=86 onch=.. bcn=.. af=0 ch=.. fc=../../../../..
```

`onch ≈ rocframes` and `fc` beacons+data only → the radio is switching and the firmware is filtering management frames:
the next step is the firmware sniffer path (`MCU_UNI_CMD(SNIFFER)` / `UNI_SNIFFER_ENABLE`), the only documented way to make
an mt7925 hand every frame to the host.
`onch = 0` → ROC is a no-op on this firmware and the AWDL channel has to be changed the hard way.

### 10.17 Following the reference implementation: the sniffer, not the station RX filter

Everything so far assumed the station path could be made to deliver another device's action frame. It cannot: `10.13` and
`10.16` show beacons and data arriving inside the ROC window and never a single management frame from a foreign BSS, on
three different channels. The one public MT7925 AWDL implementation (§4) does not work that way either - it runs the radio
as a monitor/sniffer, which is exactly why it needs the AP link on a social channel (6/44/149) in its "shared" mode.

The receive half therefore now opens the firmware sniffer for the duration of the ROC window, and only for it:

```
ROC on the social channel (grant, status 0)
  MCU_UNI_CMD(SNIFFER) / UNI_SNIFFER_ENABLE  = 1
  MCU_UNI_CMD(SNIFFER) / UNI_SNIFFER_CONFIG  (band, 20 MHz, control = centre = that channel, drop_err)
  ...frames arrive, the RX ring is drained, awdlPollRx hands them to the peer manager...
  MCU_UNI_CMD(SNIFFER) / UNI_SNIFFER_ENABLE  = 0
ROC back to the AP channel
```

This keeps the infrastructure link: the radio is already parked off-channel for the window, so nothing is taken away from
it that the ROC had not already taken, and the station is back on the AP channel 60 ms later. `awdl stat` (`onch`, `fc`,
`af`) stays as the verdict: if `fc` now shows action frames and `af` moves, the receive path is open and the remaining work
is the Family's own advertise path; if the histogram does not change, the firmware ignores the sniffer while the interface
is a station and the next attempt is a real monitor vif.

Second documented blocker that this does not solve: an iPhone only starts AWDL after a BLE advertisement from the sender
(§2), and this machine's BT scan-filter offload `0x1812` fails. A test against an iPhone therefore measures the BLE wake-up
path too; two Macs (or an iPad whose AirDrop sheet is open) are the cleaner RX test.

### 10.18 What the Family actually needs from the driver (and what it cannot send itself)

A full symbol scan of IO80211Family settles a question that was still open in `10.12`: the Family never transmits an AWDL
action frame itself. There is no `outputActionFrame` and no `sendActionFrame` on `IO80211Controller` or on the virtual
interface - the only transmit-shaped symbol on the AWDL path is `IO80211VirtualInterface::sendToBpfTap`, and the AF thread
(`IO80211AWDLPeerManager::actionFrameProcessThread`) does nothing but tap the frame to BPF, account for it and release its
buffer. On Broadcom hardware the service-request / master-indication frames are built *by the firmware* from the parameters
the Family hands over: `setAWDL_AWDL_ADVERTISERS` (`awdl_peer_advert_add`), `setAWDL_PRESENCE_MODE`,
`setAWDL_ELECTION_PARAMS`, `setAWDL_AF_TX_MODE`, `setAWDL_SYNC_PARAMS`, `setAWDL_SYNCHRONIZATION_CHANNEL_SEQUENCE`.
Those are the frames we still have to build ourselves, and their layouts are exactly what the driver was ignoring with
`awdlAccept()`.

Confirmed while reading the same vtable: `IO80211VirtualInterface::setAwdlCurrentChannelSequenceIndex` (slot 473) is an
*empty* function in the base class - a hook the driver is expected to fill. It is the Family telling the driver which entry
of the synchronisation channel sequence the cluster is on. The interface now follows that index instead of rotating on its
own, and only free-runs the sequence when the Family never drives one (discovery).

`setAWDL_AWDL_ADVERTISERS`, `setAWDL_PRESENCE_MODE` and `setAWDL_ELECTION_PARAMS` are now traced (first bytes / first four
words, bounded) instead of silently accepted, so the next AirDrop-open boot yields the layout of the advertise payload that
the service-request frame has to be built from.

### 10.19 The sniffer works - the frame is not at offset 32

With the sniffer on, the ROC window delivers 1686 frames per 100 periods instead of 86: the receive path is open. But the
`af` hits it produced were false positives, and the class histogram filled with "other management" (1681 of 1686) - the RX
buffer layout changed under the parser.

`mt7925_mac_fill_rx()` says why: after the 32 bytes of RXD the firmware appends optional groups depending on RXD1/RXD2, and
the frame starts after them (`mt76_connac2_mac.h`):

```
off = 32
    + 16 if RXD1.GROUP_4 (BIT 14)   fc/seq of the frame
    + 16 if RXD1.GROUP_1 (BIT 11)   IV
    + 16 if RXD1.GROUP_2 (BIT 12)   timestamp
    + 16 if RXD1.GROUP_3 (BIT 13)   P-RXV  (+24 more if GROUP_5, C-RXV)
    + RXD2.HDR_OFFSET (bits 15:14)
```

Station-mode frames carry no group, which is why the fixed 32 was right for the data and beacon paths since the first RX
work - but the sniffer sets GROUP_4, so offset 32 lands on `d0 00 00 00 ...`, the group, not the action frame. The AWDL
paths (action-frame probe, beacon probe, class histogram) now compute the offset with that formula; the group bits are
dumped once per boot (`awdl rx hdr off=.. rxd=..`) so the layout can be verified against real traffic instead of assumed.
