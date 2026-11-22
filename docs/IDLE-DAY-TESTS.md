# Idle-day tests: WindowServer CPU / frame path / video (side session hungry-mclean)

Boot: the package with plugin 27611e6 and kernel out-44. Conf lines in `/Library/GPUBundles/nvmtl/nvrm610.conf` for
this boot: `NVMTL_DC_CLASSIFY=1`, `NVMTL_SNAP_TIMING=1`, `NVMTL_CHURN_SITES=1`, `NVMTL_PIPE_TIMING=1`. The cost of each
is in WS-CPU 8.9. No cache-ON soak (`NVMTL_XDESCCACHE` stays unset).

Rules: Chrome only (scratch profile), never Edge; no sleep test; nothing woken unless the row says so; the machine
stays as the owner left it. Root steps are batched in `tools/890m/idle-day-root.sh`: main runs it once, right after the
owner leaves, while the display is still on.

| # | Test | Command | Duration | Answers | Root | Display |
|---|---|---|---|---|---|---|
| 1 | Who dirties a static desktop (~30 presents/s with no input) | `sudo tools/890m/idle-day-root.sh` (all-process spindump: which clients commit CA transactions), plus the per-second presents and HID idle it logs | ~25 min (two rounds 10 min apart) | the client(s) behind the steady ~30 fps: Claude apps, the Aerial lock-screen bursts, a widget, or our own VBL/damage path | yes | needs it on; refuses if asleep, wakes nothing |
| 2 | Top-down WindowServer CPU per present | step 1 of the same script (`ws-cpu-profile.sh none 10`), then `tools/890m/ws-spin-buckets.py none.spin.txt <presents from none.cpu.txt>` | in 1 | self time by image (QuartzCore, plugin, translator, RADV recording / descriptors / winsys ioctl, kernel CS / fence / wiring, rest); the top two costs | yes (in 1) | on (in 1) |
| 3 | Static-screen IPS / vblank holder | `tools/890m/ips-static-read.sh 30 90 ~/ga403-logs/idle-day-ips.txt` | 2 min | with nobody touching it: who holds vblank, whether DC may idle, PSR/IPS entries | no | needs it on; read-only |
| 4 | Keep timer vs GTT with the display asleep | every 60 s: `sysctl -n debug.nmx_gtt \| awk '$2=="WindowServer"'` and `sysctl -n debug.nmxaccel_flip_submitted`, from the start until 2 h after the display has slept | hours, passive | WindowServer's `gtt_resident` falls within NVMTL_KEEP_MS + 5 s of the last present (7ceff16 timer) instead of staying ~810 MB | no | passive; reads only |
| 5 | Aerial lock-screen bursts and x420 copies | `/usr/bin/log show --start <boot> --predicate 'process == "WallpaperAgent" AND eventMessage CONTAINS "aerials"'` for start/remove times, against the 30 s "buffer texture" census and WindowServer's gtt line (test 4) | passive, end of day | how often the system-wallpaper video (Sequoia Sunrise, 4K x420) runs while the desktop shows Solar Gradients, and what each burst costs WindowServer. Wallpaper on vs off would be the owner's setting: not changed here | no | passive |
| 6 | Warm pipeline stage timing in WindowServer | `/usr/bin/log show --start <boot> --predicate 'process == "WindowServer" AND eventMessage CONTAINS "pipe timing"'` | passive (from the boot) | translator address-lowering ms per CA specialization in WindowServer (own process: 120-200 ms each, lowered twice; WS-CPU 8.9) | no | passive |
| 7 | Census with the new classes | `/usr/bin/log show --start <boot> --predicate 'process == "WindowServer" AND eventMessage CONTAINS "frame census"'` | passive | WindowServer misses by class, set-path us per present, the VkBuffer/view churn sites idle and with video | no | passive |
| 8 | mediaanalysisd fault watch | at the end: `/usr/bin/log show --start <boot> --predicate '(process == "kernel" AND eventMessage CONTAINS[c] "fault") OR (process == "mediaanalysisd" AND eventMessage CONTAINS "NVMTL")'` | passive, all day | whether the idle-time Vision/Espresso runs (FRAME-PATH row 12) fault on out-44 | no | passive |
| 9 | Video matrix rerun (last) | `tools/890m/yt-probe/run-max.sh ~/ga403-logs/idle-day-yt 60` (scratch Chrome) | ~2 min per run | drops and WindowServer CPU under video on out-44 + 27611e6, with the churn sites of test 7 live | no | uses it: Chrome's video wake lock keeps it on. Run only while it is still on, or leave it for when the owner is back |

Order: run 1-3 at the start (display on), start 4 and leave 5-8 passive, and run 9 last or skip it. Reports go to
docs/WS-CPU.md (9.x) and docs/FRAME-PATH.md.

## Post-reboot checks (first minutes of the out-44 + 27611e6 boot, before the idle-day list)

All are read-only and need no root. Run them with the owner's normal load; none wakes or changes anything.

| # | Check | Command | Pass |
|---|---|---|---|
| P1 | Frame path counters | `tools/890m/out31-verify.sh 30` | its PASS rows as on out-43 (no new FAIL); `flip_timeouts`/`flip_tripped` do not move |
| P2 | Package loaded | `/usr/bin/log show --last boot --predicate 'process == "WindowServer" AND eventMessage CONTAINS "NVMTL"' \| grep -m3 -E "translate: opened\|vk: driver opened"` and `sysctl kern.osversion` | the translator / ICD lines are present (the plugin's own UUID, 6CF3E097, shows in `vmmap` only as root; main can add `sudo vmmap WindowServer \| grep -m1 NVMTLDriver` to its root batch) |
| P3 | Keep entries with the display asleep | test 4 of the list (`sysctl -n debug.nmx_gtt \| awk '$2=="WindowServer"'` every 60 s) | WindowServer `gtt_resident` drops within NVMTL_KEEP_MS + 5 s of the last present, instead of staying ~810 MB |
| P4 | Mesa cache dir leak gone | `ps -axeww -o pid,comm \| grep -c MESA_SHADER_CACHE_DIR` (the owner's processes; apps reopened at login) and `/usr/bin/log show --last boot --predicate 'eventMessage CONTAINS "for shader cache"'` | 0 processes carry the variable; no "Failed to create ... for shader cache (Permission denied)" lines |
| P5 | Pipe timing at WindowServer start | `/usr/bin/log show --last boot --predicate 'process == "WindowServer" AND eventMessage CONTAINS "pipe timing"' \| head -40` | lines exist (the knob reached WindowServer); count and ms per lowering for the cold start (baseline for the 9.2 disk cache in the next package) |
| P6 | Census classes and churn sites | test 7 of the list, the first two "frame census" lines | `classify` counters present; churn sites listed |

If P1 or P4 fails, report before the idle-day list starts.
