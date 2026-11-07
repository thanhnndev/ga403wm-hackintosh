<!-- Copied 2026-11-07 from the session that ran the first real fresh install (25G332). Kept as written; the design that uses it is docs/FRESH-INSTALL.md. -->

# GA403WM fresh install: lessons from the first real run (2026-11-07)

For the session building the USB installer (docs/FRESH-INSTALL.md, option c). On 2026-11-07, Tahoe 26.7.2
(25G332) was installed fresh on this machine, and the whole stack was brought up by hand. It works now:
WindowServer runs Metal on the 890M, and the RTX 5060 is headless. Each point below is something the
installer has to handle. Some correct the current design.

## 0. How the run differed from the plan

* **The install did not go through Recovery from USB.** It was `Install macOS Tahoe.app`, run from the old macOS
  onto a new APFS volume in the same container. Wi-Fi in Recovery and "Reinstall macOS" from the USB are **still
  untested** (4.7 risk 2 stays open).
* **Apple served 25G332, not 25G241.** Risk 3 in 4.7 has now happened: the build changed. The installer has to
  expect a newer build than the manifest lists.
* The old disk was then migrated with Migration Assistant. The old container was deleted and the Tahoe container grown.

## 1. Corrections to the design

| Topic | Design today | Found on the real run | Change |
|---|---|---|---|
| Captured payload | `~/ga403-payload-25G241` (captured 2026-11-05) is the golden payload | **Stale after 2 days.** NVRM, StrixS0ix, NVMTLDriver, nvmtl, RogAudio and RogControl differed from the live system. The stack was copied from the live system instead | Capture right before building the stick. `verify.sh` must compare payload against live and **fail on drift**. Show the capture date in the app |
| Payload rows | 93 components | Missing: `/Library/NullMoth/*.sh` (top-level scripts), `/usr/local/share/strixamp`, `/Library/StrixGraphicsFix/nmx-relink.probes` | Add them to the manifest |
| WindowServer sandbox (1.5) | "to check: may be unnecessary" | **Required.** Without the `/dev/dri` rule, CoreDisplay logs `Failed to create MetalDevice` | Make `ws-sandbox-dri.sh` a fixed step in S4/S5. It needs csr 0x800 and a new blessed snapshot, and must be redone after every macOS update |
| NMXAccel build gate | not in the design | NMXAccel armed the 890M pipe only when `IOKitBuildVersion` equalled the 25G241 kernel string. On 25G332 the result: no Metal, an extremely laggy desktop, and a freeze at the login step | Ship the family gate from commit 74a6f5c (`scripts/macos-install-nmxaccel-gate.sh`, IOAcceleratorFamily2 class-size check). It replaces the exact-string retarget in d25c241. Add a S5 check that the pipe is armed (section 4) |
| `graphics-bootstrap` daemon | "leave it out" | Migration Assistant **brings it back**, together with `com.nullmoth.crashcheck` (its 1401.app is gone) | A post-migration cleanup step must remove both. Removed copies on this machine: `/Library/StrixGraphicsFix/removed-20261107T045548Z/` |
| Apps | ItlWiFi and 1401 listed in post-install | The owner does not want **1401.app** or **ItlWiFi.app**: native Wi-Fi and the custom driver are used | Drop them from the full profile |
| Python | `nmx-caves/check.py` and the gate script are Python | A fresh macOS has **no python3** until the Command Line Tools are installed | Stage scripts must be bash plus compiled tools only. `kccheck` (C, no otool/python) was the right choice; ship it prebuilt |

## 2. AuxKC: what works

* GPU kexts **cannot** be injected by OpenCore. They link against IOGraphicsFamily, IOAcceleratorFamily2 and
  AppleGraphicsDeviceControl, which exist only in the System KC. They must go in the AuxKC.
* An **offline prelink for another volume** works, and lets S4 build the AuxKC before the reboot:

  ```
  kmutil create -n aux --volume-root / --allow-missing-kdk \
    --kernel <target>/System/Library/Kernels/kernel \
    -B <target>/System/Library/KernelCollections/BootKernelExtensions.kc \
    -S <target>/System/Library/KernelCollections/SystemKernelExtensions.kc \
    --repository <target>/Library/Extensions -A out.kc -z
  ```

  Use `--volume-root /`, not the target: `--volume-root /Volumes/X` fails with `KextExcludeList not found`.
  Use the **target's** kernel and KCs, not the running system's.
* **kernelmanagerd rebuilt the AuxKC without our kexts on the first boot.** Observed: one relink and one extra reboot.
  The guard that fixed it, `com.ga403wm.auxguard`, works and can become the base of the resume daemon:
  `/Library/StrixGraphicsFix/auxguard.sh` with a RunAtLoad LaunchDaemon. It does this:
  1. Waits 45 s.
  2. Runs `kccheck` on the AuxKC (UUIDs plus probe windows, 9 kexts).
  3. If the check fails, relinks into `$KC.relink`, checks that file, keeps the old KC as a backup, then `mv`.
  4. Runs `ws-sandbox-dri.sh` once (a `.done` marker).
  5. Reboots at most twice (a counter file).
* Kexts in `/Library/Extensions` must be `root:wheel`, 755 or 644. Copy as root.

## 3. Symptoms seen, for the app's error messages

| Symptom | Cause |
|---|---|
| First boot reaches userspace, then black screen / no login; WindowServer aborts in `CoreDisplay CGXMappedDisplayStart` | no GPU stack (or AuxKC without our kexts) |
| Desktop draws but is extremely slow, then freezes at the account or login step | WindowServer has no Metal device: the NMXAccel gate did not arm, or the sandbox rule is missing |
| `kmutil` "KextExcludeList not found" | `--volume-root` pointed at the target volume |
| Installer: "not enough free space, additional N MB" after space was freed | the installer reads free space only once; relaunch it. `/Library/InstallerSandboxes/.PKInstallSandboxManager*` can hold many GB |

## 4. S5 verify: checks that proved the stack works

* `sysctl debug.nmxaccel_armed` = 1
* unified log has `debug.nvaccelfb now reads 1` (NMXAccel native framebuffer watch)
* unified log has NVMTL `this GPU owns the display (NMX pipe armed)` for WindowServer
* `system_profiler SPDisplaysDataType`: AMD Radeon 890M, Metal 3, 2880x1800; RTX 5060 without a display
* about 440 processes have the drm user client open (`drm-uc`)
* 16 GPU-stack kexts loaded; the AuxKC on disk passes `kccheck` after the 45 s wait
* agents running: RogControl, TapGuard, rogaudiod, rogkeyd

## 5. Smaller traps

* Build `/Volumes` paths with a slash and quote them. A missing slash created `/Volumes/WorkApplications` on the
  boot disk and filled it.
* The `restricted` SIP flag on RADV/libdrm/ICD files: `ditto` fails as a normal user; `cp -R` works (as in 4.8).
* Per-user data (LaunchAgents with the user name in paths, app settings) can only be restored after the account
  exists. An `after-login.sh` with `rsync --update` worked.
* In zsh, `log` is a builtin: call `/usr/bin/log`. The owner's login shell is fish, and fish fails on globs that match nothing.
* Renaming the system volume: `diskutil rename / "Macintosh HD"` works on the sealed volume, but the OpenCore picker
  reads `Preboot/<group UUID>/System/Library/CoreServices/.disk_label.contentDetails`, and `diskutil apfs
  updatePreboot` did **not** refresh it. Write the file directly (as root).
* Delete or grow containers only after checking the target (`diskutil info` UUID and name) and that the free space
  follows the container directly.

## 6. Suggested order change for "full install after first boot"

S1–S2 stay as designed. Proven on this run: S4 can do everything offline, then reboot once:

1. Copy kexts as root.
2. Prelink the AuxKC against the target KCs.
3. Run `kccheck`.
4. Arm the guard daemon.

On the next boot the guard re-checks the AuxKC, relinks if kernelmanagerd replaced it, applies the sandbox rule and
reboots. The two-reboot cap covers the kernelmanagerd case. S3 (EFI, csr) must still come first, because the
sandbox step needs csr 0x800.
