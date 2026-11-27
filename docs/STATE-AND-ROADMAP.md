# GA403WM on macOS 26 Tahoe: state and roadmap (2026-11-27)

**Updated after v2; the tagged copy is older.** Release [v2](https://github.com/thanhnndev/ga403wm-hackintosh/releases/tag/v2)
was published from tag `v2` at commit 3901d1d on 2026-11-25. This document on branch `release/tahoe-v2` continues to
be updated after the tag.

State document of the "v2 (macOS 26 Tahoe)" release. Written from the install log of the reference machine, the
documents in this repository and a read-only check of the running machine on 2026-11-25 (`kmutil showloaded`,
`sw_vers`, boot-args), updated on 2026-11-27 with the read-only traces of the 15:34 and 16:36 boots. Nothing here was tested on a second machine. macOS 15 is the previous release (v1 / kext-v1.1)
and is not described here; its documents are [INSTALL.md](INSTALL.md), [HANDOFF.md](HANDOFF.md) and [ROADMAP.md](ROADMAP.md).

Words used in the tables:

- **works**: verified on the reference machine on the date given.
- **partly**: works with a stated limit, or was verified on an older build of the stack and not since.
- **broken**: known not to work.
- **not verified**: no test on record for the current stack. This is not a claim that it fails.

## 1. Summary

One ASUS ROG Zephyrus G14 GA403WM (Ryzen AI 9 HX 370, Radeon 890M, RTX 5060 Laptop, 2880x1800 120 Hz OLED, 32 GB) runs
macOS Tahoe 26.7.2 (25G332, Darwin 25.6) under OpenCore 1.0.9 as a daily machine. The internal display, WindowServer and
all applications run on the Radeon 890M through `NMXGPU`, a source port of Linux amdgpu on a LinuxKPI layer (fork of
NullMoth's driver), with a Metal-on-Vulkan plugin on RADV in user space. Video decode for H.264, HEVC, VP9 and AV1 runs
on the 890M's VCN through a VideoToolbox decoder (`VCNDec`). The RTX 5060 is normally powered off and removed from the
PCI bus at boot (Eco mode, `StrixDgpuGate`). Wi-Fi and Bluetooth (MT7925), audio, the ASUS controls, Docker and the
Android emulator (both through the `RyzenHV` hypervisor kext; the emulator since RyzenHV 0.7.24, verified 2026-11-25)
and the iOS Simulator work. The main open items are: WindowServer costs about 6.5-7 ms of CPU per presented frame, and
GPU power follows the compositing rate, because every present recomposites the whole screen (the colour pass and the
software cursor moved to display hardware on 2026-11-27; no power saving measured from that yet); power under a Docker load reaches 62 W and 95 C; sleep/wake has not been re-tested on the current stack. The
reference EFI in the repository is an export of the live Tahoe ESP (2026-11-25): a reference for this one machine, not
a ready-to-boot EFI. Almost all code was written by an AI and tested on this one laptop.

## 2. What works, by area

"Doc" is the file that backs the row. Files marked (branch `research/audio-rog-dolby`) are on that branch only: the
audio work is not merged into this release. "Log" is the maintainer's install log (package notes, 2026-11-18 to
2026-11-25), which is not in the repository.

### Boot

| Item | State | Detail | Evidence | Doc |
|---|---|---|---|---|
| OpenCore boot of macOS 26.7.2 from the internal disk | works | OpenCore 1.0.9 debug build (`opencore-version` DBG-109-2026-10-09) with the Zen 5 timer patch | live boot 2026-11-25 10:40 | `patches/opencore`, `efi/README.md` |
| Eco boot to the login window | works | 14.4 s after kernel start on 2026-11-19 (was 77 s: a 60 s GPU wrangler timeout and a 3.5-4.4 s APFS trim, both fixed). Later boots measured about 23 s and 33 s (cold shader caches once; `MtkBtFw` holds the registry busy for 4-9 s). The owner accepts this | 2026-11-19, 2026-11-23 | `docs/BOOT-TIMELINE.md`; log |
| OpenCore picker | works | Still shown (2 s). A script to hide it exists; whether Esc at power-on still reaches the picker is not verified | 2026-11-19 | `docs/BOOT-TIMELINE.md` |
| Reference EFI in the repository (`efi/`) | partly | `efi/OC/config.plist` and the SSDTs were exported from the live Tahoe ESP on 2026-11-25 with `scripts/export-efi.py`: the current boot-args, the Tahoe kext entries, and the S0-idle / PTS5 / LIDFIX / ECRAM tables enabled. The export replaces serial, MLB, UUID and ROM, zeroes the Bluetooth controller info in NVRAM, empties the 890M's `vbios` device property (vendor firmware, not redistributed) and resets SSDT-RMNE's MAC to NullEthernet's default. Kexts are not included; `efi/kexts.json` lists 32 third-party kexts by hash. It is a reference for this one machine, not a ready-to-boot EFI: with its placeholders and the empty `vbios` the exported copy is not a tested boot configuration | exported 2026-11-25; `scripts/check-efi-privacy.py` passes | `efi/README.md`, `docs/FRESH-INSTALL.md` 1.1 |
| Fresh install on a blank disk | partly | Done once by hand on 2026-11-07 through the Tahoe installer app. The one-click installer is a design and read-only prototype scripts | 2026-11-07 | `docs/FRESH-INSTALL.md`, `docs/FRESH-INSTALL-LESSONS-2026-11-07.md` |

### Display, brightness, HDR

| Item | State | Detail | Evidence | Doc |
|---|---|---|---|---|
| Internal OLED on the 890M, 2880x1800 at 120 Hz | works | amdgpu display core inside NMXGPU; zero-copy page flips; flip completion from the page-flip interrupt and vblank from the real CRTC since out-33 | 2026-11-18 (out-33), verify script 19 pass / 0 fail on 2026-11-25 | `docs/FRAME-PATH.md`; log |
| Brightness slider and brightness keys | works | Handler inside NMXGPU (Step130c), owner verified | 2026-11-08 | `docs/890M-ROADMAP.md` |
| HiDPI | partly | "Looks like 1440x900" and native 2880x1800, both 120 Hz. No other scaled sizes: the framebuffer reports one mode. Extra modes are deferred | 2026-11-04 (owner report) | `docs/890M-TRACE.md`, "HiDPI scaled modes" |
| HDR / EDR | not verified | No test on the NMXGPU display path. The earlier HDR work was in `StrixGOP`, which is now switched off by boot-arg | - | - |
| Display sleep and wake | works | PASS on Step106c (2026-11-04) and listed as passing in the 2026-11-08 state; no run on record for the kernels since out-31 | 2026-11-08 | `docs/890M-ROADMAP.md` |
| PSR on a static screen | partly | PSR1 is enabled. On a static screen the GPU gates and PSR is reported active (`debug.nmx_gpu_metrics`, NMXGPU out-50; GFX rail 0.09 W). Read once, not a controlled measurement | 2026-11-25 (one read) | `docs/POWER-FEATURES.md`; log |
| HDMI output | partly | The port is wired to the RTX. Dead in Eco. In Standard it needs a re-test with the OLED on the 890M. The mode is decided at boot; no switch without a restart | owner question 2026-11-19 | `docs/890M-ROADMAP.md`; log |

### GPU acceleration

| Item | State | Detail | Evidence | Doc |
|---|---|---|---|---|
| WindowServer composited on the 890M | works | Frame-path check 19 pass / 0 fail on the 2026-11-25 boot. Trace on out-33: frame total p50 9.27 -> 6.05 ms, late frames 6 % -> 1.3 % | 2026-11-18, 2026-11-25 | `docs/FRAME-PATH.md`; log |
| WindowServer CPU cost | partly | 6.5-7.1 ms of CPU per present (26 % of a core at about 35 presents/s). The driver stack's share is 1.3-2.3 ms. A real Mac is about 1 ms | 2026-11-19, 2026-11-23 | `docs/WS-CPU.md` |
| WindowServer GPU work per present | partly | Every present recomposites the full 2880x1800 screen and then runs a full-screen colour pass, whatever the size of the change. 80 presents sampled on the live desktop: recomposite about 760 us of GPU (703-1476), colour pass 245 us, two 79x79 software-cursor passes of 8 us each; about 1.1 ms of GPU per present. The colour pass (fragment shader f1c2052c) is CoreDisplay's own GPU pass (`default.metallib` "GPUPass": combined gamma LUT, pre-matrix linearization, CSC matrix, post-gamma CSC). Measured on out-50. **Since NMXGPU out-51 (2026-11-27, `nmxhwcolor=1`) the colour pass is gone**: one Metal command buffer per present (1.00 in every sampled line, 38.5-99.5 presents/s, 0 errors), the colour tables applied by the display pipe. **The cursor is a hardware cursor plane since out-51 (`nmxhwcur=1`)**: cursor moves at about 55 states/s give 2-3 flips/s instead of a full present each. Since out-53 (16:36 boot) every cursor image has its own buffer: a cursor-size cycle of 40 to 250 px gave 25 images, 0 errors. The full-screen recomposite per present remains | 2026-11-25; 2026-11-27 (out-51, out-53) | `docs/WS-CPU.md` 9.6; log |
| Who causes the presents (flip census) | partly | First read only: plugin a6cec1ba with `NVMTL_FLIP_CENSUS=1` in WindowServer, about 9 minutes after boot; to be reread under the daily load. With the animated Aerial wallpaper moving, 887 of 899 presents in one 30 s window (30.0 presents/s) were caused by `WallpaperAerialsExtension` (4K HEVC wallpaper video), each one a full-screen recomposite, the colour pass and a flip. In the minutes before, presents fell from 51/s to 3/s with no client surface changed (WindowServer's own login animations and the cursor) | 2026-11-25 (one read) | log |
| WindowServer memory | works | QuartzCore's 160 MB metallib is mapped, not copied (log line "mapped (160153248 bytes, not copied)"). With VCNDec 0.2.1 the plugin holds 0 MB of plane shadows for VCN-decoded video (1.74 GB with the Aerial wallpaper on 2026-11-23). Census 7 minutes after boot: 1309 MB of imported client surfaces (631 MB of them idle in the surface keep), 181 MB device images, 33 MB buffers and heaps. Verified on plugin 8de348c, the build before the live one | 2026-11-25 | log |
| Shader caches across boots | works | The lowering cache "low2" is reused across boots: 12.6 s of lowering in WindowServer on the cold boot, 0.46 s on the next boot; 128 disk hits re-checked with 0 mismatches. Its key no longer depends on the plugin build | 2026-11-23, 2026-11-25 | log |
| Metal in applications | works | Every app gets the 890M (allow list `*`); sandboxed apps go through a user client in NMXAccel | 2026-11-04 (Step102-104) | `docs/890M-ROADMAP.md` |
| WebGL in Chrome and Edge | works | On the 890M since Step104. Google Maps broken strokes fixed (plugin + translator) | 2026-11-04; Maps fix verified 2026-11-18 | `docs/MAPS-WEBGL.md` |
| WebGL in Safari | works | Needs `StrixSbxMap`, a kernel-side exception that lets the WebKit GPU process map eight pinned plugin files by code hash. The pins must be refreshed after every plugin or RADV rebuild | A/B on 2026-11-04 (Step105c) | `docs/890M-ROADMAP.md`, "Safari WebGL" |
| Metal device for the RTX 5060 (hybrid) | broken | Not implemented on this stack. Deferred by the owner | - | `docs/890M-ROADMAP.md`, "Hybrid" |
| GPU compute for LLM runtimes | not verified | No test on the 890M stack | - | - |

### Video decode

Codec matrix of 2026-11-18 (NMXGPU out-33, RADV with all codecs, VCNDec 0.2.0): 59 cells (1080p30/60 and 4K; MP4,
fragmented MP4 over MSE, WebM, WebM over MSE), **58 pass, 0 fail, 1 without a test clip** (10-bit AV1 in WebM). Before
the fixes it was 19 pass, 39 fail. Doc: `docs/VIDEO-CODEC-MATRIX.md`.

| Codec | Chrome | Safari | QuickTime |
|---|---|---|---|
| H.264 8-bit | hardware | hardware | hardware |
| HEVC Main 8-bit | hardware | hardware | hardware |
| HEVC Main10 | hardware | hardware | hardware |
| VP9 profile 0 | hardware | hardware | no WebM in QuickTime |
| VP9 profile 2 (10-bit) | hardware | hardware | - |
| AV1 8-bit | hardware | hardware | hardware |
| AV1 10-bit (MP4 only) | hardware | hardware | hardware |

Limits of this evidence:

- The matrix was run on VCNDec 0.2.0. The live decoder is 0.2.1 (256-byte plane alignment; installed 2026-11-23, live
  since the 2026-11-25 10:40 boot). 0.2.1 was tested in-process (`vt_check`: every frame index right, 0 errors) and
  read once after the boot. **The full browser matrix has not been rerun on 0.2.1.**
- Edge was not part of the matrix (the test rule is Chrome only). Edge 4K VP9 on the VCN was observed under the
  owner's use on 2026-11-23.
- Hardware encode is not covered by any document: not verified.
- Each decoded frame is copied once on the GPU into the output IOSurface (12 MB at 4K 8-bit). Linux plays the decoder's
  image without a copy.

### RTX 5060

| Item | State | Detail | Evidence | Doc |
|---|---|---|---|---|
| Eco mode: card powered off and off the bus | works | `StrixDgpuGate` runs `_DSM` + `_PS3` and terminates the card's PCI nubs, so macOS does not wait for it. Verified on every boot since 0.2.1; 0.2.12 is live | 2026-11-19 to 2026-11-25 | `docs/BOOT-TIMELINE.md`; log |
| Loop guard (Eco falls back to Standard after an unfinished boot) | works | False trips on 2026-11-16 and 2026-11-22 came from a missing clear at shutdown; fixed in 0.2.5+. The shutdown clear was proven on 2026-11-23 | 2026-11-23 | `docs/BOOT-TIMELINE.md` 0.1 |
| Eco with sleep/wake, and charger plug/unplug with the card off the bus | not verified | The owner starts sleep tests; none was run since the card is taken off the bus. One charger hang on 2026-11-09 was not reproduced in two tests; the third test is deferred | - | `docs/HANDOFF-2026-11-16.md` 5.5 |
| Standard mode (card powered, NullMoth NVRM 2.7.1) | partly | The kernel side boots. The Standard boots on record since 2026-11-10 were loop-guard trips (2026-11-16, 2026-11-22), not planned tests. Apps get no Metal device from the RTX; HDMI needs a re-test | 2026-11-16 | `docs/HANDOFF-2026-11-16.md` |
| Switching mode | partly | NVRAM `strix-gpu-mode` (RogControl 0.6.0 GPU tile); needs a reboot | 2026-11-10 | rog-control-macos PR #17 |

### Wi-Fi and Bluetooth (MT7925)

| Item | State | Detail | Evidence | Doc |
|---|---|---|---|---|
| Wi-Fi, native mode (Wi-Fi menu, join from System Settings) | works | `itlmt7925` + `itlmt7925Native`. On 25G241 the mt7925-macos README records 176.6 Mb/s down, 65.0 Mb/s up, HE 160 MHz. In daily use on 25G332; no throughput run on record for 25G332 | 2026-11-02 (numbers), 2026-11-25 (loaded) | mt7925-macos `README.md` |
| Wi-Fi limits | partly | WPA2-PSK and open networks (an open network was used 2026-11-11, mt7925-macos `v2.0-beta.1` notes); no WPA3, 802.1X, 6 GHz. A-MSDU receive is off on purpose. The driver is fully polled, no interrupt: estimated 3-6 % of a core under traffic | 2026-11-23 | `docs/KERNEL-TASK-POLLERS.md` |
| AirDrop / AWDL / Continuity | not verified | In progress in mt7925-macos `dev/awdl`. `itlmt_awdl=1` is set on the reference machine; no working result is recorded | - | mt7925-macos `docs/ROADMAP-AWDL.md` |
| Bluetooth | works | `MtkBtFw` 0.3.3 (since 2026-11-27) + `BtLeDlFix` 1.4.0 + BlueToolFixup. The 15 s `bluetoothd` restart loop after a warm reboot was fixed on 2026-11-08; the `bluetoothd` fault at every boot was fixed on 2026-11-23. A BLE mouse is in daily use. Keyboard pairing is not recorded | 2026-11-08, 2026-11-23 | mt7925-macos `docs/BLUETOOTH.md`; `docs/SHUTDOWN-TIMELINE.md` |

### Audio

| Item | State | Detail | Evidence | Doc |
|---|---|---|---|---|
| Built-in output and input devices | works | SimpleHDA 1.0.1 brings AppleHDA back on Tahoe; AppleALC 1.9.9 (a local build with a GA403WM layout) for the ALC285 codec | 2026-11-05 | `docs/AUDIO-TAHOE.md` |
| Speakers | works | All four driver groups verified by a microphone sweep: tweeters on the codec, woofers on two CS35L56 amplifiers through `StrixAmp` 0.2.0. The "ROG Speakers" device and its DSP need the RogAudio HAL driver and `rogaudiod`, which must stay unsigned | 2026-11-23 | `docs/AUDIO-ROG.md` (branch `research/audio-rog-dolby`) |
| Microphones | partly | The internal pair works; Clear Mic (noise reduction) verified by speech. The third microphone cannot be reached under AppleHDA (one input engine). The input gain has been found at its minimum, cause unknown; a trace is armed | 2026-11-23 | `docs/AUDIO-ROG.md` 16-19 (branch `research/audio-rog-dolby`) |
| Headphone jack, audio after sleep | not verified | On Tahoe. A fix for ALC285 crackle is known but not applied | - | `docs/AUDIO-TAHOE.md` |

### Keyboard, Fn keys, touchpad, USB

| Item | State | Detail | Evidence | Doc |
|---|---|---|---|---|
| Keyboard | works | Internal USB keyboard. Needs a fix for the 2 s key-release lag: `ItlXhciKick` until 2026-11-26; since the 2026-11-27 boot `ItlXhciKick` is off and XHCILagFix (issue #9) is on test: checks 1-5 of the test pass; the owner's checks 6-11 are parked | live; XHCILagFix test only | `docs/USB-XHCI-LAG.md` |
| Fn keys | partly | Mute and volume work natively. The vendor-page keys (keyboard light, Aura, profile, airplane mode, M3/M4 and others) need `rogkeyd`, a user-space helper with Input Monitoring and Accessibility grants, plus `AsusWmi`. Fn+F10 (touchpad toggle) and Fn+F6 are not mapped | 2026-11-06 (release rogcontrol-v0.5.2) | rog-control-macos `docs/FN-HOTKEYS.md` |
| Touchpad | works | VoodooI2C + VoodooI2CHID in **GPIO interrupt mode** since 2026-11-27: VoodooGPIO built from upstream PR #22 (missed end-of-interrupt on AMD), and `-vi2c-force-polling` removed. I2C controller events: idle 10.1k/s (forced polling) -> 0/s; touching 4.4k/s, plus 193/s GPIO interrupts; `EoiRecoveries` 0. Before: forced polling at about 10k/s on CPU 0 | 2026-11-27 (16:36 boot) | `docs/KERNEL-TASK-POLLERS.md` |
| USB ports | works | `ItlXhciKick` 0.1.0 polled at 1 kHz until 2026-11-26; off on the 2026-11-27 boot (XHCILagFix on test). The live ESP has a USB map (USBToolBox + UTBMap). The 2026-11-25 export does not copy kexts, so `efi/OC/Kexts/UTBMap.kext` in the tree is the map as it was on 2026-10-13, not compared with the live one | live; map noted 2026-10-12 | `docs/USB-XHCI-LAG.md`, `docs/HANDOFF.md` |
| Webcam | works | UVC, last noted with the audio work | 2026-11-05 | `docs/AUDIO-TAHOE.md` |
| SD card reader | not verified | `Sinetek-rtsx` 9.0.0 is loaded; no function test on record | - | - |

### Sleep, wake, shutdown

| Item | State | Detail | Evidence | Doc |
|---|---|---|---|---|
| Sleep and wake | partly | The firmware has no S3. S0 idle sleep with RTC, lid and power-button wake passed with `StrixS0ix` 0.1.12 on 2026-11-07. S0i3 residency was not reached (DISPLAY and NBIO blocks not idle). **Not re-tested** since NMXGPU became a source build (2026-11-08), since IOSurface parking, and since Eco takes the RTX off the bus | 2026-11-07 | `docs/890M-TRACE.md` (Step107-126) |
| Shut Down | works | Stays off since `SSDT-PTS5` (2026-11-05). A shutdown takes 5-18 s for apps to quit plus 4-11 s of teardown, both third-party | 2026-11-05, 2026-11-23 | `docs/SHUTDOWN-TIMELINE.md` |
| Restart | partly | One restart on 2026-11-23 took 3 min 50 s between the kernel's restart message and the reset; cause unknown; a shutdown trace is armed in the gate | 2026-11-23 | `docs/SHUTDOWN-TIMELINE.md` 1.3 |

### Battery, power, thermals

| Item | State | Detail | Evidence | Doc |
|---|---|---|---|---|
| Light working load | works | Edge video + Claude app + 4 CLI sessions, AC, Eco, EPP 191: **17.0 W package (RAPL, 60 s), Tctl 57 C average (55-60)**, fans low, wired memory 6.6 GB | 2026-11-23 14:54 | `docs/POWER-UNDER-LOAD.md` |
| Heavy working load | partly | Docker + Android emulator + a Python backend + Claude, AC: **62.2 W package, Tctl 95 C average (91-96)**, fans at maximum, `kernel_task` 108 % from memory compression. Measured at EPP 0 (Turbo), with the RTX powered, Docker on 24 vCPUs and the whole guest wired. **Not re-measured** with EPP 191, Eco, 8 vCPUs and lazy guest wiring | 2026-11-16 18:56 | `docs/HANDOFF-2026-11-16.md` 3; `tools/health/2026-11-16/` |
| GPU rail readout | partly | `debug.nmx_gpu_metrics` on NMXGPU out-50. First read, 2 minutes after a boot: socket 17.4 W, of which **GFX 9.3 W**, all cores 9.4 W, GFX activity 22 %; the derived "rest of SoC" field came out negative (formula wrong). Later reads the same day: **GPU power follows the compositing rate.** Static screen: 0.09 W on the GFX rail, 6.2 W socket (the GPU gates, PSR active). 45-66 flips/s: 4.7-6.2 W on the GFX rail. 81-91 flips/s: 12.4-19.3 W on the GFX rail, socket up to 39.9 W. So the rail does go down when nothing is composited; the cost is per present (see "WindowServer GPU work per present") | 2026-11-25 | `docs/POWER-FEATURES.md`; log (the static and per-flip-rate numbers are in the log only) |
| Idle floor | not verified | 5.5 W at 47 C was measured once on 2026-11-08. A newer data point: 6.2 W socket with a static screen on 2026-11-25 (a single read of the SMU metrics, not a controlled measurement). Cores idle in HLT; no CC6 at run time | 2026-11-08; 2026-11-25 (one read) | `docs/POWER-FLOOR.md`; log |
| Profiles, fans, power limits, charge limit | works | `AsusWmi` 0.3.3 (since the 2026-11-27 16:36 boot; fan-curve sanity checks since 0.3.2) + RogControl + `AmdCppcPolicy` do what Linux and Windows do for the presets (one thermal-policy write; firmware loads limits and fan curve). Manual power limits verified on 2026-11-27: a 25 W cap held under an all-core load (section 4, item 20). The per-profile bench is not done | 2026-11-16; 2026-11-27 (power limits) | `docs/PLATFORM-LIMITS.md` |
| Battery | partly | Charge level through SMCBatteryManager. Battery life is not measured in Eco. One reading with the RTX powered and a heavy load: 75 W drain against 31 W package. The "60 W" adapter figure in System Information is a placeholder | 2026-11-16 | `docs/POWER-FLOOR.md` |

### Virtualization and the iOS Simulator

| Item | State | Detail | Evidence | Doc |
|---|---|---|---|---|
| Docker Desktop on `RyzenHV` | works | Since 0.7.23 guest memory is wired lazily (about 3 GB wired for an 8 GB guest instead of 8 GB). Reclaim of cold guest memory is a run-time switch that resets to off at boot (2.86 -> 1.74 GB when on). Idle containers on 8 vCPUs cost 17.5 % of a core. These figures were measured on 0.7.23 and not re-measured on 0.7.24, which is live since 2026-11-25 | 2026-11-18, 2026-11-23 | `docs/RYZENHV-GUEST-MEM.md` |
| Docker quit | partly | Quitting Docker Desktop 4.98 can leave a HyperKit process spinning two cores (a HyperKit deadlock, not RyzenHV) | 2026-11-23 | log |
| Android emulator (QEMU with HVF) | works | Fixed by RyzenHV 0.7.24 (fork commit 11ec930) and verified on 2026-11-25. The owner's own AVD (Medium_Phone, Android 37) boots after "Cold Boot Now". On a scratch AVD (1 vCPU, Android 37 playstore x86_64, Linux 6.12.81) a cold boot reaches `sys.boot_completed` in 23.8-31.6 s (80.8 s on the very first boot, Android's first-boot setup); the guest sees no pku/ospke, and the `xstate.c` WARN is gone in 6 of 6 kernel logs. Limits: a quickboot snapshot saved from a stalled guest restores the stall, so the first start after the fix must be a cold boot (Device Manager > Cold Boot Now). Restoring a snapshot saved from a healthy boot is **not verified**. Tested with the emulator's default software GPU (`hw.gpu.mode` auto resolves to swiftshader); host-GPU rendering is **not verified**. Cause: section 4, item 1 | 2026-11-25 | log; ryzen-hypervisor.framework fork, branch `fix/vmcb-cache-switch` 11ec930 |
| iOS Simulator | works | Renders on the 890M; SimBench 60 fps; the crash loop that cost 1.1 cores was fixed in the translator. One wallpaper shader still fails. Flutter and Android toolchains are not measured in any committed document | 2026-11-07 | `docs/SIMULATOR-PERF.md` |

## 3. Component versions live on 2026-11-27 (boot of 15:34)

Source: `kextstat` on the boots of 2026-11-25 19:46 and 20:42; source commits from the install log. Rows changed on
2026-11-27 (packages live since the 15:34 and 16:36 boots) follow their install notes and say so. UUIDs are the first
8 hex digits of the binary's LC_UUID.

### Ours (built from the five repositories)

| Component | Where it loads from | Version | UUID | Source commit |
|---|---|---|---|---|
| NMXGPU (`com.nullmoth.NMXGPU`) | AuxKC | 1.0.0, build out-53 | C98C699B | nvidia-macos-driver fork, `claude/integ-out53` bdcef38a: a cursor buffer per image, and run counting for thread calls (backlight and paging wake included). Live since the 2026-11-27 16:36 boot; replaces out-51 DC67434B (edb0c79a, 15:34 boot) and out-50 7390F47B. Boot-args `nmxhwcolor=1 nmxhwcur=1` |
| NMXAccel (`com.nullmoth.NMXAccel`) | AuxKC | 0.1 | 4C8A5A6E | fork, `claude/integ-out51` 8c3ad77f, 2026-11-27 package (replaces D454C218) |
| NMXAGDC (`com.ga403wm.NMXAGDC`) | AuxKC | 0.1 | 9182A055 | fork, `claude/integ-out51` 8c3ad77f, 2026-11-27 package (replaces 90C7A833) |
| Metal plugin (NVMTLDriver) | `/Library/GPUBundles` | - | 36577BD4 | fork, `claude/mem-census` a6cec1ba (replaces AAC482F2 / 8de348c) |
| Shader translator | `/Library/GPUBundles` | - | - | 6208982 (installed 2026-11-18; no later entry in the log) |
| RADV (`libvulkan_radeon.dylib`) | `/Library/GPUBundles/nvmtl` | - | 07725f8c (hash prefix from the log) | Mesa built with `-Dvideo-codecs=all` + `scripts/radv/radv-disk-cache-euid.patch` |
| VCNDec | `/System/Library/Video/Plug-Ins` (blessed snapshot) | 0.2.1 | E7D4AB21 | this repo, `tools/890m/vcndec` at 15c33fa (the tree here is one test-only commit newer, d378c71). Installed 2026-11-23, live since 2026-11-25 10:40 |
| StrixDgpuGate | ESP | 0.2.12 | 7AD92287 | rog-control-macos `fix/eco-offbus` 80356b5 |
| AsusWmi | ESP | 0.3.3 | 0370E5BC | rog-control-macos main 40d5a6c (PRs #21 and #23), released as `rogcontrol-v0.6.1`. Live since the 2026-11-27 16:36 boot (replaces 0.3.2 4430BC34 of the 15:34 boot and 0.3.1 42393DEB) |
| AmdCppc | ESP | 0.2.1 | 2EBD4419 | rog-control-macos; commit not in the log |
| RogControl.app, rogkeyd | `/Applications`, user LaunchAgent | 0.6.0, 1.2 | - | rog-control-macos `feat/gpu-mode` (PR #17, open); as of 2026-11-16, not re-read on 2026-11-25 |
| RyzenHV | ESP | 0.7.25 | CCD7FEC3 | ryzen-hypervisor.framework fork, 42ce5e1 (a CPL fix on top of 0.7.24 11ec930), 2026-11-27 package (replaces 0.7.24 4DB41FBD) |
| itlmt7925 (core) | ESP | 0.1.0 | D2CAADD0 | mt7925-macos `dev/awdl` (0ec468c records the install) |
| itlmt7925Native | ESP | 0.1.0 | 149441A4 | mt7925-macos |
| MtkBtFw | ESP | 0.3.3 | 41826D92 | mt7925-macos d5c3f8b (MT7922 port on top of 0.3.2), released as `bt-v1.2`; 2026-11-27 package (replaces 0.3.1 D173A506) |
| BtLeDlFix | ESP | 1.4.0 | C6274348 | mt7925-macos |
| StrixS0ix | AuxKC | 0.1.17 | 1700FABF | this repo, `kexts/StrixS0ix` |
| StrixSbxMap | ESP | 0.1.0 | F66BFC76 | this repo, `kexts/StrixSbxMap` |
| ItlXhciKick | ESP | 0.1.0 | 5D179C74 | this repo, `kexts/ItlXhciKick`. Loaded but switched off since 2026-11-27 (`itlkick=0`) for the XHCILagFix test below |
| ItlDiag | not recorded (its entry in the exported `config.plist` is disabled) | 0.1.0 | 9FFBB49A | this repo, `kexts/ItlDiag` |
| StrixAmp | ESP | 0.2.0 | 6E9C3F38 | this repo, branch `research/audio-rog-dolby` |
| RogAudio HAL driver, rogaudiod | `/Library/Audio`, `/Library/Application Support/RogAudio` | - | - | this repo, branch `research/audio-rog-dolby` (installed 2026-11-23) |

Loaded but switched off by boot-arg on this machine: StrixGOP 0.1.11 (E0F294C0, `-strixgopoff`), StrixAccel 0.1.21
(AF1F2E29, `-strixaccoff`), StrixMetalGate 0.1.1 (A1DAB568, `-strixmetalgateoff`). Also loaded from the earlier
research: StrixProbe 0.1.2 (DA6A1F25), StrixHeadroom 0.1.0 (13E8A6D4); their role on the current stack was not
re-checked. The versions of these five were re-read on the evening boots; the UUIDs are from the 10:40 boot.

On test since 2026-11-27: **XHCILagFix** (ESP), a third-party Lilu plugin by the reporter of
[issue #9](https://github.com/thanhnndev/ga403wm-hackintosh/issues/9) that sends all xHCI transfer events to
interrupter 0 instead of polling. Built locally from its source for this test. It has no licence, so it is not
redistributed by this project and no binary of it is published here. Test only; result not recorded yet.

### Third-party (not ours, not redistributed)

| Component | Version | UUID |
|---|---|---|
| OpenCore | 1.0.9 debug build of 2026-10-09 + Zen 5 FSB patch | - |
| NullMoth NVIDIA stack (NVRM, NVAccel, NVRMFB, NVRMAGDC) | 2.7.1 in the AuxKC. In this Eco boot only NVRMAGDC is loaded (4DBD6B43) | |
| Lilu | 1.7.3 | 38ACFA46 |
| VirtualSMC, SMCBatteryManager | 1.3.9 | FF5A572E, CAF7573C |
| AppleALC (local layout build) | 1.9.9 | 58752E4F |
| SimpleHDA | 1.0.1 | F1EA3386 |
| VoodooI2C, VoodooI2CHID, VoodooInput | 2.9.1, 1, 1.1.7 | 0BD5308D, 92D5DDB4, 15EDDA4B |
| VoodooGPIO | 1.1, built from upstream [VoodooGPIO PR #22](https://github.com/VoodooI2C/VoodooGPIO/pull/22) by [brkbrlz16](https://github.com/brkbrlz16) (AMD end-of-interrupt fix; open upstream, not in a release). Live since 2026-11-27; replaces 5D44616D | 954AEF39 |
| BrightnessKeys | 1.0.4 | AE157CF3 |
| ForgedInvariant | 1.5.0 | F0302C2D |
| NVMeFix | 1.1.4 | BDF0CF20 |
| RestrictEvents | 1.1.7 | A708639D |
| AMFIPass | 1.4.1 | 7DF1CDFC |
| BlueToolFixup | 2.7.2 | 037F9890 |
| USBToolBox | 1.2.0 | DF8F0CD3 |
| Sinetek-rtsx | 9.0.0 | 27134E65 |
| NullEthernet | 1.0.6 | A38D6C66 |

### Installed or built, but not running

| Component | State | Purpose |
|---|---|---|
| ItlXhciKick 0.2.1 | built, not installed, never run on hardware. An earlier 0.2.0 was 3A784B45 (branch `thermal/xhcikick-pending` 60548a7); the UUID and commit of 0.2.1 are not recorded here | kick only when an event is queued; back off when idle |

### Version conflicts between sources

- `docs/HANDOFF-2026-11-16.md` lists itlmt7925 B9E6878A, RyzenHV 0.7.22, AsusWmi 0.3.0, gate 694511EA, NMXGPU out-29.
  All were replaced later; the table above follows the loaded-kext list of 2026-11-25, the log and the 2026-11-27 package.
- RyzenHV 0.7.24 (4DB41FBD) printed "0.7.22" in its own log line. The string is stale; the loaded binary is 0.7.24.
  A first 0.7.24 without the emulator fix (56D13B2B, commit 2e2c95c) was staged on 2026-11-25 at 10:44 and replaced
  the same day.
- The maintainer's notes say BtLeDlFix 1.3.0 was live on 2026-11-08 with 1.4.0 staged. 1.4.0 is what is loaded now.
- The mt7925-macos README (status dated 2026-11-02) says Bluetooth is "not checked" on Tahoe. The newer notes
  (2026-11-08, 2026-11-23) record it working on 25G332. The README is out of date.
- `docs/HANDOFF-2026-11-16.md` lists "NMXAccel from source" as deferred. `docs/FRAME-PATH.md` (2026-11-18) says NMXAccel
  is built from the fork (`kexts/NVRM/accel/nvrm-accel.cpp` with `NMX_ACCEL`). The later document is followed here.
- The 2026-11-18 15:54 boot: the install log says the gate held Eco; the boot table in `docs/BOOT-TIMELINE.md` labels
  the same boot "RTX on". Not resolved here; no claim in this document depends on it.
- `research/890m-cobalt64` still carries October copies (all 0.1.0) of `kexts/AsusWmi`, `kexts/AmdCppc`,
  `kexts/MtkBtFw`, `kexts/itlmt7925`, `macos/RogControl` and `macos/ItlWiFi`. They are removed on the release branch,
  as on `main`: the live builds come from mt7925-macos and rog-control-macos.

## 4. Known issues, with what is known about the cause

1. **Android emulator guest stalled under RyzenHV: fixed, verified 2026-11-25.** The guest kernel reached
   "dlkm_loader: module load count is 47" at 13.9 s and then went silent; qemu spun. The emulator uses a software GPU,
   so host graphics was ruled out. Cause: RyzenHV showed the CPUID bits PKU and OSPKE to guests, while macOS never
   enables PKRU state in XCR0. A Linux 6.12 guest that sees PKU cannot build signal frames, so init loops. Fix:
   RyzenHV 0.7.24, commit 11ec930 on branch `fix/vmcb-cache-switch` of the ryzen-hypervisor.framework fork (the same
   fix as upstream 0.7.9's 62fcd1d, plus CPUID leaf 0xD bit 9). Verified on the owner's AVD and on a scratch AVD; the
   numbers are in the Virtualization table. The earlier belief that RyzenHV 0.7.22 broke the emulator was wrong: an
   A/B of its two shortcuts (run-time switch `rhv-info hv cache 0/1/2/3`) boots in all four settings with no
   measurable difference. Still open: a quickboot snapshot saved from a stalled guest restores the stall, so the first
   start after the fix must be a cold boot; restoring a snapshot saved from a healthy boot is not verified; host-GPU
   rendering in the emulator is not verified. A review also found CLTS/LMSW decoded as MOV CR0 (older than the stall,
   not shown to be related; on the roadmap).
2. **WindowServer CPU per frame.** 6.5-7.1 ms per present. Found and fixed so far: two shader translations of 3.6 s
   each, an empty Mesa disk cache in WindowServer, plane shadows recopied in every command buffer, address lowering run
   twice with no cache (the lowering cache now holds across boots). Remaining: the per-frame work in QuartzCore plus
   plugin. A "static" desktop still presented about 30 frames/s; the first flip census (2026-11-25, one read) names
   the animated Aerial wallpaper: `WallpaperAerialsExtension` caused 887 of 899 presents in a 30 s window. Who drives
   the flips under the daily load is not counted yet.
3. **Heat and fan noise under a Docker load (62 W, 95 C on 2026-11-16).** Ranked causes: the VM's exit path (most guest
   exits go to user-space HyperKit) and its wired memory, which pushed `kernel_task` to 108 % in compression; EPP 0 on
   AC at that time (now 191); the RTX powered on that boot. In Turbo, 95 C is also what the firmware's limits allow
   (80 W sustained), so part of it is the chosen profile. Not re-measured since the fixes.
4. **GPU and SoC power at light load.** 17 W package while the cores account for 4-6 W. The first rail read gives
   9.3 W to GFX. Every power feature is at the upstream default. Reads on 2026-11-25 show that GPU power follows the
   compositing rate: a static screen is 0.09 W on the GFX rail (6.2 W socket, the GPU gates, PSR active), 45-66
   flips/s is 4.7-6.2 W, 81-91 flips/s is 12.4-19.3 W on the GFX rail (socket up to 39.9 W). So the rail does drop
   when nothing is presented, and the cost is the work per present, not a missing power feature: every present
   recomposites the full 2880x1800 screen (about 760 us of GPU) and then runs CoreDisplay's full-screen colour pass
   (245 us), about 1.1 ms of GPU in all (`docs/WS-CPU.md` 9.6). Since out-51 (2026-11-27) the colour pass is done by
   the display pipe and the cursor is a hardware plane (roadmap items 1 and 2, done). Power at 45-66 flips/s on out-51
   is about the same as on out-50, so **no saving is measured yet**; the full-screen recomposite remains. The first flip census names the Aerial wallpaper for an idle desktop (item 2); the read under the daily
   load is not done.
5. **`kernel_task` with no memory pressure.** About 20 % of a core before 2026-11-27; about 7 % at light load on the
   15:34 boot (ItlXhciKick off, `itlkick=0`, XHCILagFix on test). On the 16:36 boot the touchpad left forced polling
   (GPIO interrupts, 0 controller events/s when idle), and `kernel_task` measured **100 ms of CPU per second (10 % of a
   core) in steady state under work** (difference of its CPU time over an interval). Remaining known poller: the Wi-Fi
   receive/transmit loop with no interrupt (est. 3-6 %).
6. **Memory exhaustion hang (2026-11-18 17:46).** 25.2 of 32 GB wired. Cause found: WindowServer leaked about 330 MB of
   GPU memory per Aerial wallpaper clip (plugin keep cache). Fixed in the plugin on 2026-11-19 and verified flat over
   14 min. Parked-buffer and pinned-memory work under real memory pressure is still open.
7. **Graphics page fault from `mediaanalysisd` (2026-11-18 20:34).** It wrote a parked IOSurface import that its submit
   did not list. The code path is not found; three synthetic repros passed; not seen again. Newer kernels print the
   IOSurface on the fault line.
8. **Process-exit hang in `amdgpu_vm_fini` (2026-11-19, once, blocked a shutdown for 2 h 14 min).** Root cause: the
   compatibility layer freed the Linux task of a thread still inside the driver's close path (use after free, lost
   wake-up). Fixed in out-43; not seen since. Review follow-ups on the same teardown path went into out-45.
9. **Restart took 3 min 50 s once (2026-11-23).** No log between the kernel's restart message and the CPU reset.
   Cause unknown (driver shutdown, platform reset or firmware). The gate writes a shutdown trace to NVRAM since 0.2.9.
10. **Sleep.** S0i3 was never reached (DISPLAY and NBIO blocks stay busy), so sleep saves less than it should. No sleep
    test exists for the current kernel, with parked buffers, or with the RTX off the bus.
11. **Microphone gain found at minimum.** coreaudiod does persist the gain, so something sets it. Suspect: an app's
    automatic gain control (WebRTC). A trace in `rogaudiod` logs every change.
12. **Third microphone.** AppleHDA runs one analog input engine with exclusive sources, so no codec layout can capture
    both inputs. It needs a capture driver outside AppleHDA; not started.
13. **Safari WebGL depends on pinned code hashes.** After any plugin or RADV rebuild the pins must be refreshed, or the
    WebKit GPU process loses the 890M (it fails closed).
14. **WindowServer picks up a new plugin or RADV only at a reboot.** A logout does not restart it on this machine.
15. **HDMI.** Wired to the RTX: no output in Eco, and no way to bring it up without a reboot.
16. **Old panics, not ours as far as known.** HoRNDIS (USB tethering) `fq_codel` panics on 2026-11-08; a kernel use
    after free on 2026-11-09 during CloudflareWARP matching whose owning kext was not found.
17. **Docker Desktop quit leaves a spinning HyperKit.** A HyperKit read deadlock on SIGTERM; not RyzenHV.
18. **The reference EFI is a reference, not a bootable EFI.** `efi/` was exported from the live ESP on 2026-11-25.
    A reader must fill in serial, MLB, UUID and ROM, put their own card's VBIOS image into the emptied `vbios`
    property, and supply every kext. The exported copy was not booted. See `efi/README.md`.
19. **Where the versions named here are published.** Published: this repository's release `v2` (tag at 3901d1d),
    and three source tags: nvidia-macos-driver `ga403wm-890m-out50` (kernel, f47d3ed) and
    `ga403wm-890m-plugin-a6cec1b` (plugin, a6cec1ba), ryzen-hypervisor.framework `v0.7.24-ga403wm`. Published on
    2026-11-25: mt7925-macos `v2.0-beta.1` (Wi-Fi) and `bt-v1.1` (Bluetooth), rog-control-macos `rogcontrol-v0.6.0`.
    Published on 2026-11-27: rog-control-macos `rogcontrol-v0.6.1` (AsusWmi 0.3.3) and mt7925-macos `bt-v1.2`
    (MtkBtFw 0.3.3; the BLE mouse is not tested on 0.3.3 yet, MT7922 support is experimental and untested). NMXGPU
    out-51 and out-53 have no source tag yet. StrixAmp and RogAudio are still only on branch `research/audio-rog-dolby` of
    this repository.
20. **Manual power limits (SPL, SPPT, FPPT) reported a firmware error: fixed, verified 2026-11-27.** The BIOS's WMI
    method calls `ALIB(0x0C, ...)`, whose handler `A032` sends the SMU message and then has no `Return`, so the AML
    store fails and WMNB aborts (the same pattern as `A026` in `ACAD._PSR`, which the EFI already patches). The limit
    is applied anyway: on 0.3.2 (AC, Balanced + custom curve, 24 busy threads) package power went from 64-71 W to
    24.4-25.0 W within 5 s of `spl=25`, Tctl 91-93 -> 66 C. `AsusWmi` 0.3.3 counts this one error as sent: on the
    16:36 boot the writes return 0, the 25 W cap held and RogControl applied its limits (61 / 65 / 68 W) at boot.
    Released as `rogcontrol-v0.6.1`.
21. **Hardware colour: open checks.** A grey-ramp eye check is not done. The colour tables are not re-applied after
    a modeset by HDMI or a client. The profile readback matches (sRGB pure; Adobe RGB red 219/2/0, green 144/255/60,
    blue 2/0/250; the panel default is P3-like), so the profile is applied in composition.
22. **Hardware cursor: open check.** The cursor after a logout and login is not checked.
23. **Aerial lock screen draws 9-10 W.** Its video does not decode on VCN.

## 5. Roadmap

Order follows the owner's priority, stated on 2026-11-16 and again on 2026-11-23: the machine is on only while the
owner works on it, for hours, under video + Claude + Docker. What counts is smoothness under that load, heat and fan
noise, and memory. Boot, login and shutdown seconds do not matter unless something hangs for minutes. Tests that need
the machine idle or asleep come last.

### Next (in order)

Done on 2026-11-27 (NMXGPU out-51 on the 15:34 boot, out-53 on the 16:36 boot):

- **Hardware colour pipeline** (`nmxhwcolor=1`). CoreDisplay's GPU colour pass is gone: one command buffer per present
  (1.00), 0 errors. Night Shift works through the CTM. Profile readback in section 4, item 21.
- **Hardware cursor plane** (`nmxhwcur=1`). Cursor moves at about 55 states/s give 2-3 flips/s instead of a full
  present each. out-53 (16:36 boot) gives every cursor image its own buffer: 40-250 px size cycle, 25 images, 0 errors.
- **Manual power limits** (`AsusWmi` 0.3.3, section 4 item 20) and **touchpad interrupts** (VoodooGPIO PR #22, forced
  polling removed; `kernel_task` 100 ms/s in steady state under work).
- Power at 45-66 flips/s is about the same as on out-50: no measured saving yet. `kernel_task` is about 7 % at light
  load (was about 20 %; ItlXhciKick off for the XHCILagFix test).

Open from these: the grey-ramp eye check, colour after an HDMI or client modeset, the cursor after logout/login.

1. **Measurement build out-54 and plugin keep-pressure.** Built, in review, not installed.
2. **The surface keep in WindowServer.** The 631 MB of idle imported client surfaces seen on 2026-11-25 is a cache
   bounded by its cap, not a leak (analysis of 2026-11-27). What remains is how the keep behaves under memory
   pressure (item 1's plugin change).
3. **Heat under the Docker load** (moved up). Re-measure the 62 W / 95 C state with the current settings (EPP 191,
   Eco, 8 vCPUs, lazy wiring), then the RyzenHV exit path.
4. **Who drives the flips under the daily load, and damage-sized composition.** Reread the flip census under video +
   Claude + Docker (the first read covers an idle desktop only), then composite only the changed rectangle instead of
   the full 2880x1800 screen on every present.
5. **USB event lag: XHCILagFix test (issue #9) against ItlXhciKick 0.2.1.** XHCILagFix is on test since 2026-11-27
   with ItlXhciKick off; checks 1-5 pass, the owner's checks 6-11 are parked. If it holds (keyboard key-up, webcam, USB audio, sleep/wake), ItlXhciKick is not needed.
   ItlXhciKick 0.2.1 (kick only when an event is queued) stays built, never run.
6. **Aerial lock screen** (9-10 W, not on VCN).
7. **RyzenHV follow-ups.** CLTS/LMSW decode, flush bookkeeping, upstream 0.7.9's read-only map fallback.
8. **The items listed as not verified.** Sleep/wake with the RTX off the bus, HDR, hardware encode, the SD reader,
   the headphone jack, emulator quickboot snapshots saved from a healthy boot, host-GPU rendering in the emulator.

### Later

- RyzenHV cost with Docker: keep exits in the kernel where HyperKit allows it; make guest-memory reclaim safe to leave
  on. This is the only lever sized like the 62 W state (estimated 8-15 W).
- WindowServer CPU per present (6.5-7.1 ms).
- Polling in `kernel_task`: a sleep instead of a busy window in the Wi-Fi loop (it also keeps idle cores from sleeping
  deeply).
- Memory under pressure: pinned and parked GPU memory when RAM is short; the `mediaanalysisd` fault if it returns.
- GPU readout: fix the derived "rest of SoC" field and commit the 2026-11-25 reads to `docs/POWER-FEATURES.md`.
- Sleep/wake on the current stack, then S0i3; Eco with sleep and charger events (the owner starts these).
- A controlled idle-floor measurement, the IPS read, per-profile bench and fan-curve read (need a quiet machine).
- Rerun the codec matrix on VCNDec 0.2.1; decode straight into the IOSurface (no per-frame copy).
- Wi-Fi: interrupts instead of polling, WPA3, AWDL/AirDrop.
- Audio: microphone gain cause, headphone jack, audio after sleep; merge `research/audio-rog-dolby`.
- HDMI in Standard mode with the OLED on the 890M.
- Hide the OpenCore picker after the Esc test; compare the USB map in `efi/` with the live one; the one-click
  installer.
- Housekeeping: merge the branches the live kexts were built from (rog-control-macos PRs #16 and #17 and `fix/*`,
  mt7925-macos `fix/bt-waitquiet`); decide on `research/audio-rog-dolby` and `thermal/xhcikick-pending`. Done on
  branch `release/tahoe-v2`: side branches merged, the branch reconciled with `main`, the live EFI exported through
  `scripts/export-efi.py` and checked with `scripts/check-efi-privacy.py` (2026-11-25).
- The unexplained 3 min 50 s restart, if it happens again.

### Not planned (or deferred by the owner)

| Item | Reason |
|---|---|
| Metal device for the RTX with automatic GPU choice per app | large; deferred by the owner (2026-11-10, 2026-11-16) |
| Extra HiDPI scaled modes | deferred by the owner; the two existing sizes are enough for daily use |
| RADV / libdrm replacement, dropping the NullMoth NVIDIA kexts | deferred; the NVIDIA kexts are the only RTX 5060 driver on macOS |
| HDMI without a reboot | the port belongs to the RTX and the mode is decided at boot; a study was offered, not started |
| Third microphone | needs a new capture driver outside AppleHDA |
| DMUB IPS2 in active idle, Panel Replay | upstream amdgpu forbids IPS2 on this PMFW (93.11 < 93.99, hard-hang workaround); the panel reports PSR1 only |
| Boot, login and shutdown time | owner: not a priority unless it is a hang |
| macOS 15 for the 890M stack | the work targets Darwin 25.x; macOS 15 stays on the v1 / kext-v1.1 setup |
| Other laptops | one machine, one BIOS; no second tester |

## 6. How the pieces map to the repositories

| Repository | Holds | Live pieces built from it |
|---|---|---|
| **thanhnndev/ga403wm-hackintosh** (this one) | OpenCore reference EFI and SSDTs, OpenCore Zen 5 patch, install and recovery scripts, all documents and traces, 890M tools (`tools/890m`: VCNDec, video suite, verify and probe scripts), small kexts | ItlXhciKick, StrixS0ix, StrixSbxMap, VCNDec; StrixAmp and RogAudio from branch `research/audio-rog-dolby`; the retired boot-display kexts StrixGOP / StrixAccel / StrixMetalGate / StrixHeadroom / StrixProbe |
| **thanhnndev/mt7925-macos** | MT7925 Wi-Fi (core + native front end, AWDL work) and Bluetooth | itlmt7925, itlmt7925Native, MtkBtFw, BtLeDlFix |
| **thanhnndev/rog-control-macos** | ASUS platform kexts, the RogControl app, the CPU policy daemon, the Fn-key helper, the dGPU gate | AsusWmi, AmdCppc, AmdCppcPolicy, RogControl.app, rogkeyd, StrixDgpuGate |
| **thanhnndev/ryzen-hypervisor.framework** (fork of OverlordDev/ryzen-hypervisor.framework) | SVM hypervisor kext and its Hypervisor.framework front end | RyzenHV (Docker Desktop runs on it) |
| **thanhnndev/nvidia-macos-driver** (fork of nullmoth/nvidia-macos-driver, PolyForm Noncommercial) | NMXGPU (amdgpu on the xkpi layer), NMXAccel, NMXAGDC, the Metal plugin and translator; the upstream NVIDIA stack | NMXGPU, NMXAccel, NMXAGDC, NVMTLDriver plugin, translator. RADV is Mesa plus two patches kept in this repo under `scripts/radv` |

Notes:

- The licence split matters for a release: everything from the nvidia-macos-driver fork is PolyForm Noncommercial and
  is kept out of this BSD repository. The reference EFI derives from nullmoth/1401 and is PolyForm Noncommercial too.
- A sixth repository, **thanhnndev/strix-890m-macos**, holds a copy of the boot-display kexts and traces (last push
  2026-11-02). The same kexts and traces are still in this repository and are newer here. Which one is the home for
  them is an open question for the maintainer.
- The NVIDIA kexts (NVRM 2.7.1 and friends) are NullMoth's binaries, installed by
  `scripts/macos-install-nvidia-2.7.1.sh`; they are needed only for Standard mode.

## 7. Credits

This setup stands on other people's work. The list covers what the reference machine really uses (checked against
`efi/kexts.json`, `efi/OC/config.plist`, `NOTICE.md` and the build scripts) and the code the drivers were derived from.
Third-party binaries are not redistributed here; licences are in [NOTICE.md](../NOTICE.md) and in each project.

**Boot and kernel patches**

| Project | Used for |
|---|---|
| [OpenCore](https://github.com/acidanthera/OpenCorePkg) (acidanthera) | the boot loader; `patches/opencore/fix-zen5-fsb.diff` is a patch against its `OcCpuLib` |
| [nullmoth/1401](https://github.com/nullmoth/1401) (NullMoth) | the base OpenCore configuration and SSDTs that `efi/` derives from |
| [AMD_Vanilla](https://github.com/AMD-OSX/AMD_Vanilla) kernel patches (AMD-OSX; patch comments name algrey, XLNC, Shaneee, Zormeister, Goldfish64, Visual, laobamac) and CaseySJ's IOPCIFamily patches | the `Kernel > Patch` entries that let XNU run on an AMD CPU, as shipped by the base configuration |
| [Dortania](https://dortania.github.io/OpenCore-Install-Guide/) guides | read during the bring-up; source of `AppleMCEReporterDisabler` |
| [MacKernelSDK](https://github.com/acidanthera/MacKernelSDK) (acidanthera) | kernel headers and libraries for `scripts/build.sh` |

**Kexts on the ESP (third-party)**

| Project | Used for |
|---|---|
| [Lilu](https://github.com/acidanthera/Lilu) (acidanthera) | patching framework for the plug-ins below and for `StrixSbxMap`, `BtLeDlFix` |
| [VirtualSMC](https://github.com/acidanthera/VirtualSMC) with SMCBatteryManager and SMCLightSensor (acidanthera) | SMC emulation, battery status; the light-sensor plug-in is on the ESP but disabled |
| [AppleALC](https://github.com/acidanthera/AppleALC) (acidanthera) | ALC285 codec (a local build with a GA403WM layout) |
| [SimpleHDA](https://github.com/laobamac/SimpleHDA) (laobamac) | brings AppleHDA back on macOS 26 |
| [WhateverGreen](https://github.com/acidanthera/WhateverGreen) (acidanthera) | on the ESP, disabled in this configuration |
| [NVMeFix](https://github.com/acidanthera/NVMeFix) (acidanthera) | NVMe power management |
| [BrightnessKeys](https://github.com/acidanthera/BrightnessKeys) (acidanthera) | brightness hot keys |
| [RestrictEvents](https://github.com/acidanthera/RestrictEvents) (acidanthera) | CPU name and the `sbvmm` patch |
| [BlueToolFixup](https://github.com/acidanthera/BrcmPatchRAM) (acidanthera, BrcmPatchRAM) | lets `bluetoothd` accept a non-Apple controller |
| [AMFIPass](https://github.com/dortania/OpenCore-Legacy-Patcher) (dhinakg, shipped with OpenCore Legacy Patcher) | lets platform binaries load the ad hoc signed driver bundles |
| [USBToolBox](https://github.com/USBToolBox/kext) (dhinakg) | USB port map |
| [VoodooI2C](https://github.com/VoodooI2C/VoodooI2C), [VoodooI2CHID](https://github.com/VoodooI2C/VoodooI2CHID), VoodooGPIO, VoodooInput | the I2C-HID touchpad |
| [NullEthernet](https://github.com/RehabMan/OS-X-Null-Ethernet) (RehabMan) | the fake `en0` |
| [ForgedInvariant](https://github.com/ChefKissInc/ForgedInvariant) (ChefKiss) | TSC synchronisation on AMD |
| [Sinetek-rtsx](https://github.com/sinetek/Sinetek-rtsx) | Realtek SD-card reader driver (loaded; function not verified) |
| [HoRNDIS](https://github.com/jwise/HoRNDIS) (Joshua Wise) | USB tethering from an Android phone while installing |
| AppleMCEReporterDisabler | stops the AppleIntelMCEReporter panic on AMD |

**GPU, video and virtualization**

| Project | Used for |
|---|---|
| [NullMoth's NVIDIA driver for macOS](https://github.com/nullmoth/nvidia-macos-driver) (NullMoth) | the RTX 5060 driver in Standard mode, and the NMX stack (`NMXGPU`, `NMXAccel`, the Metal plugin and translator) that the 890M work is a [fork](https://github.com/thanhnndev/nvidia-macos-driver) of |
| The Linux kernel's [amdgpu and DRM](https://gitlab.freedesktop.org/drm/kernel) (AMD and the DRM maintainers) | the driver source `NMXGPU` is a port of (display core included), and the reference flow the documents compare against |
| FreeBSD [drm-kmod](https://github.com/freebsd/drm-kmod) and LinuxKPI ([freebsd-src](https://github.com/freebsd/freebsd-src)) | the copy of amdgpu that is built, and the compatibility layer the port's "xkpi" layer comes from |
| [Mesa](https://gitlab.freedesktop.org/mesa/mesa) / RADV, with libdrm and glslang | the Vulkan driver under the Metal plugin and the VCN video decode (built with `scripts/radv`) |
| [FFmpeg](https://ffmpeg.org/) (libavcodec, LGPL build) and the Khronos Vulkan headers | `VCNDec`: Vulkan video decode of H.264, HEVC, VP9 and AV1 (`tools/890m/vcndec/ff-build.sh`) |
| [ryzen-hypervisor.framework](https://github.com/OverlordDev/ryzen-hypervisor.framework) (OverlordDev) | `RyzenHV`, the SVM hypervisor Docker and the Android emulator run on; the machine runs a [fork](https://github.com/thanhnndev/ryzen-hypervisor.framework) |

**Wi-Fi, Bluetooth and ASUS controls (through the sibling repositories)**

| Project | Used for |
|---|---|
| The Linux kernel's `mt76` / `mt7925` and `btmtk` drivers, and MediaTek's MT7925 firmware | hardware layer, reference and firmware of [mt7925-macos](https://github.com/thanhnndev/mt7925-macos) |
| [asusctl](https://gitlab.com/asus-linux/asusctl) / [asus-linux.org](https://asus-linux.org/) and the Linux `asus-wmi` / `asus-armoury` drivers | reference for the ASUS WMI and EC interface in [rog-control-macos](https://github.com/thanhnndev/rog-control-macos) |
| G-Helper, itlwm, k10temp | further design references, listed in the `NOTICE.md` of the two sibling repositories |

**Authoring**

| | |
|---|---|
| [Claude](https://www.anthropic.com/claude) (Anthropic) | wrote almost all of the code and documents of this project, directed and tested by the maintainer |
