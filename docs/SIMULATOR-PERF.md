# iOS Simulator performance on the GA403WM (2026-11-07)

Machine: macOS Tahoe 25G332, Xcode 26.5 (17F42), iOS 26.5 runtime (23F77), iPhone 17 simulator.
GPU stack: 890M on NMXGPU/NMXAccel (NVMTL plugin over RADV), RTX 5060 headless (NVAccel, NVK).
Tools: `tools/sim-bench/` (sources and scripts below). Flutter and the Android SDK are not installed on this Mac,
so only native iOS was measured.

## Result

| | before | after |
|---|---|---|
| MercuryPosterExtension crashes (SIGFPE) | **34 per minute** | **0** |
| SimMetalHost CPU, SimBench running (2x10 s) | 83-92 % | 27-31 % |
| ReportCrash CPU | 48-59 % | 0 % |
| SimMetalHost CPU, sim idle on the home screen | 53 % | not in the top 9 (< 7 %) |
| SimBench fps (CADisplayLink, after the first second) | 60.0 | 60.0 |
| SimBench frames > 1.5x the frame time, first 14 s | 1-2 (one 192-231 ms hitch at launch) | 0 (worst 18 ms) |
| SimBench process start -> first frame | 338 / 422 / 592 ms | 444-575 ms, median 514 ms (5 runs) |

About 1.1 CPU cores are freed while the simulator runs. Launch time did not change beyond the noise of a busy desktop
(Edge, Zalo, Claude, the NullMoth display trace all running); the fix does not target it.

Root cause and fix: one translator bug (below). Nothing in the Simulator's own settings helped.

## Measurements

### Which GPU the simulator uses
- Rendering runs in `SimMetalHost` (three processes, XPC services of CoreSimulator's SimRenderingServices, parent
  launchd). They map `NVMTLDriver`, `libvulkan_radeon.dylib` and `libdrm_amdgpu.1.dylib`: the 890M. The log says
  `GPU vendor 1002 (AMD, RADV)` and `accelerator vendor 10de, but this process runs Metal on 1002: no second device`.
- `Simulator.app` also has the NVMTL stack loaded (it shows the frames); `SimRenderServer` uses about 6 % CPU.

### Baseline CPU (before)
Idle home screen, 15 s window: WindowServer 68 %, SimMetalHost 53 %, ReportCrash 47 %, diagnosticd 42 %,
`log` 37 %, bluetoothd 33 %, launchd_sim 5 %.
SimBench running (2x10 s): SimMetalHost 83-92 %, backboardd 26-27 %, SimBench 8 %, SimRenderServer 6 %,
Simulator 3 %, ReportCrash 48-59 %.

`sample` of SimMetalHost: almost every busy frame is in `libnvmtl_translate.dylib` (operand clones, hash map
inserts, `value_queries`, `owned_cfg`): the host was retranslating the same failing kernel every time the crashed
extension came back.

### The crash loop
- `MercuryPosterExtension` (the iOS 26 wallpaper poster) died with EXC_ARITHMETIC / SIGFPE in
  `-[MTLSimBlitCommandEncoder copyFromBuffer:...toTexture:...]` (MTLSimDriver +0xce59, `divq %r13`).
- Disassembly: the divisor is `[pipeline threadExecutionWidth]`, the dividend `maxTotalThreadsPerThreadgroup`, of a
  compute pipeline MTLSimDriver builds from its own `default.metallib` (`newDefaultLibraryWithBundle:` ->
  `newFunctionWithName:constantValues:` -> `newComputePipelineStateWithFunction:`). The sim decodes ASTC textures
  with that kernel because the host GPU has no ASTC.
- On the host (`tools/sim-bench/lib.swift`, `astc.swift` with the runtime's metallib): every kernel builds except
  `astc`, on both the 890M and the RTX:
  `native emitter: owned InBoundsAccessChain violates its access-chain contract: index 0 into ... (TypeStruct) is
  ... (UConvert ...), and a struct member index must be an OpConstant`. The pipeline is nil, `threadExecutionWidth`
  reads 0, the divide traps.
- Counting: ReportCrash wrote only some `.ips` files (68 in the first ~10 min); its log has 34
  `Formulating fatal 309 report for corpse[...] MercuryPosterExtension` lines per minute
  (`tools/sim-bench/crashrate.sh`).

### Translator root cause (fork `translator-renderbox-vfn`, commit 2da7b21)
`astc` keeps `%union.Everything = { <4 x i32> }` as a local in the kernel and reads it in helpers through dynamic
`getelementptr i8, ptr %0, i64 %n` (DecodeASTC_RGBA -> DecodeIntegerSequenceEncoding, through an identity bitcast).
The translator gives a local object byte storage when it sees an i8 GEP on it, but only looked in the object's own
function. Three gaps, all fixed:
1. `infer_local_alloca_pointees` did not follow the pointer into a helper (now: an i8 GEP on the parameter, through
   bitcasts and forwarded calls, gives the alloca byte storage).
2. The one-block helper inliner refused the call (helper pointee `i8` vs alloca type), and bound the parameter to a
   proxy carrying the helper's struct pointee (now: a byte-storage alloca binds by name and keeps its own pointee).
3. Multi-block helpers: call-argument pointees did not include allocas, forwarded parameters passed their declared
   type, and `callee_param_accepts_call_pointee` refused byte storage (now: allocas pass their byte storage, a
   parameter forwards what its callers give it until nothing changes, a helper with a byte GEP accepts it).
Minimal repros: `tools/sim-bench/repro/u.ll` (one-block helper), `u7.ll` (multi-block helper with a lane GEP).
Unit tests: `struct_alloca_read_by_bytes_in_a_helper_uses_bounded_byte_storage`,
`struct_alloca_read_by_type_in_a_helper_keeps_its_type`. Library tests on this Mac: 1724 pass before and after,
the same 513 fail before and after (they need `spirv-val`/`llvm-dis`, which this Mac does not have).

### NVIDIA for the simulator: no
Steering: not possible today without a plugin change.
- The plugin hands each process one Metal device; the choice is `NVMTL_GPU=amd|nvidia` (env only).
- `launchctl setenv NVMTL_GPU nvidia` does not reach SimMetalHost (launchd XPC services take their environment from
  the bundle): after a sim reboot it still mapped libvulkan_radeon only.
- Simulator.app `File > GPU Selection > Prefer Discrete GPU`: no effect (same log lines, radeon only). Set back to
  Automatic.

Would it help: no. Host A/B with `tools/sim-bench/xgpu.swift`, one 1206x2622 BGRA frame (iPhone 17 size) into a
global IOSurface, 25 blended quads, then the 890M samples that IOSurface the way WindowServer composites the
Simulator window:

| fragment loop count | 890M render | RTX render | 890M sampling the surface |
|---|---|---|---|
| 8 (UI-like) | 0.95 ms (p95 1.16) | 2.84 ms (p95 4.20) | 0.37 ms (890M surface) / 0.31 ms (RTX surface) |
| 64 | 1.56 ms | 3.51 ms | |
| 512 | 9.63 ms | 9.79 ms (p95 12.08) | |

The RTX's shared IOSurfaces live in system RAM (`b80 LOCAL+mapped memory -> system RAM`), so for simulator-sized UI
frames the RTX is 2-3x slower and only ties at 64x the shading work. Both GPUs see each other's writes (pixel
counts match). Keep the simulator on the 890M.

Why the RTX loses (`tools/sim-bench/split.swift`, same frame, 2026-11-07):

| | 890M | RTX |
|---|---|---|
| empty command buffer, commit -> completed | 0.022 ms | 0.025 ms |
| frame into a private (VRAM) texture, GPU time per frame | 0.56 ms | **0.11 ms** |
| frame into a shared IOSurface, GPU time per frame | 0.85 ms | 0.38 ms |
| frame into a shared IOSurface, 1 frame per command buffer | 1.16 ms | **2.83 ms** |
| fp32 FMA throughput | 4.0 TFLOP/s | 7.4 TFLOP/s |

RTX extra cost per command buffer on an IOSurface (IOSurface minus private, 1 frame per buffer):
3 MB surface 0.65 ms, 12 MB 2.5 ms, 25 MB 4.4 ms, about 5.5 GB/s and linear in size. So the RTX's per-commit cost
is one transfer of the whole surface over PCIe, plus slower drawing into system RAM. Submission latency, Metal and the
GPU itself are not the cause. The cause is the port: the plugin keeps shared IOSurfaces in system RAM (b79/b80
placement) and moves the full surface on every command buffer. The simulator commits about once per frame, so it pays
that cost every frame. A fix would keep a VRAM copy and transfer only damaged regions. But the 890M still has to read
the frame for WindowServer, so the sim stays on the 890M anyway.

### Simulator settings tried
| setting | SimMetalHost | fps | verdict |
|---|---|---|---|
| default | 83-92 % | 60.0 | |
| Debug > Graphics Quality Override > Low Quality | 85-86 % | 60.0 | no gain, set back to Device Default |
| Simulator hidden | 85-87 % | 60.0 | the sim keeps rendering; no gain |
| File > GPU Selection > Prefer Discrete GPU | | | no effect (one device per process) |

## Flutter on the simulator (2026-11-07, boot 20:36)
Flutter 3.47.9 stable via mise (`mise use -g flutter@3.47.9`, on PATH in zsh and fish through `mise activate`),
analytics off. `flutter doctor`: Xcode OK, CocoaPods missing (plugins need it), no Android SDK, and "Flutter is
deprecating support for Intel-based Macs" (this host is x86_64). The simulator only runs debug builds (JIT).
Impeller draws with Metal, i.e. through NVMTL on the 890M.

`tools/sim-bench/flutter/run.sh` (400-row list, auto-scroll, every row animated each frame, 5 hot reloads):

| | result |
|---|---|
| `flutter run`, first frame (Xcode build already cached; first build 30 s) | 22.9 s |
| fps while scrolling | 36-63, mostly 50-58 |
| raster (GPU side) per frame, p50 / max | 5.8-6.7 ms / 7.8-11.1 ms |
| build (Dart, debug JIT) per frame, p50 | 5.4-24.7 ms |
| hot reload (1 of 754 libraries) | 302 / 369 / 373 / 427 / 436 ms |
| after each reload, ~2 s | 5-26 fps, build p50 26-98 ms, worst frame 178-285 ms |
| CPU while scrolling | Runner 86 %, WindowServer 41 %, SimRenderServer 9 %, backboardd 10 % |

Raster stays at ~6 ms: the GPU path is not the limit. Frames are lost in the Dart build phase on the CPU (debug JIT,
the benchmark rebuilds 400 animated rows every frame), and the stutter after a hot reload is the JIT recompiling.
Both are debug-mode costs, so they are not specific to this port. Real frame rates need a profile build on a device.
No translator failures and no crashes in the log during the run.

## Installed change and undo
The fixed translator (sha256 `eb6acb2af570f9ab`, built from fork 2da7b21 = 164adb3 + this fix) is installed in
`/Library/GPUBundles/NVMTLDriver.bundle` with the existing installer, and the StrixSbxMap pins were refreshed:

    sudo scripts/macos-nvmtl-translator-install.sh ~/develop/sim-bench/xl/libnvmtl_translate.dylib
    scripts/macos-install-strixsbxmap.sh --refresh

Backup: `/Library/NullMoth/nvmtl-translator-20261107T084052Z` (translator `355050159d33ce71`). Undo:

    sudo scripts/macos-nvmtl-translator-install.sh --undo
    scripts/macos-install-strixsbxmap.sh --refresh

New processes load it at once (the simulator after `xcrun simctl shutdown all` + boot); WindowServer loads it at its
next start, which makes the next reboot the first WindowServer run on it. The plugin keys its SPIR-V caches by the
translator's hash, so every app compiles its shaders once more after the install.

## Open
- Wallpaper still black: `space::rasterizeBackgroundFragment` (fragment, PosterBoard) fails with
  `native emitter: owned SampledImage image, sampler, and result types are inconsistent`. Cosmetic, no CPU cost now
  that the extension no longer crashes. A separate translator fix.
- `/Library/NullMoth/nullmoth-displaytrace.sh` runs two `log stream` processes all the time: `log` ~38 % CPU plus
  most of diagnosticd's ~45 %. Not the simulator, but it is the largest CPU user left on an idle desktop.
- bluetoothd ~32 % CPU at idle (not looked at).
- Android emulator: not installed (no Android SDK).
- Launch time (~0.5 s to first frame for a SwiftUI app) was not traced.

## Tools (`tools/sim-bench/`)
- `SimBench/` SwiftUI app: CADisplayLink fps, frames over 1.5x the frame time, worst frame, process start -> first
  frame. `SimBench/build.sh release` builds it with `swiftc` for the x86_64 simulator (no Xcode project).
- `run.sh LABEL [s]` cold launch + fps + CPU; `exp.sh LABEL` CPU per sim process with SimBench running;
  `after.sh LABEL` sim reboot + idle CPU + launch; `cpu.sh`; `crashrate.sh [s]`.
- `flutter/run.sh` + `flutter/main.dart`: Flutter frame timings (FrameTiming) and timed hot reloads on the booted sim.
- `split.swift` submit latency / VRAM vs IOSurface / ALU split per GPU (`W=`, `H=` for the surface size).
- `xgpu.swift` render-on-one-GPU / sample-on-the-890M IOSurface A/B (`NVMTL_GPU=nvidia` for the RTX).
- `lib.swift`, `astc.swift`, `tew.swift`: compute pipelines from MTLSimDriver's `default.metallib`
  (copy it from the runtime's `MTLSimDriver.framework`); `DYLD_LIBRARY_PATH=<dir with a translator build>` tests a
  translator build without installing it.
- `airdis.c` (AIR bitcode -> text with the plugin's own libLLVM, no llvm-dis here), `spvdump.py` (SPIR-V lister).
