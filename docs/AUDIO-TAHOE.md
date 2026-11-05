# Audio on macOS Tahoe (AppleHDA restore)

Status 2026-11-05 14:33: SimpleHDA 1.0.1 installed, loads on the next reboot.

Installed: `EFI/OC/Kexts/SimpleHDA.kext` (executable sha256 5a1beec9...83c1, release zip f2fc55da...5982, all 10 files match
the zip's SHA256.json), Kernel>Add index 5 right after AppleALC (MinKernel 25.0.0), boot-arg `shda-lang=en`, HAL package
in `/Library/Audio/Plug-Ins/SimpleHDA/` (Apple-signed, sha256 matches `Resources/AppleHDA.json`; the pkg has no scripts).
Config backups: `EFI/OC/config.plist.pre-simplehda-20261105-143159` and the same name in `~/efi-audit`. ocvalidate: no issues.
Nothing had to be removed: no other AppleHDA, VoodooHDA, OCLP root patch or NMXAudio on the machine; AppleALC, StrixAmp and
RogAudio stay. After the reboot: `zsh scripts/macos-simplehda.sh check` (and `idle`); undo: `-shdaoff` or `... undo`.

## Problem

macOS 26 removed `AppleHDA.kext` (from 26 DP2). On this machine (26.7.1, 25G241):

- AppleALC 1.9.9 loads and HDEF has `alc-layout-id = 33`, but no `AppleHDAController` attaches.
- CoreAudio has only the two RogAudio virtual devices (ROG Clear Mic, ROG Speakers).
- rogaudiod looks for a `kAudioDeviceTransportTypeBuiltIn` device and finds none, so
  `status.plist` shows `micActive=false`, `speakerActive=false`. Nothing reaches the speakers or comes from the mic.
- StrixAmp 0.2.0 is fine: both CS35L56 (0x30/0x31) status 0, firmware bring-up trace with rc=0. They only lack an HDA stream.

Not affected: HDMI/DP audio, USB/Bluetooth audio, the webcam (ASUS FHD webcam, UVC, `UVCService`).

## Options

| Method | System volume | Fit here |
| :--- | :--- | :--- |
| **SimpleHDA** (laobamac, Lilu plug-in, OpenCore injection) | untouched | **chosen**. Keeps AppleALC layout 33, rogaudiod and StrixAmp as they were on Sequoia |
| OCLP-Mod AppleHDA root patch | patched, revert before every OTA | no: conflicts with our own `/System` snapshot patches (VTStub); the 5T33Z0 guide marks it obsolete |
| VoodooHDA (Tahoe build) | `/Library/Extensions` | fallback only: no AppleALC layout, no jack auto-switch, lower quality |
| Inject a Sequoia AppleHDA ourselves | untouched | this is what SimpleHDA already does (it ships a kxld to link AppleHDA at runtime); no reason to redo it |

Acidanthera has no official Tahoe method; the AppleALC README only says macOS 26 "may require additional actions".

## SimpleHDA facts

- Repo https://github.com/laobamac/SimpleHDA, source open (Sources/, Tools/build.zsh, CI build). v1.0.1, 2026-11-04.
- Payload: original AppleHDA 600.2 from the macOS 15.8 KDK (24H23), hashes in `Resources/AppleHDA.json`, checked by the build.
- Needs: Lilu >= 1.7.1, AppleALC, a working layout, `Kernel > Quirks > DisableLinkeditJettison = true`. Order Lilu > AppleALC > SimpleHDA.
  From 1.0.1, `keepsyms=1` is not required.
- Boot args: `-shdaoff` (disable), `-shdahaloff`, `shda-lang=en`, `-shdadbg` (DEBUG build).
- Optional `SimpleHDA-HAL-1.0.1.pkg`: Apple's signed legacy `AppleHDAHALPlugIn` in `/Library/Audio/Plug-Ins/SimpleHDA/`.

This machine already meets every requirement: Lilu 1.7.3, AppleALC 1.9.9 (Kernel>Add index 4), layout 33 through
DeviceProperties, `DisableLinkeditJettison = true`, `SecureBootModel = Disabled`, `keepsyms=1`, SIP 0x0A43.

## Known issues from the tracker that apply

- #7 ALC285 (ROG Flow Z13 2023): crackle on the 3.5 mm jack, and very quiet output before the HAL package.
  The fix was codec node 0x20 coefficient 0x10 = 0x0020 (macOS left 0x0220). Same codec as ours: check the jack.
- #6 ALC289: idle HDEF interrupt storm (~4300/s, +3 W) from `AFGLowPowerState=3` in the AppleALC layout. Check
  `powermetrics --samplers interrupts` at idle; layout 33 is our own build, so we can change its value.
- #4 no boot with `SecureBootModel` enabled: ours is Disabled.
- #9 output about half of Windows: compare with the StrixAmp gain.
- #10 device names in Chinese: set `shda-lang=en`.

## Install plan (batch with the next reboot)

1. Build SimpleHDA 1.0.1 from source (or take the RELEASE zip) and check the payload hashes against `Resources/AppleHDA.json`.
2. ESP: `EFI/OC/Kexts/SimpleHDA.kext`, Kernel>Add entry right after AppleALC, `MinKernel 25.0.0`. Back up config.plist first.
3. boot-args: add `shda-lang=en`.
4. Install the HAL package.
5. Undo: `-shdaoff`, or disable the Kernel>Add entry.

## Checks after the reboot

- `ioreg -r -c AppleHDAController` attaches to HDEF; Built-in Output / Built-in Microphone exist in CoreAudio.
- rogaudiod: `speakerActive` / `micActive` become true when playing / recording.
- Speakers through the CS35L56 pair (StrixAmp), headphone jack (pin 0x21) detect and switch, internal mic (pin 0x12).
- Jack crackle (#7) and idle interrupts (#6).
- Display sleep and s0ix sleep/wake keep audio.
