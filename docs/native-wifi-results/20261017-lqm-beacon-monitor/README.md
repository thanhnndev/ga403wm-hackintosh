# 2026-10-17 — the link died 60 s after every join: the family's missed-beacon monitor needed the LQM event (0x27)

Trace of the 12:40 boot on Tahoe (25G241, stage b) plus the 12:41 boot's logs: the link came up, DHCP worked, and then,
with the machine idle, the family declared the beacons missed and dropped the link. Same shape every boot: join, ~60 s of
traffic, `link recovery` + `link_off`, a `missed beacons timeout` fault report, and (because the fault report's core
capture is malformed for corecaptured) a `corecaptured` SIGSEGV ~80 s after boot. The panics of the morning (09:34,
10:30, 10:37) were the scan-cache and CoreCapture-pipe bugs already fixed; this one is new and separate.

## What the logs show

* `itlmt_native_trace` (12:41 boot): link up, `assoc:result ok=1`, datapath clean (`rx=20598 tx=12718 drop=0`), and the
  last line is `wcl:link up done`.
* `log show` (kernel): at 12:42:11.532 `corecapture: CoreCapture errorCodeStr for fault missed beacons timeout`, then at
  12:42:16.533 `configd: Process interface link status inactive: en5` / `airportd: kevent intf=en5 event=link_off`, then
  `WiFiAgent: link recovery started`.
* The join completed at 12:41:02 (first link up) — the fault lands **70 s later**, the leave 5 s after that. Exactly the
  60 s window in `WCLNetManager::assocTimerAction` below.

## Root cause: nobody fed the beacon counter

`WCLNetManager::handleMissedBeacons` (25G241 `0xffffff80021902be`) either reports the `CommonFaultReporter` fault
`missed beacons timeout` (fault code 5, line 0xcd8, both strings at `0xffffff80023c0ffa`) or leaves the network outright
(`leaveNetworkCommand(..., "missed beacons timeout")`). It is called from `WCLNetManager::assocTimerAction`
(`0xffffff800218fa92`) at `+0x24b`:

```
0x218fcbb: mov [ctx+0x150], now      ; refreshed every run
0x218fcc6: cmp [rbp-0x78], 0xea61    ; now - ctx[0x150]  (60001 ms)
0x218fcd0: cmp [rbp-0x70], 0xea61    ; now - ctx[0x158]
0x218fcdd: call handleMissedBeacons  ; both older than 60 s -> the link is declared dead
```

The two timestamps are the family's "the link is alive" pair. `ctx+0x158` is only refreshed by
`WCLNetManager::handleLqmUpdate` (`0xffffff8002191d30`), which is the handler for **driver event 0x27** (WCLNetManager's
dispatch table entry at `0xffffff8002487930`: `id 0x27, type 2 -> handleLqmUpdate`; the table is a 24-byte
`{0, id<<16|type, handler}` array at `0xffffff8002487318..`). The payload is Apple's `apple80211_lqm_event_data`,
`0x1dc` bytes — the handler first checks `[msg+8] == 0x1dc` (the message length) and then reads:

| offset | meaning to the handler | gate |
|---|---|---|
| +0x1d8, +0x1d9 | "data valid" flags, both set in `AppleBCMWLANLQM::updateLQM` (`0xffffff80015cfd72`/`0x15cfd82`) | must be nonzero |
| +0x30, +0x28 | stats valid + a u32 counter | `[+0x30] && [+0x28] != 0` -> `ctx+0x150 = now` |
| +0x1c vs +0x14, +0x24 | counters (ratio `[+0x14]*100/[+0x1c]` is computed family-side in `IO80211LQMData::createDeltaLQMData`) | `[+0x1c] > [+0x14] \|\| [+0x24] != 0` -> `ctx+0x158 = now` |

Apple's driver posts this event from `AppleBCMWLANCore::postLQMEvent` (`0xffffff80015fda2a`):
`postMessage(iface, 0x27, data, 0x1dc, 1)` — and it is the only producer. This driver never posted 0x27, so both
timestamps stayed at their link-up values, the 60 s check fired on schedule, and the family did the leaving itself.

## Fix

* Core (`kexts/itlmt7925`): `tgtBcnCount` counts beacons heard from the connected BSS (`itlmt7925_uc.cpp`, next to
  `tgtLastBcnMs`), reported as `ItlNativeStatus.beaconCount` (appended at the end of the struct; both kexts rebuild).
* Native (`kexts/itlmt7925Native`): `postLqmUpdate()` runs from the datapath tick once a second while the core reports the
  link up and posts event 0x27 with a zeroed `0x1dc`-byte payload where:
  * `+0x1d8 = +0x1d9 = 1`, `+0x30 = 1` (the "valid" flags Apple sets),
  * `+0x14` = beacon count at the previous post, `+0x1c` = beacon count now, `+0x24` = `+0x28` = beacons since the
    previous post.

  All four values are the core's real counter, so the timestamps only refresh while beacons actually arrive; a driver
  that stops posting (or a link that really died, which the core reports as 0xd8 and stops posting) is still caught by
  the family's own 60 s timeout. Trace: `wcl:lqm post beacons=%u delta=%u` (first four posts).

## Second fix in the same round: DFS channels were never scanned

The scan request (`itlmt7925_m2.cpp`, `UNI_SCAN_CHANNEL`) listed 2.4 GHz 1–11 and 5 GHz {36, 40, 44, 48, 149, 153,
157, 161, 165} — while the channel domain (`itlmt7925_m3.cpp`, `UNI_SET_DOMAIN_INFO`) already allowed the whole 5 GHz
set **including the DFS bands 52–64 and 100–144**. Any AP on a DFS channel (the common pick for 80 MHz in auto mode, and
the user's case: a phone sees "Kefoff Coffee" at 5 GHz >400 Mb/s, this Mac never did) could not appear. The scan list
now covers 2.4 GHz 1–13 and all of 5 GHz, and the driver's reported supported-channel list
(`itlmt7925Native` `kScanChannels`, used by 0x1b/0xfe) mirrors it. Whether the firmware probes passively on DFS with
the scan marked active is a hardware question; Linux's mt7925 sends the same shape and lets the firmware decide.

## Verified

* `bash scripts/build.sh io80211check itlmt7925 itlmt7925Native` clean (pre-existing warnings only).
* `check_native_slots.py` 225/0 (interface) and 23/0 (controller) against the 25G241 vtables;
  `check_native_symbols.py --dumps abi/native-wifi/25G241` 0 family symbols outside the dumps;
  `KC=... check_kext_links.py` exit 0 (6 baseline-missing `IONetworkController` symbols); `gen_native_iface.py --check` ok.

## Hardware test

Boot with the stage-b build and watch:

1. `ioreg -l | grep itlmt_native_trace` — expect `wcl:lqm post beacons=N delta=D` lines with N growing once the link is
   up, and **no** `link recovery` / `link_off` in `log show` after 60 s of idle (previously guaranteed).
2. `log show --last boot --predicate 'eventMessage CONTAINS "missed beacons"'` — expect nothing.
3. `/Library/Logs/DiagnosticReports/corecaptured-*.ips` — no new crash after ~2 minutes idle (the crash was the
   malformed core capture from the missed-beacons fault report; without the fault there is nothing to parse).
4. Wi-Fi list: a network known to be on a DFS channel (e.g. "Kefoff Coffee" 5 GHz) should now appear.

## Open items

* The core capture our `IO80211FaultReporter` produces still crashes `corecaptured` when a fault report does happen
  (link recovery BSS-blacklist events can still trigger one). Its payload needs the crash-tracer structure; until then,
  fewer faults = fewer crashes.
* 6 GHz / Wi-Fi 7 (the MT7925 is a Wi-Fi 7 chip): needs the `AppleChannelSpec` band encoding for 6 GHz in the beacon
  message (0xc000 is 5 GHz), 6 GHz entries in the domain and scan list (band index 3 in the channel TLV, per Linux
  mt7925), the RX `ch_freq > 180 -> ch = (ch_freq-181)*4+1` conversion (`mt792x_get_status_freq_info`), and SAE for
  6 GHz joins. Planned as the next round.
