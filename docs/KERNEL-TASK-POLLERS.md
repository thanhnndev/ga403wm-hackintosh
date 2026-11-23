# kernel_task under the working load: who polls, and the fixes (2026-11-23)

Question from main: kernel_task uses ~20 % of a core with no compression, and our polling threads stop idle cores
from sleeping deeply. Break it down per thread and per owning kext. This builds on `ga403wm-hackintosh/docs/POWER-FLOOR.md`
section 4 (source review, 11-16) and does not redo it.

## 1. Live state, 15:24-15:40 (read-only, no root)

- **Load:** two Android emulators (qemu 97 % + 96 %), Docker (hyperkit 12.7 %, backend and helpers ~28 %), Edge video,
  the Claude app. kernel_task **19.5 %** (top, 15 s).
- **Wi-Fi traffic:** 144 RX + 51 TX frames/s (itlmt counters, 20 s).
- **ItlXhciKick** (`itlz0`, uptime 3179 s): c1 and c2 (these have devices) were kicked 2,902,270 times each, which is
  913/s. c0 and c3 (empty) were kicked 57/s. Total **1,940 work-loop wakeups/s**, plus 1,000 timer wakeups/s for the
  worker thread.
- **Touchpad:** `-vi2c-force-polling` is still in boot-args. VoodooGPIOAMD is loaded and bound to AMDI0030, so the GPIO
  driver for the touchpad pin is present.
- **Logging:** 306 lines/s in total (60 s). The kernel share is:
  - 30.4 lines/s of `<compose failure [missing precomposed log]>`. 28.8/s of these come from **one kernel thread
    (tid 418)**, in bursts 1-30 ms apart. The sender cannot be named without root; the spindump below names it.
  - IO80211Family 16.3/s, all from the AWDL machinery (`itlmt_awdl=1`).
  - Our kexts' named lines: ~0.

The per-thread CPU split of kernel_task needs root. One command, about 30 s, read-only:
```
sudo ~/develop/projects/ga403wm-power/tools/kt-probe.sh 30
```
It records `ps -M -p 0` before and after, plus powermetrics (tasks + interrupts) and a spindump of kernel_task at
10 ms. The output goes to `/var/tmp/kt/`, chowned to the owner. The spindump names each thread's kext, so it gives the
CPU % column below and names tid 418.

## 2. Pollers, ranked (estimates until kt-probe runs)

| # | Poller | Rate now | Est. CPU | Why it polls | What Linux does | Fix | Owner |
|---|---|---|---|---|---|---|---|
| 1 | **VoodooI2C touchpad** (`-vi2c-force-polling`) | ~10k I2C controller IRQs/s on CPU 0 (11-08) | 5-8 % of a core, all on CPU 0 | the boot-arg makes VoodooI2CHID read the touchpad on a timer instead of on its GpioInt | i2c-hid, GpioInt level-low via pinctrl-amd, threaded IRQ: 0 IRQs while idle | One test boot without `-vi2c-force-polling`. VoodooGPIOAMD is already bound to AMDI0030. If the touchpad works in interrupt mode, the cost goes to ~0 at rest. If it does not, the work is in VoodooGPIOAMD's AMD pin handling (third party). | boot-arg: main; code: third party |
| 2 | **Wi-Fi m3 RX/TX pump** (`itlmt7925_m3.cpp:2789-2792`) | at 144 frames/s the 50 ms "keep polling" window is always re-armed, so the loop runs `IODelay(200)` passes at ~4-5k/s, each pass doing ring MMIO reads | 3-6 % | there is no interrupt: the driver registers no MSI and runs fully polled | mt7925e: MSI, then NAPI (mask IRQ, poll up to budget 64, unmask); 0 CPU when quiet | Short term: `IOSleep(1)` after one empty pass instead of the 50 ms `IODelay(200)` window (throughput has to be re-measured; baseline 29-36 MB/s). Real fix: WFDMA MSI and an interrupt event source that wakes the loop (the NAPI model). | Wi-Fi session (repo was edited today; not touched here) |
| 3 | **ItlXhciKick** | 1,940 work-loop wakeups/s + 1,000 timer wakeups/s | 1-2 % plus IPIs | Strix xHCI has one MSI vector. Apple's driver puts transfer events on interrupter 1, which never raises it, so ring 1 has to be drained by kicking the event source. | xhci puts every event on interrupter 0, so one vector is enough and there is no poll | **Done on a branch (section 3):** kick only when ring 1/2 has an event queued; back off to 4 ms after 1 s quiet | ours (this session) |
| 4 | **NMXAMDFB software VBL** | 120/s, never stops | < 1 % (also keeps PSR out) | IOFramebuffer VBL emulation | DRM vblank IRQ, disabled after a few idle frames (then PSR) | `patches/power-floor/nmx-fb-vbl-gate.patch` (exists, not built) | main (NMXGPU) |
| 5 | **NMXGPU work threads** (linuxkpi irq wq, gfx ring, ttm) | ~per frame (~1.6k/s at 11-08's load) | follows frames | real GPU work | the same | none at idle; this cost belongs to the per-frame WS work | main |
| 6 | **Kernel logging, tid 418** | 28.8 lines/s | < 0.5 % | unknown kext (named by kt-probe) | n/a | Rate-limit or drop the line once it is named | owner of that kext |
| 7 | **AWDL** (`itlmt_awdl=1`) | 16 IO80211 lines/s, sync/election every ~1 s, ~1.8 ROC windows/s | < 0.5 % CPU; radio time | AirDrop/Continuity discovery | n/a | Owner's choice: AWDL off when AirDrop is not used | Wi-Fi session / owner |
| 8 | StrixDgpuGate poll 1 s, 250 ms heartbeat for 20 s after an event; AsusWmi, AmdCppc, BtLeDlFix, MtkBtFw | ≤ 1-4/s | ~0 | | | none needed | |
| 9 | RyzenHV | only while a VM runs; exit handling is charged to the hyperkit vCPU threads, not to kernel_task | 0 in kernel_task | | | see `rhv-wt-exits/docs/RYZENHV-EXITS.md` | |
| 10 | Audio (SimpleHDA, rogaudiod) | IOAudioEngine buffer interrupts while playing; rogaudiod is a user process | small | | | none | |

Expected total: rows 1-3 are ~10-15 % of the 20 %. Removing them also lets CPU 0 and the Wi-Fi/kick cores sit in HLT
undisturbed, which is the precondition for any CC6 gain (POWER-FLOOR #5).

## 3. Started: ItlXhciKick 0.2.0 (branch `thermal/xhcikick-pending` in ga403wm-hackintosh, 60548a7)

- Before each kick, the worker reads interrupter 1 and 2's ERDP (BAR0, read only) and the cycle bit of the event TRB
  it points at (the event ring is mapped read only from the ERST).
  - That TRB is the consumer's, i.e. an event is waiting, when its cycle bit equals the consumer cycle state.
  - The consumer cycle state is the cycle bit of the TRB just before it, inverted when the dequeue pointer sits at
    the ring's start.
  - The work loop is signalled only then. Nothing in the controller or in Apple's driver is written.
- **Safety net:** a forced kick still runs every 16 periods (`itlkickidle`). A wrong "nothing pending" therefore costs
  at most 16 ms (64 ms during backoff), never the old 2 s. If a forced kick drains something that was not seen as
  pending, it is counted as `m<n>` in `itlz0` (an upper bound).
- **Backoff:** after 1 s with nothing pending on any controller, the worker sleeps 4 ms. It goes back to 1 ms on the
  first event.
- **Expected saving:**
  - at rest (no typing, no USB/BT traffic): 1,940 to ~180 work-loop wakeups/s, and 1,000 to 250 timer wakeups/s;
  - while typing or using a BT mouse: wakeups only per event.
- **Boot-args:** `itlkickpend=0` gives the 0.1.x behaviour; `itlkickslow=1` turns the backoff off. Both names were
  grepped against every kext in the ESP and /Library/Extensions: no other user.
- **Built:** UUID 3A784B45-0FFC-3FC9-A737-C68BCE8D6A9F, md5 8ac8af01be0a36b39a0ef9a52a68f738, no warnings. **Not
  installed.**
- **Verify after install:**
  - `ioreg -r -c ItlXhciKick -l | grep itlz0`: `s` (skips) grows at ~900/s per busy controller, `u` (unknown) stays 0,
    `m` (misses) stays near 0;
  - key-up while typing is instant (no stuck key);
  - the BT mouse is smooth;
  - kt-probe shows the xHCI work loops at ~0 when idle.

## 4. Docker after the owner's restart (15:24, read-only check)

- **VM disk:** `initial fsck`, `recovering journal`, done in 56 ms. ext4 mounted r/w cleanly.
- **Postgres:**
  - 15:19 start: `redo starts/done` at the same LSN, i.e. crash recovery after the killed orphan, with nothing to
    replay;
  - 15:21: clean shutdown checkpoint;
  - 15:24: clean start, no recovery.
- **Valkey:** loaded its RDB cleanly (0 keys).
- **Not recovery related:** `object-storage-1` is in a restart loop (11 restarts). Its log says
  "MINIO_LICENSE_B64 is required for AIStor": the project's compose file uses the AIStor image without a licence
  variable. This is the owner's config.
