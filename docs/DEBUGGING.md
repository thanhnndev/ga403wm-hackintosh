# Debugging without a working screen, keyboard or network

> **Since 2026-10-11 this is bring-up tooling only.** macOS boots and keeps its own logs, so the reference config disables
> `ItlDiag.kext`, drops `itldiag`/`itlxr`, and `itlmt7925` writes NVRAM only with the boot-arg `itlmt_nvlog=1`. On a working
> install use: `log show --last boot` (or `log collect`), `ioreg -rc itlmt7925 -d1` (all driver logs and counters),
> `/Library/Logs/DiagnosticReports` for panics, OpenCore's own log only to time the boot loader (`Misc/Debug/Target` 0x41 =
> file only, then back to 0: the file is flushed per line and slows the boot). Re-enable ItlDiag only when macOS cannot get
> far enough to keep a log (Recovery, no display).

On a Hackintosh in the Recovery environment there is nothing to `scp` and the screen may be gone after a panic. The kexts
here therefore log into **firmware NVRAM** under the Apple GUID `7C436110-AB2A-4BBB-A880-FE41995C9F82`. NVRAM survives
hangs, panics and power cycles, and can be read from Windows on the same machine.

## Reading

```powershell
# Windows, elevated PowerShell on the same PC (needs SeSystemEnvironmentPrivilege)
.\scripts\read-nvram.ps1                 # all itl* variables below, plus boot-args
.\scripts\read-nvram.ps1 itls0 itlz0     # only some
.\scripts\clear-nvram.ps1                # delete them again (NVRAM space is small)
```

Kexts write with `IONVRAM-FORCESYNCNOW-PROPERTY` on `/options`, so values reach the flash without a clean shutdown.
From macOS: `nvram -p | grep itl`. From Linux: `/sys/firmware/efi/efivars/<name>-7c436110-ab2a-4bbb-a880-fe41995c9f82`
(not tested here).

> **Redact before posting.** The Wi-Fi logs contain the card MAC, BSSIDs and the SSIDs of nearby networks.

## Variables

| Variable | Written by | Content |
|---|---|---|
| `itl0`..`itl3` | ItlDiag | digest: clocks (mach/TSC ratio), xHCI controller state, USB device list |
| `itlm0`..`itlm5` | ItlDiag | mirror of the kext's probe / firmware / scan logs: `start 14c3:7925 ... CHIP=...`, download stages, scan summary (APs per channel) |
| `itln0`..`itln4` | ItlDiag | copy of the connect (M3) log; `itln4` = one-line result (`hs-ok tgt=1 ch=44 ...`) |
| `itlk0`..`itlk7` | itlmt7925 | the connect log written by the kext itself, 380 characters per variable, in order |
| `itls0` | itlmt7925 | data path counters: `up=145s rxd=5905 eapol=2 eth=5903 drop=0 tx=4698 fail=0 rxpk=8552` |
| `itlb0`..`itlb2` | itlmt7925 | fast-mode / Block Ack log (`itlmt_fast`), see [WIFI.md](https://github.com/thanhnndev/mt7925-macos-wifi/blob/main/docs/WIFI.md#reading-the-result-of-a-test); in `fast` mode `itls0` also carries `L<level> uni=.. ba=.. reo=.. txf=.. am=..`; `itlb*` also holds the `rxd`, `amsdu ok/BAD` and `fast feat` diagnostics |
| `itlmt7925-log` | itlmt7925 | the last log line, useful for a hang |
| `itlt0`, `itlt1` | ItlDiag | timer probe: `mach/cal/tsc` per 100 ms sleep, and the mach vs. wall-clock ratio |
| `itli0` | ItlDiag | xHCI interrupter register state per controller |
| `itly0`..`itly2` | ItlDiag | HID device list with the transport (USB / I2C) |
| `itlx0`..`itlx3` | ItlDiag | event-ring sampler for xHCI 0..3: `ev`, `late5`, `maxlat` per ring (`itlxr=2`) |
| `itlz0` | ItlXhciKick | `kick up=<s> p=<us> c0:kicks/hits/miss ...` |

## Reading a Wi-Fi log

```
credentials: 2 network(s);net1 ssid len=8 psk len=9;net2 ssid len=13 psk len=8;       <- SSID/PSK lengths only, never the values
scan #1 for net2 (directed);selected net2 ssid len=13;target <bssid> ch=44 ...;       <- which network was picked and where
roc_acquire rc=0 st=0;roc grant=1;auth resp alg=0 seq=2 status=0;assoc resp status=0 aid=38;
eapol m1 ..;eapol m2 tx;eapol m3 mic ok;eapol m4 tx;key(ptk) rc=0;key(gtk) rc=0;     <- 4-way handshake
RESULT rc=0 link up;ethernet interface created;tx udp 68>67 ...;rx udp 67>68 ...      <- DHCP
```

A nonzero `rc` names the stage that failed (`-110` is a timeout, `-5` an I/O error). Typical causes: wrong passphrase
(the AP rejects msg 2, the log ends with `eapol: no msg3`), AP not found (out of range, or on a channel that is not
scanned; 6 GHz is not scanned), firmware not ready (`stage 9: FIRMWARE READY` missing).

## ItlDiag

Optional kext, boot-args:

| Boot-arg | Effect |
|---|---|
| `itldiag=<n>` | enable the diagnostics worker (any non-zero value; it runs for about 20 minutes) |
| `itlxr=1\|2` | sample xHCI event rings (`itlx*`); `2` is the variant used on the reference machine |
| `itlfile=0` | the raw-file log path is on by default: ItlDiag looks for `ITLLOG.BIN` in the root of every FAT32 partition (the ESP OpenCore booted from, the stick) and writes the text log into its clusters, so no stick is needed. `scripts/usblog.ps1 -Esp -Prepare` creates the file on the ESP (elevated shell), `-Esp -Read` shows it. `itlfile=0` turns it off |
| `itlpanic=<s>` | after that many seconds call `panic()` with the digest as the message, to get a log out of a machine you cannot otherwise reach |
| `itloff=1` | stay completely passive (to check whether the diagnostics themselves disturb something) |
| (ESP log) | ItlDiag opens the partition holding `ITLLOG.BIN` only while it writes, and skips writing while the partition is mounted or open elsewhere, so `diskutil mount` works while ItlDiag runs (since 2026-10-11) |
| `itlkbd=<ms>` | fallback: initial key-repeat delay in milliseconds, `0` = off |

`scripts/recovery-dump.sh [mountpoint]` collects `ioreg`, `system_profiler`, `kextstat`, `dmesg` and a 25-second typing
trace from the Recovery Terminal into `<stick>/dump`.
