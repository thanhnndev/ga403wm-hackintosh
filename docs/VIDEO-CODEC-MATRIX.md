# Video codec matrix: hardware decode per codec and app (2026-11-18)

Goal (owner): every video codec decoded on the 890M VCN in Chrome, Safari and QuickTime. This page has the
before-matrix on the live stack (out-30), the root causes with file and function, the fixes on branch
`claude/video-suite-27beee` (compile-checked and tested in-process, **nothing installed**), and what main must build,
install and verify. Tools: `tools/890m/video-suite/` (README "Codec matrix") and `tools/890m/vcndec/`.

## Before (live stack: VCNDec 0.1.0, RADV 90402a4b, out-30)

59 cells (1080p30/60 and 4K; MP4, fMP4/MSE, WebM, MSE WebM; Chrome scratch profile, Safari in its own window,
QuickTime), **19 pass, 39 fail**, 1 without a clip. Every cell, with frame check, drops and CPU:
[`tools/890m/video-suite/results/matrix-before-out30.md`](../tools/890m/video-suite/results/matrix-before-out30.md).
"HW" = VCNDec logged a session on the 890M VCN for that cell; Chrome's "platform decoder" alone is not hardware.

| codec | Chrome | Safari | QuickTime | cause (fix #) |
|---|---|---|---|---|
| H.264 8-bit (1080p30/60, 4K, MP4 + fMP4/MSE) | **SW** FFmpeg (0/4) | **SW** WebKit (0/4) | **SW** Apple VT, 35-119 % CPU (0/4) | 1, 2 |
| HEVC Main 8-bit (1080p60, 4K, MP4 + fMP4/MSE) | **SW** Apple VT, 47-161 % (0/3) | **SW** Apple VT (0/3) | **SW** Apple VT, 37-121 % (0/3) | 1, 2 |
| HEVC Main10 | **SW** Apple VT (0/1) | **SW** Apple VT (0/1) | **SW** Apple VT (0/1) | 1, 2, 3 |
| VP9 profile 0 (1080p30/60, 4K, WebM + MSE) | HW, PASS (6/6) | **SW**: VCNDec fails in WebKit's GPU process, 120-516 % CPU (0/6) | no WebM in QuickTime | 5 |
| VP9 profile 2 10-bit | **SW** libvpx: 0.1.0 refuses (0/2) | **SW** (0/2) | - | 3 |
| AV1 8-bit (1080p30/60, 4K; WebM, MSE, MP4) | HW, PASS (7/7) | HW (6/7; 1080p60 MSE "Media failed to decode") | plays, VCNDec errors "copy fence 2" (0/1) | 8 + open finding below |
| AV1 10-bit (MP4) | **SW** dav1d: 0.1.0 refuses (0/1) | **does not play** (0.1.0 refuses, Safari has no software AV1) | **does not play** | 3 |

Not playing at all on the live stack: AV1 10-bit in Safari and QuickTime. Everything else plays; the failures are
software decode (H.264 / HEVC everywhere, VP9 in Safari, all 10-bit) and AV1 decode errors.

**Open finding (driver side, for main / NMXGPU owner), not fixed here:** every VCNDec `copy fence 2` today follows a
gfx page fault by ~2.1 s, and the gfx ring then times out ("ring gfx_0.0.0 timeout, but soft recovered"): 12:02:36 ->
12:02:38, 12:05:02 -> 12:05:04, 12:37:10 -> 12:37:12, 12:37:18 -> 12:37:21. Fault: `[gfxhub] page fault ring:40`,
client TCP (shader), `PERMISSION_FAULTS 0x5`, `RW 1`, `MAPPING_ERROR 0`, "NMX: address is in no recorded read-only
mapping", in the pasid of the VTDecoderXPCService that hosts VCNDec. RADV runs VCNDec's image-to-buffer copy as a shader
into a host-imported IOSurface (`vcndec.c: surface_buffer()`), so the write is most likely VCNDec's copy into an
output IOSurface whose GPU PTE is not valid/writable at that moment (not a romap entry, so not a read-only userptr).
17 such faults on this boot (from 11:27, ~every 2 min 43 s in pasid 32816 while Safari/QuickTime played AV1), **none**
on the out-29 boot (11-16 18:39) or on this morning's 08:54 boot. Not reproduced in-process (`vcndec_test -p` with
0.5-3 s idle pauses: longest copy wait 9 ms). Next step: VCNDec logs the GPU VA range of each imported surface (needs
`bufferDeviceAddress`) so the fault address can be matched, or an A/B with imports off (staging copy) under QuickTime.

## After (installed 2026-11-18 15:54 boot: RADV 379787c4 all codecs, VCNDec 0.2.0, NMXGPU out-33)

**58 pass, 0 fail** (1 without a clip: 10-bit AV1 WebM). **38 cells fixed, 20 were already on the VCN, 0 still failing.**
Every cell: [`results/matrix-after-out33.md`](../tools/890m/video-suite/results/matrix-after-out33.md); per cell
before/after decoder and CPU: [`results/compare-before-out30-after-out33.md`](../tools/890m/video-suite/results/compare-before-out30-after-out33.md)
(`node compare.mjs before-out30 after-out33`).

- `vkcaps`: decode queue family `videoOps 0xf`, `VK_KHR_video_decode_h264/h265`.
- `vt_check` (installed VCNDec, no `-b`): all 9 MP4 clips (H.264 1080p60 / fMP4 / 4K, HEVC 8-bit / fMP4 / 4K, HEVC Main10,
  AV1 8/10-bit) hw yes, every frame index right, 0 errors.
- CPU (VideoToolbox XPC + the app's decoding process), before -> after: QuickTime H.264/HEVC 39-127 % -> 0-13 %;
  Safari HEVC 129-233 % -> 15-44 %, Safari VP9 137-516 % -> 9-52 %, Safari H.264 84-164 % -> 7-18 % (one 1080p30
  cell 139 %: WebKit GPU process rendering, decode on the VCN); Chrome HEVC 64-183 % -> 22-28 %. Chrome H.264 before
  reads low (8-21 %) because FFmpeg decoded in the renderer, which is not in this column; after 13-23 % is the GPU process.
- gfx page faults / ring timeouts since the boot: **0** (17 on the out-30 boot). VCNDec: 89 sessions, 0 frame errors,
  0 copy waits over 100 ms (longest 23 ms), no "copy fence" errors.
- Harness fix found in this run: `lib/vcnlog.mjs` kept one record per process, so a codec probe (`CreateInstance hvc1`)
  in Safari's VTDecoderXPCService relabelled a running AV1 session and the cell read "SW"; sessions are now per pid:thread.

## Root causes and fixes

| # | symptom | root cause (file: function) | fix (commit) |
|---|---|---|---|
| 1 | H.264 and HEVC never reach the VCN, in any app. Chrome: H.264 on `FFmpegVideoDecoder` (software), HEVC on Apple's software HEVC decoder inside VTDecoderXPCService (~50 % CPU at 1080p60, Chrome calls that "platform decoder"). Safari / QuickTime: software. | **RADV**: the live `libvulkan_radeon.dylib` is built by `~/develop/projects/radv-video/build-res.sh`, whose `meson setup` has no `-Dvideo-codecs`, so Mesa uses `all_free`: the device exposes `VK_KHR_video_decode_av1/vp9` only; the VIDEO_DECODE queue family reports `videoCodecOperations 0xc` (AV1 + VP9). libavcodec then fails with "Device does not support decoding h264". | `scripts/radv/build-radv.sh` (`-Dvideo-codecs=all`; out-of-tree build from the same Mesa tree, no source change since the live build; `pkg-config` shim and the Android SDK's ninja because MacPorts' were removed; install names, rpath and ad hoc signature as `macos-nvmtl-radv-install.sh` requires). Result: `videoOps 0xf`, `VK_KHR_video_decode_h264/h265`. (7fa3239) |
| 2 | same | **VCNDec 0.1.0** registers only `vp09`/`av01` (`tools/890m/vcndec/Info.plist` CMClassImplementations, `src/vcnvt.c: handled()`), and its libavcodec has no H.264/HEVC decoder (`ff-build.sh` configure). | VCNDec 0.2.0: `avc1`/`hvc1`/`hev1` entries, `check_config()` for avcC/hvcC, libavcodec h264/hevc + Vulkan hwaccels, decode-order output patches (`h264_slice.c: h264_select_output_frame`, `hevcdec.c: hevc_frame_end`; one picture per VideoToolbox sample, the client reorders). (4b98e78) |
| 3 | 10-bit streams (HEVC Main10, AV1 10-bit, VP9 profile 2) decode in software. | VCNDec 0.1.0 `src/vcnvt.c: check_config()` accepts 8-bit only; `src/vcndec.c` copies NV12 only. | 0.2.0: P010 output (`x420` / `xf20`), per-depth row copy, `check_config()` accepts VP9 p2 / AV1 10-bit / HEVC Main10. (4b98e78) |
| 4 | Sessions on VCNDec report `UsingHardwareAcceleratedVideoDecoder = false`. | `src/vcnvt.c: d_props()` returned an empty supported-property dictionary, so VideoToolbox never forwarded the property to `b_copyProperty()`. | list the key (read-only boolean). (20588a7) |
| 5 | Safari VP9 always software (Safari AV1 is on VCNDec). | Safari runs VP9 **supplemental** decoders inside WebKit's GPU process, not in VTDecoderXPCService. Its sandbox denies `getegid` (kernel: `deny(1) syscall-unix 43`); the Vulkan loader then treats the process as elevated and ignores `VK_DRIVER_FILES`, finds no driver, `vkCreateInstance` = `VK_ERROR_INCOMPATIBLE_DRIVER`; VCNDec `src/vcndec.c: vcn_open()` fails ("Vulkan device: Generic error in an external library") and VideoToolbox falls back to Apple's software VP9 (WebKit GPU 140-340 % CPU). Reproduced with `sandbox-exec` denying only `getegid`. | `vcn_open()` retries with RADV opened directly (`FF_VULKAN_ICD`, `vk_icdGetInstanceProcAddr`, no loader); `ff-build.sh` adds that "loader-less" patch to `libavutil/hwcontext_vulkan.c: load_libvulkan()`. Under the same sandbox: 600/600 VP9 and AV1 frames on the VCN, md5 identical to 0.1.0. (c85282b) |
| 6 | (safety) VCNDec 0.2.0 on a RADV without H.264/HEVC accepted the session and failed every frame (2700 errors, 0 pictures) instead of letting VideoToolbox fall back. | `src/vcndec.c: vcn_open()` did not check the device's decode operations. | `device_decodes()`: no decode queue for the codec = StartSession refused (`kVTVideoDecoderUnsupportedDataFormatErr`), logged "refused". (929d3e9) |
| 8 | Under VCN contention (another process decoding 4K flat out), Chrome VP9 1080p30 and AV1 4K MSE got `-12911` decode errors (32 drops / "plays no"); log: `VCNDEC decode #258: copy fence 2`. | `src/vcndec.c: copy_out()` waited 2 s on the copy fence (the copy waits on the decode's timeline semaphore), then on `VK_TIMEOUT` called `vkResetFences` on a fence whose submission was still pending (invalid) and returned an error; the next frame's submit reused that fence, so one slow frame became a run of errors. | wait in 1 s steps up to 10 s, reset only a signalled fence; if it never signals, fail the session (`fence_lost`) instead of reusing the fence. Contention test (3 uncapped 4K decodes + VP9 at once): all indices right, 0 fence errors. Present in the installed 0.1.0 too. (748d7f2) |
| 7 | (test clips) "8-bit" HEVC clips were Main10; "fragmented" MP4s were plain MP4s (MSE rejected them). | AVAssetWriter: the HEVC encoder defaults to Main10 without a profile; `movieFragmentInterval` output is rewritten into moov+mdat by `finishWriting`. | `gen/genmp4.swift`: `HEVC_Main_AutoLevel`; CMAF segments through `AVAssetWriterDelegate`. AV1 8/10-bit MP4 clips from macOS's hidden AOM encoder (`AV1EncoderSW`, by EncoderID). (a87836e) |

VP9 profile 2 (Chrome WebCodecs encodes it, `mx-vp9p2-1080p60.webm`, first frame header profile 2): the installed
0.1.0 **accepts** the session and then fails every frame (`VCNDEC decode #1: sw_format p010le not NV12`, 600/600
errors), so the app gets errors rather than a clean fallback. 0.2.0 decodes it on the VCN with the right index on all
600 frames, **on the live RADV too** (VP9 is in its `all_free` set): this cell needs only VCNDec 0.2.0. VideoToolbox
always routes `vp09` to the installed supplemental decoder (`vt_test -b` cannot override it), so the in-process test is
`vcndec_test -x -i` (new: P010 pool and frame-index check).

AV1 10-bit exists as MP4 only (`mx-av110-1080p30.mp4`, macOS's AOM encoder): WebCodecs has no 10-bit AV1 encoder, so
there is no 10-bit AV1 WebM / MSE-WebM cell.

## In-process tests of the fixes (nothing installed)

`VK_DRIVER_FILES` = a test ICD json naming the new RADV; `vt_check -b build/VCNDec.bundle/...` registers the new
VCNDec in-process and requires a hardware decoder (frame-index strip of every picture compared with pts * fps):

| clip | codec / depth | pictures | VCN output | index ok / wrong / unreadable | errors |
|---|---|---|---|---|---|
| mx-h264-1080p60.mp4 | H.264 High 8-bit | 1800 / 1800 | hw yes, 420v | 1800 / 0 / 0 | 0 |
| mx-h264-1080p60-frag.mp4 (CMAF) | H.264 8-bit | 1800 / 1800 | hw yes, 420v | 1800 / 0 / 0 | 0 |
| mx-h264-2160p30.mp4 | H.264 8-bit 4K | 900 / 900 | hw yes, 420v | 900 / 0 / 0 | 0 |
| mx-hevc-1080p60.mp4 | HEVC Main 8-bit | 1800 / 1800 | hw yes, 420v | 1800 / 0 / 0 | 0 |
| mx-hevc-1080p60-frag.mp4 (CMAF) | HEVC Main 8-bit | 1800 / 1800 | hw yes, 420v | 1800 / 0 / 0 | 0 |
| mx-hevc10-1080p60.mp4 | HEVC Main10 | 1800 / 1800 | hw yes, x420 | 1800 / 0 / 0 | 0 |
| mx-hevc-2160p60.mp4 | HEVC Main 8-bit 4K | 1800 / 1800 | hw yes, 420v | 1800 / 0 / 0 | 0 |
| mx-av1-1080p30.mp4 | AV1 8-bit | 600 / 600 | hw yes, 420v | 600 / 0 / 0 | 0 |
| mx-av110-1080p30.mp4 | AV1 10-bit | 600 / 600 | hw yes, x420 | 600 / 0 / 0 | 0 |
| mx-vp9p2-1080p60.webm (`vcndec_test -x -i`, 600 frames) | VP9 profile 2 | 600 / 600 | P010 | 600 / 0 / 0 | 0 |
| mx-vp9-1080p30, mx-av1-1080p30 webm (`vcndec_test -i`) | VP9 p0 / AV1 8-bit | 600 / 600 each | NV12 | 600 / 0 / 0 each | 0 |

VP9 / AV1 8-bit md5 per frame identical to the installed 0.1.0, also under a sandbox that denies `getegid` (fix #5).
Build note: `build.sh` links the libavcodec at `$FF` (default `~/develop/projects/radv-video/ff-vcn/inst`); built
against the old VP9/AV1-only libavcodec, VCNDec 0.2.0 logs "StartSession avc1: no libavcodec decoder" and refuses, so
run step 2 before step 3.

## What main builds and installs (in this order, one boot)

1. **RADV with all video codecs** (no reboot needed, new processes load it; WindowServer at its next start):
   ```bash
   scripts/radv/build-radv.sh                       # -> ~/develop/projects/radv-video/mesa/build-codecs/libvulkan_radeon.dylib
   sudo scripts/macos-nvmtl-radv-install.sh ~/develop/projects/radv-video/mesa/build-codecs/libvulkan_radeon.dylib
   sudo scripts/macos-install-strixsbxmap.sh --refresh   # the dylib's CDHash is pinned
   VK_DRIVER_FILES=/Library/GPUBundles/nvmtl/radeon_icd.json tools/890m/vcndec/build/vkcaps   # qf 2 ... videoOps 0xf
   ```
   Undo: `sudo scripts/macos-nvmtl-radv-install.sh --undo` + `--refresh`.
2. **libavcodec** (static, linked into VCNDec): `tools/890m/vcndec/ff-build.sh ~/develop/projects/radv-video/ff-vcn/src ~/develop/projects/radv-video/ff-vcn/inst`
   (adds h264/hevc, applies the decode-order and loader-less patches; it refuses to continue if a patch does not apply).
3. **VCNDec 0.2.0**: `tools/890m/vcndec/build.sh`, then `sudo tools/890m/vcndec/install.sh --system` (system volume +
   bless, takes effect at the next boot). Kill switch without reinstalling: `touch /Library/NullMoth/vcndec-off`.
   **Install step 1 with it, not after**: VCNDec 0.2.0 makes `VTIsHardwareDecodeSupported(hvc1)` true; on the old RADV
   its guard (#6) refuses HEVC, and Chrome, which has no HEVC software decoder of its own, would then fail HEVC instead
   of using Apple's software decoder as it does today.

## How to verify after the boot

```bash
VK_DRIVER_FILES=/Library/GPUBundles/nvmtl/radeon_icd.json tools/890m/vcndec/build/vkcaps | grep "flags 0x20"   # videoOps 0xf
for c in mx-h264-1080p60 mx-hevc-1080p60 mx-hevc10-1080p60 mx-av110-1080p30; do   # installed VCNDec, no -b
  tools/890m/vcndec/build/vt_check ~/Library/Caches/ga403wm-video-suite/clips/$c.mp4 ${c##*p}; done          # hw yes, index ok = samples
node tools/890m/video-suite/matrix.mjs after-out30            # Chrome, ~10 min, small background window
node tools/890m/video-suite/apple.mjs after-out30             # Safari + QuickTime (Automation prompt must be allowed)
node tools/890m/video-suite/matrix-report.mjs after-out30     # results/matrix-after-out30.md: every cell PASS
/usr/bin/log show --last 30m --predicate 'subsystem == "com.ga403wm.vcndec"' | grep -E "refused|Vulkan device|errors [1-9]"   # nothing
```

Expected: every cell "HW (VCNDec 8/10-bit)" and PASS. Safari VP9 should show VCNDec
in `com.apple.WebKit.GPU` (in-process) with "StartSession vp09 ... on the 890M VCN".

## Wired memory: VCNDec import cache (out-33 hang 17:46, 2026-11-18)

Question from main: VTDecoderXPCService pid 7309 held 7.5 GB at the wired-memory hang (~300 4K P010 frames, 24.9 MB
each); pid 5628 on out-34 held 902 MB in 38 "owned physical footprint (unmapped)" regions.

**Who is the client.** Both services hosted only **WallpaperAerialsExtension** (the macOS Aerial wallpaper, 4K 10-bit
HEVC, a new clip every ~4-5 min, two sessions per clip). Before VCNDec 0.2.0 it decoded on Apple's software HEVC.
All sessions were closed: pid 7309 31 started / 31 closed (last close 17:44:26, ~2 min before the hang), pid 5628 6 / 6.

**Do closed sessions leak?** No.
- 8 consecutive 4K10 sessions through the installed VCNDec (XPC service, client releases each frame): service
  footprint 14-18 MB, IOSurface 0 B after every close and after a 5 s hold.
- Pin leak test: 5 sessions, ~3000 import/evict cycles of 24.9 MB surfaces: system wired before 12797 MB, 10 s after
  12795 MB (-2 MB). VCNDec's host imports release their wired pages.

So the frames owned by the service after its sessions closed are kept alive by the client (Aerials' player queue /
layers; the service owns them, the client maps them). What wires them after close is not VCNDec (its imports are
gone); the display path (WindowServer / NMX surface wiring of displayed layers) is the next place to look.

**What VCNDec itself did wrong (while a session is open)** - `src/vcndec.c: surface_buffer()`, cache of 32 entries:
- every cached import pins (wires) the whole output surface: 32 x 24.9 MB = ~800 MB wired per 4K10 session (Aerials
  runs two at a clip change), and the cache's `CFRetain` kept surfaces alive after VideoToolbox's pool retired them;
- a client that keeps frames (`vt_check` with `VT_KEEP=40`, like AVPlayer) makes the pool cycle > 32 surfaces: the LRU
  then missed on **every** frame (imports 600 of 600): pin + GPU map + unpin per frame.

| 4K10 HEVC, 600 frames, in-process | CPU / frame | wired peak | imports | max fps |
|---|---|---|---|---|
| client keeps 0 (pool small), before and after | 1.9-2.0 ms | +30-80 MB | 1 | 188-196 |
| client keeps 40, **before** (32-entry LRU) | **12.9 ms** (6.9 s sys) | **+1247 MB** | 600 | 80 |
| client keeps 40, staging only (`VCN_NO_IMPORT`) | 5.2 ms | (not wired) | 0 | 119 |
| client keeps 40, **after** | **5.1 ms** | **+256 MB** | 10 | 119 |
| client keeps 40, after, 5 s idle with the session open | - | released by the idle trim (237 MB) | 10 | 118 |

**Fix** (`vcndec.c`, `vcnvt.c`): byte budget per session (`VCN_CACHE_MB`, default 256 MB, still at most 32 entries:
10 surfaces at 4K10, 20 at 4K 8-bit, 32 at 1080p); an entry still in the pool's rotation is never evicted, so when the
cache is full a miss goes through the staging copy (5.2 ms) instead of a one-frame import (12.9 ms); entries unused for
128 lookups (retired by the pool) are released with their surface retain; `vcn_trim()` releases all imports after 2 s
without a decode (paused video, a player holding its last frames) and on memory pressure (dispatch memory-pressure
source, warn + critical); the close line reports `cache hits, staged, peak of budget MB, trims idle / pressure, MB
released`. All 9 MP4 clips with `VT_KEEP=40` and the VP9 / AV1 / VP9 p2 WebMs: every frame index right, 0 errors.
Not tested: a real memory-pressure event (simulating one needs root); it calls the same trim as the idle path.

**Do output surfaces need to be wired while only cached?** Only to skip the per-frame import: the GPU copy writes
through a host-pointer import, which pins the pages. Wiring is now bounded (256 MB per session) and dropped on idle,
pressure, retirement and close. The zero-wire alternative is the staging copy for every frame (5.2 vs 2.0 ms CPU per
4K10 frame); `VCN_CACHE_MB=0` selects it without a rebuild.
