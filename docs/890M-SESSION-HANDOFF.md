# 890M port - session handoff (2026-10-18, written ~17:00)

## Latest override — Step50 native display batch installed, reboot pending

New candidate is installed and both UUIDs are in AuxKC:
- NMXGPU `0456558e...`, UUID `7FB0A912-7ECC-3597-B51F-55266CBA4F0C`;
- NMXAccel `63026c11...`, UUID `1043D6C4-4189-3A44-88AE-0C5DD4085A20`;
- plugin v2.3.1 baseline with AMD owned-pipe gate, deployed SHA `d5ad4d06...`.

Source: NMX fork `b5ce9e2` on `ga403wm-nmx`; plugin `2b2620c` on `research/890m-ws-plugin`
(worktree `~/develop/projects/890m-ws-plugin`). Both pushed. Backup:
`/Library/NullMoth/nmx-ws-20261020T023645Z` (both kexts, complete old plugin bundle, allow list and AuxKC).

**Current kernel still build15; WindowServer acceleration is not verified.** Deployed new plugin passes a fresh
unprivileged Metal -> BGRA IOSurface -> CPU pixel check. No WindowServer restart was performed. Policy now has
`!WindowServer`, in addition to the selected GPU's Boolean owned-pipe gate; headroom-hold remains excluded.

After reboot: verify both loaded UUIDs; `sysctl debug.nmxaccel_headless debug.nmxaccel_armed
 debug.nmxaccel_iop_ok debug.nmxaccel_iop_fail`; inspect NMXDisplayPipeArmed/NMXDisplayBindError and WindowServer
Metal/renderer plus family prepare/transaction logs. Registration alone is not GPU rendering proof. The
presentation adapter currently copies RADV's IOSurface to DCN scanout; zero-copy/native flips remain unfinished.
No forced prepare success or fake GPU mapping was added. Preserve the working display and real resource errors.

Build: `scripts/macos-nmx-ws-build.sh <out>` (no fetch/install); its manifest feeds the transactional
`scripts/macos-nmx-ws-install.sh` with administrator auth. The separate early TLB/IPI panic is still open.
See Step50 at the end of `docs/890M-TRACE.md`. No automatic reboot tests are armed.

## Previous verification — Step49, Oct 20 09:18 boot

**Build15 is live**, UUID `304F821C-A6F0-323B-8328-DC580234D3AF`, SHA `c5dea0e0...`.
The formerly failing sequential two-client case is **6/6 correct**. A separate simultaneous-client case
holds VM1 alive while VM2 renders: **6/6 initial triangles + 5/5 VM1 probes correct**, both processes exit 0.
Distinct PD/PASID/VMID3 and VMID4 are confirmed. **No GFX timeout/reset** in the recorded boot/test window.
The b15 IB preparation hook executes (38 logged submissions). See final Step49 in `docs/890M-TRACE.md`.
Do not rerun build14 stress or request another reboot for this result. This is a bounded regression pass,
not a declaration of complete graphics reliability or fixed WindowServer CPU.

The intervening Linux Step47/48 notes record an early TLB/IPI panic and a one-time stale attach-guard clear.
This boot successfully attached after that recovery, but the early panic's cause is still unresolved. Preserve
those notes and investigate attach/interrupt safety before calling general stability or widening WS exposure.

Next milestone: NMXAccel still forces headless in its start path. Bind its display pipe/resources and
presentation to native AMD OLED scan-out before granting WindowServer Metal access. Preserve the current
working framebuffer; no StrixGOP re-enable or allow-list shortcut. No new kext was installed this turn.

## Previous installation batch — Step46

This block supersedes the older live/install and next-step sections below. Read Step46 at the end of
`docs/890M-TRACE.md` first. Current macOS is **26.7.1 / 25G241**. NMXGPU owns DCN35 OLED scan-out
2880x1800 @120; NMXAccel remains headless and the NVMTL allow list remains rung 1. StrixGOP/StrixAccel
are not loaded in this boot. VBIOS acquisition succeeds through VFCT; PCI `vbios` fallback was not exercised.

Loaded/installed before the new batch: SHA256 `b5b573db11bc52ffd5791bffc0efaefdef93b4f64f8af0943adc169132648958`,
UUID `80D4A3FF-1840-3AF3-8219-1E007B0CEB11` (build14). One new two-VM check: VM1 3/3 correct,
VM2 first frame fails. Do not repeat build14 stress. Its flush/dump hook is dead: scheduler clears `job->vm`
before that hook; it also fails to mask canonical VAs. Build14 therefore never tested actual user-IB flushing.

Build15 moves GFX IB preparation into the reserved CS path, checks VA/BO bounds, flushes IB lines and owns a
96-dword first-IB snapshot for timeout reporting. It also fixes ordered patch replay and stale-object builds.
The old build pipeline could silently reinsert obsolete patch hunks and link a failed compile's old object;
**reject `03d85486`**, the first failed attempt. Use only the verified full rebuild recorded in Step46.
**Installed and AuxKC rebuilt:** build15 SHA256
`c5dea0e09c96981cd186036831c6dd03ad3f81087156eea7820c1d5d198c61ee`, UUID
`304F821C-A6F0-323B-8328-DC580234D3AF`, fork commit `05562f5` pushed. Full build: runtime 76/76,
driver 900/900, failure 0. Installed file hash matches; new UUID occurs in AuxKC. Backup of the running build:
`/Library/NullMoth/nmxgpu-step46-20261019T143851Z/NMXGPU.kext`. **Reboot pending; live kernel still build14.**

No new automatic reboot tests are armed. After booting the verified build15: compare loaded UUID to its manifest,
then one bounded pair of processes (3 renders each), capturing `ibprep b15` and `ibsnapshot b15` if it fails.
If it still hangs, decode the owned PM4 snapshot and the context transition rather than adding another blind
ring/wptr flush. Do not open WindowServer's allow list until graphics jobs are reliable.

REA MCP is connected, but deep providers are unavailable (no Ghidra/Java, Hopper, IDA or Kuna configured).
Mach-O identity inspection succeeded; focused assembly came from the existing llvm-objdump. No installations.

Read this first, then `docs/890M-TRACE.md` (Step33c .. Step39b are the live log) and `docs/NULLMOTH-2.3.6-LESSONS.md`.
Everything described here is committed and pushed (repo branch `research/890m-cobalt64`; fork branch `ga403wm-nmx`),
except what section 3 lists as "not yet installed / not yet built".

## 0. The owner, the goal, the rules

Owner: thanhnndev (Vietnamese; reply in Vietnamese, code/comments/commits in English). Machine: ASUS GA403WM Hackintosh,
macOS 26.7.1 Tahoe, Radeon 890M (1002:150e, GC 11.5.0), OLED panel, OLED-only is the primary case.

**Goal (their words, repeated with anger): fix the WindowServer high CPU first.** WindowServer sits at 400-950% CPU
because it has no usable Metal device. `sample WindowServer` shows `CA::OGL::SW::image_sampler / scan_convert / scanline`:
CoreAnimation's SOFTWARE rasteriser. The only real cure is a GPU that runs graphics jobs reliably and a Metal device
that WindowServer is allowed to use. Do not drift into side issues ("mấy cái râu ria") and do not propose CPU
mitigations as the end state (memory: full-port-not-workarounds). They said it hurts the machine; keep it short.

Standing rules the owner enforces (all are in `~/.claude/projects/-Users-thanhnndev-develop-projects-ga403wm-hackintosh/memory/`):
- **Batch changes per reboot.** Never ask for a reboot to test one fix. Every reboot must carry all pending fixes plus
  trace/diagnostics for every open question. Do not tell the owner to reboot until the batch is substantial.
- **Never wait for builds.** Start builds in the background and do other work; no idle monitor loops.
- **Terminal discipline.** Anything slow goes in `run_in_background: true`; never `sleep` in a foreground call; macOS has
  no `timeout(1)` (use `perl -e 'alarm N; exec @ARGV' cmd`); GPU test binaries can block until the kernel job timeout
  (~18 s + GPU reset), so run them one at a time, bounded, in the background. A stuck foreground call blocks everything
  and the owner was angry about it twice.
- Commit + push every finished batch with clear trace in `docs/890M-TRACE.md` (memory: commit-push-after-work).
  Commit trailer: `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`. `git pull --rebase --autostash` first.
- Root steps: run them yourself with `osascript -e 'do shell script "..." with administrator privileges'`; the owner types
  the password in the dialog. Put multi-line scripts in a file (scratchpad, not /tmp: /tmp is wiped at reboot).
- Ask before: `pmset -a displaysleep 0` (never changed so far), installing NullMoth 2.3.6, any download, any security
  setting. Never add `strix-headroom-hold` (or anything that draws) to the NVMTL allow list. Never kill WindowServer.
- Public repo hygiene: no PolyForm-licensed NullMoth code copied into the BSD repo (the fork `nmx-src-2.0.4` is where
  NullMoth-derived code lives).
- Shell is fish; use `bash -c` / heredocs for anything with globs or `$()` subtleties. `dmesg` needs root: read kernel
  logs with `/usr/bin/log show --start "YYYY-MM-DD HH:MM:SS" --predicate 'senderImagePath CONTAINS "NMXGPU"'`.

## 1. Architecture in one screen

- **NMXGPU** = Linux 6.14 amdgpu running on xnu through the FreeBSD drm-kmod + LinuxKPI ("xkpi") compatibility layer.
  We build it ourselves (route B) from NullMoth v2.0.4 sources; NullMoth 2.3.x ships no NMX any more.
- **NMXAccel** is headless (compute/Metal only, no WindowServer acceleration). NVMTLDriver (from the NullMoth 2.3.1
  userland we have installed) talks Metal -> RADV (`/Library/GPUBundles/nvmtl/libvulkan_radeon.dylib`) -> libdrm_amdgpu
  -> libdrm.2 -> `/dev/dri/renderD128` (our cdev).
- xnu cannot `mmap` a kext cdev (ENODEV): the kernel offers an NMX ioctl 'N' 0x40, libdrm exports
  `drmNmxMmap/drmNmxMunmap`, and two scripts patch libdrm and RADV to use them
  (`scripts/macos-nvmtl-libdrm-minor-patch.sh` v2, `scripts/macos-nvmtl-radv-nmxmap-patch.sh`; both have `--undo`).
- NVMTL allow list `/Library/GPUBundles/nvmtl-allow.txt` is on **rung 1**: only processes named
  `mtlprobe` / `nvmtltest` / `nvmtlrender` get the Metal device (scan stops at the first deciding line; `-Name` denies;
  `!Name` is NOT a deny). Test binaries must be run as copies named `nvmtltest` (`/tmp/nvd/bin/nvmtltest`; recreate it
  after every reboot: `mkdir -p /tmp/nvd/bin && cp tools/890m/build/<tool> /tmp/nvd/bin/nvmtltest`).
- StrixAccel 0.1.21 + StrixGOP 0.1.11 (the OLED display path) are separate kexts and are loaded and fine.
- Kernel time: `uptime_ns()` in `bsdcompat/src/nmx_time.c` is calibrated to user `CLOCK_MONOTONIC`
  (= calendar time - kern.boottime, which trails mach_continuous_time by ~0.42 s). Do not "simplify" it back.
- Locking: `sched_pin` only counts (td_pinned); `critical_enter` still disables interrupts (per-thread nesting). The old
  behaviour (sched_pin = interrupts off) caused TLB-flush panics when the MES reset polled for 2 s. A GPU hang now ends
  in a MODE2 reset ("GPU reset(N) succeeded!") with no panic.

## 2. Where things live

| What | Path |
|---|---|
| Repo (docs, scripts, tools) | `~/develop/projects/ga403wm-hackintosh`, branch `research/890m-cobalt64` |
| Port source (fork) | `~/develop/projects/nmx-src-2.0.4`, branch `ga403wm-nmx`, remote `fork`; port in `gpu-port/xkpi` |
| Build tree | `~/develop/projects/gpu-src` (`xkpi` is a symlink to the fork's `gpu-port/xkpi`; `drm-kmod` and `freebsd-src` are vendored, untracked) |
| Patches against vendored drm-kmod | `gpu-port/xkpi/patches/*.patch`, applied idempotently at the start of `all.sh` (`patch -N`) |
| Built kext | `~/develop/projects/gpu-src/out/NMXGPU.kext` |
| Installer / undo | `scripts/macos-nmxgpu-own-install.sh <kext>` / `--undo` (backup in `/Library/NullMoth/nmxgpu-backup`) |
| Test tools | `tools/890m/` (sources) and `tools/890m/build/` (gitignored binaries) |
| NullMoth 2.3.6 (downloaded, NOT installed) | `~/efi-audit/upgrade-2.3.6/{dl,pkg}`; lessons in `docs/NULLMOTH-2.3.6-LESSONS.md` |

Tools in `tools/890m/`: `amdgpu-smoke` (raw GFX IB; argv[2]=heap mask, argv[3]=BO size), `metal-compute.swift` (1M floats),
`metal-render.swift` (offscreen triangle, polled, never blocks), `syncobj-wait.c` (500 ms wait with three clock bases),
`pciinfo-shim.c` (DYLD interpose, `SHIM_TRACE=1/2` traces ioctl/mmap), `vk-compute-min.c`, `drm-open.c`, `drm-devices`,
`macho_lite.py`, `kext_relocscan.py`, `render-stress.sh [N]` (N bounded renders then the kernel's ipdump lines).

### Build / install recipe

```bash
cd ~/develop/projects/gpu-src/xkpi && (bash rt.sh && bash all.sh 30 && AMD_ONLY=1 bash kext/build.sh ~/develop/projects/gpu-src/out) > ~/develop/projects/gpu-src/buildN.log 2>&1 &
# result: last line "NMXGPU <sha8> <bytes> B". CHECK the log for "failed: 0" on the "sources:" line.
```

Trap: a source that fails to compile still yields a kext built from stale objects (this happened: ae7202bd lacked the
dump). Always `grep "failed" buildN.log` and `strings -a .../NMXGPU | grep "NullMoth ipdump"`-style checks for the code you added.
Heredoc trap: when generating C/patch text with python from a shell heredoc, use a QUOTED heredoc (`<<'EOF'`) or `\n`
turns into real newlines / gets eaten.

Install: `osascript -e 'do shell script "bash <repo>/scripts/macos-nmxgpu-own-install.sh <kext> 2>&1" with administrator privileges'`
(rebuilds the AuxKC; the kext loads at the NEXT BOOT). Undo: same with `--undo`.

## 3. State right now (17:00, before the owner's reboot)

- **Live (loaded in the running kernel): NMXGPU `12bf55a8`** = own build with sched_pin fix, per-thread critical sections,
  mmap PAGE_MASK fix, calibrated CLOCK_MONOTONIC, readable IP-state dump on job timeout, display-sleep/setPowerState timing.
- **INSTALLED on disk (loads at next boot): `2f79cc2f` = build 7, the full diagnostic batch (verified strings: STALE fence read, fence fallback on, ipdump, display power timing). Installed 2026-10-18 via the installer; AuxKC rebuilt.** Step 0 of section 6 is DONE.
- **Built later but NOT installed:** `6754453b` (build6, adds the `amdgpu_fence_read` clflush + `STALE fence read` log
  only; incomplete, do not install). **Build 7 (`build7.log`) was still running at handoff time**; it adds the full
  diagnostic batch below. If it finished with `failed: 0`, install `~/develop/projects/gpu-src/out/NMXGPU.kext` BEFORE
  the reboot (see section 6 step 0). Check: `tail -3 ~/develop/projects/gpu-src/build7.log`.
- One test process is stuck in kernel exit (`nvmtltest` pid 4188, state `?NE`) plus `render-stress.sh` (pid 4178/4187)
  waiting on it: a consequence of the very bug below. A reboot clears it. Do not kill -9 expecting it to go away.
- The headroom-hold LaunchAgent (`com.thanhnndev.strix.headroomhold`) is unloaded/exiting ("no Metal device") and must
  stay off the allow list.
- Uncommitted at handoff: `tools/890m/render-stress.sh` (perl alarm instead of the missing `timeout`) is being committed
  with this document.

### Verified facts since Step33d

1. `syncobj-wait`: wait with a `CLOCK_MONOTONIC` deadline now returns after ~502-510 ms (was 78 ms; the early ETIME was why
   NVMTL reported "GPU event segment submission failed"). Do not build deadlines on other clocks.
2. `metal-compute` (via NVMTL): all 1,048,576 values correct, ~2.3 ms. `amdgpu-smoke` GFX IB: "GPU wrote it".
3. `metal-render` (graphics job, offscreen 64x64 triangle): **intermittent**. Some runs finish in 1-2 ms with the right
   pixel `[255,128,64,255]`; others hang (NVMTL reports submission failed after ~254 ms), the kernel detects it
   ~18 s later, MES REMOVE_QUEUE fails, MODE2 reset succeeds. Sequence seen: fail, pass, fail, fail.
4. First readable dump at a hang (kext 12bf55a8, `NullMoth ipdump:` lines in the kernel log):
   `ring sdma0 timeout, signaled seq=11, emitted seq=13`; `CP_RB0_RPTR == CP_RB0_WPTR == 0x600`; `CP_BUSY_STAT`,
   `CP_CPC/CPF_BUSY_STAT` = 0; `SDMA0_STATUS_REG` idle bit set; `UTCL1_*_XNACK` = 0 (no page fault); after that
   `Fence fallback timer expired on ring sdma0/gfx_0.0.0` every 0.5 s (52 times in 90 s) and the process cannot exit.
   **The engines are done and idle; the CPU does not see the completion.**
5. `Fence fallback timer expired` is printed only when `amdgpu_fence_process` saw `seq != last_seq`, i.e. fences DO
   advance but only because the 0.5 s timer polled, not because the completion interrupt processed them.

### Two live hypotheses (build 7 tests both in one boot)

- **H1 stale CPU cache**: the fence/writeback page is written by the GPU through system memory, the port keeps kernel
  mappings write-back (it cannot change the cache type of an existing kernel mapping; `nmx_page.c` pmap_change_attr is a
  no-op; user mappings do honour the cache mode via `nmx_umap_insert`), so a cached line hides the GPU write until eviction.
  Explains the pass/fail lottery.
- **H2 lost/late interrupts**: EOP/IH interrupts are not delivered or not dispatched, fences only complete through the
  fallback timer. Explains "fallback timer expired" and the 254 ms vs 18 s timing.
- (H3, ring contents not visible to the GPU, is weakly disfavoured: RPTR==WPTR shows the CP consumed the ring.)

## 4. What build 7 contains (all in `gpu-port/xkpi`, committed)

- `patches/amdgpu-timeout-ipdump.patch`: `amdgpu_coredump()` stub prints every IP block's captured registers as
  `NullMoth ipdump: <reg> <value>` (custom `printfn`, because the port's printf has no `%pV`).
- `patches/amdgpu-fence-read-flush.patch`: `amdgpu_fence_read` reads, `clflush`es the line, reads again and returns the
  post-flush value; logs `NullMoth: STALE fence read on <ring>: cached X, memory Y` (first 40).
- `patches/amdgpu-fence-irq-diag.patch`: global `nmx_irq_dispatched` (incremented in `amdgpu_irq_dispatch`); the fence
  fallback timer logs `NullMoth: fence fallback on <ring>: last_seq A -> B, sync_seq S, irqs so far N` (first 60);
  `amdgpu_ring_commit` flushes the just-written ring dwords before the doorbell.
- `override/src/nmx_fb_bridge.c` + `xnu/nmx_kext.cpp`: `NullMoth display: power on|off begin/done ... in N ms` and
  `NullMoth GPU: setPowerState(n) begin` / `suspend|resume returned E in N ms` (for the display-sleep hang, section 5).

## 5. Open items, in priority order

1. **Graphics job reliability** (this is the WindowServer-CPU blocker). Decide H1 vs H2 from the log (section 6).
   Likely lasting fixes: H1 -> map writeback/fence pages uncached on the kernel side (xnu_map_phys mode) or flush at the
   fence-process points instead of per read; H2 -> check MSI/IH ring setup, `nmx_irq_dispatched` flat while jobs run,
   interrupt routing/doorbell for the IH ring, EOP irq enable state.
2. **Non-headless accelerator so WindowServer uses the GPU.** Not started. NMXAccel is headless; the 2.3.1 userland path
   is NVMTL (Metal for apps). Needs: reliable graphics jobs first, then a presentation/WindowServer path (and a bounded
   present wait, GPU-busy != gone, per `NULLMOTH-2.3.6-LESSONS.md`). Then the allow-list rung can open for WindowServer
   (never before jobs are reliable: a hung WS job = no display).
3. **Display-sleep hang**: on the 23:27 boot the machine hard-hung ~23 s after display sleep (NMXGPU SetState 0/1 slow,
   WindowServer timeout). `setPowerState` runs a full amdgpu suspend synchronously on the PM thread
   (`nmx_port_power`), and `nmx_fb_power` does a DPMS atomic commit. The timing logs in build 7 will show which is slow.
   Do not run `pmset -a displaysleep 0` without asking the owner.
4. Boot guard for NMXGPU (2.3.6 lesson; the installer already clears the existing guard), bound every present wait,
   user-thread record leak, WhateverGreen `gfxrst=4`, own userland build to drop the NVIDIA 2.3.1 dependency (Step 4).
5. NullMoth 2.3.6 install: only with the owner's OK; it overwrites our libdrm/RADV patches and the allow list (a
   re-apply plan with `--undo` must exist first).

## 6. Exact next steps for the next session

0. **Before the owner reboots**: `tail -3 ~/develop/projects/gpu-src/build7.log`. If it shows `NMXGPU <sha> ...` and the
   `sources:` line says `failed: 0`, install it: `strings -a ~/develop/projects/gpu-src/out/NMXGPU.kext/Contents/MacOS/NMXGPU | grep -c "STALE fence read"`
   must be >= 1 (also check `fence fallback on`), then run the installer via osascript. If it is still compiling, wait for
   it in the background (do other work) and install when done; tell the owner when the kext is ready for a reboot.
1. After the reboot: `shasum -a 256 /Library/Extensions/NMXGPU.kext/Contents/MacOS/NMXGPU | cut -c1-8` and
   `kextstat | grep NMXGPU` (loaded). `tools/890m/build/syncobj-wait` must show ~500 ms for MONOTONIC.
2. Recreate the test copy and run ONE bounded background stress: `tools/890m/render-stress.sh 6 > /tmp/render-stress.out 2>&1 &`
   (run it with `run_in_background: true`; it self-bounds each run with a perl alarm and prints the ipdump lines at the end).
3. Read the kernel log for the run (start time = when you launched it):
   `/usr/bin/log show --start "<time>" --predicate 'senderImagePath CONTAINS "NMXGPU"' | grep -E "STALE|fence fallback on|ipdump|timeout,|GPU reset"`.
   Decision table:
   - `STALE fence read` lines present -> **H1**: cached view was stale. Implement the real fix (uncached kernel mapping of
     the wb/fence pages, or flushes at the process points), rerun.
   - No STALE, `irqs so far` flat/zero across the fallback lines while jobs ran -> **H2**: interrupts are not arriving;
     investigate IH ring / MSI delivery in the port.
   - Neither, and all 6 runs pass -> the ring flush (or the clock fix) was enough; keep it, then tighten (remove the
     per-read clflush if proven unnecessary) and move to item 2 of section 5.
   - Neither and still failing -> look at the full `ipdump` of the failing run (GRBM/CP/RB0, SDMA, IH regs) and widen the
     diagnostics, again in ONE batched kext.
4. Whatever the outcome: write the results into `docs/890M-TRACE.md` (Step40), commit, push, update memory
   (`nmx-own-build.md` + the MEMORY.md line), and keep batching.
5. If a boot misbehaves: `scripts/macos-nmxgpu-own-install.sh --undo` restores the backup kext (rebuilds the AuxKC;
   the next boot loads it). Panic logs: `/Library/Logs/DiagnosticReports/Kernel-*.panic`.

## 7. Things that were tried and did NOT work (don't redo)

- `mach_continuous_time` as the kernel clock (2f6fc266): equals mach_absolute_time until the first sleep, not
  CLOCK_MONOTONIC.
- Vulkan symbol interposition (`vk-trace-shim`): the driver resolves functions by dlsym/GetProcAddr.
- Putting the headroom-hold agent on the allow list: it hung the GFX ring and caused the 15:35 panic (pre sched_pin fix).
- A foreground 80-run `amdgpu-smoke` loop (blocked the terminal for minutes) and a script that used the non-existent
  `timeout` (every run "failed").
- Patching `rt.sh`-listed LinuxKPI files by basename works for the port's own overrides only; drm-kmod sources come from
  the Makefile-derived list, so changes to them go through `patches/*.patch`.

## 8. Related memories and docs

Memories: nmx-own-build, nmxgpu-890m-test, full-port-not-workarounds, headroom-hold-fix, batch-changes-per-reboot,
never-wait-for-builds, terminal-usage, commit-push-after-work, root-via-osascript, oled-only-is-primary.
Docs: `docs/890M-TRACE.md` (Step33c-39b), `docs/NULLMOTH-2.3.6-LESSONS.md`, `docs/TAHOE-MIGRATION.md`.
