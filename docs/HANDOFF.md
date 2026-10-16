# Handoff: state of the GA403WM macOS bring-up (2026-10-12)

Where the work stands, what is proven, what is open, and how to get data. Written to continue on the macOS side.
No SMBIOS values, passphrases, MACs or neighbour SSIDs belong in this file.

## Status update 2026-10-12 (confirmed by the owner)

The numbered "Open issues" below are the 2026-10-11 investigation log. As of 2026-10-12 the owner reports these as **fixed**:

| Item | Now | Where the details are / what is still missing from the notes |
|---|---|---|
| 1. Trackpad (I2C `ASUP1208`) | **works** | cause (owner-reported 2026-10-12): it is dead after a **warm reboot from Windows into macOS**; a **full shutdown and cold power on** fixes it. Boot macOS from cold, or shut down after Windows |
| 7. HiDPI | **works, 2x** ("looks like 1440 x 900", like Windows 200 % scaling) | [SCRIPTS.md §4](SCRIPTS.md#4-hidpi-looks-like-1440-x-900-step-by-step); fractional scales are not supported |
| 10. Wi-Fi throughput (`itlmt7925`) | **full link speed** (HE, 160 MHz) | the owner measured it at the maximum speed; the numbers (`iperf3`, AP model, band, distance) will be supplied by the owner later for comparison: [WIFI.md](WIFI.md). Not measured by the agent |
| 13. Bluetooth, BLE mouse | **works** (`MtkBtFw` + `BtLeDlFix`) | [BLUETOOTH.md](BLUETOOTH.md) |
| ROG controls | **all working**: profiles, power limits, fan curves/speeds, charge limit, keyboard light, Slash, RogControl | section "ASUS controls" below |
| OLED brightness | **works** (`NVRMEdpBL`, DPCD AUX) | [OLED-BRIGHTNESS-DPCD.md](OLED-BRIGHTNESS-DPCD.md) (checklist results recorded 2026-10-12); the software dimmer was removed from RogControl (2026-10-12) |
| 4. Wi-Fi shows as Ethernet | **native port in progress** | [WIFI-AS-WIFI.md](WIFI-AS-WIFI.md); `itlmt7925` stays as the fallback |

Still open: sleep/wake (broad testing), audio, SD reader, battery %, a second owner reproducing the install, the USB map and the
standard EFI in the release, upstreaming the NullMoth patch (AUX backlight; the VRAM clear was dropped 2026-10-13). Plan: [ROADMAP.md](ROADMAP.md).

### Measure-and-record session 2026-10-12: skipped on purpose (decided by the owner), and not measurable

Nothing below is a result. These are the items the session did **not** produce numbers or screenshots for, and why, so nobody
reads a gap as a pass.

| Item | Status | Why / what is needed |
|---|---|---|
| Wi-Fi throughput numbers (`iperf3`, latency, loss) | **skipped by the owner** | the link is at full speed (HE, 160 MHz) per the owner; the figures are supplied later and go into [WIFI.md](WIFI.md) with AP model, band and distance |
| Battery drain / battery life | **skipped by the owner** | no promise is made ([ROADMAP.md](ROADMAP.md) row 24); the short on-battery bench (40 %, Silent / Performance) is in [ASUSCTL-MACOS.md](ASUSCTL-MACOS.md) and is not a drain test |
| Sleep / wake, 5 cycles | **skipped by the owner** | sleep/wake is a known ❌ and roadmap row 22; the machine is used plugged in, without deep sleep |
| Clean-up of the **live** ESP boot-args | **skipped by the owner** | the live config keeps its debug and `itlmt_native*` experiment arguments. Only the **exported release EFI** (made by `scripts/export-efi.py`, outside the repo) is cleaned: there `debug=0x100 keepsyms=1 msgbuf=1048576` and `itlmt_native=1 itlmt_native_if=1` are removed, `itlmt_m2=1 itlmt_m3=1 itlmt_fast=6` added (`itlmt_m1=0` kept), `itlmt7925Native.kext` disabled; `ocvalidate` clean, privacy check clean. The cleaned config has **not been booted** |
| ItlWiFi screenshot | **skipped on purpose** | the owner is porting the native Wi-Fi stack; the menu app is not representative until that lands, so no shot was taken. Add `itlwifi.png` afterwards |
| RogControl Manual mode, power limits | **new finding, not investigated** | 2026-10-13, popover, on AC, coming from Turbo: choosing Manual switched the UI and the fan mode but showed "power limit 45 W was refused" (defaults SPL 45 / SPPT 65 / FPPT 80 W); choosing Turbo again applied cleanly. Needs a look at which `Asus.set(.spl)` return code the kext gives and why |
| App screenshots (RogControl popover / window / fan curves, About This Mac) | **done 2026-10-13** | PNGs in [images/](images/README.md); About This Mac redacted (name, serial). Hero (`hero.jpg`) composed from those shots; no OpenCore picker shot (dropped); TapGuard has no UI |
| Fn+F7 / Fn+F8 visible dimming, other Fn keys | **not measured** | needs a person to look at the panel and press the keys ([ROADMAP.md](ROADMAP.md) row 23) |
| Touchpad tap / scroll / TapGuard, BLE re-pair | **not measured** | needs hands on the device |
| Audible audio, SD card insert, lid close, external monitor hot-plug | **not measured** | needs a person (sound, a card, the lid); the devices only enumerate (card reader `10ec:525a` with `Sinetek-rtsx` loaded, internal audio, the ASUS webcam) |
| Charge limit read-back | **not available** | RogControl writes 60 % at login; the firmware offers no read-back that this session could use |

## ASUS controls, RogControl and Bluetooth LE (was missing from this file)

Details live in [ASUSCTL-MACOS.md](ASUSCTL-MACOS.md), [CPU-POWER.md](CPU-POWER.md), [BLUETOOTH.md](BLUETOOTH.md) and
[rog-control-design.md](rog-control-design.md); this is the summary a new session needs.

* **`AsusWmi.kext`** (ABI 1-3) calls the ASUS ATKD/WMI device from the kernel (`ATKD.WMNB`, 20-byte argument buffer, `DSTS`/`DEVS`) the way
  Linux `asus-wmi` does: performance profile (0 balanced = "Performance", 1 turbo, 2 silent; DSTS always returns 3 on this BIOS, so the
  last set value is tracked), PPT limits through AMD ALIB (the BIOS does not report them), fan curves and speeds, charge limit, battery
  EC readout fix (`EC0._REG(3,1)`), keyboard light and Slash lighting (HID reports `0x5A` / `0x5D` sent from the kernel because user
  space cannot open the keyboard without Input Monitoring), hotkeys through `_WED` (Fn+F2/F3/F4/F5). Interface: `debug.asuswmi.*`.
* The profiles are what lifted the **2000 MHz cap on the Zen 5 cores**; together with `AmdCppc` + `AmdCppcPolicy` they now boost to
  ~4.9 GHz under load (see the CPU section at the end of this file).
* **`RogControl.app`** (menu bar popover + window): modes, Manual SPL/SPPT/FPPT, fan curves, charge limit, keyboard light, Slash,
  AC/battery settings re-applied on power change and wake, `--bench`. Build/install: `scripts/build-rogcontrol.sh --install`.
* **OLED brightness**: the panel is AUX-only; the fix is `NVRMEdpBL` (DPCD `0x722/3`, mode `0x721 = 2`), see the OLED document. The
  EC backlight (`WMAA`, GBLD/SBLD) is not the OLED's; `AsusWmi` leaves it alone on the brightness keys.
* **Bluetooth**: `MtkBtFw` downloads the MT7925 firmware over USB (Linux `btmtk` procedure), `BlueToolFixup` makes `bluetoothd` accept
  the controller, and **`BtLeDlFix`** (Lilu plugin, patches one `cmp eax,8` in `bluetoothd`) removes the wait for the LE Data Length
  Change event that kept BLE mice in `LE_READY_WAIT_FOR_LENGTH`. It must be re-derived if an OS update changes the bytes.

## Public repository and releases (added 2026-10-12)

* The repository is being prepared for public use: README (EN/VI) with a vibe-code warning and a status table, install guides
  ([INSTALL.md](INSTALL.md), [INSTALL.vi.md](INSTALL.vi.md)), [COMPONENTS.md](COMPONENTS.md), [SCRIPTS.md](SCRIPTS.md) (every script, undo,
  author-specific flags, HiDPI walkthrough), [ROADMAP.md](ROADMAP.md) (workstreams, milestones, codebase standardisation), issue
  templates. **macOS 15 only; macOS 26 is out of scope** until 15 is stable.
* **Release v1** (not tagged yet): `build-kexts` (`.github/workflows/build.yml`) builds the 7 kexts, the 3 apps and `AmdCppcPolicy`,
  and on a `v*` tag attaches them with the patched OpenCore (`opencore.yml`), a sanitized `EFI-reference.zip` and `SHA256SUMS.txt`
  (text: `.github/release-body.md`). The app and OpenCore build steps had never run in CI before this commit: run `build-kexts`
  by hand and check before tagging. Kexts in releases always carry empty Wi-Fi credentials.
* The **author's tested standard EFI** (real USB map, tested settings) is uploaded to the release **later** by the owner; run
  `python3 scripts/check-efi-privacy.py` on its `config.plist` first. README/INSTALL carry a "coming soon" note to remove then.
* **Standardisation rule**: no cleanup or renaming of a component before it passes the stability gate (14 days of daily use, a second
  machine, a baseline). The clock for the components fixed on 2026-10-12 started that day. See the roadmap.

## Machine and boot chain

* ASUS ROG Zephyrus G14 GA403WM, Ryzen AI 9 HX 370 (Strix Point), RTX 5060 Laptop (GB206), MT7925 Wi-Fi/BT,
  2880x1800 OLED (SDC `ATNA40CU05-0`, 120 Hz capable). BIOS GA403WM.310. macOS 15.8.1 (24H32, kernel 24.6.0) on the internal disk.
* OpenCore 1.0.9 boots from the **internal ESP** (NVMe partition 1). The USB stick is optional. Windows and Linux (Limine)
  are started from the OpenCore picker.
* The ESP `EFI/OC/config.plist` was generated by NullMoth's "1401" app and then edited by hand. **Do not re-run 1401
  "Build" on the ESP**: it overwrites `config.plist` (UTBMap, the ALIB patch, `itlmt_*` boot-args and `ItlDiag` are ours).
  The sanitized reference is `efi/OC/config.plist`.
* GPU mode was switched to **Ultimate (MUX -> dGPU only)** in Armoury Crate. In Hybrid mode the OLED is wired to the AMD
  iGPU and macOS has no driver for it; NullMoth's NVRMFB then reports `only 0 display(s) connected` and macOS has no
  framebuffer. NullMoth's own docs (`MUX_HELP`) say the same.

## What works (proven by `ITLLOG.BIN` on the ESP, boot of 13:49 UTC)

| Area | Result |
|---|---|
| Boot from ESP with `itlmt7925` + `ItlDiag` | up, ran about 10 min, 137 diag blocks |
| USB map (UTBMap, XHC0 ports 1-7) | webcam, mouse, BT `0489:e11e`, internal keyboard `0b05:19b6`, `hid=5` |
| ACPI `ACAD._PSR` ALIB patch | applied by OpenCore (`replaced 1 of 1`), no ACPI errors on screen or in the file |
| Wi-Fi (`itlmt7925`, `itlmt_fast=6`) | firmware ready, scan, WPA2 4-way handshake, link up (L6), DHCP/ARP/DNS, `tx=33653 fail=0 rxpk=41348` after 355 s |
| Raw log file on the ESP | `ItlDiag` writes `ITLLOG.BIN` in the ESP root through IOMedia (no stick needed) |

## Open issues (highest value first)

1. **[RESOLVED 2026-10-12; cause: warm reboot from Windows into macOS, fix: full shutdown and power on (owner-reported)] Trackpad dead on Windows and macOS.** Windows: `I2C HID Device ACPI\ASUP1208` problem 10, status `0xC000009E`
   (device not ready); AMD I2C and GPIO controllers are OK. macOS: `TPD1` has a `VoodooI2CDeviceNub` but no HID child.
   Windows logged "Touchpad QA verification succeeded" on every boot until 2026-10-10 19:51 local; it was missing from
   the 19:59 boot on. That is after the macOS session of 12:55 UTC (the first with `itlmt7925` enabled since a bisect)
   and **before** the ALIB patch was written (20:05) and before Ultimate mode. ALIB and `XOSI` patches are not the cause
   (ALIB only replaces one call inside `ACAD._PSR`; `XOSI` passes through for non-Darwin). Not proven what kills it.
   Next test: full power drain (shutdown, unplug AC, hold power 40 s), then check Windows Device Manager. If it comes
   back, bisect `itlmt7925` / VoodooI2C / VoodooGPIOAMD one at a time.
2. **Black screen / flicker with Ultimate mode (120 Hz).** Data recovered from Linux by decoding the macOS unified log
   (tracev3 + uuidtext, `mandiant/macos-unifiedlogs`) of the boots at 13:49 and 14:15 UTC on 2026-10-10:
   * NVRM, GSP, NVRMFB, NVAccel all come up; no GPU error, Xid, timeout or panic report in either boot.
   * The firmware/GOP raster is **2880x1800 @ 120 Hz** (total 2980x1824); NVRMFB adopts it as dt 0x10100 with no modeset.
   * The saved WindowServer prefs (`/Library/Preferences/com.apple.windowserver.plist`, ByHost) pin mode `0x10000`
     (60 Hz, vtotal 3648). At login WindowServer therefore does a real NVKMS modeset 120 -> 60 Hz.
   * User report: first modeset to 60 Hz was visible; switching to 120 Hz flickered/went black; back to 60 Hz black;
     every later boot black at login. Pattern matches "the first NVKMS modeset works, later ones do not". Not proven.
   * Anomaly: `NVRM-xnu: post #N caller chain (nv_post_event ... isr-thread 1)` reached 1,000,000 events in ~5 min.
   * Plan in progress: make 120 Hz the preferred mode and drop the pinned 60 Hz prefs so no modeset happens after
     the boot raster (an EDID display override, since removed, see 3.).
   Old note: NullMoth's `NVRM-fb:` lines are in the unified log (`log show --last 20m | grep -E "NVRM|NVAccel"`).
   Knobs in the NullMoth kexts (strings of 1.0.8): `-nvoff`, `-nvrmnogo`, `nvhwvbl=0`, `nvcursor=0`, `nvhud=1`,
   `nvfbsample=1`, sysctl `debug.nvrmfb_flip_latch`, `debug.nvaccel_iop`, `debug.nvaccelfb`. Do not toggle them blindly.
3. **UI scale 2 (HiDPI) and 120 Hz.** *(2026-10-11: superseded by driver 1.10.0, which offers DisplayID-only modes itself, see
   `NULLMOTH.md`. Installed here is 1.9.0.)*
   * Base EDID DTD is only 2880x1800 @ 60.001 Hz (pclk 652.27 MHz, total 2980x3648). The 120 Hz mode exists only in
     the DisplayID 2.0 block (Type VII, total 2980x1824, 120.000 Hz, same pclk), which macOS does not parse.
   * NVRMFB takes its timing list from the framebuffer family (`setDetailedTimings`) and NVKMS accepts only real EDID
     modes; the boot raster is the firmware mode, which is 120 Hz ("no modeset"); WindowServer then asks for 0x10000 (60 Hz) from its saved prefs.
   * Tried and dropped: a macOS display override (EDID with a 120 Hz base DTD). The generator and sources were removed from
     the repo. Checked on macOS 2026-10-11: `/Library/Displays/Contents/Resources/Overrides` is empty, it was never installed.
     The panel boots and stays at 120 Hz on 1.13.0. HiDPI without touching the EDID: item 7.
4. **[native port in progress 2026-10-12] Wi-Fi shows as Ethernet** in macOS (works: en2, DHCP). Runtime control: see 8. Clean-room `IO80211Controller` subclass (plan in `WIFI-AS-WIFI.md`, extract
   the ABI from the kernel collection with `tools/kc.py`; do not copy GPL `itlwm`). Step 1 (controller vtable, 12 pure virtuals)
   is in `IO80211-ABI.md`; the kernel collection is available at `Previous Content/com.apple.installer/` on the Data volume,
   so no BaseSystem.dmg download is needed. Skywalk interface and `apple80211_*` structs are not mapped yet.
5. Housekeeping: old kext backup `itlmt7925.e8df337.old` in the ESP root. (Retired remote branches `ccr-fc111298-ip8jp5`,
   `diag-esp-log`, `diag-mirror-m2m3` were deleted 2026-10-11 with the owner's permission.)

6. **Desktop lag** (NullMoth 1.13.0, 2880x1800 @ 120 Hz, measured 2026-10-11; details in `NULLMOTH.md`). Composition sustains
   ~116 flips/s while a window is dragged; the lag is spikes. Two causes found:
   * NVRMFB clears every new VRAM grant with byte stores over BAR1 (upstream PR #64 measured ~180 ms per 8 MB). Local fix:
     `scripts/macos-nullmoth-vramclear.sh` (49-byte patch of the 1.13.0 binary, harness-verified, `--undo`). Measure with
     `scripts/macos-vramtest.sh` before/after. Before: **0.7-1.1 s per 8 MB grant**. Patch applied 2026-10-11 00:52 local
     (auxKC rebuilt with all four kexts); takes effect at the next boot. After-numbers: pending.
   * NullMoth exports `MESA_SHADER_CACHE_DIR`; the Terminal process tree inherited root's cache dir, so Metal programs started
     from a shell run without a shader cache. Workaround `scripts/zshrc-nullmoth.sh`; plugin fix to be reported upstream.
   (The 1.9.0 lead "every cursor move is a primary flip" was fixed upstream in 1.10.0; installed now is 1.13.0.)
   Tools: `tools/framepace.swift` (no sudo), `scripts/macos-ws-frame-sample.sh` (sudo, WindowServer sample of the same frames).

7. **HiDPI: only "1440 x 900" works on NullMoth 1.13+; update 2026-10-11 19:13: with the round-f override below it works from System Settings at 120 Hz (user report; user guide: [SCRIPTS.md §4](SCRIPTS.md#4-hidpi-looks-like-1440-x-900-step-by-step)). The rest of this item is the chronological investigation and its early conclusions are superseded.** Original text: not possible on NullMoth 1.13 (2026-10-11, measured). With the scale-resolutions override macOS offers no HiDPI
   mode at all (every mode has points == pixels; listed with CGDisplayCopyAllDisplayModes). "1440 x 900" is a low-resolution
   mode `0x80001000`: NVRMFB implements it as a 1440x900 surface scaled by NVKMS to the 2880x1800 raster, the NVKMS test commit
   fails (`switchMode 0x80001000: test 1440x900 -> raster 2880x1800 ... -> 0`), NVRMFB stays on 0x10100 while WindowServer has
   switched: black screen with flips still running (display-trace of 01:11:36). Every scaled mode takes the same path.
   **Cause found (2026-10-11, round d):** the override's entries were `w h 1 0x200000`; 0x200000 is
   `kDisplayModeValidForMirroringFlag`, which alone makes a mode mirror-only. IOGraphicsLib installed them in NVRMFB
   (`IOFBConfig` has 3360x2100 and 2560x1600 with flags 0x00200003) but CoreGraphics drops them, so no HiDPI mode was built.
   Apple's own override for the 2880x1800 MacBook Pro panel (`DisplayVendorID-610/DisplayProductID-a013`) uses
   `w h 9 0xa00000` (always | mirror deps, valid for HiRes | mirroring); `scripts/macos-install-hidpi.sh` now writes that.
   `hidpi-try list --all` prints every mode with its flags. Result after reboot: the HiRes modes are installed (flags
   0x00a00003) and CoreGraphics still hides them; the 2880x1800 entry is dropped as a duplicate of the native mode.
   **But WindowServer's own table (private `CGSGetDisplayModeDescriptionOfLength`) has density-2 modes**: "1440 x 900"
   on the native 2880x1800 mode (60 and 120 Hz), 1680x1050 and 1280x800. `CGDisplayCopyAllDisplayModes` leaves them out
   (NVRMFB's `getInformationForDisplayMode` reports its own flags, never HiRes). `hidpi-try 1440` now falls back to
   that table and switches with `CGSConfigureDisplayMode` (as displayplacer does), native backing only, 15 s auto-revert.
   **Round f (2026-10-11):** that switch is refused: `CGCompleteDisplayConfiguration` returns 1007 and WindowServer logs
   "CGXCompleteDisplayConfiguration: Monitor ...; Mode 65792 not available" (65792 = 0x10100, the native 120 Hz mode).
   The density-2 copies of the native modes carry flag 0x80000000 (not available) because the native NVRMFB mode has no
   HiRes flag. The override now holds one entry, `2880 1800 1 0x800000` (always, HiRes, not mirror-only, so it skips
   IOGraphicsLib's duplicate check): a scaled mode whose desktop equals the raster (NVRMFB's `validateDetailedTiming`
   accepts it: no downscale, EDID raster) with the HiRes flag. The 3360x2100 / 2560x1600 entries are gone (they need a real
   scaled NVKMS commit). `hidpi-try` now ranks modes without 0x80000000 first and prints the CGError. Needs the script
   (sudo) and a reboot; untested.
   **Keep 2880 x 1800 in System Settings.** Next try (round c): the override plus the WindowServer pref
   `DisplayResolutionEnabled` (what one-key-hidpi sets; there is no HiDPI kext, HiDPI is built by WindowServer on the native
   mode). A real HiDPI mode keeps the 2880x1800 framebuffer, so NVRMFB needs no scaled mode set. Switch only with
   `tools/hidpi-try.swift` (takes nothing but a native-framebuffer HiDPI mode, reverts after 15 s without confirmation).
   Old text: the boot raster is already 120 Hz. `scripts/macos-install-hidpi.sh` adds a scale-resolutions-only override
   (1440x900, 1680x1050, 1280x800 "looks like"); no EDID change, no prefs deleted, so no new NVKMS mode. It lives in the
   same directory `scripts/remove-display-override.sh` (Linux) deletes, so that script removes it too. **Not applied yet.**

8. **[works 2026-10-12] Wi-Fi runtime control** (option B of `WIFI-AS-WIFI.md`): user client + supervisor in `itlmt7925` (scan, join, disconnect,
   reconnect after deauth/beacon loss, link down while between networks) and the ItlWiFi menu bar app (`macos/ItlWiFi`,
   `scripts/build-itlwifi.sh`). Builds clean, all symbols resolve against 24.6.0, app runs. **Kext not run on hardware yet.**
   Install: `scripts/macos-install-kext.sh itlmt7925` (keeps the plist credentials, backup in `EFI/OC/Kexts-backup/`).
   ItlDiag up to 2026-10-11 kept the ESP IOMedia open read/write for ITLLOG.BIN, so macOS could not mount the ESP (EBUSY,
   `fskit_helper error=16`). Fixed in ItlDiag: it opens the partition only for each flush and skips flushes while anyone
   else has it open (mounted, fsck, diskutil; counted as "flush(es) skipped while in use" in the log). Until the fixed
   ItlDiag is on the ESP, install from Linux: `scripts/linux-apply-2026-10-11.sh`.

9. **Boot time.** Root causes found: (a) OpenCore `Misc/Debug/Target` 0x43 (log on screen and to a file on the ESP, flushed
   per line) plus `AppleDebug`; (b) NullMoth's boot-screen copy, below; (c) bring-up diagnostics (ItlDiag, `-v`). The round-b
   script sets Target 0, AppleDebug off, PollAppleHotKeys on (Cmd+V = verbose on demand), disables ItlDiag, drops `-v itldiag
   itlxr`, adds `-nvrmnobootscreen`. Before (01:15 boot): kernel -> WindowServer 48 s, display armed after 115 s. Unified log of the 01:15 boot: kernel 01:15:07, WindowServer 01:15:55, NVRM "boot screen: copied 2880x1800
   ... in 15271 ms" (the boot before: 18674 ms), display armed 01:17:02. `NVRM::snapshotBootScreen` reads the 28 MB GOP console
   through an uncached mapping 8 bytes at a time. Fix: boot-arg `-nvrmnobootscreen` (vendor switch; the takeover shows black
   instead of the copied console, which is verbose text with `-v` anyway). Also seen: an 11 s gap after the APFS root graft and
   a 4.9 s NVMe `setPowerState`; firmware/OpenCore time is not measured yet (OpenCore logs are copied by the round-b script).

   **2026-10-11 evening:** kernel -> login window is a steady ~36 s over the last 8 boots; root is mounted at 0.6-19 s, but
   launchd's first boot task only runs at ~35 s (launchd exec'd at ~17 s, `lo0` at ~29 s), with almost no log lines in
   between. Kernel printfs in that phase are ~40 ms apart each (e.g. 41.558 -> 41.599 -> 41.642 -> 41.686): the verbose
   console draws on the 2880x1800 GOP framebuffer, which reads through PCIe at ~1.9 MB/s (the same cost as NVRM's boot
   screen copy above). The ESP had `-v` again (added by hand for debugging, backup `config.plist.addv-*`); removed
   (backup `config.plist.nov-20261011-183504`). Verbose on demand: Cmd+V in the OpenCore picker (PollAppleHotKeys).
   Not the cause: XNU's 30 s wait for IORTC/IONVRAM (`IOKitInitializeTime`) runs before the root mount; launchd does not
   import IOKit, so the 30.6 s busy of X86PlatformPlugin does not hold it.
   **SSDT-PLUG-ALT** does two things here: (1) it declares `Processor` objects C000-C017, which macOS needs because this
   firmware declares the CPUs only as `Device (ACPI0007)` (SSDT-2): removing the whole SSDT can leave AppleACPICPU without
   CPUs; (2) `plugin-type = 1` on C000 loads X86PlatformPlugin, which on AMD has empty P/C-state tables and applies the
   MacBookPro16,2 thermal profile (SFI forced-idle table, QoS thermal thresholds, `CPUOnACPower = No`). Without (2)
   ACPI_SMC_PlatformPlugin (probe score 1000) takes the CPU instead, which is what Dortania's AMD SSDT-CPUR gives. Its
   AGPMEnabler child would go too, so (2) is a separate experiment after the `-v` result, not bundled with it.
   **2026-10-11 18:49 boot (no `-v`):** kernel -> WindowServer 3.6 s (was 36-60 s), NVRM boot hold released at 10.8 s (was
   74-115 s), loginwindow connected to WindowServer at 76.8 s (was 140-180 s over the 12 boots before). The remaining 60 s:
   WindowServer logs `GPUWranglerWaitForPublish: timed out; status=0xe00002d6` at 71.47 s, exactly 60 s after it got past
   IOKitWaitQuiet. AppleGPUWrangler (`ioreg -c AppleGPUWrangler`, `debug-gpus`) tracks two GPUs: the RTX 5060 (0xED33, accel
   and fb) and the Radeon 890M (`VGA@0`, 1002:150E, class 0x038000, no accel, no fb, only AMDSupport attached), which is never
   published. Its `disable-gpu` property does nothing because WhateverGreen is disabled. (NVRM's own "flip 60 s after the
   release" line lands 0.6 s before the timeout only because both are 60 s from the same moment.) Fix: the 890M's
   DeviceProperties also get `class-code` FFFFFFFF, `name`/`IOName` `#display` (Dortania's GPU-disable values) so no driver,
   IONDRVFramebuffer or the wrangler takes it as a display device (ESP backup `config.plist.noigpu-20261011-190545`).
   Check after the next boot: no "GPUWranglerWaitForPublish: timed out" from WindowServer, one entry in `debug-gpus`.
   **19:13 boot: confirmed.** One GPU in `debug-gpus`, WindowServer registered the GPU at 13.4 s, login window shown at
   34 s (was 140-180 s before the `-v` and 890M fixes). HiDPI 1440 x 900 at 120 Hz works from System Settings with the
   round-f override (user report). Side effect to watch: brightness and lock-screen display sleep (docs/ASUSCTL-MACOS.md).

10a. **Saved networks out of range (2026-10-11):** the supervisor retried itl_ssid..itl_ssid4 forever (3 rounds of directed
   probes for every network, then 30 s back-off), so away from them the menu stayed "connecting"/"failed" and a join from the
   menu waited for the round to finish. Now each try starts with a wildcard scan and only networks seen in the last 60 s are
   tried (the joined one first); none in range = state `idle`, error "no saved network in range", wildcard scan every 30 s
   (that also drives ItlWiFi's auto-join of its Keychain networks); every 5 min all configured networks get the directed
   probes anyway (hidden SSIDs). A join or disconnect from the menu interrupts the directed probes. A joined network that
   never came up three times hands over to the configured ones instead of switching Wi-Fi off. Binary installed on the ESP
   (Info.plist with the credentials kept; backup `Kexts-backup/itlmt7925.kext.20261011-190437`).

10b. **Wi-Fi throughput (2026-10-11, measured on the same AP where a phone does 260 Mb/s):** link L6, HE 160 MHz ch 40, RSSI
   -39 dBm; download 4.3 MB/s, upload 0.9-1.7 MB/s, gateway ping 4.6 % loss idle / 30 % under load. Counters (`stat-log`):
   * under download 25-36 % of the frames from the stack failed with "no slot" (TX staging pool full) and were dropped while
     `outputPacket()` returned success; the Ethernet controller had no output queue, so the stack also called
     `outputPacket()` from several threads into one shared `txb` buffer. Now an `IOGatedOutputQueue` (512): a full pool stalls
     the queue (`kIOReturnOutputStall`), `m3TxFree()` restarts it when TXFREE returns slots, the link loop retries after 20 ms
     (300 ms slot reclaim), link changes kick it. `fail=` now counts only real drops; `txf` no-slot counts stalls.
   * under upload no drops, but ~1.1 firmware retries per frame (`txf` 5th field / frees) and ~1300 frames/s. The driver never
     sent `EDCA_UPDATE` (Linux `mt7925_mcu_set_tx`, sent after every BSS_INFO: "ensure that enable txcmd_mode after
     bss_info"). Now `m3Edca()` sends the AP's WMM parameters (station defaults without a WMM element) after each `m3Bss()`.
   * open: RX Block Ack window 64 while the AP offers 256; ~8 % of reorder input is "old" (AP retransmissions of frames we
     had); no CLC / rate power limits are sent; RX is polled (no interrupts). Binary installed on the ESP (backup
     `Kexts-backup/itlmt7925.kext.20261011-201343`); verify after reboot: `edca` line in the m3 log, `stat-log` deltas,
     speed test, ping.

10c. **Wi-Fi RX + power-table continuation (2026-10-11):** completed the unfinished RX/CLC/SAR changes.
   * RX data ring: 1536 entries at fast level >= 2, allocation fallback to 512/256; MCU RX ring 512. Frame DMA buffers
     use cached memory on x86; RX reads acquire DMA writes before touching cached data. Descriptors stay uncached.
     Ethernet input flushes at 64 frames and at the end of every data poll / MCU pass / reorder tick.
   * Added `itlmt7925_pwr.cpp` to the build and IOACPIFamily to the bundle dependencies. Reads efuse block 0xa70 for
     module encapsulation, selects firmware POWER/POWER_EXT CLC tables, and sends world (`00`, indoor) rules with ACK/status
     checking. CLC region, rule and segment offsets are bounds checked. Before association, sends 449-byte SKU tables
     for 2.4/5 GHz in batches of three channels. No 6 GHz enablement in this change.
   * Reads MTDS/MTGS from the PCI device's ACPI path, accepts actual v1/v2 layouts independently of version labels,
     handles 0xff as absent limits and treats geo offsets as unsigned (Linux layout). Uses first dynamic profile and
     world geo row. Caps per-rate power at min(SAR, 40 half-dBm = 20 dBm); firmware CLC may lower it further. This is a
     conservative world-domain ceiling, not a full cfg80211 regulatory port. Failed power setup aborts association and
     is retried on the next join; successful setup is retained across reconnects.
   * Validation: clean x86_64 kext build (no compiler warnings), plist lint, diff whitespace check, ASan/UBSan power tests
     covering SAR sentinel/layout/offset cases, SKU rate placement and invalid CLC bounds. The tests also walk all POWER /
     POWER_EXT tables in the bundled RAM firmware (4 tables, 24 world rules). Hardware behavior remains to be checked
     after reboot: `rx data ring 1536`, `sar:`, `clc 00`, `txpower:` logs, download/upload speed and gateway packet loss.
   * Installed `/Volumes/ESP/EFI/OC/Kexts/itlmt7925.kext`; binary SHA256
     `1e8b2715e63437e6f09ec416a856d2b1061c00c85491e6e53db732be026a6e44`.
     Backup: `EFI/OC/Kexts-backup/itlmt7925.kext.20261011-211949`. Saved credentials were copied and verified privately;
     OpenCore config was verified unchanged, with the existing Kernel/Add entry enabled. No reboot performed.
   * Brightness: the AUX/DPCD limitation was documented in ASUSCTL-MACOS.md (later solved by `NVRMEdpBL`; the RogControl
     software dimming mentioned there is gone);
     this continuation does not change GPU/backlight code.

10d. **ItlWiFi speed-test error:** the screenshot's "speed.cloudflare.com not reachable over en2" was caused by
   interface binding while an active VPN routed the provider through `utun4`. Reproduced on Cloudflare and Hetzner:
   `curl --interface en2` failed immediately with exit 7; unbound curl returned HTTP 200/206 via the VPN. The gateway
   remained reachable over en2. The old app discarded stderr and exit status, hiding this distinction.
   * Split the test engine into `macos/ItlWiFi/SpeedTest.swift`. Default path is "Internet (VPN allowed)"; "Wi-Fi direct"
     retains interface binding. Results identify the provider, resolved server IP and actual route (including VPN).
     A failed direct test with a working tunneled system-route probe explains the VPN restriction explicitly.
   * Auto selection probes Cloudflare, Hetzner Singapore, OVHcloud Singapore and Hetzner US West, falling back on probe
     failures. Each server can also be selected manually. Hetzner/OVH measure download only; Cloudflare supports upload.
     Endpoints were verified live with small ranged requests, rather than pinning mutable CDN IPs.
   * Capture curl JSON metrics / exit code / stderr; reject HTTP error responses as speed results, retain completed metrics
     when another direction fails, label TCP connect latency accurately. Both directions use total transfer time; the old
     code subtracted first-response time from upload duration (upload normally precedes that response). Upload payloads
     are unique temporary 8 MiB files and are removed after the run. Timed-out uploads without a successful HTTP response
     are displayed as unavailable, rather than treating unacknowledged bytes as a valid result.
   * Validation: app build, signature verification, plist lint; Swift result-validation tests and live probes of all four
     providers passed. Full 10-second-direction live test returned 22.0 Mb/s down and 9.42 Mb/s up via utun4;
     Wi-Fi-direct mode returned the explanatory VPN error. These are Internet/VPN measurements, not isolated Wi-Fi capacity.
   * Installed `/Applications/ItlWiFi.app`, retaining existing login configuration; old app backed up to
     `build/ItlWiFi.before-speed-fix.app`. LaunchServices initially returned -600 just after stopping the old process;
     launching the installed executable directly succeeded (PID 24849). No kext / ESP / VPN configuration changed.

10. **[Wi-Fi throughput: full link speed since 2026-10-12] Wi-Fi after boot did not come back (fixed in code 2026-10-11, round c):** the supervisor change wiped the credentials in
    `m3Run1()` after the first selection, so when L6 passed no unicast and the ladder stepped down, the next level ended in
    `nocred` (rc -22) and the supervisor started again at L6, forever. Now the ladder keeps them and `lvlCap` remembers the
    level that worked. RSSI decoding works (2 chains, 0xff for the unused ones; `rssi-probe` holds raw samples).
    **Wi-Fi throughput** (driver L6/HE, PHY estimate 2402 Mb/s): measured ~8 Mb/s down, ~4-6 Mb/s up (curl over en2 to
    speed.cloudflare.com). Counters after 536 s: reorder 35362 in / 18200 buffered / 1258 timeouts at 100 ms (= 126 s, 23 % of
    the time with receive held), TX retries 13269 of 44055. Reorder timeout now 30 ms (`itlmt_reo=<ms>`); next suspects are
    RX ring drops and the TX retry rate. ItlWiFi has a Speed Test (menu, curl bound to the Wi-Fi interface).

11. **Apps (no sudo):** ItlWiFi is a SwiftUI popover now (current network, speed test, inline password, saved networks;
    `scripts/build-itlwifi.sh --install`). TapGuard ignores trackpad taps for 350 ms after a key press (VoodooInput's own
    typing quiet time needs VoodooPS2Keyboard; this keyboard is USB): `scripts/build-tapguard.sh --install`, Accessibility
    permission, `defaults write com.itlmt7925.TapGuard QuietMs -int <ms>`.

12. **[RESOLVED: AsusWmi profiles + AmdCppc, see the CPU sections at the end] CPU clock** (`tools/cpuclock.c`): 1.4-1.8 GHz sustained single-thread at first (AC), 3.0-3.8 GHz later on battery.
    macOS has no AMD P-state/CPPC driver; the clock follows the firmware and the Armoury Crate profile. Measure on AC with
    the Performance/Turbo profile before writing a CPPC kext. On AC (03:45): still 1.4-3.3 GHz. `AmdCppc.kext` (round d) reads
    HWCR/PStateCtl/CPPC on every CPU (`sysctl debug.amdcppc.report`) and changes them only through root sysctls
    (`pstate`, `boost`, `cppc`, `epp`), so the fix can be tried without a reboot.

13. **[RESOLVED 2026-10-12] Bluetooth** (MT7925 BT, USB 0489:e11e): no macOS driver; bluetoothd idles out and is respawned every ~32 s.
    2026-10-11: `kexts/MtkBtFw` loads the firmware (Linux btmtk procedure) and BlueToolFixup 2.7.2 + the two NVRAM
    variables are on the ESP. Controller comes up (State On, real address, firmware v9736); pairing not tested yet. See
    [BLUETOOTH.md](BLUETOOTH.md).
14. **[RESOLVED, see the CPU sections at the end] CPU clock** (AmdCppc, `sysctl debug.amdcppc.freq`, 2026-10-11, AC, CPPC off): the 4 Zen 5 cores (cpu0-7) sit at exactly
    2000 MHz (P0, hardware P-state status FID 0x190) and never boost; the 8 Zen 5c cores (cpu8-23) run up to 3300 MHz, their
    CPPC highest perf (125 vs 196-208 for Zen 5). A single thread therefore gets 2.0 or 3.3 GHz depending on where the
    scheduler puts it, never the 5.1 GHz boost. CPPC on + EPP 0 did not change `cpuclock` once; per-core numbers with CPPC
    on still to be taken. The machine rebooted a few minutes after the first CPPC enable (cause unknown).

Everything that needs sudo from this session is in `scripts/macos-apply-2026-10-11.sh` (one run, then reboot; it prints the
undo commands and a Recovery-terminal undo for the NVRMFB/HiDPI part).

## Next steps (2026-10-11, in this order)

State: NVRMFB patch is installed in the auxiliary kernel collection (active from the next boot). ItlWiFi is in
/Applications and starts at login. The new `itlmt7925` and `ItlDiag` are built (in `build/` on the macOS volume) but **not on
the ESP yet**, because the old ItlDiag holds the ESP open while macOS runs. The ESP still has `itlmt_m1=75`.

1. macOS: `bash scripts/macos-apply-2026-10-11.sh` (safe to re-run: HiDPI override; skips what is done; the kext step is
   skipped with a note while the ESP is busy). Reboot into **Linux**.
2. Linux: `git pull`, then `bash scripts/linux-apply-2026-10-11.sh` (no sudo): both kexts from `build/` on the macOS volume
   (credentials carried over), `itlmt_m1=0`, `occonfig check`. Reboot into **macOS**.
3. macOS: ItlWiFi menu (Wi-Fi a few seconds after boot), `bash scripts/macos-vramtest.sh` (expect tens of ms, was 0.7-1.1 s),
   Displays > 1440 x 900, `sudo diskutil mount disk0s1` (must work now). Then report the numbers upstream (PR #64 comment,
   issue for the `MESA_SHADER_CACHE_DIR` leak).

Prompt for Claude Code on Linux (paste as is):

> Repo ga403wm-hackintosh. Read docs/HANDOFF.md, section "Next steps (2026-10-11)". Do step 2 on this Linux machine:
> `git pull --ff-only`, check that /mnt/macos-vol0 mounts and that build/itlmt7925.kext and build/ItlDiag.kext exist on the
> macOS volume and are newer than the kexts in /boot/EFI/OC/Kexts, then run `bash scripts/linux-apply-2026-10-11.sh`.
> Never print Wi-Fi passphrases, SMBIOS values or MACs. If any step fails, stop and show me the output, do not improvise
> on the ESP. At the end show `ls -la /boot/EFI/OC/Kexts /boot/EFI/OC/Kexts-backup` and the boot-args, then tell me to
> reboot into macOS.

## Next steps (2026-10-12): after the reboot into 1.14.2 + local patches

State on the machine (nothing of this is loaded until the reboot): upstream NullMoth **1.14.2**, NVRMFB = VRAM-clear
patch + AUX-brightness hook, `NVRMEdpBL.kext`, `nvrmacpibl=1` in boot-args. Read `NULLMOTH.md` ("Local patches on top of
upstream"), `VRAM-GRANT-STALL.md`, `OLED-BRIGHTNESS-DPCD.md`.

1. Boots? Both displays up (OLED 2880x1800 @ 120 Hz, Mi Monitor 1920x1080 @ 144 Hz). If not: boot-arg `nvrmedpbl=0`, or
   `scripts/macos-edpbl-install.sh --undo`, or the picker's "Start once without NVIDIA driver".
2. Brightness: the checklist in `OLED-BRIGHTNESS-DPCD.md` ("Verify after the reboot"); record the result in that file
   (done 2026-10-12; the software dimmer is gone from RogControl).
3. `scripts/macos-nvrmfb-vramclear-ab.sh` (root): MB/s for `clear_mode` 0 and 1; record in `VRAM-GRANT-STALL.md`; re-check
   the stall picture and `tools/framepace.swift`.
4. Report upstream: the VRAM clear (branch `nvrmfb-vram-clear-nontemporal`) and the AUX backlight (branch
   `nvrm-edp-aux-backlight`, commit `3501a25`) as PRs from the fork; (2026-10-13: both are pushed to the fork, rebased onto
   v1.15.0, next to the combined branch `ga403wm`; no PR opened. The VRAM clear is no longer worth proposing: the cause was the
   PAT slot, see `VRAM-GRANT-STALL.md`. The AUX backlight is the one to send.)

## Next steps (2026-10-13): after the reboot into 1.15.0 + overlay

State on the machine (nothing of this is loaded until the reboot): upstream NullMoth **1.15.0** (installed 17:43, backup
`/Library/NullMoth/backup-20261013-174350.lXzh5Q`), NVRMFB = upstream + the AUX-brightness hook only (`b9040104...`, swapped
17:59), `NVRMEdpBL.kext` (`433dfcbf...`), boot-arg `nvrmacpibl=1`. Built from fork `ga403wm` @ `f5b5eaa` (= v1.15.0 + the
brightness patch). 1.15.0 fixed neither of our patches; it is "the last release for macOS 15". The VRAM-clear patch is **dropped**
(PAT was the cause; tag `ga403wm-with-vramclear`). Read `NULLMOTH.md`, `OLED-BRIGHTNESS-DPCD.md`, `VRAM-GRANT-STALL.md`.

1. Boots? Both displays up (OLED 2880x1800 @ 120 Hz, Mi Monitor 1920x1080 @ 144 Hz) and `kmutil showloaded | grep nullmoth` lists
   `NVRMEdpBL`. If not: boot-arg `nvrmedpbl=0`, or `scripts/macos-edpbl-install.sh --undo` (upstream 1.15.0 stays), or
   `uninstall.sh /Library/NullMoth/backup-20261013-174350.lXzh5Q` (back to the 1.14.7 files), or the picker's "Start once without
   NVIDIA driver".
2. Brightness: the checklist in `OLED-BRIGHTNESS-DPCD.md` ("Verify after the reboot"). Still without a recorded result: on the
   17:27 boot (1.14.7 overlay) the kext was loaded, but `log show --boot --info --debug` found no `NVRM-edpbl:` line (the
   `nvrm-dpcd` read as a normal user returns 0x1b, insufficient permissions), so test the slider / Fn+F7/F8 and read DPCD `0x721`
   (= 02) with `nvrm-dpcd` as root.
3. WindowServer: 1.15.0 claims "high WindowServer CPU and low frame rate at 4K", "old content after a redraw" and "window copies
   up to 35x faster". Re-measure with the same interval as 2026-10-12 17:43 (33.4 % of one CPU, 34.5 flips/s; `tools/framepace.swift`)
   and record it in `WINDOWSERVER-CPU.md`. The instrumented readback plugin is gone (an upgrade removes it; rebuild from
   `claude/windowserver-iosurface-readback` against v1.15.0 if stage 2 is ever needed).
4. Chrome / Edge / Electron: 1.15.0 turns their GPU path (ANGLE Metal) on again by default; if pages show corrupted areas, start
   with `NVMTL_ANGLE_METAL=0` and tell upstream (their known issue).
5. `macos-ws-pat-check.sh` still checks PAT PA6 = WC and the WindowServer CPU; it skips the clear A/B (`debug.nvrmfb_clear_*` is
   gone with the dropped patch). To see whether the clear still matters, `macos-vramtest.sh` (8 MB grants, no counters needed).

## NullMoth update to 1.12.0 (manual route, EFI part done 2026-10-11)

Installed on the Mac: 1.9.0. Target: 1.12.0 (`SHA256SUMS.txt` of the release lists `nullmoth-nvidia-1.12.0.tar.gz`
`40c47c41e4410a3bf3805478df1057e77412fce072d4ef34b323aeacb5da9fe0`). The Mac app was not used, so `/Library/NullMoth/state`
stays at 1.9.0 (removal through the picker entry still works).

Done from Linux (ESP, backups next to the config: `config.plist.pre-nullmoth-1.12`, `.pre-amfipass-20261011`,
`.pre-ipc-opt-20261011`): `EFI/OC/Kexts/AMFIPass.kext` 1.4.1 (zip SHA-256 `07b26614…`, same file NullMoth setup pins),
`Kernel/Add` entry at the end (after Lilu), boot-arg `ipc_control_port_options=0`. `ocvalidate` clean. Same edits in `efi/`.

Still to do, on the Mac (in this order; nothing here is run from Linux):

1. Linux: `sudo bash scripts/remove-display-override.sh` (removes the old 120 Hz override, one variable at a time).
2. macOS Terminal:
   ```bash
   mkdir -p ~/nm && cd ~/nm
   curl -fLO https://github.com/nullmoth/nvidia-macos-driver/releases/download/v1.12.0/nullmoth-nvidia-1.12.0.tar.gz
   shasum -a 256 nullmoth-nvidia-1.12.0.tar.gz   # must equal the hash above
   tar -xzf nullmoth-nvidia-1.12.0.tar.gz && cd pkgroot
   shasum -a 256 -c SHA256SUMS                    # every line OK
   sudo ./install.sh && sudo shutdown -r now
   ```
3. Allow the extensions in System Settings > Privacy & Security if asked, reboot once more.
4. `bash scripts/macos-nullmoth-probe.sh` and read `/Library/NullMoth/display-trace/`.

Do not run 1401.exe "Build". "Send logs" uploads to NullMoth: the owner decides.

## Config tooling (Linux, no sudo once `/boot` is writable)

* `python3 tools/occonfig.py get|set|add|del|args|check|diff` edits `config.plist` by schema path
  (`UEFI/Quirks/ResizeGpuBars`, `Kernel/Add/[BundlePath=Foo.kext]/Enabled`). Every write first copies to
  `config.plist.<tag>` (never overwrites an existing backup) and re-parses afterwards. Secrets are masked unless
  `--reveal`. Default file: `$OC_CONFIG`, else `/boot/EFI/OC/config.plist`, else `efi/OC/config.plist`.
  Tests: `python3 test/occonfig_test.py`. Schema: `tools/occonfig-schema.json` (from OpenCorePkg `Docs/Sample.plist` at
  963025f1; regenerate with `occonfig.py schema`).
* `bash scripts/build-ocvalidate.sh` builds `~/.cache/ga403/bin/ocvalidate` for the pinned OpenCore commit (needs
  acidanthera/audk; upstream edk2 lacks `CommonMemoryAllocationLib`). `occonfig.py check` runs it when present.
  Both the ESP and `efi/OC/config.plist` validate clean (2026-10-11).
* Repo config vs ESP config differ only in how one short `<data>AAAAAAAA</data>` is wrapped; use `occonfig.py diff`.

## How to get data from Linux (CachyOS)

* One time: `sudo bash scripts/setup-linux-access.sh` gives your user the ESP (`/boot` gets `uid=`/`gid=`, still private)
  and a `noauto,user,ro` fstab entry for the macOS Data volume (`mount /mnt/macos-vol0`). `--undo` restores fstab.
* Afterwards, no sudo: `bash scripts/linux-collect-logs.sh [--unified]` copies the newest OpenCore logs, `ITLLOG.BIN`,
  a whitelist of NVRAM vars (efivars are world-readable; SMBIOS vars are not touched), macOS panic reports, `fsck_apfs.log`
  and optionally the unified log into `~/ga403-logs/<time>` (outside the repo).
* Writing to APFS stays a root job on purpose (`scripts/remove-display-override.sh`, experimental linux-apfs-rw).
* Decode the unified log (`linux-collect-logs.sh --unified`) with `scripts/decode-unified-log.sh <logarchive> "<UTC since>"`.
  A hard power-off loses the last minutes of it (persisted in chunks), so a log that ends abruptly is not proof of a reset.
* Tidy the ESP: `scripts/esp-cleanup.sh` (dry run; `--apply` moves, never deletes). `scripts/esp-cleanup.sh` keeps the config
  backup that NullMoth's `1401 --remove` restores from. FAT dirtied by a hard reset makes fsck rename directories to
  `FSCK0000.000`: `ls /boot/EFI/OC` after any unclean shutdown.

## How to get data on macOS

* Mount the ESP: `diskutil list` (find the EFI partition on the NVMe), `sudo diskutil mount <diskNs1>`.
  `ITLLOG.BIN` in its root starts with `ITLLOG01`, text begins at byte 512, ends at the first NUL. Read it with
  `tail -c +513 /Volumes/EFI/ITLLOG.BIN | tr -d '\000' | less`. Do not write to it while macOS is running (`ItlDiag`
  writes raw clusters); to reset it, zero it in place from Windows (`scripts/usblog.ps1 -Esp -Prepare`) or keep the
  size and head/tail magic (`ITLLOG01` at 0, `ITLEND01` at the last 512 bytes) if you do it by hand.
* Build the kexts: `bash scripts/build.sh` (Xcode command line tools). CI also builds on every push
  (`gh run download <id> -n kexts`); artifacts carry **empty** Wi-Fi credentials, inject yours locally with
  `scripts/inject-creds.ps1` (Windows) or by editing `Info.plist` (`itl_psk*`) in your local copy only.
* Install a kext on the ESP: replace `EFI/OC/Kexts/itlmt7925.kext` and `ItlDiag.kext`. Keep a backup of the old one.
  Never commit a kext with credentials (`*.kext` is ignored).
* Useful boot-args now: `itldiag=90 itlxr=2 itlmt_m1=0 itlmt_m2=1 itlmt_m3=1 itlmt_fast=6 msgbuf=1048576` (`itlmt_m1` is now an
  extra delay after the root filesystem is mounted; it was 75 s from kext start)
  (`itlfile=0` disables the ESP file; see `docs/DEBUGGING.md`).

## Reading the log

`m0-log`..`m3-log`, `m2-res`, `m3-res`, `ba-log` come from the registry properties of `itlmt7925`; `stat:` lines are the
data-path counters every 10 s (`L6` link up, `eapol`, `tx`, `fail`, `rxpk`, `ba=`, `reo=`). "usb devices=N hid=M" is the
USB/HID census. Blocks are about 5 s apart. A log that simply ends means the machine stopped (hard restart, hang or
power loss), not necessarily a reset: always ask what the screen showed. A screen frozen on the verbose blocks usually
means "no framebuffer", not "kernel hung" (the diag worker kept writing).

## Hard-won rules

* Never print Wi-Fi passphrases, SMBIOS identifiers, MACs or neighbour SSIDs; keep `itl_psk*` empty in the repo.
* Do not disable the NVIDIA driver, change boot-args or quirks as a blind bisect; find the root cause first.
* Do not re-run 1401 "Build" on the ESP; take a backup (`config.plist.<name>`) before every ESP config edit.
* NVRAM-based `itl*` variables do not land in the NVIDIA-driver configuration; use `ITLLOG.BIN`.
* Windows boots through OpenCore too: OC ACPI patches apply to Windows as well.
* NullMoth driver changes are upstream-first: build from the fork (`thanhnndev/nvidia-macos-driver`), install the release
  package with its own `install.sh`, then layer the machine patch with a script that checks hashes, backs up and has
  `--undo` (`scripts/macos-edpbl-install.sh`). Never edit installed kexts by hand.
* Root steps are run by the agent through `osascript -e 'do shell script "<wrapper file>" with administrator privileges'`
  (the user types the password in the dialog); do not ask the user to run `sudo` in a terminal. Put the commands in a
  wrapper file: `$?` inside the `-e` string breaks AppleScript quoting.
* One branch per concern in the fork for upstream PRs (AUX backlight: `nvrm-edp-aux-backlight`); the branch `ga403wm` (upstream
  tag + that patch + the machine packaging, pushed 2026-10-13, worktree `nvidia-macos-driver-ws-ga403`) is what the README/INSTALL send users to and what
  the build script uses. Rebase it onto the next upstream tag. Leave other sessions' work (Wi-Fi, Bluetooth, RogControl) untouched.

## CPU policy update (2026-10-12)

AmdCppcPolicy LaunchDaemon is installed and active: enables CPPC and sets autonomous EPP by
ASUS profile / power source, verifies all 24 CPUs, pauses during sleep and restores after wake.
One live round: Zen 5 all-worker load 4.89–4.91 GHz, Zen 5c 3.33 GHz; actual sleep/wake restored
AC Performance EPP128. A single worker mostly ran on Zen 5c (~3.2 GHz); do not claim a pinned
5.1 GHz single-core benchmark. AmdCppc 0.2.0 installed on ESP (backup 20261012-170224), not yet
loaded: running kext remains 0.1.0 until reboot. See CPU-POWER.md for validation and rollback.

## WindowServer PAT research (2026-10-12 17:29, reboot pending)

ESP and repo PAT patch now set PA6=WC instead of UC-: table 0001010600070106.
Only one entry changes; do not switch to the all-WB Shaneee variant. AmdCppc 0.2.1
is installed on ESP for read-only debug.amdcppc.cache diagnostics; live remains 0.2.0.
Backup config.plist.pre-pat-pa6-20261012-172936-498961; kext backup 20261012-172936.
After reboot, run scripts/macos-ws-pat-check.sh through osascript administrator privileges.
It checks the actual PAT on all 24 CPUs, runs clear A/B and a desktop CPU interval.
No live PAT read / post-fix speedup yet: probe was blocked by approval, hot-unload was
refused because AmdCppc is retained. CPU policy daemon was restored. See WINDOWSERVER-RESEARCH.md.

### PAT reboot validation completed (2026-10-12 17:43)

AmdCppc 0.2.1 and corrected PAT are active: PA6=1 on all 24 CPUs.
Clear mode 1 now 1043–1094 MB/s (~9–10x before); mode 0 1008–1048 MB/s.
WindowServer 33.4% of one CPU, 34.5 flips/s, zero errors/drops. clear_mode=1 restored.
No further reboot is needed for these changes; see WINDOWSERVER-RESEARCH.md.
