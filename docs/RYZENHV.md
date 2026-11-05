# RyzenHV on the GA403WM

[RyzenHV](https://github.com/thanhnndev/ryzen-hypervisor.framework) gives macOS a Hypervisor.framework on AMD-V (SVM), so
QEMU `-accel hvf`, Docker and other VM apps can run. Zen 5 / macOS 26 notes: RyzenHV repo, `docs/notes/GA403WM-ZEN5-TAHOE.md`.

## Installed on the internal ESP (2026-11-05, reboot pending)

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
