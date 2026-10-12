# WindowServer IOSurface readback: where it comes from and what can be avoided (2026-10-12)

Machine: GA403WM, macOS 15.8.1, NullMoth **1.14.2**, PAT PA6 = WC (see `WINDOWSERVER-RESEARCH.md`).
Source studied: `nullmoth/nvidia-macos-driver` tag `v1.14.2` (`1083a98`). **Upstream `main` has no commit after it** (fetched 2026-10-12,
196 commits, head = the tag), so there is no newer upstream change to take into account. Line numbers below are for that commit.

This page was written in a cloud session **without access to the Mac**. Everything labelled *proved* is read from source or run on the
host (`test/readback/`). Nothing here was measured on the machine; the numbers to collect are listed in "Runbook".

## 1. Answer in one screen

| | Status |
|---|---|
| `nvmtlSurfaceOut` skips the copy only when the texture is an alias of the family VRAM **and** the kernel accepts the dirty export | **proved** (source) |
| Every other GPU write to an IOSurface is a full GPU→staging→RAM readback with the process waiting for the GPU (`image_read` = submit + wait + row `memcpy`) | **proved** (source) |
| A texture is *not* an alias of the family VRAM in six enumerable cases (table 3) | **proved** (source); which case the compositor hits is **unknown** |
| A dirty export is refused in twelve enumerable cases. In stock 1.14.2 nine of them (cache/resource/vidmem/RM handle missing, type, flag, no valid bitmap, plane, pend table full) are reported to the plugin as the same status `0x80000004`, so today's logs cannot tell them apart; only version/off/lookup failures differ | **proved** (source) |
| The pending-page-off table (512 slots, keyed by surface ID) only frees an entry in a page-off. A surface that is GPU-written and then destroyed without a CPU read keeps its slot until reboot; after 512 of them every dirty export of a *new* surface is refused and each write falls back to the full readback | **proved as a code path** (host test `pend_test.c`, `sync_model_test.c`); **whether it happens on this machine is a hypothesis** (needs `nvaccel_ss_dirty_pend_full`) |
| A shared texture keeps the VRAM block it imported alive (RM dup). If the family frees and re-backs the resource, the kernel marks a *different* block newest | **model only** (assumptions A3/A4 in `sync_model_test.c`); the plugin has no allocation epoch to notice. **Hypothesis H6**, checkable with `vm_alloc` vs `res_new` |
| A frame is scanned out zero-copy only when `valid[6]&1` ("VRAM newest") is set; only a dirty export sets it. A frame whose writer took the readback path is therefore normally refused by `nvAccelIopFlip` (`flip_stale`) and copied row by row by the CPU in `performTransaction` | **proved as a code path** (`nvAccelIopFlip` 1523); how often it happens is unmeasured (`debug.nvaccel_iop_flip_stale`) |
| Completion waits (`commitAndWaitUntilSubmitted`) | **kept**, not touched |

The stack in the existing sample (`nvmtlSurfaceOut → nvmtl_vk_image_read → memmove` on completion workers) means the *copy-out* branch ran in
WindowServer. It does not say how often, for which surfaces, or why. That is what the instrumentation measures.

## 2. Ownership and synchronisation

```
                       ┌───────────────────────────────  kernel (NVAccel, per IOSurface plane 0)  ─────────────────────────────┐
  CPU / other process  │  NVResource (type 0xc0) ── NVVidMemory ── RM VRAM block  (one per surface, shared by every process)    │
   IOSurfaceLock ─────►│  valid[0] bit = system memory valid      valid[6] bit = VRAM newest      pend table: id ∈ ? (512)     │
   (pageoff on demand) │  NVResource::pageoff: VRAM ─copy engine─► IOSurface pages;  sets valid[0], clears pend entry            │
                       └─────────────▲───────────────────────────────────────────────▲──────────────────────────────────────────┘
        IOSurface RAM pages          │ NVRM_ESC_SURF_VRAM: dup the RM object         │ NVRM_ESC_SURF_DIRTY: mark VRAM newest,
        seed (bumps on write-unlock) │ → plugin imports it (vkAllocateMemory fd)     │ valid[6]|=1, valid[0]&=~1, pend.add(id)
        attachment NVMTLVramAt:p0 =  │                                               │
          { magic, seed, gen }       │                                               │
 ┌───────────────────────────────────┴──── plugin, one NVMTLTexture per wrapper ─────┴────────────────────────────────────────┐
 │ shared  (_vramOn): VkImage = linear alias of the imported VRAM, pitch = IOSurface row. No private pixels.                    │
 │ private          : own optimal-tiling VkImage; RAM is the exchange medium (copy in on seed/gen change, copy out after each GPU write) │
 │ per texture: _surfSeed, _surfGen, _surfSynced                                                                                │
 └─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

**Rules the code follows (all from v1.14.2):**

* `nvmtlSurfaceIn` (`NVMTLObjects.m:1146`): return if the texture is synced at the current seed (and, for private images, current `gen`); else if
  shared and the attachment tag equals the current seed, return (VRAM is already current); else `IOSurfaceLock(ReadOnly)`, copy RAM→image
  (`nvmtl_vk_image_write`: staging `memcpy` + submit + **wait**), unlock, record seed, set tag.
* `nvmtlSurfaceOut` (`:1169`): shared and dirty export accepted → no copy, record seed, `tag.gen++`. Otherwise `IOSurfaceLock(0)` (write lock: the
  unlock bumps the seed), `nvmtl_vk_image_read` (submit + **wait** + row `memcpy`), unlock, record seed, set tag.
* Who calls them: `nvmtlSurfaceIn` before a render pass that loads, before blits/compute that read or partially write a surface texture; `nvmtlSurfaceOut`
  from `nvmtlAdvancePart` for every surface in the part's `_surfDirty` set (render attachments, blit/compute destinations), and from `replaceRegion`.
* Kernel: a CPU `IOSurfaceLock` finds `valid[0]` clear and calls `NVResource::pageoff` (VRAM→RAM on the copy engine, or the staging buffer); the display
  pipe does the same through `nvAccelSurfScanoutSync` for entries of the pend table.
* WindowServer waits for the GPU on purpose in `commitAndWaitUntilSubmitted` (`:4707`): NVAccel cannot order the swap after an NVK fence. Not changed.

**Invariant the display copy path relies on (I1):** *VRAM newest ⇒ the surface is in the pend table.* `nvAccelSurfDirty` sets both under one call and refuses
(returns before touching `valid[]`) when the table is full, so a full table can only cost speed, never correctness. Dropping an entry of a live surface would
break I1 (test: the "wipe" mutant in `sync_model_test.c` is caught).

## 3. Every cause of a copy

### 3a. Readback (`nvmtlSurfaceOut` copying)

| # | Condition | Class | Where | How to see it |
|---|---|---|---|---|
| O1 | The texture is private (`_vramOn` false), for any reason in 3b | required *for that texture*; avoidable by making it shared | `NVMTLObjects.m:1173` | surfstat `copy-private`, reason column |
| O2 | Shared, dirty export refused: lookup fails, no device cache / `NVResource` / vidmem / RM handle, type≠0xc0, flag 0x8000, no valid bitmap, plane>15, **pend table full**, accelerator lock missing | avoidable (each reason has its own fix) | `nvrm-accel.cpp:1229-1262` | surfstat `copy-dirty-refused` + status; `debug.nvaccel_ss_dirty_*` (diagnostics kernel) |
| O3 | `nvmtl_vk_surface_dirty` returns early: `NVMTL_NO_SURFACE_PAGEOFF=1`, headless GPU, `pnvk_surface_dirty` absent, no device | not our case (`debug.nvaccel_headless=0`); would show status `0xFFFF0001/2` | `nvmtl_vk.c:1764` | surfstat dirty status |
| O4 | `replaceRegion` (CPU `replace`) on an IOSurface texture ends with a copy-out | required unless the write was a full overwrite *and* the texture is shared | `NVMTLObjects.m:1308,1327` | rare in a compositor; surfstat shows it as ordinary out events |
| O5 | `getBytes` (app-level readback) | required | `NVMTLObjects.m:1270-1290` | not instrumented (a real CPU read) |
| O6 | Several parts per command buffer write the same surface → one copy-out per part | not provable as redundant (events may let another process read between parts) | `NVMTLEventSync.m:361` | surfstat: out count per surface vs frames |

### 3b. Why a texture is private (`nvmtl_surface_image_create`, `NVMTLDevice.m:711`)

| Reason code in surfstat | Condition | Avoidable? |
|---|---|---|
| `share-off` | `nvmtl_vk_surface_share_on()==0`: `NVMTL_NO_SURFACE_SHARE=1`, headless GPU, NVK import / `VK_KHR_external_memory_fd` / DRM linear modifier missing | no, not on this machine (direct test shared fine) |
| `plane` | plane≠0 or the surface has several planes (YUV video) | not without new work |
| `geometry` | texture row bytes > surface row, or taller than the surface | no (format mismatch) |
| `row-align` | surface `bytesPerRow % 32 != 0` (the linear texture header's pitch unit) | only by a different sampling method; **check how many surfaces hit it** |
| `import` | `nvmtl_vk_surface_vram` failed: kernel `SURF_VRAM` refusal (no surface / no cache / **no RM VRAM** / too small / RM dup failed) or Vulkan import | yes, depends on the kernel reason (`debug.nvaccel_ss_share_*`) |
| `alias` | VRAM imported, buffer-alias image creation failed (format/usage not linear-capable) | maybe |

### 3c. Upload (`nvmtlSurfaceIn` copying)

`copy-newtex` (this texture object never synced the surface: a new wrapper of a surface whose tag is not current), `copy-seed` (the seed moved: a CPU
writer, or a peer's copy-out), `copy-gen` (private image behind a peer's GPU write). A CPU writer is **required** work. A *new wrapper per frame* is
avoidable if the import were cached (section 7), and is visible as `wraps ≫ distinct surfaces`.

## 4. What changed in the code (patch set `patches/nullmoth-readback/`)

| Patch | Contents | Behaviour change |
|---|---|---|
| `0001-plugin-surfstat.patch` + `files/plugin/nvmtl_surfstat.h` | Per-surface counters (shared/private + reason, out outcome, dirty status, bytes, GPU wait, CPU copy, lock time, import time, upload cause), bounded report file, WindowServer `waitUntilCompleted` total | none; off until a root-owned request file exists |
| `0002-nvaccel-diagnostics.patch` | `debug.nvaccel_ss_*` counters: dirty refusals by reason, SURF_VRAM outcomes, pend-table occupancy, page-off ok/fail/bytes/µs, accelerator-lock wait/hold. Dirty refusals return `0x80000010+reason` instead of `0x80000004` | none visible: the plugin only tests "non-zero" |
| `0003-nvaccel-pend-release-on-free.patch` + `files/kexts/NVRM/accel/nvsv_pend.h` | Pend table entries remember their `NVResource`; `NVResource::free()` drops its entries | frees slots of dead resources; **apply only if `pend_full` or a pegged `pend_high` shows the table saturating** |

Properties: no pixel or title is recorded; the report is ≤ 24 KB, rewritten at most every 5 s, 256 surface slots with LRU eviction into the totals;
nothing is logged per frame. The request file must be a root-owned regular file that is not group/world-writable. NVMTL release builds redirect
`access()/fopen()` for `/tmp/nvmtl-*`, so the files use other names and `open()/stat()`.

Not changed, on purpose: completion waits, zero-fill of granted VRAM, PAT, boot-args, any seed-only skip of an upload or readback.

## 5. Correctness argument for patch 0003 and what is tested

* An entry is created only together with `valid[6]|=bit` in `nvAccelSurfDirty`, keyed `(surface ID, NVResource*)`. It is removed by (a) a page-off (all
  owners of that ID, as before), (b) `NVResource::free()` of the owner, nothing else. A freed resource has nothing left to page off; the family pages off before
  it evicts (assumption A4, the reason `pageoff` is an override at all), and a destroyed surface is never read again.
* A full table still refuses (fallback = readback), never evicts a live entry.
* Entry lookup order and results are identical to upstream for one-owner-per-ID sequences (`pend_test.c`: 400 000 random operations compared with upstream's
  function copied verbatim).

Host tests (`make -C test/readback test`, ASan+UBSan, gcc and clang): `surfstat_test.c` (classifier equals upstream's predicate on 200 000 random inputs;
sentinel/ownership rules; bounded table and report), `pend_test.c`, `sync_model_test.c` (random sequences over CPU edit / GPU write / GPU read / CPU lock /
display / eviction / surface re-creation with three processes, different pitches and widths, row padding sentinel, injected import refusal, VRAM
exhaustion, dirty refusal, refused flips and fence failures), `collect_test.py` (decision logic of the collector). Result: all pass; with surface churn the
upstream table refuses thousands of dirty exports in a 64-slot model and the fixed one none, with no stale reads in either; the model also shows (and the
oracle can detect) the eviction hazard H6 without an epoch check, and a deliberately wrong release is caught.

**Limits of those tests:** the model re-implements the protocol; the kernel's valid-bit behaviour on CPU unlock (A1/A2), page-in on re-wire (A3) and
page-off before eviction (A4) are assumptions about closed IOGraphicsFamily code. They are not proof about the machine.

Hardware tests (not run): `test/readback/macos/surfsync.m check` — CPU→GPU full and partial edit, GPU blit/clear→CPU lock ×20, GPU→GPU, row padding
untouched, five geometries including rows not multiples of 32, destroy/recreate ×100 (new surface must read zero), two processes on a global surface
(child sees parent's GPU write; parent's *existing* texture sees the child's), two-plane `420f`. Run it normally, with `NVMTL_NO_SURFACE_SHARE=1` and with
`NVMTL_NO_SURFACE_PAGEOFF=1`: the three runs must agree.

## 6. Runbook (short, in this order; stop when the question is answered)

**Stage 0 — no rebuild, 20 s, read-only**

```sh
cd ~/develop/projects/ga403wm-hackintosh
/usr/bin/python3 -I scripts/macos-ws-readback-collect.py --seconds 20 --label desktop-static     # keep the workload fixed
sudo /usr/bin/python3 -I scripts/macos-ws-readback-collect.py --seconds 20 --label desktop-static-sudo   # optional: also reads display-trace/kernel.txt
```

Send back `~/efi-audit/ws-readback-*/analysis.txt` and `logs.txt` (and `build/ws-next/{windowserver.sample.txt,steady.json,analysis.md}` if you want them
cross-read). It answers from stock 1.14.2 counters: how many scanout frames were CPU copies and why (`flip_stale`/`lock`/`novram`/`refused`), VRAM
refusals, re-backing (H6), plugin log counts of `dirty refused (0x…)` and `family VRAM import refused`, and the driver's own `surfvram dirty … refused N`
lines. In stock 1.14.2 most refusal reasons read `0x80000004`, so only the diagnostics kernel (stage 2) separates them.

**Stage 1 — per-surface reasons, plugin only** (needs a reboot)

```sh
git clone --branch v1.14.2 https://github.com/nullmoth/nvidia-macos-driver ~/nvmtl-readback && cd ~/nvmtl-readback
bash ~/develop/projects/ga403wm-hackintosh/patches/nullmoth-readback/apply.sh . && git add -A && git -c user.email=x -c user.name=x commit -qm readback
xcrun clang -arch x86_64 -bundle -fobjc-arc -O1 -DNVMTL_RELEASE=1 -Wno-protocol -Wno-incomplete-implementation \
  -I"$HOME/Vulkan-Headers/include" -o /tmp/NVMTLDriver.readback plugin/NVMTLDevice.m -framework Foundation -framework Metal -framework IOSurface
codesign -f -s - /tmp/NVMTLDriver.readback && shasum -a 256 /tmp/NVMTLDriver.readback
sudo bash ~/develop/projects/ga403wm-hackintosh/scripts/macos-readback-plugin-install.sh --candidate /tmp/NVMTLDriver.readback --sha256 <hash>
# reboot, log in, then:
echo WindowServer | sudo tee /Library/NullMoth/surfstat-request; sudo chown root:wheel /Library/NullMoth/surfstat-request; sudo chmod 644 /Library/NullMoth/surfstat-request
/usr/bin/python3 -I scripts/macos-ws-readback-collect.py --seconds 20 --label desktop-static-stage1
sudo rm /Library/NullMoth/surfstat-request     # off again; the final report stays in /private/tmp/nullmoth-surfstat.WindowServer.<pid>.txt
```

Use the same flags as `build/build_plugin.sh` (this is its recipe without the LIVE checkout); if your last good plugin build used something else, use that.
Undo: `sudo bash scripts/macos-readback-plugin-install.sh --undo`, reboot.

**Stage 2 — kernel reasons, only if stage 0/1 point at the kernel** (needs a kext build and a reboot)

```sh
bash scripts/macos-build-nvaccel-local.sh ~/nvmtl-readback        # needs ~/ogkm610 (open-gpu-kernel-modules 610.57.04), as for NVRMFB; prints the sha256
sudo bash scripts/macos-readback-nvaccel-install.sh --exe ~/efi-audit/readback/stage/NVAccel --sha256 <hash>
```

The NVAccel build on this Mac is **unproven**: upstream's `build/accel_build.sh` takes its `-D` list from `ogkm610/src/nvidia/_out/Darwin_x86_64/compile_cmds.sh`
(a configured RM build), which the earlier local builds (NVRMFB, NVRMEdpBL) did not need. `macos-build-nvaccel-local.sh` uses that file when it exists and otherwise
the explicit list `macos-build-nullmoth-local.sh` uses; a compile error is harmless, nothing is installed until the install script runs.

Build 0002 first (apply without `--with-fix`; re-run `apply.sh` on a fresh checkout to add the fix later). Read `sysctl -a | grep nvaccel_ss_` after a workload. Build with `--with-fix` only if `nvaccel_ss_dirty_pend_full`
or `nvaccel_ss_pend_high ≥ 500` says so. Undo: `sudo bash scripts/macos-readback-nvaccel-install.sh --undo`, reboot.

## 7. Decision table (what each outcome means)

| Observation | Meaning | Next |
|---|---|---|
| `iop_flip_stale/s` ≈ frames/s, surfstat `copy-private` dominant | WindowServer's own render targets are private images | read the `why` column: `row-align`/`plane` → no cheap fix; `import` → kernel reason |
| `copy-dirty-refused`, kernel reason `pend_full`, `pend_high`≈512 | table saturation (the leak) | apply 0003, rerun same workload |
| reason `no_cache`/`no_res`/`no_vm`/`no_handle` | resource not yet created/backed when the plugin asks | kernel wiring order; investigate before patching |
| `import` with `share_no_vram` or `vm_refused>0` | VRAM exhausted → no backing | memory budget (`NVMTL_VRAM_HEADROOM_MB`), not a code fix |
| `wraps ≫ distinct surfaces`, `import_ms` large | a new shared wrapper per frame | consider the import cache below |
| `vm_alloc ≫ res_new` | resources re-backed (H6) | add an allocation epoch before any cache |
| `copy-dirty-refused` ≈ 0 and `out_copy_ms` small | the readback is not where WindowServer's time goes | look at `dirty_path_ms`, `commit_wait` (elapsed), upload `copy-seed` |

## 8. Import/texture cache: only with these keys

No cache was written (the data to justify it does not exist yet). If wraps ≫ surfaces, a cache must be keyed by **(surface ID, plane, allocation epoch,
pixel format / view attributes, width, height, row, usage)** and every hit must re-check the epoch. The plugin cannot read `fAllocationCookie` today:
`SURF_VRAM` returns client/memory handles and size only. The epoch has to come from the kernel with the share (the unused `pad` field of
`NVRMSurfShareEsc` fits) and be carried through NVK's `import_dma_buf`, which needs a Mesa/NVK rebuild. Lifetime: a cached block must be released when the
surface or resource dies (it pins VRAM through the RM dup), so the cache needs the same release hook as 0003. Surface IDs alone are not unique over time
for this purpose. Model evidence for the failure mode: `sync_model_test.c`, "eviction with live shared textures".

## 9. Transfer benchmark vs the WindowServer measurement

* `surfsync bench` times single operations on synthetic surfaces (GPU write+wait, plus CPU lock/read, plus CPU edit→GPU read) and reports wall and
  process CPU per operation. It is a transfer benchmark. **It must not be quoted as a WindowServer CPU change.**
* The WindowServer measurement is `macos-ws-readback-collect.py` (and `macos-ws-cpu.py`): the same visible workload, same displays, same power state, ≥ 3 runs
  of 20 s before and after, WindowServer cumulative CPU delta / wall, frames/s, copied-frame counts. A different workload (as in the 33,4 % vs 24,57 %
  rounds) is not a comparison.
* Counter times (`gpu_wait`, `commit_wait`, `famlock_wait`) are elapsed time; do not add them to CPU or to each other.

## 10. Is it worth deploying?

* Stage 0 and 1: yes — read-only/optional, off by default, fully reversible.
* Patch 0003: only if the counters show saturation. It touches a kext (collection rebuild + reboot), changes one lifetime rule, and has host tests but no
  hardware run. If `pend_full` is 0 on the machine it does nothing useful.
* Rollback: `--undo` scripts for the plugin and for NVAccel (both restore the stock executable and rebuild/keep the collection); `rm` the request file to stop
  statistics immediately; `Uninstall`/backup flow of NullMoth itself is unchanged (`/Library/NullMoth/backup-20261012-134122.*`).

## 11. What is still open

1. Which case of 3a/3b WindowServer's own surfaces fall in — stage 0/1 data.
2. Whether the pending table ever saturates here — `nvaccel_ss_pend_high`.
3. H6 (re-backing with live shared textures) — `vm_alloc` vs `res_new`, then a hardware repeat of `surfsync check` after memory pressure.
4. Per-write overhead of the *no-copy* path (escape into the kernel under the accelerator lock, two IOSurface attachment IPCs for the tag bump): measured
   by `dirty_path_ms` and `famlock_*`; not changed because `gen` is needed by private peers.
5. Reading the staging buffer in `nvmtl_vk_image_read` may itself be slow if that memory is mapped write-combined; surfstat reports `cpu_copy_ms` separately
   from `gpu_wait_ms` to show it. Not established.
6. Everything in this page that is a closed-code assumption (A1–A4).
