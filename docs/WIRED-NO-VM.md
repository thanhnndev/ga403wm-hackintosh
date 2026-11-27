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

## Lever 2: idle NMXGPU BOs (census every 10 s for 10 min, 20:41-20:51, daily load: video, Claude, Docker)

Read only: `debug.nmx_tt_census`, sampled 60 times, plus the park counters; data in `~/ga403-logs/nmx-census-20261127-2041/`.

Census classes (from `tt_census_bo` in nmx_fb_bridge.c):
- **idle**: resident, unpinned, not a user-memory import, every fence signalled. These are exactly TTM swap-out's candidates.
- **uptr**: IOSurface and other user-memory imports. These are what Step142 parks, after `nmx_userptr_park_ms` = 60000.
- **pinned**: pinned by a user CPU mapping or scanout, so not evictable.

The census has no age field. "Stays idle" is read as the 10th percentile over the 60 samples, and the spread up to p90 is churn.
Values per process in MB:

| process | idle p10 | idle p50 | idle p90 | uptr p10 | uptr p50 | uptr p90 | pinned avg |
|---|---|---|---|---|---|---|---|
| WindowServer | 95 | 140 | 167 | 440 | 754 | 1293 | 38 |
| Zalo Helper (GPU) | **115** | 115 | 140 | 50 | 73 | 147 | 18 |
| Cloudflare WARP | 24 | 33 | 101 | 0 | 8 | 17 | 5 |
| iconservicesagent | 12 | 12 | 12 | 0 | 0 | 0 | 13 |
| Microsoft Edge Helper | 10 | 22 | 314 | 28 | 88 | 211 | 98 |
| Claude Helper | 9 | 27 | 261 | 0 | 137 | 212 | 44 |
| Docker Desktop Helper | 8 | 8 | 62 | 18 | 18 | 19 | 33 |
| NotificationCenter | 6 | 6 | 6 | 0 | 0 | 0 | 5 |
| **sum of p10** | **280** | | | **536** | | | |

Over the window, from the counters:
- Park counters: parks 10637 → 13115 (+2478), unparks 705 → 873 (+168). That is 7 % of the parks coming back, so the 60 s rule mostly
  guesses right.
- userwire pages 199.7k → 433.6k, and `nmx_pages_live` 308.5k → 249.6k.
- VRAM carve-out: 451 of 512 MB used.

What could go, and how:
1. **Stable idle BOs, ~280 MB.** Zalo 115, WindowServer 95, WARP 24, iconservicesagent 12, Edge/Claude/Docker/NotificationCenter ~33.
   - Every fence on them has signalled, so moving them out is safe in the TTM sense. The next use faults them back with a copy.
   - **There is no path for it today:** xkpi has no `ttm_bo_swapout`/`ttm_device_swapout` caller, only the TTM pool trim and shrink.
   - It needs a swap-out of idle BOs to pageable memory after N seconds idle. That is the same age-and-sweep shape as Step142, but for
     non-userptr BOs. Code for main/F.
   - Zalo is the clearest case: it sits in the background holding 115 MB that never changes.
2. **userptr above the park age.** The p10 is 536 MB, nearly all WindowServer, and Step142 already parks it after 60 s.
   - A shorter age (20-30 s) would add roughly 100-300 MB, at the cost of more unparks (7 % today) and a video-drop check.
   - `nmx_userptr_park_ms` is a sysctl; changing it is main's call. I wrote nothing.
3. **Not evictable:** pinned (~300 MB in all), busy BOs, and the VRAM carve-out (not system RAM). Edge's and Claude's idle
   p10 → p90 swings (10 → 314 MB, 9 → 261 MB) are churn and should be left alone.
