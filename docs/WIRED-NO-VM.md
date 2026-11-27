# Wired memory without a VM: where the 6.2 GB goes (2026-11-27, boot 20:00, out-54)

Read without root: `zprint` (its wired-by-tag table at the end), the `debug.nmx_*` sysctls and `vm_stat`. Taken at 20:3x with the Docker
stack up.

- `vm_stat` wired: 10.06 GB. RyzenHV (the Docker guest, lazy-wired) is 3.83 GB of that, so **6.2 GB is not the VM**. That matches the
  6.17 GB measured at 17:10 with no VM running.
- zprint: VM_KERN_COUNT_WIRED 11.6 GB. It counts a little more than vm_stat.

| tag (zprint) | GB | what it is |
|---|---|---|
| com.overlorddev.RyzenHV | 3.83 | Docker guest RAM, wired on touch (0 with no VM) |
| VM_KERN_COUNT_WIRED_BOOT | 2.56 | wired before boot finished: kernel, kexts, early allocations |
| com.nullmoth.NMXGPU | 1.80 | GPU driver memory: `nmx_pages_live` 305k pages (1.17 GB of BOs) + TTM pool 32k pages (0.13 GB, at its cap of 32768) + the rest |
| com.apple.iokit.IOSurface | 1.40 | user surfaces wired for the GPU: `nmx_userwire_pages` 359k (1.37 GB) |
| VM_KERN_MEMORY_PTE + PMAP | 0.85 | page tables (many processes, plus the 2 GB HyperKit mapping) |
| apfs, SECURITY, LOPAGE, KEXT | 0.40 | |
| (VM_KERN_COUNT_RESERVED, 1.7 GB, is reserved, not counted in vm_stat wired) | | |

## IOSurface, by process (`debug.nmx_userwire_by_kind`)

| process | surface pages | GB | parked pages |
|---|---|---|---|
| WindowServer | 272,552 | **1.04** | 32,681 |
| Claude Helper | 41,456 | 0.16 | 6,360 |
| Zalo Helper (GPU) | 26,378 | 0.10 | 556 |
| Microsoft Edge Helper | 7,716 | 0.03 | 41,593 |
| Docker Desktop Helper | 4,610 | 0.02 | 2,700 |

- 253 surfaces hold 352,712 pages. 93 of them (91,660 pages, 0.35 GB) have been wired more than 60 s ("old60").
- 89,844 pages are parked.

## What can be won (owner: main, who owns NMXGPU)

1. **WindowServer's 1.04 GB of wired surfaces** is the largest controllable block. The panel is 2560×1600 at 4 B/px: one surface is
   16 MB, so 1 GB is about 65 full-screen surfaces.
   - The old60 set (0.35 GB) could be parked or unwired sooner. The existing park path already does this for 89k pages.
   - What to try: a shorter park age for surfaces not used for N seconds, measured with `nmx_userwire_parks` / `unparks` and video
     drops.
2. **NMXGPU BOs, 1.17 GB live.** A per-process census is in `debug.nmx_tt_census` (bos, resident, pinned, idle). The idle pages there
   are the candidates for eviction. Not taken in this pass.
3. Boot wired (2.56 GB) and page tables (0.85 GB) are not ours to shrink.

Under the Docker load, compression ran at 1.5-2k pages/s while the stack started (DOCKER-HEAT-PLAN.md). Items 1 and 2 both reduce
that pressure.
