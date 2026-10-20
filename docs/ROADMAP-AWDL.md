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
