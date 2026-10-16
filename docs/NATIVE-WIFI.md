# Native Wi-Fi: `itlmt7925` as an `IO80211Controller`

Branch `wifi-native-80211`. Goal: System Settings shows **Wi-Fi** (not Ethernet), the menu bar item and CoreWLAN work, and
scan/join happen from the UI. Background and the options considered are in [WIFI-AS-WIFI.md](WIFI-AS-WIFI.md) (this is its
option C); the vtable of `IO80211Controller` is in [IO80211-ABI.md](IO80211-ABI.md).

## Ground rules

* **Clean room.** `itlwm` / `AirportItlwm` are GPL-2.0; this repository is Clear BSD. Do not read, copy or paraphrase their
  sources. Everything is derived from Apple's binaries (symbol names, vtables, struct usage in `AppleBCMWLANCore`) with
  `tools/kc.py` and `tools/kc_vtable.py`, and from public Apple documentation. Record in each ABI note where a layout came from.
* **Behind a switch.** The data path (`itlmt7925_m*.cpp`, `itl_*.cpp`) is proven and stays untouched. The "front end" is the one
  class that talks to the network stack: today `itlmt7925Eth` (`itlmt7925_eth.cpp`, an `IOEthernetController`). The new class
  `itlmt7925Wifi : IO80211Controller` replaces it only with the boot-arg `itlmt_native=1`; without it the Ethernet front end is
  used exactly as before. A panic on the native path must never cost a working machine.
* **Test on the installed system**, not Recovery. Keep `itlmt7925.kext` of main on the USB stick as the way back.
* Every ABI fact in this repo is per macOS build (now Darwin 24.6.0 / 15.6.1 and 15.8.1). Record the build next to it.

## Interface between the data path and the front end

The data path already exposes what a front end needs; the native class must call the same functions `itlmt7925Eth` calls:

| Direction | Today (`itlmt7925Eth`) | Native class |
|---|---|---|
| frame from the stack to the AP | `outputPacket(mbuf_t)` through an `IOGatedOutputQueue` | `IO80211SkywalkInterface` TX path (packets, not mbufs; to be mapped) |
| frame from the AP to the stack | `rxPacket(eth, len)` queues on the `IOEthernetInterface` | Skywalk RX pool/queue (to be mapped) |
| link up/down | `setLink(bool)` | `apple80211` state + link-quality notifications |
| scan / join / disconnect | user client + ItlWiFi app | `SCAN_REQ`/`SCAN_RESULT`, `ASSOCIATE`, `DISASSOCIATE` ioctls |

So the work is: (1) the controller and interface classes, (2) the `apple80211` request handlers mapped onto the
existing scan/join code, (3) TX/RX through Skywalk.

## Milestones

1. **ABI map** (needs `BootKernelExtensions.kc`; see "Extraction tasks"). Output: `docs/IO80211-ABI-2.md` with the vtables of
   `IO80211SkywalkInterface`, `IO80211InfraInterface`, `IO80211WorkQueue`, `IO80211CommandGate`, the sizes of the
   `apple80211_*_data` structs that matter, and the call order in `AppleBCMWLANCore::start`.
2. **Stub that loads**: a kext `itlmt7925Wifi` (class registered, `start()` creates the work queue/command gate and the
   Skywalk interface, no radio). Success = `ioreg` shows it under the IO80211 plane, System Settings lists a Wi-Fi service,
   no panic on load/unload/sleep.
3. **Static answers**: `CARD_CAPABILITIES`, `DRIVER_VERSION`, `HARDWARE_VERSION`, `POWER`, `COUNTRY_CODE`, `PHY_MODE`,
   `SUPPORTED_CHANNELS`, `MAC_ADDRESS`. Success = the Wi-Fi pane opens, power toggle works.
4. **Scan**: `SCAN_REQ`/`SCAN_RESULT` fed from the existing `m2` scan. Success = the menu bar lists networks.
5. **Join/leave**: `SSID`, `BSSID`, `ASSOCIATE` (WPA2-PSK; the passphrase arrives through the keychain/`configd` path, which
   must be checked: `SET_CIPHER_KEY`/`SET_RSN_IE`-style requests versus the supplicant doing the 4-way handshake in user space;
   the current kernel-side handshake in `itl_wpa.cpp` may have to stay), `STATE`, `RSSI`, `CHANNEL`, `TXRATE`.
6. **Data path**: packets through the Skywalk interface; Block Ack / A-MSDU stay in the data path unchanged.
7. **Polish**: sleep/wake, link-quality reports, `itlmt_native` default decision, docs.

## Extraction tasks (run on the Mac; read-only)

Prerequisite: a copy of `BootKernelExtensions.kc` of the installed macOS (the installer copy under
`/System/Volumes/Data/Previous Content/com.apple.installer/`, or `/System/Library/KernelCollections/` after
`kmutil`), `pip install capstone` for disassembly. `export KC=<path>`.

```bash
sw_vers; uname -r                                   # record the build
python3 tools/kc_vtable.py find IO80211              # which classes exist (first 200)
for c in IO80211SkywalkInterface IO80211InfraInterface IO80211WorkQueue IO80211CommandGate IO80211Peer \
         IO80211VirtualInterface IO80211ControllerMonitor; do
  python3 tools/kc_vtable.py vtable $c > abi/$c.vtable.txt 2>&1
done
python3 tools/kc_vtable.py compare IO80211SkywalkInterface AppleBCMWLANSkywalkInterface > abi/skywalk-if.diff
python3 tools/kc_vtable.py methods AppleBCMWLANCore SCAN        > abi/bcm-scan.txt
python3 tools/kc_vtable.py methods AppleBCMWLANCore ASSOCIATE   > abi/bcm-assoc.txt
python3 tools/kc_vtable.py methods IO80211Controller               > abi/ctrl-methods.txt
```

Then, with `kc.disasm`, for these functions (call order and struct offsets only, no logic): `AppleBCMWLANCore::start`,
`AppleBCMWLANCore::createWorkQueue`, `IO80211Controller::start`, `IO80211SkywalkInterface::initWithController` (names as
they appear in the symbol list), and the `apple80211_scan_data`, `apple80211_scan_result`, `apple80211_assoc_data`,
`apple80211_capability_data` structs (size = the `memset`/copy length in the callers). Keep the output out of git if it is
large; commit the distilled tables.

## Open questions

* Does the 4-way handshake on Sequoia stay in the kernel driver (as for `itlwm`-class drivers) or does `wpa_supplicant`-like
  user-space code in `airportd` expect the driver to hand EAPOL frames up? The answer decides whether `itl_wpa.cpp` is reused.
* Can an `IO80211Controller` subclass load with `AMFI` relaxed and no `IO80211Family` signature issues on this build
  (`amfi=0x80` is already set), and what `OSBundleLibraries` entry does it need (`com.apple.iokit.IO80211Family`)?
* Does CoreWLAN require `IOSkywalkFamily` features (logging pipes, fault reporter) that the 12 pure virtuals hide?

## Status

* 2026-10-12: branch created from `main` (7635608); `tools/kc_vtable.py` and this plan added. No driver code changed.

* 2026-10-12: installed macOS 15.8.1 / 24H32 collection dumped successfully without sudo.
  Partial ABI findings and remaining milestone 1 work: [IO80211-ABI-2.md](IO80211-ABI-2.md).
  `tools/collect_native_wifi_abi.py` collects vtables, method lists, overrides, startup and
  scan/association disassembly in one run; use an ignored `build/` destination. BCM uses WCL
  scan/association handlers on this collection; the original narrower filters returned empty output.
  No native kext has been built or installed.

* The 24H32 extraction bundle is committed in `abi/native-wifi/24H32/` at the user's request
  so the cloud session can continue from the same evidence. No kernel collection binary is included.

* 2026-10-12 (cloud): round-2 analysis of the 24H32 dump in [IO80211-ABI-2.md](IO80211-ABI-2.md#analysis-round-2-cloud-session-from-the-committed-dump-only):
  the controller needs a real `CCLogStream` logger and an existing work queue before the base `start`; the data path is
  IOSkywalkFamily packet queues/pools registered through `registerInfraEthernetInterface`; instance sizes and the
  IOSkywalk/CoreCapture layouts are the blockers. `tools/annotate_vcalls.py` added. Next extraction batch is listed at the end of that page.

* 2026-10-12 (Mac): round-3 evidence committed under `abi/native-wifi/24H32/round3/`.
  MetaClass instance sizes, IOSkywalk/CoreCapture vtables and factories, RegistrationInfo
  call sites, and GET/SET dispatch tables are now extracted. WCL request IDs 441/442
  route through interface virtuals / AppleBCMWLANInfraProtocol; see the round-3 ABI note.
  Struct layouts, protocol forwarding and ownership remain open before a native stub.

* 2026-10-12 (cloud, round 3): `kexts/itlmt7925/io80211/IO80211Controller.h` is generated from the vtable dump and checked
  against it (`tools/gen_io80211_header.py`, `tools/check_io80211_header.py`: 463 slots, 0 mismatches). Not part of the kext
  build yet. Open: `CCPipeOptions`/`CCStreamOptions` for the logger, the interface-side headers, RegistrationInfo.

* 2026-10-12 (Mac, round 4): logger option layouts (`CCPipeOptions` 0x350, `CCStreamOptions` 0x358) with Apple's values,
  `RegistrationInfo` (0x130 bytes), the queue/pool contract (one pool, 4 Tx submission, Tx/Rx completion, common Rx submission,
  numeric defaults, ownership at stop) and seven verified interface-side headers (`kexts/itlmt7925/io80211/`, 0 mismatches each)
  are in [IO80211-ABI-2.md](IO80211-ABI-2.md#extraction-round-4-mac-2026-10-12-read-only). Raw: `abi/native-wifi/24H32/round4/`.
  Milestone 1 is complete except request payload layouts; milestone 2 (stub) is unblocked. Nothing has been loaded.

* 2026-10-12 (Mac, stub stage 1): `kexts/itlmt7925Native` (`itlmt7925Wifi : IO80211Controller`, separate kext, idle without
  `itlmt_native=1`) builds with the kext flags; every override sits on Apple's slot, all 481 undefined symbols resolve against the
  collection (`tools/check_kext_links.py`). Found on the way: a null fault reporter panics `start` (like a null logger), the object
  is an `IO80211FaultReporter`. Never loaded. Next: the interface and queues (stage 2). Details:
  [IO80211-ABI-2.md](IO80211-ABI-2.md#native-stub-stage-1-mac-2026-10-12-controller-only-built-and-link-checked-never-loaded).

* 2026-10-12 (cloud, stub stage 2): `itlmt7925WifiInterface : IO80211InfraProtocol` with pool and queues, created behind
  `itlmt_native_if=1`; compiled with the kext flags and slot-checked against Apple's vtables (209 + 19 overrides, 0 wrong), then
  built and link-checked on the Mac (exit 0; only the 6 baseline-missing `IONetworkController` symbols), not loaded. Next: first load. Details:
  [IO80211-ABI-2.md](IO80211-ABI-2.md#native-stub-stage-2-cloud-session-2026-10-12-interface--pool--queues-compiled-and-slot-checked-never-loaded).

* 2026-10-13 (Mac, live boot of 3b4ff24): CoreWLAN lists no interface and `SCNetworkInterfaceCopyAll()` omits en9 even though en9 is
  `UP,RUNNING` and a direct BSD lookup says IEEE80211. The controller refuses ioctl 12 (CARD_CAPABILITIES), which Apple's library asks
  right after DRIVER_VERSION when binding; the build after 3b4ff24 answers it with the unconditional subset of Apple's capability bits.
  Hypothesis, untested on hardware. Details: [TEST-NATIVE-WIFI.md](TEST-NATIVE-WIFI.md) "CARD_CAPABILITIES (ioctl 12)".

* 2026-10-13 (Mac, f6b7162 boot): the IOSkywalkLegacyEthernet shim assigned the unit; the interface is a Wi-Fi hardware port and the
  Wi-Fi power switch works. Milestones 4 and 5 (scan, WPA2-PSK join with a userland-supplied PMK, status getters) are written and
  host-checked, not yet booted: [TEST-NATIVE-WIFI.md](TEST-NATIVE-WIFI.md) "Scan + WPA2-PSK join through the native path".
