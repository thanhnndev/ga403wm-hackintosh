# Docker heat and fan: measurement plan, exit ranking, top lever (2026-11-27)

This covers roadmap Later items 1 and 2, moved up. On 2026-11-16 the machine hit 62 W / 95 °C under Docker + video + Claude.

Live on this boot (17:10, up 34 min):
- RyzenHV 0.7.25 (42ce5e1), with lazy wiring live and reclaim off (`hv reclaim` on: 0);
- AsusWmi 0.3.3, with the AC PPT limits 61/65/68;
- Eco, EPP 191;
- Docker settings: 8 vCPUs, `UseVirtualizationFramework=false` (HyperKit).

Nothing was installed or switched. Docker was not running, and I did not start it.

## (a) Measurement plan, all without root

The probe is `scripts/docker-heat-probe.sh [seconds=600] [interval=5] [outdir]`. It is read-only and starts or stops nothing.

Every `interval` it samples:
- `debug.amdcppc.sensors`: `pkg_mw` and `tctl`;
- every `rhv-info stats` counter;
- `vm_stat`: wired, compressor, compressions, decompressions, swap.

Over the whole run it records:
- the delta of kernel_task's cumulative TIME (from `top -pid 0`; `ps -p 0` prints nothing);
- per-process CPU and power, from `top -l 2 -s <run>`. The second sample is the average over the run.

It writes `samples.csv`, `top.txt`, the RyzenHV status and stats at start and end, and `summary.txt` under `~/ga403-logs/docker-heat-<stamp>/`.

The summary prints:
- average and maximum package power and Tctl;
- kernel_task in cores;
- wired GB and compression rates;
- RyzenHV exits/s, VMRUNs/s, traps to HyperKit/s, NPT faults/s, in-kernel re-entries/s;
- TLB flushes against new ASIDs;
- cores spent in guest+switch, kernel pre/post and front end;
- lazy faults and re-faults, reclaim evictions, GB mapped.

The fan speed cannot be read without root (AsusWmi publishes no fan property). Tctl stands in for it.

### Owner run (no setting changes)

1. Normal day: the compose stack, a video playing and Claude working, everything up for at least 10 minutes.
2. `scripts/docker-heat-probe.sh 600 5`
3. Same window, read-only: `docker stats --no-stream` (guest CPU per container) and `docker info | egrep 'CPUs|Total Memory'`.
4. Optional, main's call, at run time and with no reboot: `sudo rhv-info hv reclaim 1`, run the probe again, then `hv reclaim 0`. The test
   and failure criteria are in RYZENHV-GUEST-MEM.md section 4.2. This is not a boot-arg and not pmset.

W per core is calibrated from the same run: (package W minus the 8.2 W baseline) / total busy cores from `top.txt`. Until then the tables
use about 5 W per busy core, from 62 W against about 9 busy cores on 11-16.

### First numbers (17:2x, no VM running: baseline only)

| | value |
|---|---|
| package power | 8.2 W average, 9.5 W max (15 s) |
| Tctl | 43 °C |
| kernel_task | 0.11 cores |
| wired | **6.17 GB with no VM at all** (GPU, kexts, apps); compressor 0.01 GB |
| RyzenHV | every vm* counter 0: no VM since boot |
| top CPU | WindowServer 10.9 %, Zalo renderer 7.5 %, kernel_task 7.3 %, WallpaperAerials 5.8 %, VTDecoder 5.1 % |

The Docker numbers come from the owner run. The last loaded sample (11-16, RYZENHV-GUEST-MEM.md 2.1) had:
- 216.8k exits/s, of which 147.9k trapped to HyperKit;
- 106.6k NPT faults/s on xAPIC MMIO, about 49k/s of them EOIs;
- kernel exit path 0.26 cores, HyperKit userland 0.5 cores, guest+switch 1.6 cores.

That sample was taken with 24 vCPUs and before lazy wiring.

## (b) Which exits stay in user space, and what each lever is worth

What 0.7.25 handles in the kernel (Vm.cpp run loop), so these never reach HyperKit:
- host interrupt and NMI exits (the bulk of exits minus traps, ~69k/s on 11-16);
- lazy-RAM first-touch NPT faults;
- WRMSR to the TSC;
- MOV CR8 under the TPR shadow;
- CLTS and LMSW;
- trace-only exceptions.

WRMSR 0xC0000502 (CPU-THERMALS.md §1) is gone since 0.7.17: CPUID 0x80000021 bit 22 is hidden from HyperKit guests.

Everything else reaches HyperKit, and **nothing more can move into the kernel while HyperKit is the client**:

| exit to HyperKit | rate (11-16) | could the kernel handle it? |
|---|---|---|
| NPT fault on the xAPIC page: EOI | ~49k/s | **No.** IRR, ISR, PPR and the timer live in HyperKit's vlapic. An EOI absorbed in the kernel leaves its ISR set, so the next interrupt never comes. |
| NPT fault on the xAPIC page: TMICT (one-shot timer), ICR (IPIs) | ~58k/s | No, for the same reason. AVIC would not help TMICT anyway. |
| HLT | not counted yet | No. Whether an interrupt is pending is HyperKit's decision. |
| I/O ports (virtio legacy notify, PIC) | not counted yet | No. The devices are HyperKit's. |
| CPUID, other MSRs, CR0/CR4 writes | small | Only by caching HyperKit's answers. CPUID leaf 1 changes with CR4.OSXSAVE, and the rate is low. Not worth it. |

**There is no per-reason counter today.** `vmTraps` and `vmNptFaults` are totals, so the split above is inferred from the 11-16 sample.

Levers, in watts (at about 5 W per busy core, to be calibrated):

| # | lever | what it removes | W (est.) | who | cost |
|---|---|---|---|---|---|
| 1 | **The guest's own work**: the p0 postgres test/migration loop, container CPU limits (`cpus:` in compose), dev DB `fsync=off` | 1.6-3 cores of guest work (5.2 cores on the 62 W run) | **8-15** | owner | settings |
| 2 | **Guest memory**: lazy wiring (live) plus `hv reclaim 1` (built, off), Docker memory 8 → 6 GB | wired drops to the hot set, so less compression in kernel_task under pressure | 0.5-1.5 (if compressions/s is high in the run) | main/owner, run time | none |
| 3 | **In-kernel APIC in RyzenHV**, so Docker can run on Virtualization.framework | the ~0.5 cores of HyperKit vlapic/device emulation and most of the ~107k NPT faults/s; with AVIC also EOI and IPI exits | **2.5-4** | RyzenHV branch | weeks, gated (c) |
| 4 | Modified HyperKit (x2APIC + PV EOI/IPI) | similar to 3 | 2-3 | owner decision: replaces Docker's binary | weeks |
| 5 | Trim the kernel exit path | part of 0.26 cores | 0.3-0.5 | RyzenHV | skipped in RYZENHV-GUEST-MEM.md 2.3 |
| 6 | Fewer TLB flushes | flushes were 13.5 % of VMRUNs; mostly vCPU migration (new ASID per CPU, which cannot be avoided without pinning), plus one per reclaim scan | ≤ 0.3 | RyzenHV | measure first: the probe prints flushes against new ASIDs |
| - | Docker vCPUs 24 → 8 | fewer IPI targets and idle↔busy cycles | done | owner | done |

Checked and ruled out:
- **NPT 2 MiB leaves**: the guest's TLB reach is capped by 4 KiB NPT pages. But HyperKit's RAM is ordinary anonymous memory, not 2 MiB contiguous, so there is nothing to promote.
- **ASID_NEW flushes**: they cost nothing extra, because a migrated vCPU starts cold anyway.
- **Lazy fault-in**: it does not bump `nptGen`, so it causes no global flush.

**Ranking**: 1 is the largest by far and is owner work, not code. 2 costs nothing to try. 3 is the top lever that code can reach,
and the only one in RyzenHV worth more than half a watt.

## (c) Design: in-kernel APIC for clients that ask for it (RyzenHV branch `research/inkernel-apic`)

### Today
- `tVmCreate` refuses flag 0x400 (the in-kernel APIC variant of `hv_vm_create`) with HV_UNSUPPORTED.
- Task traps 10 `intctl(atpic/ioapic/lapic)` and 11 `lapic_msi`, and thread trap 13 `apic(sub-op)`, are stubs (`S(0,10)`, `S(0,11)`, `S(1,13)`).
- HyperKit never asks for any of these, so Docker gains only by switching to Virtualization.framework (VZ). VZ is Apple's XPC service
  and uses the in-kernel APIC API.

### Stage 0: feasibility gate, before any APIC code (1-2 days)
Questions to answer:
- Does VZ's VM service get as far as `vm_create(0x400)` on this machine?
- What does it call after that?

Method:
- `rhv-info hv mode 2` already answers success to every trap and logs each call with its argument words. That is a run-time switch and needs root.
- During one VZ VM start, let the frontend accept 0x400 in mode 2 only, and log the traps that follow.
- The owner or main starts the VZ VM: a minimal Linux through any VZ CLI, or Docker with `UseVirtualizationFramework=true` for one start.
  That is an owner app setting.

Result: the list of traps and sub-ops VZ needs, including `hv_vm_space_*`, `vcpu_run_until` and any VMX capability it checks.

Stop here if VZ checks for Intel (vendor, VMX MSRs) in a way the frontend cannot answer, or needs memory spaces RyzenHV does not have. In
that case lever 3 is dead and lever 4 is the only route.

### Stage 1: per-reason exit counters (small; useful whatever stage 0 says)
- Stats V6 gains `vmExitByReason[16]`, counted per vCPU in `fProf` and flushed with the cycle counters. It is keyed by the VMX reason the
  client sees: external interrupt, HLT, I/O, CPUID, RDMSR, WRMSR, CR, EPT violation, the rest.
- It also gains `vmApicFault[4]`: NPT faults at GPA 0xFEE00000, split by register (EOI 0xB0, ICR 0x300/0x310, TMICT 0x380, other), decoded
  from EXITINFO2.
- `rhv-info stats` prints them, and the probe picks them up with no change.
- Cost: one increment per exit. The stats ABI grows; rhv-info keeps accepting V5.
- This replaces the inferred split in (b) with measured numbers, and sizes the gain of stage 2.

### Stage 2: the LAPIC model in the kernel (weeks)
- Per vCPU, a vlapic: IRR/ISR/TMR, TPR/PPR, LVT, timer, ICR. This could be a port of bhyve's `vlapic.c` (BSD-2), which is what HyperKit
  runs in user space today.
- xAPIC page writes are emulated in the run loop. They are already NPT faults at 0xFEE00000, and EXITINFO2 plus decode assists give the
  register and value.
  - EOI, TPR, ICR to self or another vCPU, and the timer stay in the kernel.
  - Only accesses the model does not own go to the client.
- The timer is a `timer_call` per vCPU, at the deadline TMICT × divider. On expiry it sets IRR and kicks the vCPU (the existing
  `vcpu_interrupt` path). The guest TSC offset is already per VM.
- Injection: before each VMRUN, the highest IRR above PPR goes to `eventInj` or V_IRQ, the same place `takePendingEvent` uses now.
- Traps:
  - task 10 sets and reads IOAPIC/ATPIC pin state (the kernel owns the IOAPIC redirection table);
  - task 11 delivers an MSI to the vlapic of the destination;
  - thread 13 reads and writes the vlapic state (save/restore, the client's debug view).
- Stage 3, optional: AVIC on Zen 5 (x2AVIC too).
  - The vlapic backing page becomes the AVIC backing page, so EOI of edge interrupts and IPIs to running vCPUs complete without exiting.
  - The timer still exits.

### Risks and how they are contained
- Clients that do not ask for 0x400 (HyperKit, QEMU, Parallels) keep today's path byte for byte. The flag selects the model at VM creation.
- A wrong vlapic hangs or slows the guest, not the host. Every stage is a run-time choice: mode 1 keeps refusing 0x400 by default until
  stage 2 passes hvf tests and a VZ guest boot.
- VZ is a system service. Nothing is patched in it, and the frontend answers only its documented traps.

### Expected gain, to be checked against stage 1
At 8 vCPUs, the ~107k APIC NPT faults/s and the HyperKit vlapic work (~0.5 cores) become in-kernel handling at about 0.3 µs each, roughly
0.03 cores, so the saving is **~0.5-0.8 cores ≈ 2.5-4 W**. That is if Docker on VZ is otherwise as efficient as on HyperKit: virtio-fs
against gRPC FUSE, and VZ's own device model, are unknowns that stage 0 and one A/B run would show.

## What I need from main or the owner
- The owner run in (a), with Docker, video and Claude up.
- A decision on stage 0: one run with `hv mode 2` and a VZ start. That means a root run-time switch and an owner app setting, so it is
  their call.
- Stage 1 can be built on a branch now, with no install.
