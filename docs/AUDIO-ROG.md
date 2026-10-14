# Audio on the GA403WM: speakers, microphone array, and a "Dolby-like" chain on macOS

> **Status 2026-10-14: research + one read-only probe staged (reboot pending).** Branch `research/audio-rog-dolby`
> (worktree `.claude/worktrees/audio-rog-dolby`). `StrixAmp.kext` (section 2.4) is in `EFI/OC/Kexts` and `config.plist`;
> it takes effect at the next boot. The internal microphone was measured and works (section 3.1).
> Sections are tagged **[measured]** (read from this machine, read-only), **[external]** (kernel / firmware sources, linked) or
> **[hypothesis]** (reasoning that has not been tested). Speaker output has not been heard (needs a person, see
> [HANDOFF.md](HANDOFF.md), row "Audible audio"); microphone level was measured once (section 3.1).

## 1. What is in the machine

| Piece | Evidence | Tag |
|---|---|---|
| HD-Audio controller `1022:15e3` (`HDEF`, ACPI `AZAL@6` under `GPPA@80001`), SSID `1043:1024` | `ioreg -n HDEF`: `vendor-id 0x1022`, `device-id 0x15e3`, `subsystem-vendor-id 0x1043`, `subsystem-id 0x1024` | measured |
| Codec **Realtek ALC285**, `VendorProductID 283902597 = 0x10EC0285`, codec SSID `0x10431024` | `IOHDACodecDevice` / `IOHDACodecFunction` | measured |
| **Cirrus Logic CS35L56 smart amps** on I2C: ACPI `SPKR` with `_HID CSC3556`, under controller `I2CB` (`AMDI0010`, `_UID 1`) | `ioreg -p IOACPIPlane` | measured (part number from the HID, not from a chip marking) |
| AMD Audio Coprocessor `1022:15e2` (ACP 7.0, rev 70; ACPI `ACP@5` with children `HDA0@1`, `I2SC@3`, `BTSC@4`, `SDWC@5`, `SDWS@6`, `USBS@7`) | Linux `lspci` in [890M-LINUX-DUMP.md](890M-LINUX-DUMP.md); ACPI node names from `ioreg -p IOACPIPlane` | measured |
| HDMI/DP audio `1002:1640` on the iGPU | Linux `lspci` | measured |

Speakers: the same SSID `1043:1024` is the Linux quirk "ASUS Zephyrus G14 2025", which says the woofers must be remapped to
DAC1 and the mic on the jack is not detected ([patch](https://lkml.iu.edu/2601.1/06212.html), merged for Linux 6.19). That is
**[external]**; whether the same remap is needed on macOS is **[hypothesis]**.

### 1.1 What macOS does today **[measured]**

* `AppleALC 1.9.9` + `Lilu 1.7.3` loaded; `AppleHDAController`, `AppleHDA 600.2`, `AppleHDADriver` (`IOAudioDeviceModelID "AppleHDA:7"`).
* EFI sets `layout-id` 33 (`PciRoot(0x0)/Pci(0x8,0x3)/...` in `efi/OC/config.plist`); the live registry shows `alc-layout-id = 0x21 (33)`
  and AppleALC's resolved `LayoutID = 7`, codec name *"PIut02 - Realtek ALC285 for ROG-Zephyrus-G14"*. The `7` vs `33` is how
  AppleALC reports an injected layout, not necessarily a mismatch; confirm once against the kext's resources.
* System Information shows *Built-in Input* (2 ch, "Internal Microphone") and *Built-in Output* (2 ch, "Internal Speakers"), 48 kHz.
  Every stream is 2-channel, 16/20/24-bit, 48 kHz only. The input engine reports `num-internal-mics = 1` (pre-gain 25), i.e.
  macOS treats the array as a single mic.
* The pin table AppleALC injects (decoded from `BootConfigData`):

| NID | macOS value | Windows dump (from the Linux patch) | Meaning |
|---|---|---|---|
| 0x12 | `0x90a60170` | `0x90a60140` | internal digital mic |
| **0x13** | **`0x400000f0` (disabled)** | `0x90a60550` | **second digital-mic pin: enabled on Windows, off on macOS** |
| 0x14 | `0x90170140` | `0x90170510` | speaker |
| 0x17 | `0x90170141` | `0x90170120` | speaker (bass) |
| 0x19 | `0x028b1020` | `0x03a11050` | headset mic |
| 0x21 | `0x022b1050` | `0x03211430` | headphone |
| 0x1d | `0x400000f0` (disabled) | `0x40663a45` | beep |

### 1.2 What is already usable for a kext **[measured]**

* **VoodooI2C is loaded and already owns `I2CB`**: the registry has `VoodooI2CACPIController -> VoodooI2CControllerNub ->
  VoodooI2CControllerDriver -> VoodooI2CDeviceNub "SPKR"`. So there is a ready I2C transport to the amps; no controller
  driver has to be written. Today nothing attaches to that `SPKR` nub.
* **The DSDT is in the ESP** (`SysReport/ACPI/DSDT.aml`, OpenCore SysReport). Decoded from it, `\_SB.I2CB.SPKR`:

| Item | Value |
|---|---|
| `_HID` / `_SUB` / `_UID` | `CSC3556` / `"10431024"` / `1` |
| I2C slaves (I2cSerialBusV2, `\_SB.I2CB`, 1 MHz, 7-bit) | **`0x30`, `0x31`, `0x3A`** (VoodooI2C's nub takes the first, `0x30`) |
| `cirrus,dev-index` (_DSD) | `{0x30, 0x31}`: two amps; `0x3A` is declared but its role is unknown |
| `cirrus,boost-type` (_DSD) | `0` |
| `reset-gpios` | `\_SB.GPIO` pin **24** (`0x18`), output, pull-down, shared by both amps |
| `spk-id-gpios` | `\_SB.GPIO` pin **104** (`0x68`), input, pull-up (selects the `spkid0` / `spkid1` firmware) |
| interrupt | `\_SB.GPIO` pin **18** (`0x12`), edge, shared, debounce 100 |
| `_DSM` | present (Cirrus UUID `3cdff6f7-4267-4555-ad05-b30a3d8938de`) |

  The GPIO controller is `AMDI0030`; VoodooGPIO is loaded but a driver still has to drive pin 24/104/18 itself.
* `ACP@5` carries `acp-audio-config-flag = 0x10` (`SSDT-9`), which is `FLAG_AMD_LEGACY_ONLY_DMIC` in Linux's `mach-config.h`:
  the BIOS says "legacy ACP driver, DMIC only". Its endpoint list is render (speaker/headphone), a Bluetooth-SCO device
  (16/48 kHz and 8/16 kHz capture) and nothing else; no SoundWire peripherals are declared.
* `AsusWmi` (ours) is loaded and exposes a user client; useful later for hotkeys / profile hooks, not for audio itself.
* `ACP@5` and its children are `!registered, !matched`: macOS has no driver for ACP 7.0, SoundWire (`SDWC`/`SDWS`) or I2S (`I2SC`).

## 2. Speakers

### 2.1 Why they are probably silent or thin **[external] + [hypothesis]**

The CS35L56 driver documentation states that on HDA systems the amps need firmware (`.wmfw` + `.bin` per amp) to enter
"HDA bridge mode", and without it there is no audio from the amplifiers; firmware is laptop-specific
([kernel docs](https://docs.kernel.org/sound/codecs/cs35l56.html)). Linux does this in `cs35l56_hda` (I2C control, DSP firmware
load, calibration from an EFI variable, speaker-ID GPIOs). macOS has no equivalent, so the ALC285 can play into amps that
were never taken out of reset-default. Whether the internal speakers are currently audible at all is **not measured**.

### 2.2 Firmware exists **[external]**

`linux-firmware` ships symlinks for our SSID in `WHENCE`:

* `cirrus/cs35l56-b0-dsp1-misc-10431024-spkid{0,1}.wmfw` -> `cs35l56/CS35L56_Rev3.11.16.wmfw`
* `cirrus/cs35l56-b0-dsp1-misc-10431024-spkid{0,1}-amp{1,2}.bin` -> the `10431044` tuning files

That is two amps (`amp1`, `amp2`) and two speaker-ID variants (`spkid0`, `spkid1`); the GPIO that selects the variant is
read from ACPI on Linux and has to be read here too (`_DSM`/GpioIo in `SPKR._CRS`). The firmware is redistributable under
the Cirrus licence in linux-firmware; the repo should fetch it at install time, not vendor it.

### 2.3 Options

| # | Route | Effort | Risk | Notes |
|---|---|---|---|---|
| S1 | **Linux-primed amps experiment**: boot Linux (kernel with the 1043:1024 quirk and firmware), play a tone, then *warm* reboot straight into macOS and see if ALC285 -> amps sounds | hours | none to the machine | Tells us if the path works once the amps are alive, before writing any driver. Amps may reset on reboot; then the answer is "inconclusive", not "no". |
| S2 | ~~Read `SPKR._CRS` / `_DSD` (I2C address, speaker-ID GPIO, reset GPIO) from the DSDT~~ **done** | - | - | Results in section 1.2; the table came from the ESP's OpenCore SysReport. |
| S3 | **`StrixAmp.kext`**: a `VoodooI2CDeviceNub` client for `CSC3556` that ports the `cs35l56_hda` init: reset/power sequence, read device ID/revision, load `.wmfw`/`.bin` (needs a Wmfw/Bin parser and a DSP memory writer), apply calibration, unmute/enable I2S/TDM | weeks | medium: wrong register writes into a boost amp can damage drivers; start read-only (ID registers only) | The long pole. Firmware must come from user space (a small helper + `IOUserClient`) because kexts should not read files. |
| S4 | Pin/verb tuning in AppleALC for the DAC1 woofer remap (`0x14`/`0x17` -> DAC mapping) once S1/S3 shows sound | days | low | Equivalent of `ALC285_FIXUP_ASUS_GA403U_HEADSET_MIC` on the speaker side; done through a custom AppleALC layout (platform + pin config), not through a runtime kext. |

Order: S2 (done) -> S3 read-only probe (staged, 2.4) -> S1 (decide if S3 is worth it) -> S3 full -> S4.

### 2.4 `StrixAmp.kext`, the read-only probe (staged)

`kexts/StrixAmp` matches the VoodooI2C nub named `CSC3556` and does two single-register reads: `DEVID` (0x00000000, expect
`0x00035A56`) and `REVID` (0x00000004), 32-bit big-endian address and value, as in the Linux cs35l56 I2C regmap. It never writes.
Output: `ioreg -r -c StrixAmp -l -w0` properties `ProbeStatus`, `DEVID`, `DEVID_IsCS35L56`, `REVID`, plus a line in the kernel log.

* Install: `scripts/macos-strix-amp-install.sh` (ESP, no root); remove: `--undo`. A config.plist backup is written to
  `~/efi-audit/config.plist.pre-strixamp-*`.
* **It cannot go through `/Library/Extensions`**: tried, `kmutil load` fails with code 31 because the AuxKC build cannot find
  `com.alexandred.VoodooI2C` (OpenCore injects it into the boot collection; it is not on disk in a repository kmutil searches).
  The copy was removed again; `/Library/Extensions` is as before.
* Reading the answer: `DEVID 0x00035a56` means the amp is alive and reachable and S3 is feasible without touching GPIO 24;
  a NAK/timeout (`ProbeStatus != 0`) means the amp is held in reset (GPIO 24 low) or unpowered, so S3 must also drive the reset GPIO
  and the S1 experiment becomes the cheaper first step.

## 3. Microphone array

### 3.1 Findings **[measured] + [external]**

* **The internal mic works on macOS today.** A 4 s level capture of the default input (`Internal Microphone`, 2 ch, 48 kHz,
  nothing played, audio not stored) gave RMS -34 to -41 dBFS, peak 0.10-0.36, DC about 0, and a channel correlation of
  0.8-0.97: a live stereo pair, not silence or a floating input. (The first run's 0.76 peak was a start-up transient.)
  So the ALC285 DMIC pin `0x12` is the working capture path; ACP/PDM is not needed for basic capture.
  Consequently section 3.2 M3 (an ACP 7.0 driver) is demoted to "only if a *second* array turns out to be on ACP".
* The internal mics reach the ALC285 as **digital mic pins 0x12 and 0x13** on Windows (both `0x90a6....`). macOS layout 33
  enables only `0x12` and disables `0x13`, and `AppleHDA` reports `num-internal-mics = 1`. Whether `0x13` carries a second
  physical mic (the G14 is sold with a multi-mic array and "AI noise cancelling") or nothing is **not established**: that is
  what M2 tests.
* The BIOS ACP flag is `0x10` (`FLAG_AMD_LEGACY_ONLY_DMIC`, section 1.2), which only says ACP is in "legacy, DMIC only" mode;
  other Strix Point ASUS models that route DMIC through ACP use the same flag
  ([example](https://lkml.iu.edu/2603.1/00275.html)). Given the measurement above it does not block anything here.
* The headset/jack mic is **broken on Linux too** for this SSID ([patch thread](https://lkml.iu.edu/2601.1/06212.html)):
  pin `0x19` set from the Windows dump still does not detect. Treat it as "unknown on macOS" until measured.

### 3.2 Options

| # | Route | Effort | Risk |
|---|---|---|---|
| M1 | ~~Measure the input~~ **done once** (3.1): stereo, live. Still open: SNR in a quiet room and whether pin `0x19` (jack mic) works. | minutes | privacy only (level meter only, nothing stored) |
| M2 | Enable NID `0x13` (and the Windows `0x12` association bits) in a **custom AppleALC layout**; verify 4-channel capture or a second stereo pair | days | low |
| M3 | ACP 7.0 PDM route, i.e. a DriverKit/kext driver for the ACP DMA engine. A **large** project (new DMA engine, no Apple reference); not justified by the current evidence (3.1). | months | high |
| M4 | **Noise suppression, user space**: an `AudioServerPlugIn` virtual microphone that reads the built-in input, runs RNNoise (BSD, C, 10 ms @ 48 kHz) or DeepFilterNet, and exposes "ROG AI Mic". Apple's [AudioServerPlugIn sample](https://developer.apple.com/tutorials/data/documentation/coreaudio/creating-an-audio-server-driver-plug-in.md) and BlackHole are the references. No kernel code. | 1-2 weeks | low |
| M5 | Multi-mic beamforming (needs 2+ real channels from M2 first) | later | low |

macOS 12+ also offers system *Voice Isolation* / *Wide Spectrum* on the input side for apps that adopt it; M4 is for apps that do
not, and for headless use.

## 4. "Dolby" without Dolby

The Windows experience (Dolby Atmos / Sonic Studio / ASUS "AI Noise-Cancelling Microphone") is proprietary software and
licensed content on the Windows side; none of it will be copied, extracted or reverse-engineered here. What can be built on
macOS is an open DSP chain that gives the same *effect*:

1. **Virtual output device** (`AudioServerPlugIn`, "ROG Audio") that all apps play into; it forwards to the real
   `Built-in Output` after processing. Same technique as BlackHole + a system EQ app.
2. **Chain**: speaker-protection high-pass (~80 Hz for the small woofers) -> parametric EQ (a measured or Cirrus-derived
   curve for this chassis) -> multiband loudness/limiter -> optional crossfeed / HRTF virtualiser for headphones -> true-peak
   limiter. Profiles (Music, Movie, Voice, Game) switchable from RogControl and hotkeys (the Fn keys already go through
   `AsusWmi`).
3. **Speaker tuning source of truth**: the Cirrus `.bin` tuning files above contain the DSP protection/EQ the OEM wanted
   for these exact speakers; once S3 loads them, macOS inherits the OEM's speaker protection and EQ for free, and the user-space
   chain only adds taste. Without S3, the user-space chain has to protect the speakers itself, so keep gains conservative.

Do not ship anything that boosts low frequencies hard before S3 (or an equivalent excursion limiter) exists.

## 5. Proposed work order

| Step | Deliverable | Needs |
|---|---|---|
| 0 | `scripts/macos-audio-collect.sh` (read-only snapshot; included in this branch) | nothing |
| 1 | ~~Dump DSDT/SSDT, decode `SPKR._CRS` and `acp-audio-config-flag`~~ **done** (1.2); the ESP already had a SysReport | - |
| 2 | S1 experiment (Linux-primed amps) and M1 measurement | the user, ears and a quiet room |
| 3 | M4 virtual mic (RNNoise) as `macos/RogAudio` | step 0 only |
| 4 | M2 custom AppleALC layout | a build of AppleALC |
| 5 | S3 `kexts/StrixAmp` read-only probe **built and staged**; read `DEVID` after the next reboot, then decide on reset GPIO + firmware load | reboot |
| 6 | Virtual output + DSP chain + RogControl integration | steps 3, 5 |

## 6. Hard limits and risks

* Wrong writes to a CS35L56 can over-drive a speaker. Probes are **read-only** until the register sequence is cross-checked
  against `cs35l56_hda` for this exact SSID; do not write calibration, reset or boost registers first.
* Firmware is laptop-specific (see 2.2); never use the files of a different SSID.
* Kernel code on macOS 15 for audio must not touch the USB/I2C buses used by the touchpad (`I2CA`, `ASUP1208`): bind only to the
  `CSC3556` nub.
* Sleep/wake already has a slow `AppleHDADriver` resume ([ROADMAP.md](ROADMAP.md) row 22); any new audio kext must not make that worse.
* Everything in section 1 was read from the live system with read-only `ioreg` / `system_profiler` / `kextstat`; no audio was played or captured.

## References

* Linux quirk patch (GA403W / CS35L56, SSID `1043:1024`): <https://lkml.iu.edu/2601.1/06212.html>
* CS35L56 driver and firmware naming: <https://docs.kernel.org/sound/codecs/cs35l56.html>
* linux-firmware `WHENCE` (Cirrus `10431024` entries): <https://gitlab.com/kernel-firmware/linux-firmware/-/blob/main/WHENCE>
* ACP 7.0 BIOS flag / DMI override example: <https://lkml.iu.edu/2603.1/00275.html>
* AudioServerPlugIn: <https://developer.apple.com/tutorials/data/documentation/coreaudio/creating-an-audio-server-driver-plug-in.md>
* RNNoise (BSD): <https://github.com/xiph/rnnoise>
* DeepFilterNet: <https://github.com/Rikorose/DeepFilterNet>
