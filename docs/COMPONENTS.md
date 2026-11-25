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
| **itlmt7925**, **itlmt7925Native** | - | ✅ | MT7925 Wi-Fi (legacy Ethernet mode + native Wi-Fi front end): **moved to [mt7925-macos](https://github.com/thanhnndev/mt7925-macos)** with its own guide, roadmap and releases |
| **ItlXhciKick** | 0.1.0 | ✅ | Services the second xHCI event ring of single-vector AMD controllers every 1 ms. Fixes USB keyboards/mice releasing keys ~2 s late. Nothing is patched or written | `itlkick=0` off, `itlkick=<us>` period | [USB-XHCI-LAG.md](USB-XHCI-LAG.md) |
| **AsusWmi** | - | ✅ | ROG profiles, fans, charge limit, lights: **moved to [rog-control-macos](https://github.com/thanhnndev/rog-control-macos)** (release `rog-v1.0`) | - | [docs](https://github.com/thanhnndev/rog-control-macos/blob/main/docs/ASUSCTL-MACOS.md) |
| **AmdCppc** | - | ✅ | Zen 5 CPPC, clocks, Tctl, RAPL: **moved to [rog-control-macos](https://github.com/thanhnndev/rog-control-macos)** | - | [docs](https://github.com/thanhnndev/rog-control-macos/blob/main/docs/CPU-POWER.md) |
| **MtkBtFw** | - | ✅ | MT7925 Bluetooth firmware loader: **moved to [mt7925-macos](https://github.com/thanhnndev/mt7925-macos)** (release `bt-v1.0`) | - | [docs](https://github.com/thanhnndev/mt7925-macos/blob/main/docs/BLUETOOTH.md) |
| **BtLeDlFix** | - | ✅ | BLE fix (Lilu plugin): **moved to [mt7925-macos](https://github.com/thanhnndev/mt7925-macos)** (release `bt-v1.0`) | - | [docs](https://github.com/thanhnndev/mt7925-macos/blob/main/docs/BLUETOOTH.md) |
| **ItlDiag** | 0.1.0 | debug | Boot diagnostics (clocks, xHCI, HID census), log to NVRAM and to `ITLLOG.BIN` on the ESP. Off in daily use | `itldiag=<s> itlxr=2` | [DEBUGGING.md](DEBUGGING.md) |

## macOS user-space (built from `macos/`)

All are ad-hoc signed, x86_64, built without Xcode projects: `swiftc` + Command Line Tools. They need the matching kext
loaded. The first launch of an ad-hoc app can show a Gatekeeper prompt (right-click, Open).

### ROG Control (`RogControl.app`)

Moved to [rog-control-macos](https://github.com/thanhnndev/rog-control-macos) with `AsusWmi`, `AmdCppc` and `AmdCppcPolicy` (design notes, screenshots, build and release `rog-v1.0` are there).

### ItlWiFi (`ItlWiFi.app`)

Moved to [mt7925-macos](https://github.com/thanhnndev/mt7925-macos) together with the Wi-Fi driver.

### TapGuard (`TapGuard.app`)

`bash scripts/build-tapguard.sh --install` (needs Accessibility permission). Drops mouse clicks within 350 ms of a key press
("ignore trackpad taps while typing"; `defaults write com.itlmt7925.TapGuard QuietMs -int 350`). State: ✅. For the I2C touchpad,
which works again (2026-10-12).

### AmdCppcPolicy (root launch daemon)

Moved to [rog-control-macos](https://github.com/thanhnndev/rog-control-macos) (`docs/CPU-POWER.md`).

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
| `scripts/macos-install-kext.sh` | install a built kext on the ESP, with backup and `--undo` |
| `scripts/export-efi.py`, `scripts/check-efi-privacy.py` | write `efi/` from a working EFI with placeholders; fail if real SMBIOS slipped in |
| `scripts/linux-collect-logs.sh`, `scripts/setup-linux-access.sh` | collect OpenCore logs, `ITLLOG.BIN`, panic reports from Linux |
| `scripts/restore-limine-entry.ps1`, `scripts/esp-cleanup.sh` | dual-boot repair, ESP housekeeping |
| `tools/cpuclock.c`, `tools/framepace.swift`, `tools/hidpi-try.swift` | CPU clock probe, frame pacing, HiDPI experiments |
| `tools/kc.py` | explore the macOS kernel collection: symbols, vtables, disassembly (for the `IO80211` research) |
| `tools/occonfig.py` | typed get/set/check/diff for `config.plist` (safer than hand-editing the plist) |
