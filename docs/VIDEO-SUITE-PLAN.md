# Ad-free local video suite: plan

Status 2026-11-16: **plan only**. Two capability checks are built and were run (see "What exists"). The clip generator, server, pages and runner are not built.

Why: YouTube runs aren't repeatable. Pre-roll ads that can't be skipped (25 fps AV1) were measured instead of the video in 2 of 4 runs in trace part 42, the codec and stream change between runs, and network stalls get mixed in with decode or present drops. The owner asked for a suite that covers ordinary users' cases, with no ads.

## What exists

| piece | where | state |
|---|---|---|
| VideoToolbox encoder list | `tools/890m/video-suite/checks/vtlist.swift` | built and run 2026-11-16: H.264 and HEVC (`hevc.vcp`) encoders present, software only (no hardware flag); ProRes too |
| WebCodecs / MSE support check | `tools/890m/video-suite/checks/enccheck.mjs` | run 2026-11-16 in scratch Chrome 157 on a localhost page: VP9 `vp09.00.51.08` 1080p60 + 4K60, AV1 `av01.0.12M.08` 1080p60, `av01.0.13M.08` 4K60, H.264 `avc1.640033` all **supported**. MSE: VP9 WebM, AV1 MP4, AV1 WebM supported. On `about:blank` there is no `VideoEncoder` (not a secure context), so the page must be `http://127.0.0.1` |
| package power | `sysctl debug.amdcppc.sensors` | readable without root: `tctl=… pkg_mw=… rapl=…` |
| YouTube probe and sampler | `tools/890m/yt-probe/` | working; parts reused below |

### Reusable from tools/890m/yt-probe
- `run-max.sh`:
  - scratch Chrome launch (`--user-data-dir` in the output dir, `--remote-debugging-port`, `--disable-gpu-sandbox`, `--autoplay-policy=no-user-gesture-required`, `--start-maximized`) and `pkill -f user-data-dir=…` cleanup;
  - the once-a-second kernel sampler: rec.txt columns `time userrec_made ws_cputime userwire_pages userrec_live pages_live page_chunks page_free chunks_freed parks unparks chunks_filled chunks_inline page_hwm`, with `c()` printing `-` for a sysctl the running kext lacks;
  - the window/averages, chunk-phase, park and prefill awk summaries. Lift these into the suite's runner almost as they are.
- `probe.mjs`:
  - the CDP helpers (`send`, `ev`, page lookup over `/json`);
  - the per-second table (`sec playRate decoded dropped rvfc aheadS readyState`);
  - the pause/resume mode (drops in the 5 s after each resume).
  - The YouTube parts (ad skip, quality menu, `LXb3EKWsInQ`) are dropped.
- `tools/890m/inuse-test/`: native CALayer/IOSurface 60 Hz present test. It is a control case with no browser and no decoder.

## Clips: generated on this machine, no ffmpeg
- **Content:** each frame is drawn on a canvas or with CoreGraphics:
  - moving gradients, rotating shapes and scrolling text, so motion is everywhere;
  - per-frame grain, which keeps the bitrate near what YouTube serves (VP9 1080p60 ~8 Mb/s, 4K60 ~25 Mb/s) so the decoder works as hard as on real video;
  - a large frame counter and a small binary strip, so lost or repeated frames can be read off a capture.
- **VP9 and AV1:** a localhost page in scratch Chrome renders the frames and encodes them with WebCodecs `VideoEncoder` (libvpx / libaom in Chrome). It POSTs the chunks to the node server, which writes WebM through a small hand-written muxer: EBML header, Segment, Info, Tracks, Clusters of SimpleBlocks with a keyframe every 2 s, and Cues so seeking works. An MP4 (fMP4) writer for AV1 is optional, because Chrome's MSE takes AV1 in WebM too.
- **H.264 and HEVC:** a Swift tool draws the same content with CoreGraphics into CVPixelBuffers and writes MP4 with AVAssetWriter, using the software encoders above. These clips also feed Safari and QuickTime.
- **Audio:** none at first. Add an Opus track (WebCodecs `AudioEncoder`) if A/V clock behaviour turns out to matter.
- **Set, 90 s each (the first 10 s are warm-up and not counted):**
  - VP9: 1080p60, 1440p60, 4K60
  - AV1: 1080p60, 4K60
  - H.264: 1080p30, 1080p60
  - HEVC: 1080p60, 4K60
- **Size and time:** about 1.5 GB in all, kept in `tools/890m/video-suite/clips/` (gitignored, never committed). Software encode of 4K60 AV1 may run at a few fps, so it is generated once in the background.

### Downloads that would need the owner's permission
**None are needed.** The checks above show the machine can make every codec itself.

Optional only, if synthetic content is ever judged unrepresentative: a real-footage reference. Blender Foundation open movies (CC BY), for example "Big Buck Bunny" 1080p60 or 4K60 from download.blender.org, are ~350 MB to ~1 GB depending on the file. They are H.264 only and would still need re-encoding to VP9/AV1 with the WebCodecs path. Ask the owner first with the exact file and size.

## Server and pages (tools/890m/video-suite/)
- **Server:** a node server on 127.0.0.1 that serves `clips/` with HTTP Range and receives the pages' reports (POST `/report`).
- **Pages:**
  - `play.html?clip=…`: plain `<video>`, muted autoplay, loop off.
  - `mse.html?clip=…`: fetches ~2 s WebM segments by Cues and appends them like YouTube. One quality switch, 1080 → 1440 → 1080.
  - `scroll.html?clip=…`: a long text page with the video embedded; the runner scrolls it.
  - `two.html?a=…&b=…`: two videos side by side.
- **What every page reports, once a second:**
  - `getVideoPlaybackQuality()` (decoded / dropped);
  - rVFC callback count, and p99 of presented-frame intervals (from `presentedFrames` and `expectedDisplayTime`);
  - `waiting` / `stalled` events, `readyState`, buffered-ahead;
  - window size, fullscreen and PiP state.
  - Because the page reports this itself, Safari needs no CDP.

## Runner
- **Per case:** start what the case needs, wait for the page's first report, sample for 90 s, then stop and clean up. It never touches the owner's profiles: scratch Chrome only, and never Edge.
- **Sampled once a second:**
  - the kernel sampler from `run-max.sh`;
  - WS ms/frame from `ps -o cputime`;
  - CPU % of the Chrome GPU process (child of the scratch browser with `--type=gpu-process`), WindowServer, kernel_task and VTDecoderXPCService;
  - `pkg_mw` and `tctl` from `debug.amdcppc.sensors`.
- **Hardware decode yes/no:**
  - Chrome: CDP `Media.enable` player events give the decoder name. `VideoToolboxVideoDecoder` means VCNDec (VP9/AV1) or VT; `VpxVideoDecoder` / `Dav1dVideoDecoder` means CPU.
  - Safari and QuickTime: count `log show --predicate 'subsystem == "com.ga403wm.vcndec"'` lines in the window, plus VTDecoderXPCService CPU.
- **Chrome control over CDP:**
  - `Browser.setWindowBounds` sets windowed (1280x800), maximised and fullscreen;
  - PiP is `requestPictureInPicture()` evaluated with `userGesture: true`;
  - scrolling is `Input.dispatchMouseEvent` mouseWheel at 60 Hz;
  - seek and pause are page JS.
- **Output:** `tools/890m/video-suite/results/<build>-<yyyymmdd-hhmm>/` with per-case TSVs and `table.md`, one row per case:
  `case | decoded | dropped | p99 interval | WS ms/frame | GPU-proc % | WS % | kernel_task % | pkg W | decoder | chunks filled/inline/freed | min free | parks/unparks`.
- `compare.sh A B` prints two results dirs side by side. `results/` is committed as text; clips are not.

## Cases
| # | case | app | clip | notes |
|---|---|---|---|---|
| 0 | idle desktop, 30 s | - | - | power / WS baseline |
| 1 | windowed | Chrome | VP9 1080p60 | |
| 2 | maximised | Chrome | VP9 1080p60 | the case traced in parts 35-42 |
| 3 | fullscreen | Chrome | VP9 1080p60 | |
| 4 | Picture in Picture | Chrome | VP9 1080p60 | |
| 5 | maximised | Chrome | AV1 1080p60 | |
| 6 | maximised | Chrome | VP9 4K60 | scaled to the panel |
| 7 | maximised | Chrome | AV1 4K60 | |
| 8 | maximised | Chrome | H.264 1080p60 | |
| 9 | maximised | Chrome | HEVC 1080p60 | |
| 10 | MSE stream + quality switch | Chrome | VP9 1080/1440 | YouTube-like append pattern |
| 11 | scroll a long page while playing | Chrome | VP9 1080p60 | compositor + video together |
| 12 | seek, pause 70 s, resume | Chrome | VP9 1080p60 | crosses the 60 s IOSurface park (Step142b); drops in the 5 s after resume |
| 13 | two videos at once | Chrome | VP9 + AV1 1080p60 | |
| 14 | case 2 under Docker load | Chrome | VP9 1080p60 | the owner's daily load |
| 15 | windowed | Safari | H.264, HEVC, VP9 1080p60 | needs the owner's OK (below) |
| 16 | local file | QuickTime | HEVC 4K60, H.264 1080p60 | needs the owner's OK (below) |

- Full pass: ~25 min.
- Quick pass (0, 2, 5, 12): ~6 min.
- Also record the RTX state for each run (Eco or standard), because part 42 ran with the dGPU powered.

## Open questions for the owner (only cases 14-16 wait on them)
1. **Safari** has no scratch-profile flag, so case 15 would open a localhost tab in the owner's Safari (it adds history). OK, or skip Safari?
2. **AppleScript** is needed to press play in QuickTime and to maximise or fullscreen Safari. It pops the macOS Automation permission prompt once. Without it: Safari runs windowed with muted autoplay, and the owner presses play in QuickTime.
3. **Docker for case 14:** does the owner keep Docker running, or may the runner start and stop Docker Desktop?

## Build order
1. Clip generator (WebCodecs page + WebM muxer; Swift AVAssetWriter tool). Check each clip plays in scratch Chrome and that seeking works.
2. Server, pages and runner for cases 0-13, reusing the yt-probe pieces above.
3. First baseline on the live build (out-29 as of 2026-11-16). Write a trace part and commit the results.
4. Cases 14-16 after the owner's answers.
