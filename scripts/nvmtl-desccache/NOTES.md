# NVMTL desc-cache (draft section for docs/890M-TRACE.md)

## Step100 (draft): descriptor-set cache in NVMTL, for WindowServer CPU (2026-11-04, macOS, built, not installed)

**Hot path.** The Step96 WindowServer sample (`~/ga403-logs/step96/ws.sample`) had per-draw descriptor snapshots as
the largest NVMTL cost on the main thread: `-[NVMTLRenderCommandEncoder nvmtlBindSamplerPipeline]` →
`nvmtl_vk_cmd_bind_set` → `nvmtl_snapshot_set_c` → `nvmtl_snapshot_set_md` → `radv_UpdateDescriptorSets`.
Self time: radv_UpdateDescriptorSets 138, nvmtl_snapshot_set_md 121, ac_set_buf_desc_word3 18 samples; about
400-470 samples of 4851 (~8-10 % of a core).

Why every draw built a set: the old reuse (fork `nvmtl_vk.c`, `nvmtl_snapshot_set_c`) only reused the last set
when *no* slot of the stage had changed (`t->dirty`). CoreAnimation calls setVertexBytes/setFragmentBytes on every
draw, and NVMTL's setBytes ring hands out a new offset each time, so the stage was always dirty. The translator
lowers buffer access to the address table (binding 640, a `UNIFORM_BUFFER_DYNAMIC` in WindowServer, see the G1 log
line), so the table is usually the only thing that really changed.

**Design** (fork branch `desc-cache`, commit d5da629, file `plugin/nvmtl_desc_cache.h`):
- Per command buffer, a 128-entry open-addressing table of sets already written, stored in the bind table and freed
  with it at retire, so an entry never outlives its set or address page.
- Key = stage, storage-texture count, the pipeline's binding mask, and the canonical descriptor (what
  `nvmtl_snapshot_set_md` would write, dummy for empty or misaligned slots) of every binding the pipeline reads. Full
  keys are compared, not only hashes. In UBO-table mode binding 640 is not in the key.
- Hit: write a fresh address-table slot (same page as the cached set's slot), bind the cached set with a dynamic
  offset = new slot − old slot, so binding 640 reads the new table. No set allocation, no vkUpdateDescriptorSets.
  The three bind sites that use `nvmtl_snapshot_set_c` (graphics, dispatch_threads, dispatch_indirect_tg) pass the
  per-set dynamic offsets instead of `g_dyn_zero`.
- Reused handle values: hooks on vkDestroyImageView/Image/Sampler/BufferView (image epoch) and
  vkDestroyBuffer/vkFreeMemory (buffer epoch). An entry records which handle classes its key holds and the epochs;
  it is not used once one of those moved. With the cache on, the old last-set reuse gets the same guard (the test
  shows the old path reusing a set across a freed and reused view).
- Toggles: `NVMTL_NO_DESCCACHE=1` (environment, or a line in `/Library/GPUBundles/nvmtl/nvrm610.conf`) gives the old
  path exactly; `touch /tmp/nvmtl-desccache-off` turns it off live (checked about every 2 s; it is a no-op if the
  WindowServer sandbox denies the read). Stats every 60 s: `desc-cache stats: hit … miss … (stale, page, long, full)`.

**CPU-side test** (fork `plugin/tests/desccache_test.sh`, no GPU): the real snapshot code is extracted from
`nvmtl_vk.c` and run against a fake descriptor store (ASan + UBSan). After every draw it checks that the bound set
holds, for each binding the pipeline reads, the same handle and generation a fresh build would hold, and that binding
640 + the dynamic offset lands on a table slot that matches the current bindings. 120000 draws per run:

| run | new sets | descriptor writes | result |
|---|---|---|---|
| WindowServer-like, cache off | 157674 | 335350 | ok |
| WindowServer-like, cache on | 5059 | 13817 | ok |
| WindowServer-like, cache on, frees | 5553 | 16461 | ok |
| mixed pipelines, cache on, frees | 63089 | 2118996 | ok |

**Artifact.** `~/develop/projects/nmx-plugin-890m/out/plugin-desccache-d5da629/NVMTLDriver`, sha256
`ff3bc393de139c67e4744fa5dad1ce2647d490b04d6d9f745c1ab8c256e6a85d`, LC_UUID `7927EB9E-CED4-3CCF-9F83-CA9167A2C74D`
(the installer re-signs the bundle, so after install check the UUID, not the sha). Built from 899c64f + d5da629 with
the same command as the live plugin (non-release, all build_plugin.sh markers present, 336 warnings like the base).

**Install** (integrator, part of the batched reboot):
`sudo scripts/nvmtl-desccache/install.sh install` (checks the sha, then runs `scripts/macos-nvmtl-plugin-install.sh`,
which backs up the bundle to `/Library/NullMoth/nvmtl-plugin-<stamp>` and swaps
`/Library/GPUBundles/NVMTLDriver.bundle/Contents/MacOS/NVMTLDriver`). Undo: `... install.sh undo`.

**After the boot:** `scripts/nvmtl-desccache/install.sh status` (desc-cache log lines: hit/miss counts),
`top -l 2 -stats pid,command,cpu`, `tools/890m/present-rate.sh`, and a WindowServer `sample`: the
`radv_UpdateDescriptorSets` share should be near 0. A/B without a restart: `touch /tmp/nvmtl-desccache-off`, compare,
`rm` it.

**Expected:** the snapshot path was ~8-10 % of a core; with a high hit rate most of it goes, so WindowServer should
drop by about 5-8 percentage points (e.g. 55 % → ~48 %). It does not touch the other main-thread costs.

**Risks:** first live use of non-zero dynamic offsets on binding 640 (RADV adds them to the descriptor's base; the
range stays inside the 256-slot page). If pictures break (stale textures, wrong geometry), turn it off with the
flag file or the conf line and report the stats line. Memory: ~24 KB per command buffer that draws.
