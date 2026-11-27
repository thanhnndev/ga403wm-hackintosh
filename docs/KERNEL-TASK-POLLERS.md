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
| 3 | **ItlXhciKick** | 1,940 work-loop wakeups/s + 1,000 timer wakeups/s | 1-2 % plus IPIs | Strix xHCI has one MSI vector. Apple's driver puts transfer events on interrupter 1, which never raises it, so ring 1 has to be drained by kicking the event source. | xhci puts every event on interrupter 0, so one vector is enough and there is no poll | **Replaced (section 5):** XHCILagFix rev2 puts control/bulk/interrupt events on interrupter 0, which raises the vector; live 2026-11-27 with ItlXhciKick off (`itlkick=0`). ItlXhciKick 0.2.x is no longer needed if it holds. | ours (this session) |
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

## 5. Live: XHCILagFix rev2 instead of ItlXhciKick (boot 2026-11-27 15:34:11)

- **What:** the issue #9 Lilu plugin (hbyonly1/USBXHCIWakeup, local build only, no licence upstream: never published
  or bundled). It clears the Interrupter Target of control/bulk/interrupt TRBs before Apple links them, and of the slot
  context in `setAddress`, so those events land on interrupter 0, the one that raises the controller's single MSI.
  Isochronous transfers are not routed: their filter timestamp is needed by `IsochRequest::update`.
  Build UUID 987614EA-194A-32B8-8E9E-03CC0C4111EE; audit and test plan in the shared notes (`xhcilagfix-test-plan.md`).
- **Boot:** `itlkick=0`, so ItlXhciKick logged "off" and started no thread.
- **ioreg (main):** Active = Yes; `Rewritten` 11,508; `SetAddressRewritten` 4; every skip reason 0; `MaxTDCapacity` 16
  (well below the 256 limit). Every transfer request was rewritten.
- **Owner:** keyboard and trackpad normal.
- **powermetrics** (interrupts, tasks, cpu_power; 6 x 5 s, owner working;
  `~/ga403-logs/trace-20261127-boot1/powermetrics.txt`):
  - XHC0 19-25 IRQ/s, XHC1 0.4/s: per event, no poll;
  - kernel_task 72-132 ms/s CPU, 3.4-4.2k timer deadlines/s, 4.7-5.8k interrupt wakeups/s;
  - ItlXhciKick's 1,940 work-loop + 1,000 timer wakeups/s (section 1) are gone.
- **Biggest single source now:** I2CA at 10.1k IRQ/s, constant, on CPU 0: the touchpad under `-vi2c-force-polling`
  (row 1). That is the next item.
- **Decision:** if USB input, Bluetooth, webcam and USB storage hold through today's work, retire ItlXhciKick
  (remove the kext and its config entry together with `itlkick=0`). Branch `thermal/xhcikick-pending` (0.2.1) is then
  not needed. Undo for XHCILagFix: `-xhcilagfixoff`, then remove `itlkick=0`.

## 6. Plan: touchpad off forced polling (I2CA, ~10.1k IRQ/s on CPU 0)

Read-only trace on 2026-11-27. Nothing installed, no boot-arg changed.

### Why it polls today
- `-vi2c-force-polling` has been in the boot-args since the first EFI. Nothing records an interrupt-mode attempt on this
  machine (STATE-AND-ROADMAP: "Interrupt mode is not tested").
- VoodooI2C's own docs recommend polling for "buggy GPIO (various ASUS laptops)".
- In polling mode VoodooI2CHID reads the pad on a timer: every 5 ms, 2 ms while busy, 50 ms after 1.5 s quiet. Each
  read is an I2C transfer with many DesignWare controller interrupts, hence I2CA's constant ~10k IRQ/s.

### What the firmware describes (DSDT from OpenCore SysReport)
- `\_SB.I2CA.TPD1`, `_HID` ASUP1208 (by TPID), `_CID` PNP0C50 (I2C-HID).
- `_CRS` returns one template:
  - I2cSerialBus, address 0x15, 400 kHz, `\_SB.I2CA`;
  - **GpioInt (Level, ActiveLow, ExclusiveAndWake, PullUp) pin 8** on `\_SB.GPIO`.
  - There is no APIC `Interrupt()` alternative, so interrupt mode means GPIO mode.
- The GPIO controller AMDI0030 has its own interrupt: IRQ 7, Level, ActiveLow, Shared (registry specifier
  `07000000 07000000`).
- No SSDT is needed: VoodooI2C's resource parser takes the GpioInt as is (pin 8, level-low).

### What Linux does with the same tables
- i2c-hid-acpi binds PNP0C50 and pinctrl-amd provides the irqchip for pin 8 (level-low).
- i2c-hid requests a threaded, oneshot IRQ: the line stays masked until the thread has read the report. pinctrl-amd
  sends the controller EOI (`WAKE_INT_MASTER_REG` bit 29) after each handler.
- At rest there are 0 interrupts; one per report while touching.
- Not verified on this machine's Linux install: check `/proc/interrupts` for the `pinctrl_amd` / ASUP1208 line on the
  Linux fallback if wanted.

### What macOS has
- VoodooGPIO 1.1 (upstream 733dc80, pinned by VoodooI2C v2.9.1) contains VoodooGPIOAMD, a port of pinctrl-amd. It is
  already bound to AMDI0030.
  - At start it clears enable, mask and wake on every pin (`amd_gpio_irq_init`).
  - It registers IRQ 7 only when the first pin is registered, so today, in polling mode, IRQ 7 is not in use at all.
- Without the boot-arg, VoodooI2CDeviceNub picks GPIO mode (pin 8, level-low). VoodooI2CHID then uses an
  IOInterruptEventSource. Because the controller IRQ is level, that event source disables and re-enables the
  interrupt around every report read, and the re-enable re-arms pin 8 (enable, set type, unmask).
- **Known defect 1, the real risk (upstream PR #22, open, 2026-11-22; Ryzen 5800H, AMDI0030, I2C-HID level-low pin 9):**
  - A delivery that arrives while the vector is masked for a read never runs the handler, so no EOI is sent. The
    controller then raises nothing until reboot: the touchpad goes dead with nothing logged.
  - The PR re-sends the EOI in `enableInterrupt()` when bit 29 is clear and no handler shows up within ~1 ms.
  - The author ran 6 min of stress plus an 8 h sleep cycle without a dead pad (unpatched: dead within a minute).
- **Known defect 2, harmless:** `do_amd_gpio_irq_handler(irq)` gets the source index (always 0) as `irq`. So the
  "Disabling spurious GPIO IRQ" branch runs after every serviced pin and writes the pin word back with its low 12
  bits cleared (confirmed in the installed binary at +0x17d8).
  - The next `enableInterrupt()` from the event source restores enable, trigger type and polarity, so it works. Debounce
    is 0 in `_CRS` anyway.
  - Its IOLog is skipped in primary interrupt context, so there is no log spam. Not changed.

### Change (built, local, not installed)
- **VoodooGPIO 1.1 + PR #22 only.** Source `~/develop/projects/vgpio-build/w/voodoogpio-src`, local branch
  `local/ga403wm-eoi` (7eb2f19 on 733dc80). GPL-3.
- Built with Xcode 26.5 against our MacKernelSDK: `~/develop/projects/vgpio-build/out/Release/VoodooGPIO.kext`,
  **UUID 954AEF39-0691-3AD4-B259-126692E0BADD**, md5 f38327da15a93aa8ebacb8863e0016e1.
- Compared with the installed 1.1:
  - exported symbols identical, vtables included, so the ABI towards VoodooI2C 2.9.1 is unchanged;
  - new imports: OSIncrementAtomic and OSDecrementAtomic only;
  - Info.plist identical except the build-machine fields;
  - `kext-undeclared-syms.sh`: ok.
- It adds `PatchVersion` = "eoi-fix-1" and `EoiRecoveries` (the count of swallowed deliveries repaired) to the
  VoodooGPIOAMD registry entry.
- There is no VoodooI2C/VoodooI2CHID change and no SSDT.

### Boot test (main installs)
1. Back up the installed plugin outside the Kexts tree, e.g. `EFI/OC/backup/VoodooGPIO.kext.1.1-733dc80`.
2. Replace `EFI/OC/Kexts/VoodooI2C.kext/Contents/PlugIns/VoodooGPIO.kext` with the build. The config.plist entry is
   unchanged.
3. Remove `-vi2c-force-polling` from boot-args.
4. Batch it with the next package; one boot.

### Undo
- **One arg:** add `-vi2c-force-polling` back. The patched VoodooGPIO is then inert: no pin is registered and IRQ 7
  stays unused, exactly as today.
- **Full:** restore the backed-up 1.1 plugin.
- The touchpad is the fallback input if USB breaks; USB input is fine on XHCILagFix. If the pad dies, USB/BT input
  still works to add the arg back.

### What to measure
- `ioreg -r -n TPD1 -l | egrep "Interrupt Mode|gpioPin|gpioIRQ"` should show `GPIO`, pin 8 and IRQ type 8
  (level-low).
- `ioreg -r -c VoodooGPIOAMD -l | egrep "PatchVersion|EoiRecoveries"` should show `eoi-fix-1`. A count above 0 means a
  dead pad was averted.
- `sudo powermetrics --samplers interrupts,tasks,cpu_power -i 5000 -n 6`, under the same conditions as 15:34:
  - I2CA at rest should be about 0 (was 10.1k/s); while touching, about the report rate times the per-read controller
    IRQs;
  - the new GPIO line (IRQ 7) should be about the report rate while touching and 0 at rest;
  - kernel_task interrupt wake-ups and CPU, and CPU 0 idle residency.
- Feel: pointer smoothness, tap, two-finger scroll, three/four-finger gestures, palm rejection. Check again after
  display sleep/wake and after a few hours of work (the PR #22 failure was time- and load-dependent).
- **Not in this boot:** system sleep. VoodooGPIOAMD now owns IRQ 7, and StrixS0ix arms pin 0 (lid/power button)
  during s0ix halt. A pin 0 interrupt would reach VoodooGPIOAMD's handler, which services it as unowned: it clears
  its status and enable before StrixS0ix reads it. The wake itself still happens, but StrixS0ix may log "no wake
  reason" and skip `_EVT(0)` (the lid/power-button Notify). Check this in an owner-started sleep test, and if needed
  make StrixS0ix latch pin 0's status from its own ISR path or have VoodooGPIOAMD ignore pins without an owner.

### Expected saving
- About 10k IRQ/s off CPU 0 at rest. The 11-08 estimate was 5-8 % of a core and CPU 0 never idling.
- This removes the biggest remaining kernel_task interrupt source after XHCILagFix.
