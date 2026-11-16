# Local video suite (no YouTube, no ads, no network)

Repeatable video playback tests for the 890M path: local clips made on this machine, a localhost page that reports
per-second playback metrics, and a runner that samples power, temperature, CPU and the NMXGPU counters at the same
time. Built to replace `tools/890m/yt-probe/run-max.sh` (YouTube: ads and network stalls made the same build give 0 to
142 dropped frames per 60 s). Plan: `docs/VIDEO-SUITE-PLAN.md`. First baseline: `docs/VIDEO-SUITE-BASELINE.md`.

## Run

```bash
node tools/890m/video-suite/gen.mjs core          # once: makes the core clips (about 15 min, CPU heavy)
tools/890m/video-suite/run.sh list                # cases; [core] marks the core set, TODO marks stubs
tools/890m/video-suite/run.sh core out-29 3       # core set, 3 rounds (about 40 min)
tools/890m/video-suite/run.sh vp9-1080p60-max out-29
tools/890m/video-suite/compare.sh results/out-29-A results/out-30-B
```

- Needs only node (24+, built-in `fetch`/`WebSocket`), Google Chrome and `swiftc`. No npm packages, no root.
- Chrome runs with a scratch profile (`--user-data-dir` under the clip cache). The owner's profile is never touched,
  and cleanup kills only processes with that exact profile path. Never Edge.
- Refuses to run on battery (power limits differ) unless `VS_ALLOW_BATTERY=1`.
- Every case brings its window to the front for about 80 s (115 s for the seek/pause case); fullscreen takes over the
  screen. Do not use the machine during a run, or the run records it (see "hidden s" / "unfocused s").

## Pieces

| file | what |
|---|---|
| `gen.mjs`, `gen/gen.html`, `gen/content.js` | VP9/AV1 clips: content drawn on a canvas, encoded with WebCodecs `VideoEncoder` (realtime, VBR) in headless scratch Chrome, muxed by `lib/webm.mjs` (EBML, Clusters per keyframe every 2 s, Cues, so seeking works) |
| `gen/genmp4.swift` | H.264/HEVC clips with AVAssetWriter (VideoToolbox, software encoders here), same layout drawn with CoreGraphics |
| clip cache | `~/Library/Caches/ga403wm-video-suite/clips/` (outside git, shared by all worktrees; `VS_CLIPS` overrides) with `manifest.json`: codec, size, fps, target and average bitrate, frames, keyframes, sha256, encoder, Chrome version |
| `lib/server.mjs` | 127.0.0.1 server: pages, clips with HTTP Range, `POST /report` from the page, `POST /gen/*` from the generator |
| `pages/play.html`, `pages/suite.js` | plays `?clip=`, runs the scenario (`plain` or `seekpause`), posts one row per second |
| `drive.mjs` | one case: sampler + scratch Chrome over CDP (window mode, fullscreen, decoder name) + page reports; writes `<case>.tsv` and `<case>.json` |
| `run.sh` | case list / core set / rounds, `context.txt`, `table.md` |
| `table.mjs`, `compare.mjs`, `compare.sh` | per-run table and spread over rounds; per-case diff of two runs |

Content of every clip: moving gradient, 24 moving and rotating shapes, a scrolling text panel, two grain layers at
co-prime tile sizes with per-frame offsets (so the encoder must spend the bitrate, like real footage), a large frame
counter and `t=` time (top left) and a 16-bit frame index strip (bottom left) for screen captures. Same frame index
gives the same pixels. 90 s per clip; the first 10 s are warm-up.

## Cases

| case | what | window |
|---|---|---|
| `idle` | 30 s, no scratch Chrome: the reference for "W over idle" | - |
| `vp9-1080p60-win` | VP9 1080p60 | 1280x800 window |
| `vp9-1080p60-max` | VP9 1080p60 (the case traced in trace parts 35-42) | maximised (zoomed, not fullscreen) |
| `vp9-1080p60-fs` | VP9 1080p60 | element fullscreen of the `<video>` (own Space) |
| `av1-1080p60-max` | AV1 1080p60 | maximised |
| `h264-1080p30-win` | H.264 1080p30 | 1280x800 window |
| `vp9-seekpause` | 10 s warm-up, 10 s play, seek to 40 s, 5 s play, 70 s pause (longer than the 60 s IOSurface park), resume, 20 s play | maximised |
| `vp9-2160p60-max` | VP9 4K60 scaled to the panel | maximised |

Plain cases: 10 s warm-up, then a 60 s measured window. TODO stubs (listed by `run.sh list`): PiP, AV1 4K60, H.264
1080p60, HEVC, MSE with a quality switch, scroll while playing, two videos, Safari and QuickTime (both wait for the
owner's answers on Safari history and the AppleScript Automation prompt), and "under Docker" (the suite never starts
or stops Docker; every run records whether it was running and how much CPU it used).

## Metrics (table.md columns)

Page side (one row per second, from the page itself):
- **decoded / dropped**: `getVideoPlaybackQuality()` deltas over the window. Dropped = frames Chrome decoded but did
  not show (late for their vsync).
- **skipped**: gaps in the presented `mediaTime` between consecutive `requestVideoFrameCallback` callbacks: frames the
  viewer never saw, whatever the reason. Usually equals dropped; it is the visual truth.
- **iv p95 / p99 / max (ms)**: intervals between `expectedDisplayTime` of consecutive presented frames. At 60 fps on
  the 120 Hz panel the ideal is 16.67 ms; 25 / 33 ms means a frame stayed up one or two extra vsyncs.
- **late**: count of intervals longer than 1.5 frame periods (judder events, including the ones around a drop).
- **hidden s / unfocused s**: seconds the page was not visible / its window not focused. A run with hidden seconds is
  disturbed and should be repeated.
- **decoder**: from CDP `Media` events. `VideoToolbox` = platform decoder (VCNDec on this machine for VP9/AV1, the
  hardware VT decoder for H.264); `Vpx`, `Dav1d`, `Ffmpeg` = software, shown as `(SW)`.

Runner side (sampled once a second, aligned to the page rows by wall time; averaged over the window):
- **pkg W**: package power from the RAPL energy counter in `debug.amdcppc.sensors` (energy delta / time, no root).
  **W over idle** = case watts minus the same round's `idle` watts.
- **Tctl**: from `debug.amdcppc.sensors`.
- **CPU %** (100 = one core), from `ps` cputime deltas: Chrome GPU process, renderer(s), WindowServer,
  `VTDecoderXPCService`, Docker (Docker.app/com.docker/vfkit/qemu processes), all processes. `kernel_task` from a
  streaming `top -pid 0` (ps cannot see pid 0 without root). The TSV also has the browser process, other Chrome
  helpers, Claude and the owner's other apps.
- **NMX frames/s**: `debug.nmxaccel_pipe_perform` rate (frames the 890M presented).
- **chunks fill/inl/free**: `nmx_page_chunks_filled / _inline / _freed` deltas (Step141c prefill: inline should stay 0).
- **parks/unparks**: `nmx_userwire_parks / _unparks` deltas (Step142b IOSurface park).
- **fails**: sum of `nmx_userwire_unpark_fail`, `nmx_park_fail`, `nmx_upin_restore_fail`, `nmx_timeouts`,
  `nmxaccel_fence_timeouts` deltas. Must be 0.
- The TSV keeps every counter of handoff 5.2 per second (`pages_live`, `page_free`, `page_hwm`, `userwire_pages`,
  `surfwire_pages`, `parked_pages`, ...).

Seek/pause case extra table: drops/skipped/late in the 5 s after resume, package watts while paused, parks/unparks
while paused, unparks in the 5 s after resume.

## Known limits

- Synthetic content. Bitrates match YouTube's (VP9 1080p60 ~8 Mb/s, 4K60 ~25 Mb/s), but real footage may stress
  the decoder differently. No audio track (A/V clock behaviour is not exercised).
- Drops are counted by Chrome and by rVFC; a frame the compositor shows late but rVFC reports on time is invisible
  here. A camera or screen capture with the burned-in counter would be the ground truth.
- 1 s sampling cannot split events closer than a second (e.g. a park burst vs a chunk fill).
- Package power includes everything the owner runs. "W over idle" subtracts the same round's idle, but the background
  load (Docker, Claude, builds) changes between rounds; the TSV records it per second.
- Sampling itself costs ~2-3 % of one core (one `ps` and two `sysctl` per second), in idle and video cases alike.
