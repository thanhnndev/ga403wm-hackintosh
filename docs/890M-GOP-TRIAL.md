# StrixGOP fixed boot framebuffer trial

Implemented Step03: `kexts/StrixGOP/`. It is an IOFramebuffer implementation
for the already-scanning boot raster, separate from Cobalt64 engine bring-up.
It supplies one mode, one32bpp XRGB pixel format and software cursor; only the
same mode/depth is accepted. It performs no hardware modeset or GPU engine init.
IOGraphics/WindowServer can write the selected raster: this is no longer a
read-only diagnostic. The superclass also participates in graphics/power lifecycle.

Default bundle personality has `AdoptBootGOP=false` and no memory profile.
It is excluded from normal builds. `tools/strix_gop_trial.py` builds the explicit
target, verifies an initial physical Step02 snapshot and creates a separate local
opt-in bundle under a timestamped ignored trace. It rejects live virtual HDMI
console snapshots, duplicate targets, identity/BAR mismatch, unsupported layouts
and rasters outside the contiguous BAR0 range. No Linux addresses are embedded
in the source. Runtime checks bind the profile to actual PCI1002:150e revc1,
subsystem1043:3998 and the captured macOS BAR0 base/size.

Only the rounded raster range is exposed, not the256MiB BAR or other UMA/firmware
regions. Aperture references are retained for each consuming call. IODeviceMemory
factories return general/sub descriptors in XNU, so the implementation deliberately
avoids an invalid IODeviceMemory runtime metaclass cast. The subdescriptor retains
its parent. XRGB channel layout is explicitly selected for this experiment and
still needs visible color validation; PE's `PPPPPPPP` placeholder is not evidence.
Refresh rate is unspecified; no invented EDID-based hardware timing is reported.
There is no acceleration, native backlight, hardware vblank, hotplug or sleep/wake
implementation in this trial.

Source contracts reviewed:

- [IOFramebuffer aperture ownership](https://developer.apple.com/documentation/kernel/ioframebuffer/1813036-getaperturerange).
- [IOFramebuffer controller initialization](https://developer.apple.com/documentation/kernel/ioframebuffer/1813011-enablecontroller).
- [IOGraphics source](https://github.com/apple-oss-distributions/IOGraphics/blob/76285384ff0ce63965a21b8023bf6d7e447fcc19/IOGraphicsFamily/IOFramebuffer.cpp):
  start registers the service; open calls enableController; aperture lengths are
  checked before mapping. Reference source, not asserted identical to loaded599.
- [XNU descriptor factories](https://github.com/apple-oss-distributions/xnu/blob/43a90889846e00bfb5cf1d255cdc0a701a1e05a4/iokit/Kernel/IODeviceMemory.cpp).
- MacKernelSDK `3f750085caa17ec3a7880f11c11bf4f48cd6a164` graphics headers.

## Local trial prepared2026-10-13

Source snapshot: `out/890m-trace/step02-20261013T090147.620403Z/ioreg.plist`.
Profile:2880x1800, stride11520, depth32, offset0 in BAR0;
raster20736000 bytes, page-rounded20738048 bytes.

Final0.1.1 trace: `out/890m-trace/step03-build-20261013T091914.471933Z/`.
Strict compilation/link PASS.370 imports resolve to declared KPI/IOPCI/IOGraphics
providers through kmutil libraries, with no missing defined symbols.13 geometry
boundary cases PASS with ASan/UBSan;6 profile tests PASS, including real boot
acceptance and live virtual rejection. Plist/header/kmod checks PASS.

Installed local trial: `/Library/StrixGOPTrial/StrixGOP.kext`.
Normal kmutil load returned27, approval required. Explicit administrative
`kmutil load --no-authorization` built an Auxiliary Kernel Collection and returned
28, reboot required. Final collection inspection confirms0.1.1 at that path.
Installed binary equals the profiled build. **No StrixGOP service currently exists;
no OLED success or runtime controller pass claimed.** The existing HDMI desktop
and active EFI config were not modified. The next normal Hybrid boot is the actual
framebuffer trial, not another diagnostic-only reboot.

## After reboot

Run `bash scripts/macos-strix-gop-collect.sh`. It preserves missing-service
attempts too, plus IOFramebuffer/probe census, loaded module state and narrow
kernel logs. Require StrixGOPVersion0.1.1, Controller,Enabled=true and two
independent framebuffer services. A person must confirm OLED desktop updates,
correct colors, cursor motion and unchanged HDMI operation. Software rendering
may be slow; do not label this Metal/compute acceleration.

If loaded but unmatched, investigate live properties/resources and use a targeted
personality rematch in this session if appropriate; do not immediately ask for
another reboot. `kmutil load` supports `--load-style match-only` and a selected
personality for an already loaded kext. Changes to executable code still need
a separate load/reboot gate; this is not a hot-patching mechanism.

## Disable and recovery

Boot argument `-strixgopoff` makes probe return before attachment. A local
OpenCore off-config, validated by ocvalidate1.0.9, is saved on ESP as
`EFI/OC/config.plist.strixgop-off-20261013`. It differs from the active config
only by that boot argument. Restore it as config.plist from Recovery/Linux if
needed; do not re-run1401 Build. When macOS is usable, agent performs root changes
through the administrator-wrapper workflow and backs up the current config first.
The trial was added to AuxKC, not production Kernel/Add, so merely removing an
EFI entry will not disable it. Keep the off-config and package until the trial is
validated or removed deliberately.
