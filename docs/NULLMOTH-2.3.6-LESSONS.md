# What NullMoth 2.3.1 -> 2.3.6 teaches the 890M port

Source studied: `nullmoth/nvidia-macos-driver` v2.3.6 (release tarball, sha256 3855954d..., read-only study; the code
is PolyForm-Noncommercial, so nothing is copied here - these are ideas, written in our own words). Diff of the package
against 2.3.1: NVAccel, NVRM, NVRMFB, NVMTLDriver, libnvmtl_translate changed; `libvulkan_radeon`, `libdrm*` and the ICD
files are byte-identical, so upstream never touched the RADV userland (our mmap and libdrm patches stay ours). The
AMD/Intel kernel driver (NMXGPU/NMXAccel) left this repository after 2.0.4 and now ships separately, so there is no newer
NMX source to merge.

## Directly useful for the 890M

| Upstream change | Why it matters here |
| --- | --- |
| 2.3.2: a test driver whose start fails no longer panics; memory still mapped when the start gave up is kept until it is unmapped | Our teardown frees BOs and user maps in one go; any user mapping of freed pages is a panic waiting for a crash. Audit nmx_xnu_map_user / unmap on close. |
| 2.3.4: "a GPU that is busy is not a GPU that is gone" - the Metal driver waits for a late frame instead of disabling itself | Our first graphics job (headroom-hold, 2026-10-18 15:35) tripped `amdgpu_job_timedout` and the reset path panicked. A slow first job must be survivable; recovery must never run with interrupts off. |
| 2.3.4: a reset inside the driver's own start-up wait does not count toward the boot guard; 2.3.1: two failed starts switch the driver off and restore the previous one | We need the same boot guard for NMXGPU (counter + automatic fall back to headless/no-kext after two starts that never reach the desktop). |
| 2.3.4/2.3.5: present waits are bounded to one refresh period and wake on the display's event; a fixed 60 s wait before frames reached the panel left a black login for exactly a minute | Our display-sleep hang (WindowServer timeout 30 s, then silence) looks like an unbounded wait. Every wait in the SetState / present path needs a bound and a log line. |
| 2.3.6: a surface whose VRAM was set aside is put back before its update is recorded, so each frame no longer copies the whole window to system memory | This is the WindowServer CPU melt in another guise (readback per frame). Our accelerator must never read a window back; compositing must stay in VRAM. |
| 2.3.6: cursor position applied on its own thread, not under the cursor lock | Cursor updates must not sit in the compositor's critical path. |
| 2.3.5/2.3.4: per-display line every 10 s with flip rate vs panel rate, missed refreshes, skipped frames; first N refusals logged then every 256th | The trace format to copy for our own accelerator bring-up. |
| 2.3.4: WhateverGreen's boot-screen copy reads a console mapping macOS may have freed and panics in IOFramebuffer::postOpen; boot-arg `gfxrst=4` | This machine's boot-args have no `gfxrst=4`; check whether WhateverGreen is loaded before the first non-headless framebuffer open. |
| 2.3.0: flip/submission waits wake on the event, not a 1 ms poll | Same for our fences: no polling loops at interrupt level. |

## Bug class we hit and upstream could not have
LinuxKPI spin_lock -> sched_pin -> interrupts off (Step33c, Step35): two panics (IF leak, TLB shootdown timeout).
See docs/890M-TRACE.md Step35.
