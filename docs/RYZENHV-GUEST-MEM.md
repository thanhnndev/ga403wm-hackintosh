# RyzenHV: guest memory and VM exit cost (2026-11-16)

Sub-session report for the main coordinator. Source: `~/develop/projects/ryzen-hypervisor.framework`. The base is branch
`research/ga403wm-zen5` @ 50275d0 (live 0.7.22). The patches are on branch **`research/guest-mem-lazy`** (0.7.23, compile-checked only,
not loaded):

- b7daa2f: step 1, lazy wiring.
- **f1df9fb**: step 2, reclaim of cold chunks. It is off by default and switched at run time. Everything below was measured read-only at about 19:20, on the boot of 18:39. Docker had been restarted at about 18:59 (hyperkit pid 35288).

## 0. Corrections to the handoff

| Handoff says | Measured |
|---|---|
| "RyzenHV wires the whole guest: 12.3 GB" | The Docker guest is **8 GiB** (`hyperkit -m 8192M`, `docker info`: 7.747 GiB), not "no explicit memory limit". Now `zprint -t` shows the RyzenHV tag at **8.03 GB**, and `rhv-info stats` shows `vmPagesMapped` = 2,097,152 = exactly 8 GiB of 4 KiB pages. The 12.3 GB at 18:58 was 8 GiB of Docker plus another Hypervisor.framework VM. Most likely that was the Android emulator (`qemu-system-x86_64` with HVF, listed in STATE.md, not running now), or the orphaned hyperkit from before Docker's restart. Any HVF client's RAM is wired the same way. |
| "~65k exits/s go to HyperKit, ~91k handled in the kernel" | 0.7.22 counters: 148k traps/s return to HyperKit, against 217k exits/s (1.28 VMRUNs per trap). Most exits reach user space. STATE.md's own figure (226k/s to HyperKit) agrees. |
| "Next CPU lever: in-kernel APIC timer/ICR or AVIC" | **Not possible as long as the client is HyperKit** (section 2.2). |
| postgres 217 % "real work or spinning?" | Real work, driven from the host (section 2.4). |

## 1. Memory

### 1.1 The current mapping path (0.7.22)

1. HyperKit calls `hv_vm_map(uva, gpa, size, RWX)` once per RAM segment: low RAM below the PCI hole, and high RAM above 4 GiB.
2. `kext/Source/HvFrontend.cpp: tVmMap` → `mapItem` (copyin) → `com_overlorddev_RyzenHVVmShared::map` (`kext/Source/Vm.cpp`).
3. `map` builds `IOMemoryDescriptor::withAddressRange(uva, size, kIODirectionInOut, task)` over the client's virtual range, calls `kickAll()`, and takes
   the page-table write lock.
4. `mapDescriptorLocked` calls **`md->prepare(kIODirectionInOut)`**. For a task-VA descriptor this is `IOGeneralMemoryDescriptor::wireVirtual`
   → a UPL / `vm_map_wire` of the whole range. It **faults in (zero-fills) and wires every page**, all 8 GiB at VM start, tagged with the kext.
5. `fNpt.mapRange` (`kext/Source/Npt.hpp: Table::mapRange`) walks `getPhysicalSegment` and fills **every 4 KiB leaf eagerly**. That is 2M leaves, about
   16 MB of table pages. There are no large pages: the user pages are physically scattered.
6. A `Backing {md, live}` per map holds the wiring until the last page is unmapped (`dropPage` → `complete`). `unmap`/`protect` change leaves
   under the write lock and bump `fNptGen`, so every vCPU flushes its ASID on the next VMRUN.
7. An NPT fault is never resolved in the kernel. It goes to the client as an EPT violation (exit 48). Only the APIC page and unmapped MMIO fault in practice.

### 1.2 Root cause

The NPT holds host physical addresses. A page the NPT points at must not be paged out, compressed or moved while any guest TLB may
still hold it. xnu gives a third-party kext no notifier for "this page is about to leave": no MMU-notifier equivalent. The simple
correct answer was to wire everything at map time. Nothing ever undoes it while the VM lives, so 8 GiB is wired from guest boot,
whatever the guest uses.

### 1.3 What Apple's Hypervisor.framework does, and why we cannot copy it directly

- xnu exports **`hv_ept_pmap_create(void **ept_pmap, void **eptp)`** to AppleHV only (`config/Private.x86_64.exports`, section "exports
  for AppleHV"; declared in `osfmk/i386/pmap.h`). The x86 pmap knows an EPT flavour: `pm_eptp` beside `pm_cr3`, `is_ept_pmap()`, and the bits
  `INTEL_EPT_READ/WRITE/EX/REF/MOD`, `INTEL_EPT_WB 0x30`. Guest memory is thus an ordinary pmap that the VM system manages. Pageout and
  compression reach the EPT mappings through the normal PV lists, so nothing is wired. AppleHV itself is closed source. How it turns an EPT
  violation into a `vm_fault`, and how EPT TLB invalidation is hooked (`pmap.c` was not read), is **unverified**.
- **The EPT pmap format cannot serve as an AMD nested page table:**
  - EPT bit 2 is X, while NPT bit 2 is US.
  - EPT bits 5:3 hold the memory type. WB = 0x30 sets NPT PCD, so every page would be uncached-minus.
  - EPT has no NX at bit 63.
- **A normal x86 pmap does have the NPT format**: long-mode PTEs, US set on user mappings, NX at bit 63, and hardware-set A/D bits.
  It still cannot be used:
  - There is no KPI for its root (`pm_cr3` is a private struct field: a layout hack, against the owner's rules, and it changes per build).
  - xnu's TLB shootdown only IPIs CPUs that have that pmap live in CR3. Guest ASIDs would never be flushed on pageout, so a guest could write into a
    freed page.
- `hv_callbacks_t` has a `memory_pressure` callback, but **xnu never calls it**, so RyzenHV does not register it:
  - `osfmk/kern/hv_support_kext.c` initialises it as `.memory_pressure = NULL, /* (unused) */`. It is copied by `hv_set_callbacks`, and nothing in
    that file reads it.
  - A GitHub code search for `hv_callbacks` in apple-oss-distributions/xnu returns only `hv_support_kext.c/.h`, `osfmk/i386/pcb.c` (`volatile_state`,
    `preempt`, `dispatch`), `pcb_native.c` (`thread_destroy`) and `machine_task.c` (`task_destroy`). None of them calls `memory_pressure`.
  - Caveat: this covers the public main branch of the open source. The shipping 26.x kernel could differ, but nothing suggests it does.
  - Step 2 therefore runs on its own period, not on a pressure signal.

**Conclusion:** the correct design open to a third-party kext is "the NPT only ever points at wired pages; wire on first touch,
and unwire on our own schedule after removing the NPT entry and flushing". The kext controls both edges, so it needs no notifier.

### 1.4 What the guest actually uses

Guest `/proc/meminfo` (read via `docker exec`, VM-wide):

| | GB |
|---|---|
| MemTotal | 7.75 |
| AnonPages | 1.38 |
| Shmem | 0.20 |
| Slab unreclaimable | 0.16 |
| Active(file) | 0.48 |
| Inactive(file) | 2.28 |
| Slab reclaimable | 1.32 |
| MemFree | 1.83 |
| MemAvailable | 5.60 |

- The hot set is about 2.3-2.8 GB. About 5 GB is cold cache, reclaimable slab or free.
- The containers: pathcan-p0-pg 1.14 GiB, clamav 1.03 GiB, the rest under 0.1 GiB each.
- The guest has 1 GiB of swap, unused. THP is `[always]`, which matches 2 MiB chunks.
- The VM's virtio devices are net, blk ×2, vsock and rng. **There is no virtio-balloon**: HyperKit has no balloon device, so free-page reporting or
  a balloon cannot work without changing HyperKit.

### 1.5 Options, ranked

| # | Option | GB saved (8 GiB guest) | Risk | Effort |
|---|---|---|---|---|
| 0 | **Owner: Docker memory 8 → 6 GB** | 2.0, at once, on 0.7.22 | low (hot set ~2.5 GB, clamav 1 GB) | a setting and a Docker restart |
| 1 | **Lazy wiring on first touch, 2 MiB chunks (0.7.23, done)** | about 5-6 right after the VM starts; it shrinks toward 1-2 as the guest page cache fills RAM (hours of I/O) | medium (new path in VmRun) | done, compile-checked |
| 2 | **Unwire cold chunks** (NPT A-bit aging plus the `memory_pressure` callback) | durable: wired falls to the hot set (~2.5-3.5 GB), so ~4.5-5.5 GB becomes host-reclaimable under pressure | medium | ~1-2 days |
| 3 | Guest cooperation (balloon / free-page reporting) | as for 2, plus free guest pages are reclaimed as zero pages instead of compressed | needs HyperKit changes | not ours |
| 4 | Pageable guest through a real pmap (Apple's way) | everything | high: no KPI, no shootdown for guest ASIDs | no |

**Step 1 (commit b7daa2f, `research/guest-mem-lazy`):**

- `map()` handles a range of 64 MiB or more through `mapLazy`. It records `{gpa, size, uva, perm, task}` in up to 16 slots, and wires and maps only
  the first chunk. That also validates the client's range, as the eager path did.
- An NPF in a lazy range with no leaf (`lazyCandidate`, under the read lock) is not returned to HyperKit. If an event was being delivered, it is
  re-injected. The vCPU loops, and at the top of the loop, with no lock held and interrupts on, it calls `faultIn`:
  1. `withAddressRange` + `prepare` of the 2 MiB chunk, outside the lock. A page-in may sleep there.
  2. The write lock, without `kickAll`: any exit lets it in.
  3. A re-check that the range is unchanged.
  4. `mapDescriptorLocked(..., prepared=true)`.
- There is no `fNptGen` bump and no ASID flush, because only not-present entries become present.
- `unmap` trims or splits lazy ranges (`forgetLazyLocked`). `protect` first wires what is still lazy (`materializeLocked`). The debug `readPhys` fails on
  untouched chunks.
- `rhv_lazymap=0` restores the eager path. That boot-arg is the owner's to set.
- For 8 GiB, at most 4096 first-touch faults happen per VM lifetime.

**Step 2 (commit f1df9fb, written, off by default). The design:**

1. `Npt.hpp` gains `scanClearAccessed(lo, hi)`. The NPT leaf A bit is bit 5, which AMD sets on nested walks.
2. A per-VM `thread_call` runs every 10 s. It clears the A bits of the mapped lazy chunks and bumps `fNptGen` once, so translations re-walk and set A
   again. A chunk whose A bits stay clear for N scans (≥ 60 s) is cold.
3. Eviction runs in batches under the write lock after `kickAll`: `fNpt.unmap` of the chunk's leaves → `dropPage` → `complete()` (unwire), then one
   `fNptGen` bump per batch.
4. The rate is capped by the batch setting (default 256 MiB per scan per VM). There is no pressure trigger: xnu has none for hv (1.3).
5. The unwired pages stay resident until the host needs them. The next guest touch goes through `faultIn` again (a compressor page-in, in ms).
6. Cost: one ASID flush per vCPU per scan period, which is negligible at 13k exits/s per vCPU. A scan reads about 2M NPT entries for 8 GiB:
   a few ms per period, under the read lock, while vCPUs keep running.

What was built:

- One `thread_call` serves all VMs. It runs with the VM registry lock held, so a VM cannot be freed during a scan.
- `Npt::scanAccessed` handles one leaf table per chunk and is covered by `npt_test`.
- Phase 1 holds the read lock and clears the A bits. Phase 2 runs only when there are victims: kick, write lock, unmap, then one `nptGen` bump per batch.
- Each lazy range keeps a byte per chunk: a cold-scan count and an evicted bit. A split range gets its own copy of that array.
- Controls, set as admin and readable by anyone, with no boot-arg and no reboot: `rhv-info hv reclaim [0|1 | period MS | cold N | batch MIB]`. The
  defaults are off, 10000 ms, 6 scans and 256 MiB. They map to HvControl commands 9-12, where value `~0` only reads.
- New counters, stats V5, 43 words (the V4 layout of 0.7.22 is still accepted): `vmLazyFaults`, `vmLazyRefaults`, `vmLazyRefaultCyc`, `vmReclaimScans`,
  `vmReclaimScanned`, `vmReclaimEvicted`. `rhv-info stats` also prints a summary line: MiB wired now, faults, re-faults with µs each, and evicted
  out of scanned chunks.
- `rhv_lazymap=0` turns off both steps, because reclaim only works on lazy ranges.

This is "balloon-less overcommit", the same behaviour Apple's hv gives Docker on Intel Macs.

## 2. VM exit overhead

### 2.1 Exit mix, sampled now

`rhv-info stats`, two samples 10 s apart. The TSC runs at 1.996 GHz.

| | per second |
|---|---|
| exits | 216.8k |
| VMRUNs | 147.7k |
| traps to HyperKit | 147.9k |
| NPT faults (xAPIC MMIO) | 106.6k |
| ASID flushes | 26.8k (13.5 % of VMRUNs) |

- Kernel cost per VMRUN: pre 0.77 µs, post 0.36 µs. Front end per trap: 0.62 µs. In total about **0.26 cores** of kernel exit path.
- Guest+switch: 1.6 cores. hyperkit uses 2.65 cores in all (`top`), so HyperKit userland is about **0.5 cores**, APIC emulation included.
  Load was lighter than STATE.md's run (5.2 cores).
- Guest `/proc/stat` over 5 s: busy 3.0 vCPUs (user 1.54, sys 1.13, softirq 0.31). Exit time counts as guest time, because the TSC runs through.
- Guest totals: 49k interrupts/s and 73k context switches/s. Softirqs per second: NET_RX 5.7k, BLOCK 2.0k, RCU 3.6k, SCHED 1.3k, TIMER 0.3k.
- `/proc/interrupts` is masked in containers, so the split per vector was not visible.

Every guest interrupt ends in an xAPIC EOI write, which is an NPT fault to HyperKit. **About half the NPT faults are EOIs (~49k/s).** Most of
the rest are TMICT (`icrtmr`, the one-shot timer: AMD has no TSC-deadline) and ICR (IPIs). This matches the earlier `sample`
(`vlapic_write` icrtmr/icrlo).

### 2.2 Clock and APIC facts that rule options out

- **Clocksource:** `tsc`, with `tsc=reliable` on the guest cmdline, and `constant_tsc nonstop_tsc` exposed. The clock is fine, so a PV clock buys nothing.
- **x2APIC:** not in the guest's CPUID (the flags have `apic` but no `x2apic`).
  - HyperKit emulates CPUID in user space and owns the x2APIC decision (its vlapic `x2apic_state`). Docker starts it without x2APIC.
  - A kext that set the bit would desynchronise HyperKit's vlapic, which refuses an x2APIC enable it did not offer.
  - Linux 7.0 also turns on x2APIC without interrupt remapping only for a hypervisor it recognises. HyperKit's signature "xhyve" is not one
    (per `try_to_enable_x2apic`; not tested).
  - **x2APIC is therefore not reachable from the kext.**
- **In-kernel timer/ICR/EOI:** the vlapic state (IRR/ISR/LVT/timer) lives in HyperKit's memory. HyperKit decides every injection from it. EOI or
  timer writes handled behind its back would leave its ISR stuck. Not possible transparently.
- **AVIC:** it needs the hypervisor to own the vAPIC backing page and the IRR, which is the same problem. It also **does not accelerate the APIC timer**:
  TMICT writes still exit. It would only remove EOI (for edge interrupts) and IPI delivery.
- The guest cmdline also has `noapic` (no IOAPIC). Device interrupts use MSI or the PIC. The `vmexit_inout` in the sample is most likely
  virtio legacy notifies and PIC accesses.

### 2.3 Options, ranked by cost

| # | Option | Cores saved (est.) | Risk | Effort |
|---|---|---|---|---|
| 1 | **Owner: Docker vCPUs 24 → 8** | 0.2-0.4 (fewer IPI targets, fewer idle↔busy timer/HLT/EOI cycles; guest busy is ~3 vCPUs) | low | setting + restart |
| 2 | **Owner: the p0 postgres workload** (2.4) | up to 1-2 cores while it runs; it is the largest consumer | none to the VM | owner's call |
| 3 | Trim the kernel exit path: cache host TSC_AUX per CPU, skip DR0-3/6/7 reads and writes when the guest never used DRs, keep the guest FPU across in-kernel re-entries | ~0.05-0.1 | low | **skipped** (see below) |
| 4 | Apple's in-kernel APIC API in RyzenHV: task traps 10 `intctl(atpic/ioapic/lapic)` and 11 `lapic_msi`, thread trap 13 `apic` (already named in `HvFrontend.cpp`) | removes most of the 0.5 HyperKit-userland cores and most NPT faults, **but only for a client that uses it**: Virtualization.framework, i.e. Docker with `UseVirtualizationFramework=true`. VZ on this machine is unexplored. | high | weeks |
| 5 | A modified HyperKit (open source, moby/hyperkit) with x2APIC and a KVM-style PV EOI/IPI | similar to 4 | high; replaces Docker's binary | weeks, owner decision |

Option 3 was looked at and skipped:

- Keeping the guest's TSC_AUX loaded between VMRUNs would let any thread scheduled on that CPU in between read a wrong RDPID/RDTSCP value.
- Skipping the DR swap needs new DR-write intercepts, because in VMX mode the guest's DR accesses pass through.
- The two XSAVE/XRSTOR pairs per trap are needed anyway.
- What is left is at most ~0.05 cores, which does not justify a change to the run loop.

The old "in-kernel APIC timer/ICR or AVIC" plan drops out (2.2). The cheap wins are 1-3. For heat, the guest's own work dominates:
1.6 cores in the guest, against about 0.75 cores of exit overhead in kernel and userland together.

### 2.4 Is postgres 217 % real work?

Yes. `docker top pathcan-p0-pg` and `pg_stat_activity` were read through the container's local socket, as `POSTGRES_USER` from the container env, with no
password. They show short-lived connections from **172.17.0.1**, which is the Mac side through Docker's gateway. Each lives 1-6 s and runs DDL:

- `CREATE TABLE ...`, `CREATE INDEX ix_access_audit_object_accessed ...`
- `SELECT pg_advisory_xact_lock(...)`, and states "idle in transaction"

Database `pathcan`: 38k commits and 18.6M tuples inserted in 25 min. This is a host-side test or migration runner that recreates schemas in a
loop. It is not the guest spinning on timers. Each DDL commit fsyncs WAL, which means virtio-blk work and an APFS fsync on the host.

I could not determine which host process drives it: `com.docker.backend` only forwards the port.

## 3. Owner settings worth recommending now (owner decides; Docker → Settings → Resources)

| Setting | Now | Recommend | Effect |
|---|---|---|---|
| Memory | 8 GB | **6 GB** | wired −2 GB at once on 0.7.22; the guest's hot set is ~2.5 GB, MemAvailable today 5.6 GB |
| CPUs | 24 | **8** (agreed by the owner; main changed the settings file, effective at the next Docker restart) | fewer exits; the guest averages ~3 busy vCPUs |
| Android emulator RAM (if used with Docker) | ? | as small as the work allows | wired 1:1 by RyzenHV until step 2 |
| p0 test/migration loop | running | stop it when idle; for a throwaway dev DB, `fsync=off`, `synchronous_commit=off` | up to 1-2 cores |

## 4. Tests after main builds and installs 0.7.23 (both steps, one reboot)

Build with `make kext-release` and `make tools` from `research/guest-mem-lazy` @ f1df9fb. My check build passed clean: symbols 408 resolve,
ABI 344-byte RHVStats, `make test` all OK. Install the **new `build/rhv-info` too**: the old one cannot show the V5 counters or set
reclaim.

Setting reclaim needs root: run `sudo build/rhv-info hv reclaim ...` through osascript with administrator privileges. Reading
(`rhv-info stats`, `rhv-info hv reclaim`) works without root. Docker restarts with 8 vCPUs at the same time, so compare exits/s against a
first sample taken with reclaim still off.

### 4.1 Step 1, lazy wiring (reclaim off, the default)

1. Load: `kextstat` shows 0.7.23, with no new panic. `rhv-info log | grep "VM map (lazy)"` shows two lines (low and high RAM) when Docker starts.
   `rhv-info hv reclaim` shows `on: 0`.
2. Yield: right after Docker starts, `vmPagesMapped` must be far below 2,097,152, and the lazy summary line shows the wired MiB.
   `zprint -t | grep RyzenHV` should be about that much. Record both at 1 min, 10 min and 1 h of daily load.
3. Correctness: the compose stack is healthy, `docker run alpine` with curl works, and the guest dmesg (privileged) has no oops.
   - Fill guest RAM: `docker run --rm --tmpfs /t:size=5g alpine sh -c 'dd if=/dev/zero of=/t/x bs=1M count=5000; rm /t/x'`.
   - Then `vmPagesMapped` and `vmLazyFaults` rise, no `cannot bring in guest RAM` appears in `rhv-info log`, and the VM stays up.
4. Regression: `hvf-smoke`, `hvf-exit-bench 2` (their maps are under 64 MiB, so they stay eager), `rhv-map-test`. The per-VMRUN times must not
   change beyond the one-time first-touch faults.

### 4.2 Step 2, reclaim (switched on at run time)

1. Quick settings for the test: `hv reclaim period 5000`, `hv reclaim cold 3`, then `hv reclaim 1` (a chunk is cold after 15 s).
2. After 2-3 minutes of normal Docker use, a pass looks like this:
   - `vmReclaimScans` grows by one per period per VM.
   - `vmReclaimEvicted` > 0.
   - The wired MiB in the lazy line, and the zprint RyzenHV tag, fall toward the guest's hot set (expected 2.5-3.5 GB, against the 8 GB of 0.7.22).
   - The re-faults stay well below the evictions (`vmLazyRefaults` / `vmReclaimEvicted` < ~0.2 over 10 minutes).
   - A re-fault takes under ~100 µs while the page is still resident.
3. Exit cost: `guest TLB flushed on X %` may rise only by about one flush per vCPU per period. The per-VMRUN pre/post and guest+switch times stay
   within ±5 % of the reclaim-off sample. hyperkit's CPU in `top` must not rise.
4. Workload correctness: compose healthy, postgres answering, alpine curl, no guest oops or segfaults, for at least 30 minutes of daily load.
5. **Failure test: the guest under memory pressure while the host compresses.** Reclaim stays on with the quick settings.
   1. In the guest, write data that cannot be compressed away and remember its hash:
      ```bash
      docker run --rm --name rhvfill --tmpfs /t:size=4g alpine sh -c 'dd if=/dev/urandom of=/t/x bs=1M count=3000 && md5sum /t/x && sleep 600 && md5sum /t/x && dd if=/dev/urandom of=/t/y bs=1M count=500 && md5sum /t/y && md5sum /t/y'
      ```
   2. Wait about 30 s, so the chunks behind `/t/x` go cold and are unwired: `vmReclaimEvicted` jumps by about 1500.
   3. Put the host under pressure: `memory_pressure -l warn`, then `memory_pressure -l critical` (`/usr/bin/memory_pressure`, a few minutes), while
      Chrome video and Claude keep running.
   4. Watch `vm_stat`: compressions and swapouts rise, and hyperkit's footprint falls.
   5. While the host is still under pressure, the container re-reads `/t/x` (the second `md5sum`) and then writes and reads `/t/y`.

   **Pass:**
   - Both `/t/x` hashes are identical, and both `/t/y` hashes agree.
   - `vmLazyRefaults` rises by about the number of chunks re-read. Re-fault latency rises (ms, from compressor page-ins) but stays bounded.
   - No `cannot bring in guest RAM`, no guest oops, no VM abort, no host panic or watchdog.
   - The Mac stays usable, and the host compressor holds the guest's cold pages instead of other apps'.

   **Fail:**
   - A hash mismatch or a guest segfault/oops. That means memory corruption: stop at once with `hv reclaim 0`, keep `rhv-info log`, and report.
   - A panic, or a VM that hangs or aborts.
6. Off switch: `hv reclaim 0`. `vmReclaimScans` must go flat, evicted chunks come back as the guest touches them, and nothing else changes.
7. Fallbacks:
   - At run time: `hv reclaim 0`.
   - At the next boot: `rhv_lazymap=0` (owner) turns off both steps.
   - Otherwise restore 0.7.22 (`Kexts-backup`).
8. To keep after the test (owner's choice): `period 10000`, `cold 6`, `batch 256`, with `hv reclaim 1` re-run after each boot, because the setting is not
   persistent. If that proves worth it, a LaunchDaemon or a boot-arg default can come later.

## 5. Open questions

- Was the 12.3 GB at 18:58 the emulator or the orphaned hyperkit? Re-take `zprint` with the emulator running.
- ~~Where does xnu call `hv_callbacks_t.memory_pressure`?~~ Answered: nowhere (1.3). Step 2 is periodic.
- Should reclaim follow host pressure (`kern.memorystatus_vm_pressure_level`), instead of only age? Decide after test 4.2.
- Does Virtualization.framework start a VM on this machine at all? It would make option 2.3-4 worthwhile.
- Which host process runs the p0 DDL loop (it belongs to the owner's project)?
