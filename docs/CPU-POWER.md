# CPU power audit — 2026-10-12

Hardware: Ryzen AI 9 HX 370, 12 physical cores / 24 logical CPUs.

## Live results before the 0.1.1 reboot

* Repo and booted ESP configs: AmdCppc and ForgedInvariant enabled, DummyPowerManagement enabled,
  all four core-count patches use 12. OpenCore 1.0.9 validator: no issues.
* AmdCppc is loaded. CPPC_EN=0, CpbDis=0 (boost is allowed), P0=2000 MHz.
* Low-load sample: logical CPUs 0–7 around 2000 MHz; 8–23 around 1419 MHz.
* Short 24-worker load: CPUs 0–7 around 3281–3288 MHz; 8–23 around 2387–2390 MHz.
  Hardware status also changed. CPU is therefore not permanently locked at 2 GHz.
* The dependent-add single-thread probe returned 2.42–2.92 GHz. This is an approximate throughput
  measurement affected by scheduling, not a pinned per-core clock measurement.
* hw.cpufrequency=2000000000; machdep.tsc.frequency=1996248457. These fixed reference values must
  not be used as live core clocks. Use debug.amdcppc.freq for APERF/MPERF samples.

## What 0.1.1 fixes

* Removes the concurrent gNcpu update; computes the upper CPU index after rendezvous.
* Report grouping includes PStateStat, register validity and presence. Larger report buffer fits all CPUs.
* Rejects boost values other than 0/1 and CPPC values other than 1 (no pretending to disable CPPC).
* EPP checks CPPC enable validity. Unsupported requests fail before writing; readback mismatch returns EIO.
* Handles lock allocation failure and frees the lock at stop.
* Corrects the claim that MSR writes were fault-safe: only reads use rdmsr_carefully.

## Automatic policy implemented (0.2.0 + AmdCppcPolicy)

The kext exposes validated register access; a root LaunchDaemon owns automatic policy. Keeping
ACPI/profile lookup and sleep/wake orchestration outside the kernel avoids extra firmware work
inside an interrupt-disabled CPU rendezvous. No additional third-party CPU kext is needed.

The daemon starts at boot, checks every 5 seconds, enables CPPC and verifies the request on all
24 CPUs. It does not rewrite unchanged requests. It uses per-core highest performance as max,
lowest non-linear as min, desired=0 (autonomous). EPP mapping:

| Power/profile | EPP |
| --- | ---: |
| AC Performance / Manual | 128 |
| AC Turbo | 0 |
| Battery Performance / Turbo / Manual | 191 |
| Silent (either source) | 255 |

ASUS profile comes from AsusWmi's tracked set_profile, because raw firmware DSTS returns 3 here.
Missing ASUS status defaults to the battery preference. Policy never changes firmware power limits,
fan curves, HWCR boost disable or legacy P-states. Three consecutive failures stop writes until
wake or daemon restart. CPPC enable cannot be undone by this driver until a hardware reset.

IORegisterForSystemPower acknowledges sleep immediately, pauses writes during sleep and schedules
policy restoration after kIOMessageSystemHasPoweredOn. The 0.2.0 kext also resets energy/time and
clock sample baselines on wake. Its writes require AuthenticAMD family 1Ah model 24h with CPPC
MSR capability and valid caps; legacy requests are limited to validated enabled P0.

MSR reads are fault-safe; writes still use the documented instruction with hardware/capability
preflight and readback. They are not protected by Linux's wrmsrq_safe exception mechanism. XNU's
trap recovery table is kernel-owned; this implementation does not patch trap handlers or invent
an unsupported recovery mechanism. This remains a platform-specific driver, not a general AMD
power management implementation or a scheduler preferred-core driver.

### Single hardware validation round

On the currently loaded 0.1.0 kext, the same daemon code enabled CPPC and verified EPP=0 on all
24 CPUs, then collected baseline, single-worker and 24-worker samples and restored automatic
AC Performance EPP=128. No repeated benchmark loop was run.

* Single worker migrated among cores; busy Zen 5c samples reached 3142–3203 MHz. It was not pinned,
  so this does not certify a 5.1 GHz single-core workload on a preferred Zen 5 core.
* 24-worker samples: all 24 logical CPUs were busy, Zen 5 4890–4911 MHz, Zen 5c 3329–3336 MHz.
* Post-load sample: Zen 5 peak 5012 MHz at low utilization (not a sustained single-core result).
* Tctl peaked at 85.125 C in collected samples; steady loaded package power around 65 W.
* The original test inherited an ignored SIGTERM through osascript and paused at worker cleanup.
  Only its worker children were killed to resume that same run. The harness now explicitly resets
  signal dispositions and limits workers to 15 seconds. No benchmark was rerun after that correction.
* Policy mapping, 24-CPU request readback and simulated wake restoration passed.
* One real sleep/wake was requested with pmset sleepnow and a relative wake scheduled after 20 seconds.
  IORegisterForSystemPower delivered the actual wake notification; the installed daemon logged
  EPP=128 verified on all 24 CPUs afterwards. This verifies this one wake cycle, not prolonged
  suspend reliability. The new kext baseline hook remains untested until reboot.

Raw local logs: build/amdcppc-policy-test.log, build/amdcppc-physical-wake.log.
The live daemon is installed at /Library/PrivilegedHelperTools/com.itlmt7925.AmdCppcPolicy;
LaunchDaemon /Library/LaunchDaemons/com.itlmt7925.AmdCppcPolicy.plist;
log /var/log/amdcppc-policy.log. The 0.2.0 kext is on the ESP, requiring reboot to load its new guards
and sensor-baseline hook; current live policy works with the already loaded 0.1.0 interface.

Build: bash scripts/build.sh AmdCppc; bash scripts/build-amdcppc-policy.sh.
Install through osascript administrator privileges using scripts/macos-install-kext.sh AmdCppc and
scripts/macos-amdcppc-policy-install.sh. Remove policy with the latter's --undo; restore the previous
kext with scripts/macos-install-kext.sh --undo AmdCppc. Reboot to restore firmware startup CPPC state.

References: [Linux AMD P-State documentation](https://docs.kernel.org/admin-guide/pm/amd-pstate.html),
[upstream implementation](https://github.com/torvalds/linux/blob/master/drivers/cpufreq/amd-pstate.c),
[register masks](https://github.com/torvalds/linux/blob/master/arch/x86/include/asm/msr-index.h),
[Apple sleep/wake API](https://developer.apple.com/documentation/iokit/2187054-ioregisterforsystempower).
