# 73FE4CE4 boot — 2026-10-16, first native load on Tahoe (macOS 26.7.1, 25G241)

Stage b (`itlmt_native=1 itlmt_native_if=1 itlmt_native_dp=1 itlmt_native_nvtrace=1 itlmt_stat=1 itlmt_nopwr=1 itlmt_fast=6`,
`itlmt_m1=0`) on the newly ported kexts. No panic; sleep/wake not tested.

**The Wi-Fi stack came up and worked; the scan list was garbled.** `itlmt7925Wifi` initialized against
`IO80211_kexts-1566.5`, the interface registered (role 1, `mk:startWithInfo ok`, service registered, `ifnet_attach` gave
**en5**, `IOSkywalkLegacyEthernetInterface`, station address `de:56:7b:34:81:d5`), radio power from System Settings was
accepted and the scans ran: the core did 13 live scans (`scan finished done=1@2410ms rx=85 bcn=83 aps=48` and siblings,
`scan_req rc=0` every time) and all 84 of airportd's `APPLE80211_IOC_SCAN_REQ` calls answered GOOD (the rest of the 84
results came from airportd's own cache). `scan:delivered 48 of 48` on every delivery.

Root cause of the garbled names: the `0xc9` beacon message header is **0x44**, not 0x40 — Apple writes the flags dword
at `+0x40` and starts the information elements at `+0x44` (the meta buffer is `0x844 = 0x44 + 0x800`). With the header at
`0x40` the IE area sat four bytes early, so every element (the SSID element included) was parsed from the middle of its
predecessor, and the consumer read four bytes past the end of the buffer. The core's own AP table was never at fault:
the `itlm3` checkpoint below shows a clean table. Fixed in `kexts/itlmt7925Native/itlmt7925_iface.cpp` (`kBeaconHeader =
0x44`, flags moved to `+0x40`); committed as the `0xc9 beacon message header is 0x44 on 25G241` commit on `tahoe/wifi`,
**not rebuilt or re-tested yet**.

## Files

| File | Contents |
|---|---|
| `beacon-header-25G241.txt` | the three places in the 25G241 `BootKernelExtensions.kc` that fix the layout, with disassembly and how to reproduce |
| `driver-trace.txt` | every driver IOLog line of the boot (`ctl:`/`mk:`/`sw:`/`dp:`/`if:`/`ioctl:`/`scan:`/`ev eid`/`rxframe#`), in time order, from the unified log |
| `nvram-checkpoints.txt` | the `itlmt-native-trace`, `itlm*`, `itlk*`/`itln*` NVRAM checkpoints as left on the ESP by that boot |
| `wifi-events.txt` | airportd / IO80211 view of the same boot (folded: one example per pattern, repeats as `xN`) |

How they were collected: the macOS Data volume and the System volume were mounted read-only from Linux
(`mount /mnt/macos-vol0`, `sudo mount -t apfs -o ro,vol=3 /dev/nvme0n1p4 /mnt/macos-sys`), `private/var/db/diagnostics`
+ `uuidtext` were decoded with `mandiant/macos-unifiedlogs` (`scripts/decode-unified-log.sh` after
`scripts/linux-collect-logs.sh --unified`), the driver's own lines survive as absolute string arguments even where
airportd's format strings (dyld shared cache) do not, and the NVRAM checkpoints were read straight out of
`/sys/firmware/efi/efivars` on the Linux side.

Raw collection stays local. Repository extracts were reviewed: no SSIDs (`<ssid>` / `<hidden>`), no MACs/BSSIDs
(`<mac>` / `<bssid>`), no passphrases, no SMBIOS; kernel pointers are `0x<ptr>`.

## Next

Rebuild both kexts on the Mac, `scripts/native-wifi-test.sh install build/itlmt7925Native.kext --stage b --exclusive`,
reboot and check that System Settings lists the networks with their real names; join a WPA2-PSK network from there and
watch `scan:`/`assoc:` in `itlmt_native_trace`.
