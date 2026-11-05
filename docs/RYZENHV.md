# RyzenHV on the GA403WM

[RyzenHV](https://github.com/thanhnndev/ryzen-hypervisor.framework) gives macOS a Hypervisor.framework on AMD-V (SVM), so
QEMU `-accel hvf`, Docker and other VM apps can run. Zen 5 / macOS 26 notes: RyzenHV repo, `docs/notes/GA403WM-ZEN5-TAHOE.md`.

## Docker Desktop (2026-11-05): works with RyzenHV 0.7.12 (HyperKit, 24 CPUs)

Docker Desktop 4.97.0 (Intel, build 244584, sha256 of the dmg `98da1a82dac734ba…`) in `/Applications`, set to HyperKit
(`UseVirtualizationFramework=false`) and `AutoDownloadUpdates=false` in `~/Library/Group Containers/group.com.docker/settings-store.json`
(backups `settings-store.json.pre-ryzenhv-*`, `.pre-noupdate-*`). Docker had already fetched the 245422 update delta; it is kept
aside in `~/.ryzenhv/dl/held-updates/`.

* The kext patched HyperKit (`client fix-ups: signing flags 0x22014201, enforcement off, hard off`): issue 1 (code signature
  kill on macOS 26) does **not** happen here.
* HyperKit aborted twice (`SIGABRT` in `vcpu_thread`, stderr `vcpu id mismatch`); once it then failed with `Failed to set up
  pidfile` (the stale `Data/vms/0/hyperkit.pid` of the crashed run, renamed to `.stale-*`).
* Cause (HyperKit disassembled with REA + Ghidra 12.1.4, sha256 `8a1bb06d…`): each vCPU thread is named `vcpu:N`, calls
  `hv_vcpu_create(&id,0)` and aborts when `id != N` (`cmp` at 0x1002257bc). The AP threads start one per SIPI and race; the kext
  handed out the lowest free id, so `vcpu:2` (first) got 1. 24 vCPUs here lose the race every time.
* Fix in RyzenHV 0.7.9 (`kext/Source/VcpuName.hpp`): for HyperKit the kext reads `vcpu:N` from HyperKit's stack just below `&id`
  and gives id N. Installed 2026-11-05 12:23: old kext in `EFI/OC/Kexts-backup/RyzenHV.kext.20261105-122327`, Comment updated
  with occonfig (backup `config.plist.pre-ryzenhv-079-20261105-122327`, check: no issues). Binary sha256 `a19edcf6e551a35b`.
* After the reboot: `rhv-info hv sysctl 1`, open Docker, `docker run --rm hello-world`; `rhv-info log | grep -i "HyperKit vCPU"`
  shows a line only if a thread could not get its id.

### 0.7.9 boot (12:28): the id fix works; two more causes found, 0.7.10 installed 13:13

* Thread order seen: `vcpu:0, 2, 4 … 22, 1, 3 …`, each got its own id. Next abort: `hv_vcpu_create failed`, because the kext
  allowed 16 vCPUs per VM (`RHV_MAX_VCPUS_PER_VM`) and Docker gives HyperKit all 24 (`-c 24`). Worked around with `"Cpus":16`
  in `settings-store.json` (backup `.pre-cpus16-*`); 0.7.10 raises the limit to 64.
* With 16 CPUs the engine looked up, but it was not: at 12:36:47 the backend logged `docker daemon not ready, continuing:
  context deadline exceeded` and only switched its state to running (see 0.7.11 below). Then the Mac was put to sleep (12:37:16, by hand):
  the kext turned SVM off, the next VMRUN returned an error and HyperKit aborted with `vmentry error` (its message for any
  non-zero `hv_vcpu_run`). 0.7.10 hands a time-slice exit back during sleep, so the client retries until the wake.
* Not slow: QEMU boots Alpine in 2 s (1 GB/2 CPUs) and 4 s (8 GB/16); Docker's HyperKit started directly
  (`com.docker.hyperkit -A -u -c N -m M -s 0:0,hostbridge -s 31,lpc -l com1,null,log=<file> -f kexec,vmlinuz,initrd,cmdline`)
  in 1 s and 3 s. A stale `Data/vms/0/hyperkit.pid` after a crash makes the next start fail (`Failed to set up pidfile`).
* 0.7.10 on the ESP: old kext in `EFI/OC/Kexts-backup/RyzenHV.kext.20261105-131342`, config backup
  `config.plist.pre-ryzenhv-0710-20261105-131342`, check: no issues, binary sha256 `97fa3f23796070e4`.

### 0.7.11 (14:09, booted 14:18): the guest topology was the real cause; Docker works

* Docker never reached its engine on RyzenHV (16 or 24 CPUs, Docker 4.97 and 4.98.0 build 245422): the backend kept dialing
  `192.168.65.7:2376` (`no route to host`) and `Data/log/vm/init.log` stayed empty.
* Docker's own kernel (`Resources/linuxkit/kernel` + `desktop.img`, Linux 7.0.14) started by HyperKit directly with a
  virtio-sock and a listener on host port 1999 (`~/.local/opt/rea-snap/vstest.sh <cpus> <tag>`): 1 and 2 vCPUs connect in
  about 2.5 s, 4 sometimes, 16 and 24 never. Those boots stop right after `smp: Brought up`, with `APIC ID mismatch. CPUID:
  0x0016 APIC: 0x0003` (several vCPUs with the same id) and `BUG: arch topology borken`; even RCU stall warnings at 3 s print
  nothing.
* Cause: HyperKit (`src/lib/vmm/x86.c`, `x86_emulate_cpuid`) caps leaves at the host's 0x80000000 maximum and passes unknown
  ones through with `cpuid_count`, so leaf 0x80000026 (AMD extended topology) gave the x2APIC id of whichever host core the vCPU
  thread was on. Linux reads that leaf before 0xB on AMD (`arch/x86/kernel/cpu/topology_ext.c`, `cpu_parse_topology_ext`).
* Fix in RyzenHV 0.7.11 (`kext/Source/HvFrontend.cpp`, HyperKit CPUID clean-up): leaf 0x80000026 answers all zeros, an invalid
  level for Linux (`num_processors` 0), so it falls back to leaf 0xB, which HyperKit fills with `vcpu_id`. Binary sha256
  `0db8c1698a22d17e`; old kext `EFI/OC/Kexts-backup/RyzenHV.kext.20261105-140920`, config backup
  `config.plist.ryzenhv-0711-20261105-140920`, check: no issues.
* After the boot: the vsock test connects in 2.2 s with 16 and 24 vCPUs (4 of 4 runs), no APIC id mismatch. Docker 4.98.0
  with `"Cpus":24`: engine up 9 s after `open -a Docker` (server 29.9.2, 24 CPUs, 8 GB), `docker run --rm hello-world` prints
  `Hello from Docker!`, an Alpine container sees 24 CPUs and fetches https://example.com.
* Still open, harmless so far: the guest's `WRMSR 0xc0000502` at every context switch and `RDMSR 0xc0010010` fault (HyperKit
  logs them); sleep with a running VM is not retested on 0.7.10+.

### 0.7.12 (14:56, booted 16:57): Docker no longer fails after it stopped its own VM

* `hyperkit: process terminated unexpectedly ... exit code 1` / `Failed to set up pidfile` came back after Resource Saver
  stopped the VM (14:27, 5 minutes idle) and after every Quit or `docker desktop stop`.
* Cause: Docker's backend ends HyperKit right after the guest says `VM has indicated it is ready to be powered off` (gone in
  8-9 ms, so by a signal that skips `atexit`; HyperKit ignores SIGTERM/SIGINT here) and never removes `vms/0/hyperkit.pid`
  (its own `internal/pidfile` writes JSON files elsewhere; `hyperkit.(*Engine).Cleanup` is empty). HyperKit opens the file with
  `O_WRONLY|O_CREAT|O_EXCL` (`src/hyperkit.c` setup_pidfile; `mov esi, 0xa01` at 0x100227b9d in 4.98) and refuses to start
  while it exists. A guest that powers itself off makes HyperKit exit 0 and remove the file (tested with 1, 2, 24 vCPUs), so
  the hypervisor is not involved.
* Fix in RyzenHV 0.7.12: a third HyperKit fix-up (kext `HvPatch.cpp`, shim `rhv_patch.c`) turns the flags into 0x601,
  `O_WRONLY|O_CREAT|O_TRUNC`: a leftover file is overwritten. Found exactly once in Docker 4.98's HyperKit (0x227b96).
  Binary sha256 `318738c4446d1b84`; old kext `EFI/OC/Kexts-backup/RyzenHV.kext.20261105-145637`, config backup
  `config.plist.ryzenhv-0712-20261105-145637`. RyzenHV is now `Kernel/Add/46` (SimpleHDA was added at 5).
* After the boot: Docker started with the 14:41 leftover file in place (engine up 9 s, file overwritten with the new pid);
  `docker desktop stop` + start twice, the file left each time: engine up in 7 s both times, no `Failed to set up pidfile`;
  hello-world and an arm64 Alpine (`aarch64`) run.

Kernel panics the same morning (10:52 `com.ga403wm.strixs0ix` `StrixS0ix::buildPci` from `setPowerState`; 11:11 NullMoth
`NMXGPU` `amdgpu_cs_ioctl` spinlock timeout in WindowServer) have no RyzenHV frame in their backtraces.

## First boot (2026-11-05 10:42): loads, SVM on all 24 cores

`rhv-info`: AMD family 0x1a model 0x24, 24 logical CPUs, SVM usable and active on 24, **BIOS disable: no** (SVM Mode is
on in BIOS GA403WM.310, the default), VM_CR.LOCK 1, revision 1, 32768 ASIDs, features 0xfebfbdff (NPT, NRIPS, VmcbClean,
FlushByAsid, DecodeAssists, AVIC, vGIF...). Log: `SVM enabled on 24 CPUs`, `selftest: 24 of 24 CPUs ok`, `hv front end:
registered` in place of AppleHV. All 24 cores were online when the kext started (no late cores, unlike issue 1).
Counters: enableFailures 0, assertFailures 0. `kern.hv_support` is still 0 (not written at boot). No VM run yet.

## First VMs (2026-11-05, same boot)

* `rhv-info hv sysctl 1`: `kern.hv_support was 0, now 1` (not kept across reboots: run it again after each boot).
* `build/hvf-smoke`: **PASS**, all 5 stages (registers, serial/CPUID/HLT, EPT violation + `hv_vm_map` from the handler,
  `hv_vcpu_interrupt` from another thread, error codes).
* QEMU 11.1.2 (MacPorts) `-accel hvf -cpu host -m 1024 -smp 2 -nographic`, Alpine 3.24.3 netboot `vmlinuz-virt` 6.18.58 with
  `rdinit=/bin/sh`: boots to the shell. `smpboot: CPU0: AMD 1a/24`, `Brought up 1 node, 2 CPUs`, 976 MB.
  With `rdinit=/bin/sh` busybox has no applet links (`grep: not found`); use `/bin/busybox grep` or the normal init.
* **AVX-512**: the guest sees `Enabled xstate features 0x7` (x87/SSE/AVX only). QEMU's hvf takes the host XCR0 of its own
  thread, which XNU has not yet promoted to AVX-512, so the guest gets no AVX-512. This avoids the XCR0 mismatch risk
  (RyzenHV `docs/notes/GA403WM-ZEN5-TAHOE.md`); `vmFpuMismatches 0`.
* Guest note: `Measured 120 cycles TSC warp between CPUs, turning off TSC clock` (guest falls back to another clocksource).
* Counters after ~5 min of QEMU: vmRuns 211284, vmExits 212732, **vmInvalidExits 0**, assertFailures 0, vmNptFaults 112497.
* QEMU ignores SIGALRM: a `perl -e 'alarm N; exec …'` limit does not stop it; end it with `kill` (or `Ctrl-A x`).

## Installed on the internal ESP (2026-11-05)

Like the other kexts of this repo: copied to `EFI/OC/Kexts/RyzenHV.kext` (none was there before) and listed with
`tools/occonfig.py`, which wrote the backups first.

| | |
|---|---|
| kext | RyzenHV 0.7.8, built from ryzen-hypervisor.framework `f9435eb` (`make kext tools`), binary sha256 `ece26ed15b33d320…`; 401 imported symbols resolve against kernel 25.6.0 |
| Kernel/Add | last entry, `Enabled`, `MinKernel 24.0.0`, `MaxKernel 25.99.99` |
| boot-args added | `rhv_enable_svm=1 rhv_selftest=1 rhv_hv=1 rhv_allow_users=1 rhv_loglevel=4` (one boot: probe, SVM on every core, self-test, native front end) |
| backups | `EFI/OC/config.plist.pre-ryzenhv-20261105-103227` (before the entry), `config.plist.pre-ryzenhv-args-20261105-103227` (before the boot-args) |
| config sha256 | before `18056c52a738d575`, after `15ad41e6f37824c2`; `occonfig.py check`: no issues |

**Check after the reboot** (`R=~/develop/projects/ryzen-hypervisor.framework/build`):

```bash
$R/rhv-info                     # family 0x1a model 0x24, SVM supported, BIOS disable: NO, NPT [x], usable 24
$R/rhv-info log | grep -E "SVM enabled|selftest|rescan|front end|ERR|WARN"
$R/rhv-info hv                  # front end: registered
$R/rhv-info hv sysctl 1 && sysctl kern.hv_support      # then build/hvf-smoke, QEMU -accel hvf
```

`BIOS disable: YES` means SVM Mode is off in the BIOS (ASUS: "SVM(Secure Virtual Machine) mode", default Enabled; F2 at
power-on, F7 for Advanced Mode). The kext then does nothing.

**Undo / way back**
* Kill switch: boot-arg `-rhv_off` (the kext loads and does nothing).
* Without RyzenHV: `cp EFI/OC/config.plist.pre-ryzenhv-20261105-103227 EFI/OC/config.plist` (from macOS on `/Volumes/ESP`, or from
  Linux on `/boot`), then `EFI/OC/Kexts/RyzenHV.kext` can be deleted.
* A panic at boot: pick Linux in the picker and do the copy above from `/boot/EFI/OC`.

## Optional: a test stick

The rest of this page is the USB stick variant (`scripts/macos-make-rhv-usb.sh`), for trying a new RyzenHV build without
touching the internal ESP.

## How the stick follows this repo's rules

| rule of this repo | on the stick |
|---|---|
| ESP config edits only through `tools/occonfig.py` (backup `config.plist.<tag>` first, re-parse, `check` = schema + ocvalidate) | the staged config is changed with `occonfig.py add/args/set` and checked; `occonfig.py diff` against the internal config is printed |
| old kexts go to `EFI/OC/Kexts-backup/<name>.kext.<YYYYMMDD-HHMMSS>`, `--undo` brings the newest back (`macos-install-kext.sh`) | an update of the stick keeps `Kexts-backup/RyzenHV.kext.<ts>` and `config.plist.pre-ryzenhv-<stage>-<ts>` on the stick; `--undo diskN` restores the newest |
| own kexts are `Enabled` behind a `-<name>off` kill switch | `Enabled`, kill switch `-rhv_off` (in RyzenHV); simplest way back is booting without the stick |
| boot-args are merged by name in the config, `boot-args` must be in `NVRAM/Delete` | the stage's args are appended with `occonfig.py args add`; the script stops if `NVRAM/Delete` lacks `boot-args` |
| one reboot carries a batch (`batch-changes-per-reboot`) | default stage `native` answers probe, SVM enable, self-test and the native front end in one boot, with `-v` and `rhv_loglevel=4` |
| each run logged, hashes as 16-char sha256 prefixes | `build/rhv-usb-logs/rhv-usb-<ts>.log`; `RHV-USB.txt` on the stick has stage, version, git rev, config and kext hashes |
| copies of the real config stay in ignored `build/` | `build/rhv-usb/` (serial, MLB, ROM inside), never commit it |

The kext is built by RyzenHV's own Makefile (`make kext tools`), which checks every imported symbol against the running kernel
(401 resolve on 26.7.1). The staged EFI is the internal one without `Kexts-backup`, `Backup`, old `config.plist.*`, OpenCore
logs, Windows and Limine; it is made fresh from the internal ESP on every run, so changes made there since are picked up.

## Commands

```bash
scripts/macos-make-rhv-usb.sh                              # stage (native), no disk touched
diskutil list external                                     # find the stick, e.g. disk4
scripts/macos-make-rhv-usb.sh --write disk4 --format       # ERASES disk4 (MBR, FAT32 "RHVEFI"), copies the EFI
scripts/macos-make-rhv-usb.sh --stage svm --write disk4    # fall back one stage (backups kept on the stick)
scripts/macos-make-rhv-usb.sh --undo disk4                 # newest kext + config backup on the stick back
```

The script refuses internal disks, disks that are not removable/external, disks over 256 GB and the system disk, and asks
for the disk name to be typed before it writes.

## Stages

| stage | boot-args added (to the internal ones) | check after boot |
|---|---|---|
| `native` (default) | `-v rhv_enable_svm=1 rhv_selftest=1 rhv_hv=1 rhv_allow_users=1 rhv_loglevel=4` | `rhv-info`: family 0x1a model 0x24, SVM supported, BIOS disable NO, NPT, 24 usable; `rhv-info log`: `SVM enabled on 24 CPUs`, `selftest: 24 of 24 CPUs ok`, `rescan:`; `rhv-info hv`: `front end: registered`; then `rhv-info hv sysctl 1` (writes kern.hv_support), `hvf-smoke`, QEMU |
| `svm` (fallback) | `-v rhv_enable_svm=1 rhv_selftest=1 rhv_loglevel=4` | as above without the front end |
| `probe` (fallback) | `-v rhv_loglevel=4` | `rhv-info` only: SVM stays off |

`rhv-info` is `../ryzen-hypervisor.framework/build/rhv-info`. If a boot hangs or panics, take a photo (`debug=0x100` keeps
the panic on screen), boot without the stick, and write the next fallback stage; `rhv_stage=0..5 rhv_slow=3` bisects inside
the kext's start (RyzenHV `docs/DEBUGGING.md`).

Before the first boot: switch **SVM Mode** on in the BIOS and boot the internal ESP once. Do not let the machine sleep
during the tests (RyzenHV's sleep/wake path is untested, and this machine sleeps through S0ix).

## Way back

Take the stick out, or pick the internal disk in the BIOS boot menu: the internal ESP boots without RyzenHV and sets its own
boot-args again (`boot-args` is in `NVRAM/Delete`).
