# Audio on the GA403WM: speakers, microphone array, and a "Dolby-like" chain on macOS

> **Status 2026-10-14: amp firmware and mic work; speakers still silent in audible tests. RogControl audio integration installed.** Branch `research/audio-rog-dolby`
> (worktree `.claude/worktrees/audio-rog-dolby`). `StrixAmp.kext` (section 2.4) is in `EFI/OC/Kexts` and `config.plist`;
> it is loaded and attached after reboot. The internal microphone was measured and works (section 3.1).
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
the Cirrus licence; the files are vendored in `fw/cs35l56/` (see its README for provenance and SHA-256).

### 2.3 Options

| # | Route | Effort | Risk | Notes |
|---|---|---|---|---|
| S1 | **Linux-primed amps experiment**: boot Linux (kernel with the 1043:1024 quirk and firmware), play a tone, then *warm* reboot straight into macOS and see if ALC285 -> amps sounds | hours | none to the machine | Tells us if the path works once the amps are alive, before writing any driver. Amps may reset on reboot; then the answer is "inconclusive", not "no". |
| S2 | ~~Read `SPKR._CRS` / `_DSD` (I2C address, speaker-ID GPIO, reset GPIO) from the DSDT~~ **done** | - | - | Results in section 1.2; the table came from the ESP's OpenCore SysReport. |
| S3 | **`StrixAmp.kext`**: a `VoodooI2CDeviceNub` client for `CSC3556` that ports the `cs35l56_hda` init: reset/power sequence, read device ID/revision, load `.wmfw`/`.bin` (needs a Wmfw/Bin parser and a DSP memory writer), apply calibration, unmute/enable I2S/TDM | weeks | medium: wrong register writes into a boost amp can damage drivers; start read-only (ID registers only) | The long pole. Firmware must come from user space (a small helper + `IOUserClient`) because kexts should not read files. |
| S4 | Pin/verb tuning in AppleALC for the DAC1 woofer remap (`0x14`/`0x17` -> DAC mapping) once S1/S3 shows sound | days | low | Equivalent of `ALC285_FIXUP_ASUS_GA403U_HEADSET_MIC` on the speaker side; done through a custom AppleALC layout (platform + pin config), not through a runtime kext. |

Order: S2 (done) -> S3 read-only probe (staged, 2.4) -> S1 (decide if S3 is worth it) -> S3 full -> S4.

### 2.4 `StrixAmp.kext` + `strixampctl` (installed, bring-up measured)

Post-reboot verification on 2026-10-14 **[measured]**:

* Kext protocol 1 attached at boot, unsafe writes off. Both 0x30 and 0x31 report DEVID `0x00035A56`, REVID `0xB0`, OTPID 3.
* GPIO 104 pad reads `0x00050000`; published speaker ID is 1. Address 0x3A does not answer the boot probe.
* Before bring-up, both amps ran ROM firmware 3.4.4 with `PROTECTION_STATUS=1` (firmware missing).
* Ran `scripts/macos-strixamp-install.sh` through administrator osascript. Its daemon performed the one-shot bring-up:
  firmware 3.11.16, 41 algorithms and 66 block writes per amp, zero skipped blocks, using speaker-ID 1 tuning.
* Both amps now report `HALO_STATE=2`, `PROTECTION_STATUS=0`, `PM_CUR_STATE=3`, `ACTUAL_PS=0`, mute 0, volume -20 dB.
  `ASP1_ENABLES1=0x00030001` on 0x30 and `0x00030002` on 0x31; daemon reports bring-up ok and state 2.
* Logs: `/var/log/strixamp.log`; audio registry snapshot: `out/audio-post-reboot-20261014/`.
  RogAudio LaunchAgent is running and logs the balanced speaker path to Built-in Output. Mic is on demand and was not
  freshly captured in this check. Audible playback, codec routing, and sleep/wake recovery still need verification.
* Unified-log helper errors about missing `/Library/Extensions/StrixAmp.kext` coexist with the active OpenCore-injected
  service; they do not indicate that the live kext failed to attach.

Measured with the first probe build (**[measured]**): the amp at I2C 0x30 answers, `DEVID 0x00035A56` (CS35L56), `REVID 0xB0`
(b0 firmware family). So the amps are powered and out of reset at boot; what is missing is what Linux's `cs35l56_hda` does.

The work is split so that the amp sequences can be iterated without a reboot:

| Part | What | Where |
|---|---|---|
| `StrixAmp.kext` | **mechanism only**. Attaches to the `CSC3556` nub (`IOPropertyMatch` on `IOName`; `IONameMatch` does not match VoodooI2C nubs), reaches 0x30 / 0x31 / 0x3A through the nub's provider (`VoodooI2CControllerDriver::transferI2C`, because a nub is bound to one address), and exposes a user client that executes an operation stream (read / write / block / poll / update-bits). Reads the speaker-ID strap (GPIO 104) from the FCH GPIO bank and publishes it. | `kexts/StrixAmp/`, wire format `StrixAmpProto.h` |
| `strixampctl` | **policy**. Bring-up (interrupt masks, DP3 / ASP1 / TX routing as in the Linux HDA driver), `.wmfw` + `.bin` download, play / pause, volume / mute, one-shot `up` and the boot `daemon`. | `tools/strixampctl.c`, `scripts/build-strixampctl.sh` |
| Firmware | `CS35L56_Rev3.11.16.wmfw` + `cs35l56-b0-dsp1-misc-10431044-spkid{0,1}-amp{1,2}.bin` (`fw/cs35l56/README.md`: provenance, SHA-256, licence). | `fw/cs35l56/` |
| LaunchDaemon | `com.itlmt7925.strixamp`: `strixampctl daemon`, re-runs the bring-up when an amp reports firmware missing or is not playing (boot, wake). | `scripts/macos-strixamp-install.sh` |

What the kernel side enforces: only an administrator can open the user client; I2C addresses 0x30 / 0x31 are writable, 0x3A
(role unknown) is read-only; writes only inside the windows the HDA bring-up needs (ASP1 / routing 0x4800-0x4C7C, mixer, mailbox,
IRQ mask, user controls, DSP memory); `USER_VOLUME` above 0 dB is refused, including inside a firmware download block; the
boot-arg `strixamp_unsafe=1` lifts the window and volume limits.

Facts used (Linux `cs35l56` / `cs_dsp` driver interface, no code copied; NOTICE.md): 32-bit registers and values, big endian on
the wire; mailbox `PLAY 0x0B000001`, `PAUSE 0x0B000002`, `REINIT 0x0B000003`, `SHUTDOWN 0x02000005`, `SYSTEM_RESET 0x02000007`;
`PROTECTION_STATUS` (0x34000D8) bit 0 = firmware missing; HALO DSP memory packed as 12 byte groups (three BE32 words, four
24 bit words, little-endian bit order) which the algorithm-list walk depends on. The `.wmfw` / `.bin` loader was validated offline
(`strixampctl --dry -v fwload ...`): 66 block writes, 0 skipped, all inside the DSP-memory window and none touching `USER_VOLUME`,
41 algorithms resolved, firmware id `0x1a00d6` v3.11.16, for all four tuning files.

Install (the kext is OpenCore-injected, never `/Library/Extensions`: it links against the injected VoodooI2C, `kmutil` fails
with code 31):

```
scripts/build.sh StrixAmp                               # build/StrixAmp.kext
scripts/build-strixampctl.sh                            # build/strixampctl
# ESP mounted user-owned: back up the old one to EFI/OC/Kexts-backup/, copy the new one into EFI/OC/Kexts
python3 -I tools/occonfig.py -c /Volumes/ESP/EFI/OC/config.plist check
sudo scripts/macos-strixamp-install.sh                  # (via osascript) tool, firmware, LaunchDaemon; --vol <dB>, --undo
```

Use: `sudo strixampctl info | status | up [--vol -20] | pause | vol <dB> | r <reg>`; log `/var/log/strixamp.log`.
The daemon starts at -20 dB amp volume (the macOS slider is separate). First thing to check after a reboot:
`ioreg -l -n StrixAmp | grep -E "Amp3|Gpio|SpeakerId"` and `strixampctl status`.

**Not known yet:** whether `PROTECTION_STATUS` reports firmware missing on this machine (only readable once the new kext is
loaded), whether the ALC285 I2S path already feeds the amps without extra COEF writes, whether GPIO 104 really is the
speaker-ID strap at pad level (the kext reads it and the tool refuses to guess when it cannot), and the roles of GPIO 24 (reset)
and GPIO 18 (interrupt), which are not driven.

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
| 5 | S3 `kexts/StrixAmp` + `tools/strixampctl` + firmware + LaunchDaemon **built, kext staged on the ESP**; one reboot, then everything is iterated in userland (`strixampctl`) | reboot |
| 6 | Virtual output + DSP chain + RogControl integration | steps 3, 5 |

## 6. Hard limits and risks

* Wrong writes to a CS35L56 can over-drive a speaker. The kernel side only allows the register windows of the HDA bring-up sequence and refuses
  `USER_VOLUME` above 0 dB; boost / analog registers need `strixamp_unsafe=1`. Start at a low volume.
* Firmware is laptop-specific (see 2.2); never use the files of a different SSID.
* Kernel code on macOS 15 for audio must not touch the USB/I2C buses used by the touchpad (`I2CA`, `ASUP1208`): bind only to the
  `CSC3556` nub.
* Sleep/wake already has a slow `AppleHDADriver` resume ([ROADMAP.md](ROADMAP.md) row 22); any new audio kext must not make that worse.
* Everything in section 1 was read from the live system with read-only `ioreg` / `system_profiler` / `kextstat`; no audio was played or captured.

## 7. RogAudio (userland, installed and working)

`macos/RogAudio/` builds two pieces (`scripts/build-rogaudio.sh`, install with `scripts/macos-rogaudio-install.sh`, root via osascript):

- `RogAudio.driver`, an AudioServerPlugIn in `/Library/Audio/Plug-Ins/HAL`. It publishes "ROG Speakers" (stereo sink) and
  "ROG Clear Mic" (mono source) as loopback devices; there is no hardware behind them.
- `RogAudio.app/Contents/MacOS/rogaudiod`, a LaunchAgent (`com.itlmt7925.rogaudiod`). It runs RNNoise on the built-in mic and
  feeds the result to "ROG Clear Mic" (only while something records from it), and runs the biquad EQ / width / limiter chain
  ("Dolby-like" profiles off|balanced|movie|music|voice, file `/Library/Application Support/RogAudio/profile`) on what is played
  to "ROG Speakers", forwarding it to Built-in Output. Log: `/tmp/rogaudiod.log`; `-v` prints a stat line every few seconds.

Measured 2026-10-14: ROG Clear Mic returns the denoised built-in mic (rogaudiod about 1 % CPU); ROG Speakers path level matches the
profile gain with 0 underruns/overruns.

**rogaudiod must not be codesigned.** The same binary reads the microphone normally when unsigned or linker-signed, and gets pure
digital silence (no error, no prompt) after `codesign -f -s -`, whatever the identifier. The build script strips the signature.

## 8. Continuation after reboot, 2026-10-14

* Added `macos/RogAudio/rogaudio-probe.c`, built by `scripts/build-rogaudio.sh`. It captures only aggregate levels
  (no sample storage), or plays a 1 kHz sine at amplitude 0.02, for at most 30 seconds, to an explicit device UID.
* Fresh built-in mic check: 143872 frames / 3 seconds, setup/render errors 0, RMS -37.39 dBFS.
  ROG Clear Mic: 288192 frames / 6 seconds, setup/render errors 0, RMS -31.68 dBFS. These sequential ambient checks
  establish live capture, not a controlled noise-suppression comparison. The daemon starts/stops mic on demand.
* ROG Speakers tap during a 5-second tone: peak 0.02, RMS -39.09 dBFS over the 8-second measurement, 1 kHz
  component amplitude 0.01238. The virtual playback transport works.
* Acoustic checks at the built-in mic did not establish speaker output: 1 kHz component amplitudes 0.00001388
  through ROG Speakers and 0.00003075 through Built-in Output. Ambient baseline was 0.00013947; runs were sequential,
  with uncontrolled room noise. Do not claim audible output or definite silence from these measurements.
* Fixed and installed amp daemon monitoring of BOTH amps (firmware, ASP RX enables, actual power state).
  Tested by pausing only 0x31: daemon saw state 1 / PS3 and restored state 2 / PS0 on both amps within 8 seconds.
* Added read-only `strixampctl diag` for clock, DSP routing and IRQ registers. Both amps report REFCLK_INPUT 0x430,
  DSP1RX inputs 0x08/0x09, DACPCM inputs 0x36/0x37, IRQ1_STATUS 0, amp-short bit clear, temperature-error bit clear.
* Next blocker is live codec inspection: no ALCUserClientProvider exists in this boot. Built upstream `alc-verb`
  from AppleALC commit ff01db21749271916d44605503499ceaa61d94b2 in `build/AppleALC-reference` (GPL-2.0 tool, not vendored).
  Added `alcverbs=1` to the ESP and worktree configs; ESP backup is `config.plist.pre-audio-alcverbs-20261014`.
  ESP passes schema and ocvalidate checks. No codec routing writes have been made.
* After the next reboot: `bash scripts/macos-audio-codec-probe.sh`; inspect DAC stream assignment, pin 0x14/0x17
  connection selection, amp gain/mute and pin enables while a tone runs. AppleALC upstream layout33 sends pin 0x17
  to DAC 0x03, while Linux's speaker2_to_dac1 quirk restricts it to DAC 0x02. This is a routing hypothesis until measured.

Probe examples (ordinary logged-in user; amp reads require administrator):

```sh
build/rogaudio-probe input AppleHDAEngineInput:0,6,0,1,0:1 5
build/rogaudio-probe input com.itlmt7925.rogaudio.mic 6
build/rogaudio-probe tone com.itlmt7925.rogaudio.speakers 5
sudo build/strixampctl diag
bash scripts/macos-audio-codec-probe.sh
```

## 9. Wrapped installation and next-session handoff (2026-10-14)

Worktree: `.claude/worktrees/audio-rog-dolby`, branch `research/audio-rog-dolby`. Work remains uncommitted; preserve it.
The owner requested stopping tracing, installing the combined build once, and rebooting. Continue codec research next session.

Delivered:

* RogControl Audio page now writes `~/Library/Application Support/RogAudio/settings.plist`. It controls profile, amp volume/mute,
  and RNNoise enable/strength. Both daemons read the same settings; the UI reports Applied only after both acknowledge them.
  Amp limits remain -60..0 dB and the kext allowlist remains enabled. Audio status comes from fresh daemon status plists.
* Live control test passed: Voice / -30 dB / mute on / noise off was acknowledged by both daemons. Restored the owner's
  then-current Balanced / -20 dB / mute off / noise on / 85% strength settings. Keep subsequent owner changes.
* Mic test in RogControl: Built-in Mic or ROG Clear Mic, live level meter, 8-second timeout and Stop. No samples are saved.
  Tested through the signed installed RogControl app invoking the unsigned installed helper: both report Signal detected
  (built-in final level -53.2 dBFS, Clear Mic -65.24 dBFS in separate ambient runs).
* Speaker test: generated 20-second musical source, left treble, left bass, right treble, right bass, stereo finale.
  Source `build/ROG-Speaker-Test.wav`, copied into RogControl resources and `/Library/Application Support/RogAudio/`.
  Validated PCM16 stereo 48 kHz / 960000 frames, peak 0.053894; inactive channel is exactly zero in each solo phase.
  The four Heard checkboxes are user confirmations, NOT automatic claims of physical driver isolation or successful output.
* `scripts/build-alc-verb.sh` builds the upstream GPL-2.0 AppleALC tool at pinned commit
  `ff01db21749271916d44605503499ceaa61d94b2`. Installed `/usr/local/bin/alc-verb`; `alcverbs=1` stays in the ESP.
* Single root installer: `bash scripts/macos-rog-audio-install.sh` after building RogAudio, StrixAmp CLI, alc-verb, RogControl.
  It backs up prior installed apps/plists, installs the HAL/daemons/app/helper/source/tool and opens RogControl.
  Final combined install succeeded at 11:54 local; backup directory:
  `/Library/Application Support/RogAudio/backups/20261014-115358`. App signature verification, both running LaunchAgents/Daemons,
  settings/status plist validation and ESP ocvalidate passed. Reboot requested by owner after this installation.

Speaker findings to resume:

* ALCUserClientProvider now attaches and permits live verbs. Snapshot `out/audio-codec-20261014-112933/codec-routing.txt`;
  playing snapshot `out/audio-codec-playing/codec-routing.txt`.
* DAC 0x02 has stream assignment 0x10; DAC 0x03 has 0x12; stream format 0x33 (48 kHz, 24-bit, four stream channels).
  Pin 0x14: connection 0, pin control 0x40, EAPD 2. Pin 0x17: connection 1 (DAC 0x03), pin control 0x40, EAPD 0.
* Tested pin 0x17 connection 0 (DAC 0x02), then EAPD 2: no demonstrated output. BOTH changes were restored to connection 1 / EAPD 0.
  No processing-coefficient values were written. The coefficient-index query returned 0; vendor node 0x20 is D0.
* Tested the musical source with system volume temporarily 65%, amp volume -20 dB: owner confirmed still no sound.
  System output volume was restored to 26%. This is confirmed silence for those tests, not merely an absent microphone tone.
* Amps remain firmware 3.11.16, PS0, unmuted, ASP enabled, DSP RX routed to ASP RX1/RX2, DAC inputs DSP1TX5/TX6.
  No amp-short or temperature-error bits asserted. This establishes firmware/control readiness only.
* Need trace of codec I2S/COEF and DSP render path, and then verified physical speaker routing. ASUS specs describe
  a dual-force woofer system plus tweeters; do not equate four musical phases with four independently verified physical drivers.
  Owner requires the full speaker system to work, not a stereo-only workaround.

Next-session starting commands (do not reboot again just to run these):

```sh
cd .claude/worktrees/audio-rog-dolby
bash scripts/macos-audio-codec-probe.sh
sudo strixampctl status
sudo strixampctl diag
/Applications/RogControl.app/Contents/MacOS/RogControl --audio-status
```

Research source snapshots in build/: `AppleALC-reference/` and `linux-alc269.c` (Linux master); use as references only.
The Linux GA403WM SSID 1043:1024 quirk remaps speaker2 to DAC1 but has no GA403-specific I2S COEF sequence.
Remaining scope: audible speakers, individual driver verification, wake recovery, extra mic pin/beamforming.

## 10. Wrap for next boot: source-first tracing (2026-10-14)

Owner stopped further experiments and requested one packaged kext plus boot tracing.
Built and staged `StrixAmp.kext` **0.2.0** in the actual ESP; `strixamp_trace=1` and `alcverbs=1` are enabled.
EFI config passed schema validation and OpenCore 1.0.9 ocvalidate. No reboot initiated in this wrap.

* One distribution bundle: `build/StrixAmp.kext`. Resources contain firmware, CLI/alc-verb/probe,
  RogAudio HAL/daemon, RogControl, musical source and collection scripts. Only StrixAmp executes in the kernel;
  AppleALC/Lilu/VoodooI2C remain dependencies and the app/HAL/DSP remain installed userspace components.
* Kernel trace starts at service attach, identifies its controller, snapshots both amps BEFORE the helper can load firmware,
  records operation sequence, arguments/result/status, firmware block boundaries and mailbox commands.
  I2C failures include address/register/direction/length/retry count. IORegistry retains boot registers,
  counters, last operation/failure, a bounded 128-entry tail and a preserved first-1024 write/poll/error history.
  First 4096 operations are logged in full;
  mailbox/block/failure milestones continue afterward. It does not hook all AppleHDA internal verbs or record PCM DMA data.
* LaunchDaemon `com.itlmt7925.audio-boot-trace` automatically stores root-private files under
  `/var/log/rog-audio-trace/<kern.bootsessionuuid>/`. It captures HDA/codec/amp at start, 2, 10, 30 and about 90 seconds,
  plus ACPI/GPIO, boot arguments, kexts, kernel history/live log and firmware-helper log.
  When the trace kext is active, it plays a 20-second test directly to Built-in Output at unchanged volume,
  collecting additional snapshots while playing. NO microphone samples are captured automatically.
* `strixampctl fwdiag <wmfw>` resolves named controls from WMFW metadata plus the live algorithm table:
  heartbeat, clock/reference/I2S state, audio error, mute, calibration and DSP levels. Read-only, requires firmware 3.11.16.
* Codec COEF probe reads 256 entries without writing values, restores the original index, and checks restoration.
  Probe output RMS now measures generated speaker samples instead of incorrectly logging -120 dBFS.

Latest measured evidence, BEFORE loading trace kext:

* Reboot occurred 11:56. Both amps restored firmware 3.11.16, unmuted, PS0, volume -21 dB from owner settings.
* Owner confirmed a direct Built-in Output musical test is STILL SILENT (not only the virtual DSP path).
* Built-in mic live, 3-second aggregate RMS -36.59 dBFS; no sample audio stored.
* Idle/playing COEF differs only at 0x30: 0x9007 -> 0x9005. Original index 0 restored.
* Both DSP heartbeats advance; `AS_ERRR=0`, `ABNORMAL_MUTE=0`, `FU23_MR_PLAT_MUT=0`, `SHORT_DETECTED=0`.
  Both read `FW_I2S_EN=0`, `FW_REFCLK_DET=0`, `FW_HW_CLCK_STT=3` even during generated tone.
  These raw values are a lead, NOT proof of missing BCLK; field semantics need verification.
* Source data nonzero, callbacks run, setup/render return 0. No successful audible speaker port yet.
  Do not resume by changing downstream gain or bypassing protection. Establish the earliest broken boundary:
  host render -> HDA stream/converter -> ALC285 pin/I2S -> amp ASP/DSP -> physical speaker.

Backups: ESP `EFI/OC/Kexts-backup/StrixAmp-pretrace-20261014/StrixAmp.kext`,
`config.plist.pre-audio-trace-20261014`; installed stack backup
`/Library/Application Support/RogAudio/backups/20261014-121419`.
Build again with `bash scripts/build-rog-audio-bundle.sh`; unified installer also installs the boot trace collector.
After next boot, verify `TraceBuild=0.2.0` and `TraceEnabled=Yes`, then read that boot's trace directory.
Root cause and all physical speaker paths remain unverified. Changes are uncommitted.

## References

* Linux quirk patch (GA403W / CS35L56, SSID `1043:1024`): <https://lkml.iu.edu/2601.1/06212.html>
* CS35L56 driver and firmware naming: <https://docs.kernel.org/sound/codecs/cs35l56.html>
* linux-firmware `WHENCE` (Cirrus `10431024` entries): <https://gitlab.com/kernel-firmware/linux-firmware/-/blob/main/WHENCE>
* ACP 7.0 BIOS flag / DMI override example: <https://lkml.iu.edu/2603.1/00275.html>
* AudioServerPlugIn: <https://developer.apple.com/tutorials/data/documentation/coreaudio/creating-an-audio-server-driver-plug-in.md>
* RNNoise (BSD): <https://github.com/xiph/rnnoise>
* DeepFilterNet: <https://github.com/Rikorose/DeepFilterNet>
