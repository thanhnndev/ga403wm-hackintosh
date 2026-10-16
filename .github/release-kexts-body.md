> ## ⚠️ Vibe-coded, one-laptop project
> Almost all of this code was written by an AI (Claude) and tested on **one** ASUS ROG Zephyrus G14 **GA403WM**. The kexts run in
> the macOS kernel and can panic or hang the machine. No warranty. Back up first. **macOS 15 (Sequoia) only; macOS 26 is not supported.**

Kexts-only update to [v1](https://github.com/thanhnndev/ga403wm-hackintosh/releases/tag/v1). **No OpenCore build and no
reference EFI in this release**: keep the OpenCore and `config.plist` you have. Everything else in v1 (apps, `AmdCppcPolicy`,
the other kexts) is unchanged and still comes from v1.

### What changed

* **Native Wi-Fi front end `itlmt7925Native.kext` (new, opt-in).** The MT7925 appears as a real Wi-Fi interface: Wi-Fi menu,
  scan and WPA2-PSK join from System Settings, no network name or password inside the kext. Measured on the reference unit:
  28-36 MB/s on one TCP stream (`networkQuality` 293 Mb/s down, 45 Mb/s up).
* **`itlmt7925.kext` (core), rounds 17-26d.** Link-loss recovery with firmware reload, firmware MAC, RX ring 512, run-time control,
  diagnostics; **A-MSDU is off by default** (with it on, TCP collapsed to ~50 KB/s; cause not known; `itlmt_amsdu=1` re-enables it).

### What is in this release

| File | What | Install |
|---|---|---|
| `itlmt7925.kext.zip` | MT7925 core driver (credentials **empty**; needed for both modes) | ESP `EFI/OC/Kexts` |
| `itlmt7925Native.kext.zip` | native Wi-Fi front end, idle without `itlmt_native=1` | ESP, **after** the core |
| the other `*.kext.zip`, `*.app.zip`, `AmdCppcPolicy.zip` | rebuilt from the same commit, same function as in v1 | as in v1 |
| `SHA256SUMS.txt`, `LICENSE`, `LICENCE.mediatek` | checksums, licenses | |

### Use it

1. **Legacy mode (default, nothing to change):** replace `itlmt7925.kext` on the ESP (inject your network as in INSTALL.md §4).
2. **Native mode (opt-in):** also install `itlmt7925Native.kext` and add the boot-args
   `itlmt_native=1 itlmt_native_if=1 itlmt_native_dp=1 itlmt_fast=6`. Full steps, checks and the way back:
   [docs/WIFI-DRIVERS.md](https://github.com/thanhnndev/ga403wm-hackintosh/blob/main/docs/WIFI-DRIVERS.md).
   Have a wired or tethered connection ready the first time.

Not available in either mode: WPA3, open networks, 6 GHz, AirDrop / AWDL (next workstream:
[docs/ROADMAP-AWDL.md](https://github.com/thanhnndev/ga403wm-hackintosh/blob/main/docs/ROADMAP-AWDL.md)). Native mode is
still being tested: sleep/wake, a chip recovery and long uptime are not verified.

---
