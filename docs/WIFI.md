# itlmt7925: MediaTek MT7925 Wi-Fi on macOS

`itlmt7925.kext` drives the MediaTek MT7925 (PCI `14c3:7925`, a Wi-Fi 7 chip) without any Apple Wi-Fi framework. It brings its own minimal 802.11 client and presents the result to macOS as a wired Ethernet
interface (`itlmt7925Eth`), the same trick the itlwm project uses for Intel cards.

## Status

> **Update 2026-10-12 (owner-confirmed):** the driver now reaches the **full link speed** (HE, 160 MHz) with the `itlmt_fast` ladder; the
> throughput numbers and "slow" statements below (6 Mb/s, ~8 Mb/s, ~5 MB/s) are the history of getting there. The owner measured the
> final speed at the maximum and will supply the numbers (`iperf3` both directions, band, channel, width, AP model, distance) for
> comparison; they are **not recorded here yet** and were not measured by the agent. The **native front end** (`itlmt7925Native`, `IO80211Controller`) sits on top of this driver, works and is opt-in with boot-args: it gives a real Wi-Fi interface and 28-36 MB/s on the reference unit ([which mode, how to enable, how to go back](WIFI-DRIVERS.md)). **A-MSDU receive is off by default** in every level since round 26d (with it on, TCP collapses to ~50 KB/s; cause chưa xác định); `itlmt_amsdu=1` turns it back on for debugging.

Verified on the reference machine (GA403WM, macOS 15.6.1 Recovery booted from a USB stick):

* firmware download and start (patch + RAM image), NIC capabilities read, MAC address read from the firmware
* active scan of 2.4 GHz (1, 6, 11) and 5 GHz (36, 40, 44, 48, 149, 153, 157, 161, 165) with directed probes
* open-system authentication, association, WPA2-PSK 4-way handshake (CCMP), pairwise and group key install
* DHCP exchange, ARP, DNS queries with answers and an NTP request observed on the interface
* up to four configured networks, picked by priority and availability

Not done, in rough order of importance:

| Gap | Consequence |
|---|---|
| fixed transmit rate: legacy OFDM 6 Mb/s, no HT/VHT/HE, no aggregation, no QoS | low throughput. No benchmark has been run; do not expect more than a few Mb/s |
| no IO80211 integration in legacy mode (native mode: see [WIFI-DRIVERS.md](WIFI-DRIVERS.md)) | shows up as Ethernet in System Settings; the [ItlWiFi menu bar app](#runtime-control-itlwifi-menu-bar-app) gives the scan list, join and disconnect (untested on hardware yet) |
| no group re-key, no power save | battery use is not optimised (reconnect after a drop: implemented with the runtime control, untested) |
| WPA2-PSK/CCMP only | no open networks, no WPA3/SAE, no enterprise, no 6 GHz scan |
| regulatory domain is a fixed world domain (`00`: 2.4 GHz ch 1-11, 5 GHz ch 36-165); MAC address is the one stored in the card | |
| only the Recovery environment was exercised | behaviour of a full install (sleep, wake, power) is unknown |

## Speed: what to expect, and the ceiling

**Today (measured: nothing; estimated from the fixed rate).** The data path transmits at legacy OFDM 6 Mb/s, which is
0.75 MB/s on paper and roughly 0.5 MB/s once framing and ACK overhead are paid. A 16 GB download (a full macOS installer)
therefore takes about 6 hours at the theoretical rate and about 9 hours in practice, and the driver cannot reconnect after a
drop, so a single transfer of that size is unlikely to finish. Use USB Ethernet or USB tethering, or copy the installer from
another machine, until the rate work below is done.

**Measured on the GA403WM** (full macOS 15.6.1 install, `itlmt_fast=6`, link at L6: HE, 160 MHz on 5 GHz channel 44 / center 50,
2 spatial streams, A-MSDU receive on, Block Ack 8 RX sessions + 1 TX session; single TCP stream to `speed.cloudflare.com`
over the internet, about 50 ms RTT, so this is **not** a LAN `iperf3` number and the ISP uplink may be the limit):

| | `e8df337` (64 TX staging slots) | `89d2cfd` (256 TX staging slots) |
|---|---|---|
| 30 MB upload | about 1.08 MB/s | 1.5 to 1.7 MB/s |
| `no slot` drops during the upload | +479 on +17 976 frames (2.7 %) | **0** on +38 854 frames |
| 25 MB download | not recorded | about 5.4 MB/s |
| gateway ping | 3 ms, 0 % loss | 3.7 ms, 0 % loss |

The firmware still retries about 16 % of the transmitted frames (`txf` fifth number), which is where a LAN measurement and the
AP's rates should be looked at next.

**Hardware ceiling (chip, not driver).** The MT7925 is a 2x2 Wi-Fi 7 (802.11be) chip:

| Band / width | PHY rate (2 spatial streams) | Typical real throughput |
|---|---|---|
| 2.4 GHz, 40 MHz, HE | about 573 Mb/s | 150-300 Mb/s |
| 5 GHz, 80 MHz, VHT | 867 Mb/s | 400-600 Mb/s |
| 5 / 6 GHz, 160 MHz, HE | about 2.4 Gb/s | around 1 Gb/s or more, router dependent |
| 6 GHz, 320 MHz, EHT | about 2.9 Gb/s | needs a Wi-Fi 7 router; not planned here |

PHY rates are the vendor/standard figures; real throughput numbers are typical values for chips of this class, not
measurements from this driver.

**What stands between 6 Mb/s and those numbers**, in order of payoff (all are in the "Not done" table above):

1. Advertise HT/VHT/HE capabilities in the STA record and stop forcing the legacy rate. Firmware rate control then picks MCS.
2. A-MPDU: BlockAck session setup (ADDBA) on TX and a reorder buffer on RX.
3. QoS data frames and WMM queues, then 40/80 MHz channel width negotiation.
4. Interrupt-driven DMA instead of the polling thread, so the CPU is not the limit at hundreds of Mb/s.

**How to measure** once a link is up (none of this has been done): in a full macOS install run `iperf3 -s` on another machine on the
same LAN and `iperf3 -c <ip> -t 30` (and `-R`) from the Hackintosh. Recovery has no `iperf3`: use the `curl` recipe in
[Measuring the speed in Recovery](#measuring-the-speed-in-recovery). Compare against the counters in the `itls0` line (`rxd`, `tx`, `fail`).
Record results in this file with the AP model, band, channel and distance.

## HT/VHT/HE mode, Block Ack, A-MSDU and wide channels (`itlmt_fast=1..6`)

Off by default, so the verified legacy path is untouched. It is selected with the boot-arg `itlmt_fast=<level>` next to
`itlmt_m3=1`, and only used when the chosen AP advertises HT (5 GHz or 2.4 GHz); otherwise the driver stays on the legacy path.

| Level | What it adds | New risk compared with the level below |
|---|---|---|
| 1 | HT/VHT capabilities in the association, the AP's capabilities and the 20/40/80 MHz width to the firmware, unicast data as QoS data with the firmware's rate control (instead of fixed 6 Mb/s) | association rejected, firmware dislikes a TLV |
| 2 | **Receive Block Ack**: the AP's ADDBA request is accepted (`STA_REC_BA` recipient + ADDBA response, no A-MSDU, window 64), frames are put back in order in a reorder buffer (100 ms hole timeout, BlockAckReq honoured), deeper RX ring, closer polling while traffic flows | reorder bug; firmware refuses the BA record |
| 3 | **Transmit Block Ack**: after 10 unicast frames an ADDBA request for TID 0 (window 64); on success `STA_REC_BA` originator and the firmware aggregates our QoS data. Also: AC queue instead of the management queue, sequence numbers assigned by the driver, TX staging buffers released on `TXFREE` events instead of reused blindly (256 slots, so the 64-frame Block Ack window cannot exhaust the pool; the `no slot` counter in `itls0` should stay near 0) | wrong queue or sequence handling; TXFREE layout |
| 4 | **A-MSDU receive**: the AP may send A-MSDUs (the ADDBA response and `STA_REC_BA` allow it, the firmware splits them into one RX packet per subframe). The driver rebuilds the Ethernet frames, keeps all subframes of one MPDU together in the reorder buffer (a "bundle") and releases them as a unit | subframe layout (2-byte pad, first/last flag) differs from the assumption; wrong reorder of subframes |
| 5 | **160 MHz** (5 GHz, only if the AP's VHT operation says 160 MHz; 80+80 is run as 80 MHz): VHT capabilities with 160 MHz and SGI160, BSS and STA record at CBW 160 | firmware or regulatory refusal of the 160 MHz BSS |
| 6 | **HE (802.11ax)**: HE capabilities in the association, `STA_REC_HE_V2`, `BSS_INFO_HE_BASIC` and `BSS_COLOR`, HE bit in `STA_REC_PHY`, HE rates in rate control | TLV layout (HE phy/mac bytes) refused by the firmware |

2.4 GHz is not a separate level: it is used whenever the chosen AP is on 2.4 GHz and `itlmt_fast` is at least 1. There it is HT 20/40 only (VHT is cleared),
CCK/ERP basic rates and short preamble are announced, and levels 4 and 6 apply (HE on 2.4 GHz uses `AX_24G`).

Recommended for the first test, boot-args `itlmt_m1=0 itlmt_m2=1 itlmt_m3=1 itlmt_fast=6` (build the kext from this branch with
`scripts/build.sh itlmt7925` or the `build-kexts` workflow, inject the credentials as usual). The driver tries level 6 and **steps down by itself**: if the association or the
4-way handshake fails, if 25 s after link-up it has transmitted but never received a unicast frame from the AP, if A-MSDUs cannot be unpacked
(packets seen but no valid subframe, or most subframes malformed), or if the firmware reports at least 80 % of the transmitted frames as failed in two consecutive 5 s windows (level 3 and up), it
sends a deauthentication, connects again one level lower and finally falls back to the legacy 6 Mb/s path. Levels that would not change the configuration for this AP (for example HE on an AP without HE) are skipped. The result is the
highest level that works, in one boot. (Failures that do not break connectivity, such as a stalled upload, are not
detected: check the counters below.)

What the driver tells the firmware at every level (from the Linux `mt7925` driver: `mcu.c`, `mac.c`, `main.c`, `mt76_connac_mcu.h`):
`STA_REC_HT`, `STA_REC_VHT`, HT/VHT bits and A-MPDU parameters in `STA_REC_PHY`, the HT MCS bitmask in `STA_REC_RA`, bandwidth and
streams in `STA_REC_STATE`, the BSS at the AP's width with `PHY_MODE_A|AN|AC` and 2 streams. Handshake (EAPOL), management and
group-addressed frames always use the fixed 6 Mb/s basic rate.

### Reading the result of a test

After the boot, read the NVRAM from Windows (`scripts/read-nvram.ps1`, see `docs/DEBUGGING.md`):

| Variable | Content |
|---|---|
| `itlb0`..`itlb2` | the fast-mode log: `fast on lvl=6 ch=.. bw=.. c=.. nss=2 ...` negotiated; `fast feat amsdu=1 he=1(ap 1) 160=0 heph=.. hemac=.. map=..` which features were actually offered; `rxd len=.. d1=.. d2=.. d4=.. hdr@.. fc=.. qc=..` raw RX descriptor words of the first three data frames; `amsdu ok ai=.. len=.. hdr@.. hl=.. sn=.. sub=..` / `amsdu BAD ... d=<hex>` the first good and the first malformed A-MSDU (with a hex dump); `lvl N: A-MSDUs cannot be unpacked`, `lvl N: tx failing`; `rx addba tid=0 ssn=.. -> accept win=64`; `sta_rec_ba rx on ... rc=0 st=0`; `tx addba req`; `tx ba on`; `delba`; `lvl 3 given up, connecting again at 2` |
| `itls0` | counters every 5 s: `up=..s L3 ... uni=<rx>/<tx> ba=<rx sessions>/<tx sessions> reo=<in>/<direct>/<buffered>/<dup>/<old>/<flushed>/<timeouts>/<late> txf=<freed>/<reclaimed>/<no slot>/<fw failed>/<fw retries>` |
| `itlk0`..`itlk7` | the usual connect log (`fast: on ...` or `fast: off ...`) |

How to tell what worked: `L6` (or whatever number) in `itls0` is the level that stayed; `am=` with the second number growing means A-MSDUs are being unpacked; `ba=N/1` means N receive sessions and the transmit session are up;
`reo` has `buffered` > 0 and `timeouts` small relative to `in` when aggregation is really happening; `txf` should have the first
number growing with `tx` (if it stays 0 and the second number grows, TXFREE parsing is wrong and buffers are reclaimed by
timeout, which caps TX at a low rate, so tell me).

### Measuring the speed in Recovery

Recovery has `curl`. Without a second machine:

```bash
curl -o /dev/null -w '%{speed_download} bytes/s\n' http://speedtest.tele2.net/1GB.zip     # internet; use a nearby server if you have one
```

With a PC on the same LAN (Windows, in a folder holding a big file): `python -m http.server 8000`, then on the Hackintosh
`curl -o /dev/null -w '%{speed_download}\n' http://<pc-ip>:8000/big.bin`. For upload: `curl -T big.bin -o /dev/null http://<pc-ip>:8001/`
needs an upload-capable server; an `iperf3` binary is not in Recovery. Write the numbers, the level in `itls0`, the AP model, band and
channel into this file.

### What is still missing

No A-MSDU on transmit (A-MPDU already carries most of the gain), no EHT / Wi-Fi 7 and no 6 GHz, 80+80 MHz is run as 80 MHz, only TID 0 is aggregated on transmit,
CPU-polled rings. Not verified on the GA403WM: everything in this section, including levels 4 to 6 (A-MSDU, 160 MHz, HE) and 2.4 GHz. The assumptions that the
first boot will confirm or correct are in the `rxd`, `amsdu` and `fast feat` lines of `itlb*`.

## How it works

The driver is split by milestone, each file a port of the matching part of the Linux
[`mt76`](https://github.com/torvalds/linux/tree/master/drivers/net/wireless/mediatek/mt76) driver
(BSD-3-Clause-Clear, see `NOTICE.md`):

| File | Stage | Linux counterpart |
|---|---|---|
| `itlmt7925.cpp` | probe: map BAR0, take driver ownership from the firmware, read chip id | `mt7925/pci.c`, `mt792xe_mcu_drv_pmctrl` |
| `itlmt7925_m1.cpp` | WFDMA rings (polled), MCU command transport, patch and RAM firmware download | `mt792x_dma.c`, `mt76_connac_mcu.c`, `mt792x_core.c` |
| `itlmt7925_m2.cpp` | UNI command transport, device/BSS setup, scan, RXD parsing | `mt7925/mcu.c`, `mt7925/mac.c` |
| `itlmt7925_m3.cpp` | connect: ROC, auth/assoc frames, STA/BSS state, EAPOL, keys, data path | `mt7925/main.c`, `mcu.c`, `mac.c` |
| `itlmt7925_eth.cpp` | `IOEthernetController` + interface, frame conversion hooks | n/a |
| `itl_wpa.cpp` | PBKDF2-SHA1, PRF-SHA1, HMAC-SHA1, AES key unwrap, EAPOL MIC (host-testable) | n/a |
| `itl_caps.cpp` | HT/VHT element parsing, channel width choice, our advertised HT/VHT elements (host-testable) | `mac80211` capability handling |
| `fw_blob.c` | embeds `fw/*.bin` with `.incbin` | n/a |

The driver runs on its own thread, polled (it does not use interrupts), started once the root filesystem is mounted plus the extra delay given by `itlmt_m1`.
It has no dependency on IO80211Family; `IONetworkingFamily` provides the Ethernet interface.

Connection sequence (`m3Run`): hardware prep (domain info, firmware log, eeprom=efuse, RTS threshold), wildcard scan,
then for each configured SSID in priority order (networks already seen in the wildcard scan first) up to three directed
scans until the AP is found, PMK from the passphrase, BSS + STA record, remain-on-channel, authentication, association,
BSS enable and STA state 2, 4-way handshake, PTK/GTK install, interface creation.

## Configuration

### Boot-args

| Boot-arg | Effect |
|---|---|
| `itlmt_m1=<seconds>` | **required** to do anything beyond probing. The worker waits until the system is ready (the `IOBSD` resource, published when the root filesystem is mounted), then this many extra seconds, then downloads the firmware. Use `0` (until 2026-10-11 it was a fixed delay from kext start and the reference machine used `75`) |
| `itlmt_m2=1` | after the firmware is running: bring up the interface and scan |
| `itlmt_m3=1` | also connect (implies `itlmt_m2=1`) |
| `itlmt_fast=<1..6>` | **experimental, untested on hardware**: HT/VHT rates (1), + receive Block Ack (2), + transmit Block Ack (3), + A-MSDU receive (4), + 160 MHz (5), + HE (6). Falls back one level at a time if a level does not work. See [HT/VHT mode](#htvhthe-mode-block-ack-a-msdu-and-wide-channels-itlmt_fast16) |
| `itlmt_hold=<seconds>` | repeat the probe log on the verbose console for that long (to photograph it) |

Without any of them the kext only maps the card, takes ownership and logs the chip id (`CHIPID=...7925`).

### Networks

Credentials are personality keys of the kext (`Info.plist`, `IOKitPersonalities > itlmt7925`):

| Key | Value |
|---|---|
| `itl_ssid`, `itl_psk` | network 1: SSID (max 32 bytes), WPA2 passphrase (8..63 characters) |
| `itl_ssid2`/`itl_psk2` ... `itl_ssid4`/`itl_psk4` | networks 2..4; list order is priority; empty = unused |

The repository ships these keys **empty**. Fill them locally and never commit the result:

```powershell
# Windows, elevated shell (reading Wi-Fi keys needs it). Copies the passphrases of saved profiles into the built kext.
.\scripts\inject-creds.ps1 -Kext Y:\EFI\OC\Kexts\itlmt7925.kext -Ssid 'HomeWifi','Cafe'
```

The script prints only name and passphrase lengths. The passphrase ends up in plain text inside the kext on your boot
medium: treat that medium like a password file. On macOS, edit the plist by hand or with `plutil -replace`.

A matching network is chosen automatically at boot. To switch while running, use ItlWiFi (below); the plist networks
are then only the boot-time default.

### Runtime control (ItlWiFi menu bar app)

Since 2026-10-11 the kext has a user client (`itlmt7925_uc.cpp`, ABI in `kexts/itlmt7925/itl_uc_abi.h`) and a supervisor
loop that owns the connection after the first scan. **Not yet run on hardware.**

* Commands: scan (at most one per 10 s), join `{ssid, passphrase}`, disconnect. Allowed for root and for the user logged in
  at the console. The worker thread takes them between steps; a join or disconnect while connected leaves the AP first
  (deauthentication, BSS record off, interface link down).
* Reconnect: deauthentication / disassociation from the AP, or 15 s with neither beacons nor data, ends the link; the
  supervisor connects again with back-off (1, 3, 5, 10, then every 30 s). A network picked from the app that never connects is
  given up after 3 attempts (`wifi-state` = `failed`, reason in `wifi-error`).
* Status, readable without privileges: `ioreg -rc itlmt7925 -d1 | grep wifi-` (`wifi-state`, `wifi-error`, `wifi-ssid`,
  `wifi-channel`, `wifi-rssi`, `wifi-rate`, `wifi-scan-gen`, `wifi-networks` with SSID, channel, signal, security, age).
* Signal: taken from the RX vector (RXD group 3, RCPI). The group layout is only trusted when it ends exactly where the
  802.11 header was found, otherwise the signal is reported as unknown (0).
* Scanning while connected uses the firmware scan with split dwell; the radio leaves the AP's channel briefly.

The app (`macos/ItlWiFi/`, Swift, no Xcode project): Wi-Fi icon in the menu bar (bars from the signal), network list
(strongest BSS per SSID, security, channel), a join form that replaces the list while it is open (what was typed is kept),
"Remember" stores the passphrase in `~/Library/Application Support/ItlWiFi/networks.json` (mode 0600; the keychain was used
first and prompted on every rebuilt, ad-hoc signed app), right-click menu on every network (Connect, Connect with a different
password, Forget, Copy name), auto-join of saved networks when not connected, Disconnect, Open at Login (a user LaunchAgent).
The list keeps its order between scans (new networks are inserted by saved / signal band, a full re-sort happens when the popover
opens or after the Scan button), so a click lands on the row that was under the pointer. A failed attempt is explained from
`wifi-events` (`hw-prep-fail`, `auth-fail`, `hs-fail` ...).

```bash
bash scripts/build.sh itlmt7925 && bash scripts/macos-install-kext.sh itlmt7925   # ESP; keeps your plist credentials
# with ItlDiag loaded macOS cannot mount the ESP (ItlDiag holds it for ITLLOG.BIN): then, from Linux,
#   bash /mnt/macos-vol0/Users/<you>/develop/projects/ga403wm-hackintosh/scripts/linux-install-kext.sh itlmt7925
bash scripts/build-itlwifi.sh --install                                           # /Applications/ItlWiFi.app
```

`scripts/macos-install-kext.sh --undo itlmt7925` puts the previous kext back (backups in `EFI/OC/Kexts-backup/`).

### Build

```bash
bash scripts/build.sh            # needs Xcode command line tools, builds build/itlmt7925.kext (+ the other kexts)
bash scripts/build.sh itlmt7925  # only this one
```

`scripts/build.sh` clones `acidanthera/MacKernelSDK` on first use. Without a Mac, the `build-kexts` GitHub workflow
builds the same on a macOS runner and uploads the kexts as an artifact. The host test (`test/`) checks the WPA2
primitives against Python reference vectors and runs in the same workflow.

## Reading the result

The driver logs to the verbose console, to properties on its registry entry (`m1-log`, `m2-log`, `m3-log`, `m3-res`) and to
firmware NVRAM, which survives a hang or panic and can be read from Windows or Linux. See `docs/DEBUGGING.md`. A successful run
ends with `RESULT rc=0 link up;ethernet interface created` in `itlk0..itlk7` and a line like
`up=145s rxd=5905 eapol=2 eth=5903 drop=0 tx=4698 fail=0` in `itls0`.

## Power tables are best effort (2026-10-12)

The first build with SAR / CLC / rate power limits (`itlmt7925_pwr.cpp`) made them mandatory: the efuse read of the hardware
type (0xa71) was rejected by the driver's own response checks and every join ended in `hw-prep-fail`
(`efuse hw type failed rc=-5` in `m3-log`). Linux (`mt7925_mcu_read_eeprom`) takes `data[off % 16]` of the 124-byte event and
checks no header field; the driver now does the same, keeps the first bytes of the event in `m3-log` when `tag`/`addr`/`valid`
are not what was asked, and a failure of any power-table step no longer stops the join (two tries per boot, then the firmware's
defaults, which is what the earlier measurements ran on).

## Hardware notes learned on the way

* The EFI of this repository ships `SSDT-Disable_Network_GPP5.aml`, which spoofs the ids of `\_SB.PCI0.GPP5.WLAN` so that
  macOS ignores the card. It has to be **disabled** for this driver, otherwise `IOPCIMatch 0x792514c3` never matches.
* The channel domain (`UNI_SET_DOMAIN_INFO`) has to be sent before the first scan; Linux does it once at start-up.
* The firmware's default channel dwell time (~35 ms) misses most beacons; the scan request sets 60 ms minimum / 120 ms.
