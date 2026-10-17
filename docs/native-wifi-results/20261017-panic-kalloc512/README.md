# 2026-10-17 09:34 panic — the scan cache reads past the queued beacon message (`data.kalloc.512`)

`/Library/Logs/DiagnosticReports/Kernel-2026-10-17-093407.panic` (macOS 26.7.1, 25G241, Darwin 25.6.0). Wi-Fi had come up
and connected; the machine went down hard 216 s in, while scan results were flowing. Reproducible within 1–3.5 minutes.

```
panic(cpu 22): Kernel trap at 0xffffff8014501092, type = 14=page fault
CR2: 0xffffff99f0ff6000   RSI: 0xffffff99f0ff6000   R13/R15: 0xffffff99f0ff5e64
RBX: 0x1a0   RCX: 0x4   RDX: 0x1a0   Error code: 0 (read)
  Zone: data.kalloc.512, Element [0xffffff99f0ff5e00, 0xffffff99f0ff6000) of size 512
  Kind: out-of-bounds (high confidence), Access: 1 byte(s) past
Backtrace: _memmove (<- RIP 0xffffff8014501092) <- IO80211BSSBeacon::setBeaconDataFromMsg + 0x2c
  <- IO80211ScanCacheStore::updateScanCache + 0x9f <- IO80211ScanCacheStore::updateOrAddBeacon + 0x35
  <- WCLScanCacheStore::updateOrAddBeaconInternal + 0x72 <- WCLScanCacheStore::updateOrAddBeacon + 0x2b
  <- WCLMngFrameRouter::scanResultEventHandler + 0x5a <- WCLBulletinBoard::routeMsg + 0xb0
  <- WCLGlue::receiveMessageInternal + 0xb1 <- CommonGlue::receiveMessage + 0x18a
  <- IO80211Glue::sendEventAndFilter + 0xae <- IO80211Glue::processPendingEventQueue + 0x66
```

## The path, from the 25G241 `BootKernelExtensions.kc` (`IO80211Family` 1200.13.1)

| Step | Code | What it does |
|---|---|---|
| post | `IO80211Glue::addEventToPendingQueue` (0xffffff8002194094) | `entry = IOMallocZeroData(length + 0x20)`; `memmove(entry + 0x20, data, length)`; `entry->+0x14 = length` |
| workloop | `sendEventAndFilter` (0xffffff8002193d5c) | `CommonGlueMessage {code, ...; +8 = entry->+0x14; +0x10 = entry + 0x20}` |
| route | `WCLGlue::receiveMessageInternal` (0xffffff800230b03c) → `WCLBulletinBoard::routeMsg` (0xffffff8002188324) | copies the glue message into a `bulletinBoardMessage` (+8 length, +0x10 payload) |
| router | `WCLMngFrameRouter::scanResultEventHandler` (0xffffff80022a6756) | `meta = bb->+0x10`, `ies = meta + 0x44`; **the only length check is `length >= 0x44`** |
| consumer | `IO80211BSSBeacon::setBeaconDataFromMsg` (0xffffff80022d42aa) | `size = *(u32*)meta` (the message's `ie_len` at `+0`) and `allocateIEListBufferAndCopy(size, ies)` |
| copy | `allocateIEListBufferAndCopy` (0xffffff80022d461e, `+0x65`) | `memmove(beacon->ieBuffer, ies, size)` — **no check against the message length anywhere** |

The faulting instruction is `_memmove`'s forward `rep movsb` (file address `_memmove + 0x12` = `0xffffff8000101092`,
`__HIB`). Registers at the trap decode exactly:

- `R13 = R15 = 0x…5e64` = `ies` = *payload + 0x44*, so `payload = 0x…5e20` = `entry + 0x20` ⇒ `entry = 0x…5e00`, the
  `data.kalloc.512` element. The entry holds `length = 0x1e0 = 480` bytes of payload.
- `RDX = RBX = 0x1a0 (416)` = `ie_len` = the message header's `+0` field: the copy asked for **416** bytes from
  `payload + 0x44`, i.e. it needed a **484**-byte message.
- The stored message held only `480 − 0x44 = 412 = 0x19c` bytes of IEs, so `rep movsb` copied 412 bytes (from `0x…5e64` up
  to `0x…6000`), spent its `RCX = 4` remaining on the first byte past the element (`0x…6000`, a GZAlloc guard page with no
  mapping) and trapped. `Access: 1 byte(s) past` + `RCX = 4` — the overrun is exactly the message shortfall.

**Root cause.** Apple's scan-result payload is one `apple80211_beacon_msg`: a 0x44-byte header plus at most **0x19c = 412**
bytes of IEs — the family stores it in a 0x20 + 0x1e0-sized slot (one 512-byte `data.kalloc` element), and the scan cache
copies `ie_len` bytes from `payload + 0x44` without ever validating `0x44 + ie_len` against the message length. That is
the contract Apple's own driver keeps; this driver reported up to `ITL_NATIVE_IE_MAX` = **512** bytes of IEs, so any AP whose
beacon/presp carries more than 412 bytes of IEs produced a message the family clamped to 0x1e0 while the header still
declared more — a guaranteed over-read, and a panic as soon as the entry landed against a guarded page (hence the 1–3.5 min,
probabilistic). When the same AP is the 0xc9 result again, the same read happens again.

**Not the iGPU, not fq_codel:** the backtrace and the fault are entirely in the scan-result path
(`IO80211Family`); the two 2026-10-16 panics (`fq_codel_dq` assertion) are a separate, already-known failure.

## Fix (driver side, `kexts/itlmt7925Native`)

- `kEventIeMax = 0x190` (400): every beacon message (scan results in `deliverScanResults`, the current BSS in
  `getWCL_BSS_INFO`) reports at most a **whole-IE prefix** of the IEs (`ieTrim`, the same walk as the core's `ieWhole`),
  keeping `0x44 + ie_len <= 0x1d8` and 12 bytes of slack under the 0x19c budget.
- A trace line per trimmed AP (first 6 per boot), so the previously-overflowing AP is identifiable:
  `scan:trim <bssid> ch=<n> ie=<reported>-><trimmed>`.

## Verify after the fix

CI + ESP: `build-kexts` run 38998145267 on `6a73548` → `scripts/linux-install-kext.sh itlmt7925Native` →
`/boot/EFI/OC/Kexts/itlmt7925Native.kext`, sha256 `88499c27…` (previous 0x44 build kept as
`Kexts-backup/itlmt7925Native.kext.20261017-101843`, sha256 `14c6af9a…`). Installed 2026-10-17 10:18, not booted yet.

1. Boot macOS, use Wi-Fi the way that crashed before (the panic came ~4 min in, with the menu scanning).
2. `sudo wdutil scan` / `airport -s` a few times over ≥5 minutes: **no panic**.
3. NVRAM: `itlmt-native-trace` shows `scan:trim … ie=<big>->400` — the AP that used to overflow is now the one being
   capped (e.g. the 09:34 panic's message had `ie = 416`, so the trim line for that AP will read `416->400`).
4. The network list still shows real names and joining still works (the SSID/rates/RSN/HT/VHT/HE elements are well inside
   the first 400 bytes; only the tail — vendor/padding IEs — is dropped).
