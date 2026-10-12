# asusctl / ROG Control Center on macOS

[asusctl](https://github.com/opengamingcollective/asusctl) (formerly <https://gitlab.com/asus-linux/asusctl>, by Luke Jones
and the asus-linux contributors, **MPL-2.0**) is the Linux daemon (`asusd`), CLI (`asusctl`) and GUI (`rog-control-center`)
for ASUS ROG laptops. It does not talk to the hardware itself: it drives the Linux kernel drivers `asus-wmi` and
`asus-armoury` through sysfs, the keyboard LEDs through USB HID, and GPU switching through `supergfxctl`. A port to macOS
therefore has two halves: a kext that does what the Linux kernel drivers do, and a user-space tool/app that does what asusd
and rog-control-center do. Credits and license notes: [NOTICE.md](../NOTICE.md).

## Why it matters here

macOS has no driver for ASUS's ACPI WMI device (`ATKD`, `_UID "ATK"`, GUID `97845ED0-4E6D-11DE-8A39-0800200C9A66`). The
embedded controller keeps the profile and power limits it booted with, and nothing on macOS can change them. On this
laptop (2026-10-11, `sysctl debug.amdcppc.freq`) the four Zen 5 cores stay at exactly 2000 MHz in every mode (CPPC off or
on, AC or battery) and the Zen 5c cores at 1.4-3.3 GHz; boost is enabled in the CPU (`CpbDis=0`) and CPPC requests the
highest performance, so the limit sits in the platform. The profile and the PPT limits are the obvious suspects.

## Feature map

| asusctl feature | Linux path | macOS route | Status |
|---|---|---|---|
| Platform profile (Silent / Performance / Turbo) | `asus-wmi` throttle_thermal_policy, WMI dev `0x00120075` (0 balanced = Armoury Crate "Performance", 1 turbo, 2 silent) | AsusWmi user client, RogControl | built, untested |
| CPU power limits SPL / SPPT / FPPT ("Manual") | `asus-armoury` ppt_*; GA403WM: AC 15-80 / 25-80 / 35-80 W, battery 15-35 / 25-35 / 35-65 W; `requires_fan_curve` | AsusWmi checks the range for the current source (ACPI `ACAD._PSR`) and refuses limits until a custom fan curve is active (EBUSY / `kIOReturnNotPermitted`), as asus-armoury does | built, untested |
| Fan curves | dev `0x00110024` (CPU) / `0x00110025` (GPU); DSTS with arg1 = profile returns 8 temps + 8 duties; DEVS packs them into 4 dwords | read and write in AsusWmi (temps rising, duties not falling, top point >= 40 %); RogControl "Manual" uses a chosen firmware curve (Silent / Performance / Turbo) as the custom curve; no curve editor yet | built, untested |
| Fan speeds | dev `0x00110013` / `0x00110014`, value x 100 rpm | RogControl | built, untested |
| Battery charge limit | dev `0x00120057` | RogControl 60 / 80 / 100 %, re-applied at start | built, untested |
| Profile per power source | asusd | RogControl keeps one setting set for AC and one for battery and re-applies on IOPowerSources changes and at login | built, untested |
| NVIDIA dynamic boost / temp target / TGP | dev `0x001200C0` / `0x001200C2` / `0x00120099` | base TGP shown (55 W); no writes: they notify the NVIDIA ACPI device and the NullMoth driver decides the GPU clocks | read only |
| GPU MUX, dGPU disable | dev `0x00090016` / `0x00090020` | shown; **do not write** from macOS: the NVIDIA driver is running | read only |
| Keyboard LEDs (Aura) | USB HID, N-KEY device `0b05:19b6`; GA403 boards: one zone, Static/Breathe/Pulse/Rainbow | user space HID feature reports, no kext needed | todo |
| Panel overdrive | dev `0x00050019` | WMI | todo (absent in this BIOS's DSTS list) |
| GUI (rog-control-center) | Slint app over D-Bus | `macos/RogControl` menu bar app, user client (no sudo; admin or console user) | built, untested |

## RogControl

`scripts/build-rogcontrol.sh --install` copies it to /Applications and starts it at login. The popover shows CPU Tctl,
package power (RAPL, `debug.amdcppc.sensors`), both fan speeds, the mode buttons (Turbo is disabled on battery, as in
Armoury Crate), the Manual limits and fan curve choice, the charge limit, and the GPU MUX state. The first start adopts the
firmware's current profile and charge limit instead of imposing defaults.

Measuring the profiles of this machine (no sudo, through the user client):

```
/Applications/RogControl.app/Contents/MacOS/RogControl --bench 20
```

Runs Silent, Performance and Turbo (AC only) for 20 s each with every CPU busy and prints average and peak package power,
peak Tctl, fan speeds and the Zen 5 / Zen 5c clocks, then puts the previous profile back.

## AsusWmi (phase 1)

`kexts/AsusWmi` matches `IOACPIPlatformDevice` `PNP0C14` with `_UID "ATK"` and calls `ATKD.WMNB(0, method, {arg0, arg1, 0})`
like `wmi_evaluate_method()` does for asus-wmi (`DSTS` 0x53545344 reads a device, `DEVS` 0x53564544 sets it; bit 16 of a
DSTS result means "present"; `_UID "ATK"` means DSTS rather than DCTS). At start it calls `INIT`, `SPEC` and `SFUN` as Linux
does and records them in the registry property `asus-log`.

```
sysctl debug.asuswmi.status                 # profile, ppt_*, charge_limit, gpu_mux ... as value(raw DSTS)
sudo sysctl debug.asuswmi.profile=1         # 0 balanced, 1 turbo, 2 silent
sudo sysctl debug.asuswmi.ppt_spl=65 debug.asuswmi.ppt_sppt=80 debug.asuswmi.ppt_fppt=80
sudo sysctl debug.asuswmi.charge_limit=80
sudo sysctl debug.asuswmi.probe=0x00120075; sysctl debug.asuswmi.probe   # raw DSTS of any device id
sudo sysctl debug.asuswmi.dumpacpi=1        # DSDT + SSDTs as registry properties acpi-DSDT, acpi-SSDT-<n>
```

The settings live in the EC; like on Linux they may be reset by the firmware at boot or on AC/battery changes, which is
what asusd's profile-on-power-change logic is for.

## What this BIOS does (DSDT from OpenCore SysReport, 2026-10-11)

Decompiled from `/Volumes/ESP/SysReport/ACPI/DSDT.aml` with `iasl` (ACPICA source build; no Homebrew needed):

* `ATKD.WMNB` begins with `CreateDWordField (Arg2, 0x10, IIA4)`: the argument buffer must be **20 bytes** (five dwords, as
  Linux's `struct bios_args`). AsusWmi first sent 12 bytes, the method aborted before reading the method id, and every
  call failed (`status` all `-`, `profile=1 -> failed`). Fixed; failures now log the IOReturn.
* PPT writes (`DEVS`) go to AMD's `ALIB` function 0x0C with `UTDP`: `0x001200A3` SPL -> ALIB id 5, `0x001200A0` SPPT ->
  id 7, `0x001200C1` FPPT -> id 6, value in mW (`IIA1 * 1000`). The `DSTS` read of those ids is a constant `0x00010000`
  (present, value 0): the BIOS does not report the current limit, so `status` shows 0 for them.
  `0x001200B0` / `0x001200B1` (APU / platform SPPT) are unsupported here.
* `0x00120099` (NVIDIA base TGP) reads a constant 55 W; `0x001200C0` dynamic boost and `0x001200C2` temp target write ACPI
  fields of `NPCF` / `PEGP` and notify the NVIDIA driver.
* The profile (`0x00120075`), the charge limit (`0x00120057`) and anything else not listed go through `WCHK` + `W15H`: a
  software SMI (port 0xB2, `WSCP = 0xAA`) into the BIOS SMM handler with the five args in the `AII0..4` fields.
* `0x00090016` (GPU MUX) reads `DGPM`; `0x00090020` (dGPU disable) touches the EC and power-cycles the dGPU on write.

## Reading the ACPI tables

macOS does not publish them in the registry. `debug.asuswmi.dumpacpi=1` copies them into the kext's registry entry; save
them with `ioreg -a -rc AsusWmi -d 1` and decompile with `iasl` (MaciASL ships one). Needed for the fan-curve buffer format,
for checking what `WMNB` does with each device id on this BIOS, and for the EC fields if the profile alone does not lift the
2000 MHz cap.

## Findings 2026-10-11 evening (after the INIT/SFUN fix)

* **Profiles work.** `RogControl --bench 15` on AC: Silent Tctl max 88 °C, fans 2300/2500 rpm; Performance 92 °C, 2800/3000;
  Turbo 95.8 °C, 4400/4600. Zen 5 cores now boost to ~4.8 GHz (were stuck at 2000 MHz before). DEVS on 0x00120075 is
  accepted, but **DSTS always returns 3** on this BIOS, and DSTS on the charge limit (0x00120057) returns 0: AsusWmi now
  reports the values last set since boot (ABI 2), as Linux asus-wmi keeps its own copy.
* **Package power read 0**: `debug.amdcppc.sensors` now carries the raw RAPL unit / counter (`rapl=...`) to see whether the
  MSRs fault or the counter does not move.
* **Battery**: SMCBatteryManager showed design = full = remaining = 5, which are the initial values of BAT1's PBIF/PBST
  packages: `_BIF` / `_BST` only read the EC while EC0.ECOK is set (EC0._REG with space 3). `sysctl debug.asuswmi.battery`
  prints ECOK and the raw packages; `sudo sysctl debug.asuswmi.ec_reg=1` runs `EC0._REG(3, 1)` if ECOK is 0.
* **Panel brightness**: nothing on macOS drives this OLED's backlight (NullMoth has no backlight code, macOS sees the panel
  as a non-built-in display without brightness). The DSDT has the NVIDIA WMI-EC backlight method (`\_SB.PCI0.AWMI.WMAA`,
  GUID 603E9613-EF25-4338-A3D0-C46177516DB7, as Linux nvidia-wmi-ec-backlight): method 1 mode 0/1/2 = get / set / max
  (0xC8) on EC fields GBLD / SBLD. AsusWmi uses it (`debug.asuswmi.backlight`, RogControl slider) and steps it on the
  brightness keys (BRTN sends Notify 0x86 / 0x87 to VGA.LCD and PEGP.EDP1; AsusWmi listens on EDP1). The BIOS reports
  brightness source 3 (AUX), so whether the EC level reaches the OLED is the open question.

## Findings 2026-10-11 night (NullMoth 1.14, keyboard light, Slash)

* **Panel brightness**: the EC level answers the open question above: it reads 0 / 200 while the panel is lit, so it is not
  the OLED's brightness (source 3 = AUX: the GPU driver owns it). NullMoth 1.14 has panel backlight support: NVRM answers
  the NBCI `_DSM` (functions 0, 0x10) and `_DOD` on PEGP, NVKMS registers the backlight (`backlight registered: gpu 0x6200
  display 0x200 at 100%`), NVRMFB publishes a `backlight` handler, and IOGraphics makes the panel an AppleBacklightDisplay
  with `brightness` / `linear-brightness`. `DisplayServicesSetBrightness` works (no "setting failed" from NVRMFB). Whether
  the OLED follows it is to be checked by eye. AsusWmi no longer steps the EC level on the brightness keys.
* **Brightness keys**: Fn+F7 / F8 = EC queries `_Q18` / `_Q17` -> `QLIB (0x26 / 0x27)` -> `BRTN (0x87 / 0x86)` when
  `OSYS >= 0x07DC` (OSYS defaults to 0x07DF) -> Notify on VGA.LCD and PEGP.EDP1. BrightnessKeys (loaded) listens on EDP1
  and turns them into macOS brightness keys. WMNB `DEVS 0x00100021, code` calls `EC0.SKEY (code)`, the same dispatcher:
  `sudo sysctl debug.asuswmi.key=0x20` (up) / `0x10` (down) emulates the keys for testing.
* **Hotkeys through ATKD**: `IANE (code)` queues a code and sends Notify (ATKD, 0xFF); `_WED (0xFF)` -> `GANQ` returns the
  queued codes (Ones when empty). Seen in the DSDT: 0xC4 / 0xC5 keyboard light up / down (only when `KBLC & 0x80`), 0xB3
  (Fn+F4), 0xAE (Fn+F5), 0x6B, 0x40 / 0x43 / 0x45 / 0x0A, 0x1A. AsusWmi handles 0xC4 / 0xC5 / 0xAE / 0xB3 and logs every
  code in `asus-log` ("key xx").
* **Keyboard light and Slash**: no WMI device for either (0x00050021 is not in the DSDT). Both are HID feature reports on
  the N-KEY keyboard, USB 0b05:19b6 ("ITE Device(8910)", one interface, AppleUserHIDDevice): report 0x5A (62 bytes) =
  keyboard light `5A BA C5 C4 <0..3>` after `5A "ASUS Tech.Inc."` (G-Helper Aura.DirectBrightness, Linux hid-asus);
  report 0x5D (127 bytes) = Slash (G-Helper `SlashDeviceAura`: wake up `"ASUS Tech.Inc."`, `C2`, `D1 01 00 01`; enable
  `D8 02 00 01 00|80`; init `D7 00 00 01 AC`, `D2 02 01 08 AB`; mode `D3 04 00 0C 01 <code> 02 42 03 13 04 11 05 12 06 13`;
  options `D3 03 01 08 AB FF 01 01 06 <bright*85> FF <interval>`; save `D4 00 00 01 AB`). User space cannot open the
  keyboard without Input Monitoring (IOHIDDeviceOpen 0xe00002e2), so AsusWmi sends them from the kernel
  (`IOHIDDevice::setReport`): `debug.asuswmi.kbd`, `debug.asuswmi.slash`, ABI 3 (`ASUS_SET_KBD`, `ASUS_SET_SLASH`).
  RogControl stores both and sends them at start and after wake.
* Build: `IOHIDDescriptorParser.h` includes `<MacTypes.h>` when `__has_include` finds one, which pulled the host SDK's
  user-space header in; `scripts/build.sh` now compiles with `-nostdlibinc`.
* **OLED brightness**: the brightness slider appears with NullMoth 1.14 (NVKMS registers the backlight from NBCI `_DSM`
  function 0x14, AppleBacklightDisplay gets brightness / linear-brightness) and `nvKmsSetBacklight` returns success, but the
  panel does not change: the BIOS reports an AUX (DPCD) backlight (WMAA source 3) and the EC level (GBLD 0..200) is not the
  OLED's. NullMoth's framebuffer has no gamma table either (`setGammaTable` / `setCLUTWithEntries` are stubs in
  nvrm-fb.cpp), so CoreGraphics transfer tables cannot dim it. RogControl dims the built-in display in software: it reads
  `DisplayServicesGetBrightness` every 0.1 s and puts a black, click-through window (level assistiveTechHigh, all spaces,
  excluded from screenshots) over that screen with alpha `1 - (0.15 + 0.85 * brightness)`. The slider and Fn+F7 / Fn+F8
  (`debug.asuswmi.key=0x20` / `0x10` moved the value) drive it; "Dim the built-in OLED in software" turns it off.
  NBCI on this BIOS: function 0 bitmap 0x00110001 (0, 0x10, 0x14); 0x14 = display 0x8000A450, 0x200, 0, 0, 5, 1, 1000,
  50, 1000, 11 levels 50..1000, 0, 11 levels 100..1000.

## Findings 2026-10-12 (OLED brightness root cause)

* The OLED is an **AUX-only** panel: eDP DPCD `0x702 = 0x86` has no PWM-pin capability and has AUX brightness set, so the
  only control is DPCD `0x722/0x723` in mode `0x721 = 2`. RM's `SET_BACKLIGHT_BRIGHTNESS` (GSP firmware) returns success
  and leaves `0x721 = 0`. That is why `nvKmsSetBacklight` "worked" and the panel did not change, and it is not an EC or
  ACPI matter. Writing the registers by hand dims the panel (confirmed by eye).
* RogControl's `Dimmer` (software overlay, above) is therefore a **workaround** and stacks on top of the real brightness
  once `NVRMEdpBL` loads: turn "Dim the built-in OLED in software" off then. Details, evidence, fix, install and undo:
  [OLED-BRIGHTNESS-DPCD.md](OLED-BRIGHTNESS-DPCD.md). `AsusWmi` keeps leaving the EC level alone on the brightness keys.
