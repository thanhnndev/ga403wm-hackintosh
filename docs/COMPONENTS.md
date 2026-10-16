# Components: kexts, apps and tools

Every piece this repository builds (plus the pieces it depends on but does not own), what it does today, and how far along it
is. States: ✅ verified on the reference unit · 🟡 implemented, needs more testing · 🔧 in progress · ❌ not working ·
⚪ not started. "Reference unit" = the single GA403WM everything was developed on, macOS 15.8.1.

Reminder: this is a vibe-coded project (see the warning at the top of the [README](../README.md)).
Kexts run in the kernel.

## Kernel extensions (built from `kexts/`)

`bash scripts/build.sh [name...]` builds them on a Mac (Xcode command line tools). Install with
`scripts/macos-install-kext.sh <name>` (copies into the ESP's `EFI/OC/Kexts`, keeps a backup).

| Kext | Version | State | What it does today | Boot-args / knobs | Doc |
|---|---|---|---|---|---|
| **itlmt7925** | 0.1.0 | ✅ | MediaTek MT7925 Wi-Fi from scratch: firmware load, scan, WPA2-PSK (CCMP), DHCP, up to 4 saved networks. Rate control with HT/VHT/HE, Block Ack, A-MSDU RX, 160 MHz (`itlmt_fast`). User client + supervisor for the ItlWiFi app (scan, join, disconnect, reconnect with back-off). Exposes itself as Ethernet `itlmt7925Eth`. Reaches the full link speed. **Missing:** native Wi-Fi class (port in progress), WPA3, 6 GHz, open networks, power save, re-key | `itlmt_m1=0 itlmt_m2=1 itlmt_m3=1 itlmt_fast=6` | [WIFI.md](WIFI.md) |
| **ItlXhciKick** | 0.1.0 | ✅ | Services the second xHCI event ring of single-vector AMD controllers every 1 ms. Fixes USB keyboards/mice releasing keys ~2 s late. Nothing is patched or written | `itlkick=0` off, `itlkick=<us>` period | [USB-XHCI-LAG.md](USB-XHCI-LAG.md) |
| **AsusWmi** | 0.1.0 | ✅ | ASUS ATKD/WMI from the kernel (Linux `asus-wmi` calling convention): performance profile (Silent/Performance/Turbo), PPT limits SPL/SPPT/FPPT (AC/battery ranges for the GA403WM), fan curves read/write, fan RPM, battery charge limit, GPU MUX state (read only), battery EC readout fix, panel brightness query, **keyboard backlight** and **Slash lighting** (HID reports sent from the kernel), hotkeys through `_WED` (Fn+F2/F3/F4/F5). Registry/sysctl interface `debug.asuswmi.*` for the RogControl app | `sysctl debug.asuswmi.status` | [ASUSCTL-MACOS.md](ASUSCTL-MACOS.md) |
| **AmdCppc** | 0.2.1 | ✅ | CPU performance control for Zen 5 (macOS has none): reads/changes CPPC, boost, EPP on all 24 CPUs; per-CPU effective clock (APERF/MPERF), Tctl and RAPL package power for RogControl; PAT diagnostics. Writes only through root sysctls | `sysctl debug.amdcppc.*` | [CPU-POWER.md](CPU-POWER.md) |
| **MtkBtFw** | 0.1.0 | ✅ | Loads the MT7925 Bluetooth firmware over USB (Linux `btmtk` procedure) so `bluetoothd` finds a controller. Needs `BlueToolFixup`. Controller comes up with a real address; classic devices connect | `ioreg -rc MtkBtFw -l` | [BLUETOOTH.md](BLUETOOTH.md) |
| **BtLeDlFix** | 1.0.0 | ✅ | Lilu plugin: patches `bluetoothd` so it does not wait forever for the "LE Data Length Change" event (BLE mice stayed in `LE_READY_WAIT_FOR_LENGTH`). May stop matching after an OS update (nothing breaks, the mouse just fails again) | `-btledlfxoff`, `-btledlfxdbg` | [BLUETOOTH.md](BLUETOOTH.md) |
| **ItlDiag** | 0.1.0 | debug | Boot diagnostics (clocks, xHCI, HID census), log to NVRAM and to `ITLLOG.BIN` on the ESP. Off in daily use | `itldiag=<s> itlxr=2` | [DEBUGGING.md](DEBUGGING.md) |

## macOS user-space (built from `macos/`)

All are ad-hoc signed, x86_64, built without Xcode projects: `swiftc` + Command Line Tools. They need the matching kext
loaded. The first launch of an ad-hoc app can show a Gatekeeper prompt (right-click, Open).

### ROG Control (`RogControl.app`): the "Armoury Crate / asusctl" of this project

`bash scripts/build-rogcontrol.sh --install` builds it, copies it to `/Applications` and starts it at login. A normal launch
opens a window; `--background` runs it in the menu bar only. State: ✅ (working on the reference unit, confirmed 2026-10-12). Needs `AsusWmi` and, for CPU data, `AmdCppc`.

| Panel | What you get | State |
|---|---|---|
| **Overview / popover** | Performance mode buttons (Silent, Performance, Turbo, Manual; Turbo is disabled on battery like Armoury Crate), CPU temperature (Tctl), package power (RAPL), CPU and GPU fan RPM, charge limit presets (60/80/100 %), keyboard brightness, Slash settings | ✅ |
| **Performance** | Manual mode: SPL / SPPT / FPPT sliders (range checked for AC vs battery), fan base choice, firmware fan-curve charts for CPU/GPU (Swift Charts, explicit 20-105 °C axes, invalid points flagged instead of invented), separate settings for AC and battery re-applied on power-source change and login | ✅ |
| **Lighting** | Keyboard backlight level, Slash lighting mode/brightness/interval, re-sent after wake | ✅ |
| **Battery & Display** | Charge limit, battery health line (EC readout), GPU MUX state (read only). OLED brightness is not in the app: the system slider and Fn+F7 / Fn+F8 drive the panel through `NVRMEdpBL`; the old software dimmer was removed | ✅ |
| **Settings** | Open at login, details, quit | ✅ |
| **`--bench [s]`** | Runs Silent, Performance, Turbo under full load, prints power, Tctl, fans and Zen 5 / Zen 5c clocks, then restores your profile | ✅ |

Measured on the reference unit (AC, 15 s per mode): Silent 88 °C / ~2300 rpm, Performance 92 °C / ~2800 rpm, Turbo 95.8 °C /
~4400 rpm, with Zen 5 cores boosting to ~4.8 GHz (they sat at 2.0 GHz before `AsusWmi` + `AmdCppc`).
Design notes: [rog-control-design.md](rog-control-design.md).

**Not in RogControl yet:** GPU MUX switching and dGPU disable (deliberately read only: the NVIDIA driver is running), dynamic
boost / temperature target / TGP writes, panel overdrive (not in this BIOS), per-key Aura effects.

### ItlWiFi (`ItlWiFi.app`): the stop-gap Wi-Fi menu

`bash scripts/build-itlwifi.sh --install`. Menu bar popover for `itlmt7925`: current network and signal, scan list (stable
order), join with an inline password, right-click menu (Connect, Connect with a different password, Forget, Copy name),
saved networks in `~/Library/Application Support/ItlWiFi/networks.json` (mode 0600), auto-join, disconnect, open at login,
and a **speed test** (curl bound to the Wi-Fi interface; several providers). State: ✅. It exists because the driver is not a real
Wi-Fi device, so macOS has no Wi-Fi menu for it. The driver still needs credentials injected for the first connection
([INSTALL.md](INSTALL.md#4-wi-fi-inject-your-network)).

### TapGuard (`TapGuard.app`)

`bash scripts/build-tapguard.sh --install` (needs Accessibility permission). Drops mouse clicks within 350 ms of a key press
("ignore trackpad taps while typing"; `defaults write com.itlmt7925.TapGuard QuietMs -int 350`). State: ✅. For the I2C touchpad,
which works again (2026-10-12).

### AmdCppcPolicy (root launch daemon)

`scripts/build-amdcppc-policy.sh`, then install `scripts/macos-amdcppc-policy-install.sh` with administrator rights
(`--undo` removes it). Every 5 s it enables CPPC, checks all 24 CPUs and sets the autonomous EPP from the ASUS profile and
power source (AC Performance 128, AC Turbo 0, battery 191, Silent 255); pauses during sleep and restores after wake. State: ✅
(one full live round, sleep/wake included). Table and rollback: [CPU-POWER.md](CPU-POWER.md).

## Not ours, but required

| Piece | Role | State | Where |
|---|---|---|---|
| **OpenCore 1.0.9 + `fix-zen5-fsb.diff`** | boot loader; the patch fixes the Zen 5 FSB calculation | ✅ | [patches/opencore](../patches/opencore), `opencore` workflow |
| **NullMoth NVIDIA driver** (1.15.0) | RTX 5060 + OLED framebuffer, Metal-over-Vulkan | ✅ (third-party, PolyForm Noncommercial) | <https://github.com/nullmoth/nvidia-macos-driver>, [NULLMOTH.md](NULLMOTH.md) |
| ~~NVRMFB VRAM-clear patch~~ | dropped 2026-10-13: the slow clear (8 MB per 0.7-1.1 s) was the PAT slot; with PA6 = WC upstream's `rep stosq` does ~1 GB/s | ➖ not needed | [VRAM-GRANT-STALL.md](VRAM-GRANT-STALL.md), fork tag `ga403wm-with-vramclear` |
| **NVRMEdpBL** | OLED brightness over eDP AUX (DPCD `0x722/3`) | ✅ works (confirmed 2026-10-12); not sent upstream yet | [fork](https://github.com/thanhnndev/nvidia-macos-driver/tree/ga403wm) branch `ga403wm` (`kexts/NVRM/nvrm_edpbl.cpp`, `kexts/NVRMEdpBL`), [OLED-BRIGHTNESS-DPCD.md](OLED-BRIGHTNESS-DPCD.md) |
| **WindowServer PAT patch** | PA6 = write-combining instead of UC- | ✅ | [WINDOWSERVER-RESEARCH.md](WINDOWSERVER-RESEARCH.md) |
| Acidanthera, Voodoo, ... kexts | Lilu, VirtualSMC, AppleALC, VoodooI2C, ... | see list | [../efi/KEXTS.md](../efi/KEXTS.md) |

## Tools and scripts worth knowing

Every script, with where to run it, root needs and undo: **[SCRIPTS.md](SCRIPTS.md)** (HiDPI guide in §4). Highlights:

| Path | Use |
|---|---|
| `scripts/inject-creds.ps1` | put SSID/password(s) into `itlmt7925.kext` (Windows) |
| `scripts/macos-install-kext.sh` | install a built kext on the ESP, with backup and `--undo` |
| `scripts/export-efi.py`, `scripts/check-efi-privacy.py` | write `efi/` from a working EFI with placeholders; fail if real SMBIOS slipped in |
| `scripts/linux-collect-logs.sh`, `scripts/setup-linux-access.sh` | collect OpenCore logs, `ITLLOG.BIN`, panic reports from Linux |
| `scripts/restore-limine-entry.ps1`, `scripts/esp-cleanup.sh` | dual-boot repair, ESP housekeeping |
| `tools/cpuclock.c`, `tools/framepace.swift`, `tools/hidpi-try.swift` | CPU clock probe, frame pacing, HiDPI experiments |
| `tools/kc.py` | explore the macOS kernel collection: symbols, vtables, disassembly (for the `IO80211` research) |
| `tools/occonfig.py` | typed get/set/check/diff for `config.plist` (safer than hand-editing the plist) |
