> ## ⚠️ Vibe-coded, one-laptop project
> Almost all of this code was written by an AI (Claude) and tested on **one** ASUS ROG Zephyrus G14 **GA403WM**. The kexts run in
> the macOS kernel and can panic or hang the machine; `AsusWmi` and `AmdCppc` write to the EC, the BIOS and CPU registers.
> No warranty. Back up first. **macOS 15 (Sequoia) only; macOS 26 is not supported.**

First public build. "v1" is the version of this bundle; the kexts carry their own internal versions (0.1.x / 0.2.x).

### What is in this release

| File | What | Install |
|---|---|---|
| `itlmt7925.kext.zip` | MT7925 Wi-Fi (credentials **empty**: inject yours) | ESP `EFI/OC/Kexts` |
| `ItlXhciKick.kext.zip` | USB lag fix, **required** | ESP |
| `AsusWmi.kext.zip` | ROG profiles, fans, charge limit, lights | ESP |
| `AmdCppc.kext.zip` | Zen 5 CPPC / boost / EPP | ESP |
| `MtkBtFw.kext.zip` | MT7925 Bluetooth firmware loader | ESP |
| `BtLeDlFix.kext.zip` | BLE mouse fix (Lilu plugin) | ESP |
| `ItlDiag.kext.zip` | boot diagnostics (debug only) | ESP, optional |
| `RogControl.app.zip` | ROG Control: menu bar + window | `/Applications` |
| `ItlWiFi.app.zip` | Wi-Fi menu: scan, join, speed test | `/Applications` |
| `TapGuard.app.zip` | ignore touchpad taps while typing | `/Applications` |
| `AmdCppcPolicy.zip` | CPU policy launch daemon (binary) | `scripts/macos-amdcppc-policy-install.sh` |
| `OpenCore-1.0.9-zen5-fsb.zip` | OpenCore 1.0.9 with the Zen 5 timer patch (if the build step succeeded) | ESP |
| `EFI-reference.zip` | *sanitized reference*: `config.plist` (placeholder SMBIOS, debug off, legacy Wi-Fi boot-args, NVIDIA values in the installer-safe state), SSDTs, the author's `UTBMap.kext` for this laptop, kext list. **PolyForm Noncommercial**. No OpenCore binaries, drivers or third-party kexts inside | see INSTALL |
| `SHA256SUMS.txt`, `LICENSE`, `LICENCE.mediatek` | checksums, licenses | |

Third-party kexts (Lilu, VirtualSMC, VoodooI2C, ...) are **not** included: see `efi/KEXTS.md`.

**NVIDIA (RTX 5060 + the OLED):** not included either. Use [NullMoth's driver](https://github.com/nullmoth/nvidia-macos-driver) through our fork, branch [`ga403wm`](https://github.com/thanhnndev/nvidia-macos-driver/tree/ga403wm) (upstream 1.14.7 + OLED brightness over eDP AUX + faster VRAM clear, source only, PolyForm Noncommercial). Steps: [INSTALL.md §7](https://github.com/thanhnndev/ga403wm-hackintosh/blob/main/docs/INSTALL.md#7-nvidia-driver-rtx-5060--the-oled).

### How to use it

1. Read [docs/INSTALL.md](https://github.com/thanhnndev/ga403wm-hackintosh/blob/main/docs/INSTALL.md) (Vietnamese: `INSTALL.vi.md`) and
   [docs/SCRIPTS.md](https://github.com/thanhnndev/ga403wm-hackintosh/blob/main/docs/SCRIPTS.md).
2. Unzip the kexts and `AmdCppcPolicy` into `build/` of a clone so the install scripts find them
   (`scripts/macos-install-kext.sh <name>` reads `build/<name>.kext`). Apps: unzip into `/Applications`, then
   `xattr -dr com.apple.quarantine /Applications/RogControl.app` (same for the others): they are ad-hoc signed, not notarised.
3. Inject your Wi-Fi network into `itlmt7925.kext` before copying it to the ESP.

Known limits: Wi-Fi shows up as Ethernet (native Wi-Fi is being ported), WPA2-PSK only; sleep/wake, audio, SD reader and battery % are not verified. Full list: [docs/ROADMAP.md](https://github.com/thanhnndev/ga403wm-hackintosh/blob/main/docs/ROADMAP.md).

---
