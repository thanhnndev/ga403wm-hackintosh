# WindowServer / NullMoth research and targeted fix — 2026-10-12

## Finding: the boot PAT table disagrees with XNU's WC mapping

The booted ESP enables the Sequoia Algrey/Zormeister AMD PAT patch. Its replacement instructions
load EAX=0x00070106 and EDX=0x00070106, then write MSR 0x277. The implied table is
0x0007010600070106. This is evidence from the configured boot patch, **not yet a live MSR read**.

| PAT index | Existing type | Target type |
| --- | --- | --- |
| 0 | WB (6) | WB (6) |
| 1 | WC (1) | WC (1) |
| 2 | UC- (7) | UC- (7) |
| 3 | UC (0) | UC (0) |
| 4 | WB (6) | WB (6) |
| 5 | WC (1) | WC (1) |
| **6** | **UC- (7)** | **WC (1)** |
| 7 | UC (0) | UC (0) |

Source chain checked against the installed Darwin 24 kernel and corresponding XNU sources:

1. NullMoth's os_map_kernel_space(mode=NV_MEMORY_WRITECOMBINED) already requests
   kIOMapWriteCombineCache from IOMemoryDescriptor::map. Changing this request again cannot fix a wrong PAT slot.
2. XNU IOMapPages maps that option to VM_WIMG_WCOMB. The x86 memory type flags encode it as
   VM_MEM_NOT_CACHEABLE without VM_MEM_GUARDED.
3. pmap sets PCD (bit 4) and PAT (bit 7), with PWT (bit 3) clear: PAT index 6.
   Intel/AMD PAT index = PAT*4 + PCD*2 + PWT.
4. The configured AMD replacement sets entry 6 to 7 (UC-) while XNU mtrr_update_action explicitly
   intends entry 6 to 1 (WC). The masked patch matches two locations in the installed kernel;
   Count=0 deliberately applies to both. No unmasked exact-byte assumption was used.

This provides a concrete configuration-level explanation for poor effective BAR1 write throughput.
It does not by itself prove the actual loaded PAT, every BAR1 page-table entry, effective MTRR combination,
or the size of the WindowServer CPU improvement. Those need the next boot's diagnostics and measurement.

## Implemented

* tools/pat_wc.py changes exactly the PA6 immediate byte in the enabled Sequoia Algrey patch:
  89c0b806010700ba060107000f309090 → 89c0b806010700ba060101000f309090.
  New table: 0x0001010600070106. All other patch fields and config values remain unchanged.
* It refuses unknown/all-WB/ambiguous patches, can verify the masked kernel match, creates a unique backup,
  validates the plist before replacement and refuses to overwrite a concurrently changed config.
  --undo restores only the original replacement bytes, preserving later unrelated config edits.
* AmdCppc 0.2.1 adds read-only debug.amdcppc.cache: PAT, PA6 and MTRR default on every CPU,
  using rdmsr_carefully. It does not write PAT/MTRRs at runtime.
* scripts/macos-ws-pat-check.sh checks the actual expected table on all 24 CPUs before running the existing
  clear A/B and one 10-second WindowServer interval. It restores the original clear_mode.
* No NullMoth binary, synchronization, resource lifetime or zero-initialization path is modified.

Four tests cover the exact changed slot, apply/undo preservation, refusing ambiguous/all-WB variants and masked
kernel matching. Kext builds without warnings; plist and OpenCore schema/ocvalidate checks pass.

An attempted read-only PatAudit kext was not approved to load by macOS; it did not load. An attempt to hot-update
AmdCppc was refused because the service is retained; the existing 0.2.0 remained loaded and the policy daemon
was restarted successfully. Neither attempt changed the live PAT. The new diagnostic is staged via the existing
OpenCore AmdCppc entry instead. A reboot is necessary; no reboot is initiated automatically.

## Other solution paths reviewed

| Path | Assessment / required work |
| --- | --- |
| Correct PAT PA6 | Selected: concrete XNU/config mismatch, one entry correction, reversible; benchmark after reboot. |
| Change BAR1 map request | Current NullMoth already requests WC. Audit effective mapping/MTRRs if PA6 correction does not improve speed. Do not map GPU registers as WB. |
| Clear on GPU copy engine | Good fallback if CPU aperture remains slow. Requires an initialized CE context, destination-handle import, completion before exposing memory, timeout handling and allocation lifetime tracking. Existing kernel CE path currently pages VRAM out to system RAM; it is not a ready drop-in zero-fill API. NVRM cannot be rebuilt from the local package's missing vendor RM objects; a separate module would need to use the existing ABI safely. |
| Pool / reuse VRAM grants | Could reduce mapping and allocation churn. Cannot skip clearing across clients: stale pixels become data exposure. Need generation/cookie checks, bounded memory retention, reset/sleep handling and zeroing before handing an allocation to a new client. |
| Release display gate during clear | Could reduce cursor/flip stalls but would not eliminate CPU work. Must retain the framebuffer/device and allocation while unlocked and handle concurrent reset/stop, epoch changes and failures. A simple unlock around memset is insufficient. |
| Faster staging memcpy (PR #139) | Previously measured ~18% less CPU for isolated 2880x1800 uploads; no desktop CPU reduction established. Prior investigation rejected it as the main fix. Do not reinstall its 1.14.0 bundle on 1.14.2. |
| Deferred uploads / fewer fence waits | Prior upload deferral required an upstream lifetime fix. Need GPU lifetime ownership and scanout ordering, rather than removing waits. Preserve synchronization until a correct queue/fence design is demonstrated. |
| More IOSurface sharing | Current plugin already skips synchronized seed/generation and can import shared VRAM. Need per-surface counters to identify remaining copies; globally skipping uploads can show stale pixels. |
| Reduce visible repainting | Earlier hiding ChatGPT reduced load, but measurements during an active turn do not establish a persistent app defect. Current failed Kitty-hide test was discarded. Isolate a quiet workload before blaming one app. |
| Shaneee all-WB PAT variant | Not selected. It changes all eight entries, including device memory semantics; AMD Vanilla documents NVIDIA boot problems. The PA6 fix retains UC and UC- slots. |

## Baseline and post-reboot verification

Before the PAT correction, the loaded non-temporal clear ran at 109–113 MB/s versus 78–82 MB/s for rep stosq.
A 12.09-second desktop interval showed WindowServer at 24.57% of one logical CPU, 26.47 flips/s,
363 VRAM grants / 55.7 MB cleared, and 567 ms in clear (4.69% of wall time). These are driver-wide counters.
The WindowServer sample contains IOSurface uploads and submission waits but no established continuous busy loop.

After reboot, run the post-reboot script through osascript administrator privileges. Expected:
AmdCppc 0.2.1 loaded, PA6=1 on all 24 CPUs, then compare clear MB/s against the baseline. Record desktop CPU under
the same visible workload; a faster clear is not automatically proof that all compositor CPU is fixed.

Undo the PAT change with tools/pat_wc.py --config /Volumes/ESP/EFI/OC/config.plist --undo through administrator
privileges, then reboot. Full config backups are next to config.plist but restoring the entire backup can overwrite
later changes; the targeted undo is preferable. AmdCppc's diagnostic addition can remain or be reverted with the
existing kext installer --undo. CPPC policy itself is unchanged.

## Primary references

* [AMD Vanilla PAT patches](https://github.com/AMD-OSX/AMD_Vanilla/blob/master/patches.plist)
* [AMD Vanilla explanation of PAT alternatives](https://github.com/AMD-OSX/AMD_Vanilla#information-on-the-fix-pat-patch)
* [XNU PAT initialization](https://github.com/apple-oss-distributions/xnu/blob/xnu-11417.140.69/osfmk/i386/mtrr.c)
* [XNU IOMapPages](https://github.com/apple-oss-distributions/xnu/blob/xnu-11417.140.69/osfmk/device/iokit_rpc.c)
* [XNU pmap cache-bit selection](https://github.com/apple-oss-distributions/xnu/blob/xnu-11417.140.69/osfmk/i386/pmap_x86_common.c)
* [Apple IOMemoryDescriptor::map](https://developer.apple.com/documentation/kernel/iomemorydescriptor/1812830-map)
* [AMD system programming manual](https://docs.amd.com/api/khub/documents/sD1_QL~h4Afq2_tvzxqqSQ/content)
* [NullMoth 1.14.2 OS mapping](https://github.com/nullmoth/nvidia-macos-driver/blob/v1.14.2/kexts/NVRM/os-xnu.cpp)
* [Upstream VRAM-clear PR #64](https://github.com/nullmoth/nvidia-macos-driver/pull/64)
* [Deferred-upload PR #96](https://github.com/nullmoth/nvidia-macos-driver/pull/96)
* [Lifetime fix 77e4c98](https://github.com/nullmoth/nvidia-macos-driver/commit/77e4c9839f5925a7087357d552790a7edcc978fa)

## Post-reboot result (2026-10-12 17:43)

AmdCppc 0.2.1 is loaded. Live debug.amdcppc.cache reads PAT=0001010600070106,
PA6=1, valid=1 on all 24 CPUs; MTRRdef=c00. CPPC is enabled and EPP128 is applied.

One post-reboot validation round:

| Clear mode | Before PAT correction | After PAT correction |
| --- | ---: | ---: |
| rep stosq (0) | 78–82 MB/s | 1008–1048 MB/s |
| movnti (1) | 109–113 MB/s | 1043–1094 MB/s |

The selected movnti path is about 9–10 times faster. An 8 MiB clear at this throughput
is approximately 7.7–8.0 ms rather than 74–77 ms. Driver-wide counters include background
allocations, so the A/B is not a pristine isolated microbenchmark. The cumulative slowest
clear since boot is 42,856 us; this is not the worst clear within this A/B alone.

WindowServer: 33.4% of one logical CPU, 34.5 flips/s over 10.55 seconds; 364 head-0
updates, zero new flip failures and async drops. This active desktop differs from the
previous 24.57% / 26.47 flips/s workload; a reduction in total desktop CPU is not established.
The PAT correction demonstrably fixes the poor clear throughput, but does not eliminate
IOSurface upload/composition costs or visible application repainting. clear_mode restored to 1.

Artifacts: build/ws-pat-20261012-174256/{pat.txt,clear-ab.txt,windowserver.txt},
~/efi-audit/ws-cpu-20261012-174308-446775/measurement.json. No additional driver changes
were made in this validation round.
