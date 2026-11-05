# Fresh install of the whole GA403WM stack: research and design

Status: research and design, 2026-11-05 (branch `research/890m-cobalt64`). Nothing here has been run on a fresh machine.
The two prototype scripts in `scripts/fresh-install/` are read-only and were tested on the working machine only.

Owner's request: "nghiên cứu cài all bộ ga403 cho fresh install đi. Có thể cài qua usb hoặc tạo 1 app. Nói chung là
tìm đường 1 click install all ấy" (find a one-click way to install everything on a fresh machine, by USB or an app).

## Summary

* **Recommendation: the hybrid (option c).** A USB stick holds the OpenCore EFI, the macOS installer and a payload
  volume. After macOS is installed, one app on the stick (`GA403 Setup.app`) applies everything in order across two
  or three reboots, resuming on its own after each one, and verifies each stage against a manifest.
* **The step scripts cannot be replayed on a fresh machine.** The live NMXGPU (`5760efb6…`) is a source build
  (`7efe25b8`, Step69) followed by about 22 binary patches and caves (Step74 to Step112c). Each step script only
  accepts the exact sha256 the previous step produced, and some read their input from dated backup folders that exist
  only on this disk (`/Library/NullMoth/step95-bk-20261103T152156Z`, `step98-bk-20261103T171105Z`). The NVIDIA 2.7.1
  tarball the NVIDIA script expects (`~/efi-audit/upgrade-2.7.1/`) is no longer on disk either.
* **So the installer copies final, verified artifacts, not the history.** The first version uses a "golden payload"
  captured from this working machine (`scripts/fresh-install/capture-live.sh`, 93 components, sha256 for each). In
  the longer term, the caves move into the fork's source, so CI can build NMXGPU and the manifest can point at CI
  artifacts instead of a capture.
* **Licensing split.** Every PolyForm part (NMXGPU, NMXAccel, NMXAGDC, NVRM*, NVAccel, NVMTL plugin and translator,
  RADV/libdrm builds, NullMoth firmware) lives only in the payload, never in this BSD repo. The repo carries the
  manifest format, the scripts, the BSD kexts' sources, and sha256 values.
* **Clicks that cannot be automated:** the BIOS settings, picking the USB in the boot menu, macOS Setup Assistant
  (account, Apple ID), one admin password per stage, and the reboots (the app can trigger them, but a person should
  confirm each one). The setup expects no "Allow" click in Privacy & Security because `csr-active-config` 0x0A43
  includes `CSR_ALLOW_UNAPPROVED_KEXTS`. This has to be confirmed on the first real run.

## 1. Inventory: what a working machine has today

Taken read-only on 2026-11-05: macOS 26.7.1 (25G241), OpenCore 1.0.9 with the Zen 5 FSB patch, SIP custom
(`csr-active-config` 0x0A43 = untrusted kexts, unrestricted FS, unrestricted NVRAM, unapproved kexts,
unauthenticated root), authenticated root disabled, booted from a blessed snapshot (`com.apple.bless.66C4…`).

### 1.1 OpenCore EFI (internal ESP, `EFI/OC`)

| Part | Live content | Notes |
|---|---|---|
| `OpenCore.efi` + drivers | OC 1.0.9 from `963025f` + `patches/opencore/fix-zen5-fsb.diff`; `HfsPlus`, `OpenRuntime`, `ResetNvramEntry` | built by the `opencore` workflow |
| ACPI (enabled) | `SSDT-EC`, `-PLUG-ALT`, `-RMNE`, `-USB-Reset`, `-USBX`, `-XOSI`, `-ECRAM`, `-S0IDLE`, `-PTS5` | `SSDT-ECRAM` is on the ESP but **not** in `efi/OC/ACPI` of the repo |
| ACPI patches | `_OSI→XOSI`, `ACAD._PSR` skip ALIB, `_PTS→ZPTS` (pairs with SSDT-PTS5) | |
| Kernel/Add (on) | Lilu, VirtualSMC, SMCBatteryManager, AppleALC, AppleMCEReporterDisabler, BrightnessKeys, ForgedInvariant, HoRNDIS, ItlXhciKick, itlmt7925, itlmt7925Native, NullEthernet, NVMeFix, RestrictEvents, Sinetek-rtsx, USBToolBox + UTBMap, VoodooI2C (+GPIO, Services, Input) + VoodooI2CHID, AMFIPass, AmdCppc, BlueToolFixup, MtkBtFw, AsusWmi, BtLeDlFix, StrixProbe, StrixAmp, StrixMetalGate, StrixHeadroom, StrixVFCT, StrixSbxMap, RyzenHV | NVRM*/NVAccel/StrixAccel/StrixGOP entries exist but are **off** (those load from the AuxKC) |
| Kernel patches | AMD vanilla set (algrey et al.), 10-bit tags 26.0+, non-monotonic time (26.4+ variant), PAT fix, `fq_codel_dq` clamp | |
| Kernel/Block | `com.apple.iokit.IONDRVSupport` | IONDRVFramebuffer still appears on Tahoe (TRACE line 1587), so the installer has a GOP picture |
| boot-args | `debug=0x100 keepsyms=1 -vi2c-force-polling nvfb=1 nvaccel=1 nvfbheads=4 -nvkmsnosmooth amfi_get_out_of_my_way=0x1 amfi=0x80 msgbuf=1048576 ipc_control_port_options=0 itlmt_* … -nvrmnobootscreen nvrmacpibl=1 alcverbs=1 strixamp_trace=1 strixhdr=1 -strixgopoff -strixaccoff -strixmetalgateoff nmxamd=1 rhv_*` | several are trace flags (`itlmt_stat`, `strixamp_trace`, `rhv_selftest`) and belong in a "debug" profile only |
| PlatformInfo | `MacBookPro16,2`, Serial/MLB/UUID/ROM | **machine-specific**, never in the repo or the payload |
| DeviceProperties | 6 paths under `PciRoot(0x0)/Pci(0x8,0x1)` / `(0x8,0x3)` (890M model/VRAM, audio, …) | same for every GA403WM |
| `StrixVFCT.kext` | codeless kext carrying the firmware's VFCT table (890M VBIOS) | **built from a dump of the target's own VFCT**; vendor firmware, never committed or shared |
| `StrixSbxMap.kext` | pins (path, cdhash) of 8 files in `/Library/GPUBundles` into its Info.plist | must be **built after** the GPU bundles are installed (`macos-install-strixsbxmap.sh --refresh`) |
| `itlmt7925*.kext` | Wi-Fi | can carry injected Wi-Fi credentials in plain text: build fresh, never copy the live one |

The repo's `efi/OC/config.plist` is from 2026-10-11 and is far behind the live one. `scripts/export-efi.py` (sanitizes
the identifiers and fails on a leak) has to be run again before the repo copy can seed an installer.

### 1.2 `/Library/Extensions` (AuxKC, linked with `kmutil create -n aux`)

| Kext | Version | sha256 prefix | License / origin |
|---|---|---|---|
| NMXGPU | 1.0.0 | `5760efb63fc0eee9` | PolyForm; own build `7efe25b8` + cave chain, see 1.3 |
| NMXAccel | 0.1 | `48b3f689c1fc6b23` | PolyForm; fork CI `ci/nmxaccel-drmuc` 7bd4e99 (run 41789977284) |
| NMXAGDC | 0.1 | `37a390a5bcce8b7c` | PolyForm; fork CI + Step74 rename |
| NVRM | 2.7.1 | `dca5eac6cfca8e7c` | PolyForm; built from `nmx-translator-271` (`-nvrmnohold` build, installed by step112b) |
| NVRMFB, NVRMAGDC, NVAccel | 2.7.1 | `83390f17…`, `c90a08af…`, `de322206…` | PolyForm; NullMoth 2.7.1 upstream |
| NMXBacklight | 0.4.0 | `1a8e9b7d2fbb9f00` | BSD, `kexts/NMXBacklight` |
| StrixS0ix | 0.1.4 | `8cbe47a450be660c` | BSD, `kexts/StrixS0ix` |
| StrixAccel 0.1.21, StrixGOP 0.1.11 | | | BSD; still in the AuxKC but turned off with `-strixaccoff -strixgopoff` (drop them in the fresh profile) |

Known trap: kernelmanagerd rebuilds the AuxKC from its own list (which never holds NMXGPU or NMXAGDC) when a new kext
appears in `/Library/Extensions` (Step100b). Every installer here therefore relinks, checks again after 45 s, and
checks once more after the reboot.

### 1.3 How the live NMXGPU was produced

Source: NullMoth v2.0.4 tree, fork branch `ga403wm-nmx` (`~/develop/projects/nmx-src-2.0.4`, HEAD `2dbf59a`),
build env `~/develop/projects/gpu-src` (drm-kmod `c16de0f9fa`, freebsd-src `9d82546a`), `AMD_ONLY=1 kext/build.sh`.
The last source build was `7efe25b8` (Step69). Everything after that is binary patching:

| Step | Script(s) | Result sha prefix |
|---|---|---|
| 74 | `linux-patch-nmx-amdfb.sh` (NMXGPUFB → NMXAMDFB, also in NMXAccel/NMXAGDC) | `e75bb84b` |
| 75 | `linux-patch-nmx-scanout.sh` | `401c4e4c` |
| 77 | `linux-patch-nmx-rcu.sh` + `nmx-rcu/` | `02a336b4` |
| 78 | `linux-patch-nmx-mtxguard.sh` + `nmx-mtxguard/` | `9ea37786` |
| 79 | `linux-patch-nmx-idr.sh` | `c2979d9b` |
| 80 | `linux-patch-nmx-etime.sh` | `1e0e1524` |
| 84 | `linux-patch-nmx-zeroflush.sh` | `0a6c745a` |
| 88 | `linux-patch-nmx-snoopgtt.sh` | `3dbc47cc` |
| 89 | `macos-patch-nmx-step89.sh` + `nmx-ibprobe/step89_patch.py` | `47eec16d` |
| 90 | `linux-patch-nmx-step90.sh` + `nmx-wcsplit/` | `c9bf8730` |
| 91 | `macos-patch-nmx-step91.sh` | `b13ca867` |
| 92 | `macos-patch-nmx-step92.sh` + `nmx-userptr/` | `01ecc7bc` |
| 93 | `macos-patch-nmx-step93.sh` + `nmx-ibprep/` | `89969711` |
| 96 | `macos-install-step96.sh` (cstrace + userptr ro retry; reads the Step95 backup) | `44c7e552` |
| 97/97b | `macos-install-step97.sh`, `nmx-irqwatch/`, `nmx-mmfix/` | `c2326f22` |
| 99 | `macos-install-step99.sh`, `nmx-flip/step99_patch.py` (reads the Step98 backup) | `1907d9f9` |
| 100 | `macos-install-step100.sh`, `nmx-irqfix/`, `nmx-mmfix2/` | `d4830f51` |
| 100c | `linux-patch-step100c.sh`, `nmx-irqfix/st_move.py` | `3e1b6619` |
| 107 | `macos-install-step107.sh`, `nmx-s0ix/patch_s0ix.py` | `2a1bb264` |
| 112c | `macos-install-step112c.sh`, `nmx-s0ix/patch_fadt.py` | **`5760efb6` (live)** |

Steps 86, 95 and 98/98b were replaced or dropped. Every offset (for example 0x50ac10, 0x9270a0) is only valid for the
`7efe25b8` lineage, so a rebuild from source invalidates the whole chain. `scripts/nmx-caves/check.py` (cave registry)
and the per-cave `--check-kc` probes (`nmx-mmfix/step97b_patch.py:44`, `nmx-flip/step99_patch.py:54`,
`nmx-irqfix/patch_irqfix.py:149`, `nmx-mmfix2/step100_mm_patch.py:67`, `nmx-s0ix/patch_s0ix.py:51`,
`nmx-s0ix/patch_fadt.py:59`) are the verification to keep.

The NVIDIA script `macos-install-nvidia-2.7.1.sh` also gates on an NMXGPU sha (`3e1b6619…`). That means it ran
between Step100c and Step107, and on a fresh machine it cannot run after the final NMXGPU is in place without
changing that gate.

### 1.4 Userland

| Where | What | License |
|---|---|---|
| `/Library/GPUBundles/NVMTLDriver.bundle` | NullMoth plugin, replaced by the 890M plugin from the fork (`nmx-plugin-890m` / desc-cache branches) + translator dylib (`nmx-translator-271`) | PolyForm (translator carries GPL/LGPL-3.0 texts) |
| `/Library/GPUBundles/NVIDIAShared.bundle`, `nvmtl/` | NVK, RADV (`libvulkan_radeon`), libdrm, ICDs, caches | PolyForm + Mesa (MIT) |
| `/Library/GPUBundles/nvmtl-allow.txt` | = `scripts/nvmtl-allow.txt` (`*`, `!WindowServer`, …); must be readable by `_windowserver` | BSD |
| `/Library/NullMoth/` | upstream scripts, `gpu-userland/`, `firmware/` (7 MB), `nvfw/` (220 MB), `kexts/`, `licenses/`, about 190 backup folders | PolyForm + vendor firmware |
| `/Library/StrixGraphicsFix/` | `nmx-flip-default.sh` + `nmx-flip.mode` (1 = zero copy), relink tools, old `bootstrap.sh` | BSD |
| LaunchDaemons | `com.nullmoth.{bootguard,displaytrace,recover,wsdeath,wsreset}`, `com.ga403wm.nmx-flip-default`, `com.itlmt7925.{AmdCppcPolicy,strixamp,audio-boot-trace,graphics-bootstrap}` | mixed |
| LaunchAgents | `com.nullmoth.crashcheck`, `com.itlmt7925.rogaudiod`; per user: `com.itlmt7925.{ItlWiFi,RogControl,TapGuard,espmount}` | mixed |
| Programs behind them | `/Library/PrivilegedHelperTools/com.itlmt7925.*`, `/Library/Application Support/RogAudio`, `/Library/Audio/Plug-Ins/HAL/RogAudio.driver`, `/Applications/{ItlWiFi,RogControl,TapGuard}.app` | BSD (sister repos) |
| Display override | `/Library/Displays/.../DisplayVendorID-4c83` (HiDPI, embeds the panel EDID) | BSD, from `macos-install-hidpi.sh` |

### 1.5 Changes inside the sealed system (blessed snapshot)

| Change | Tool | Needed in the fresh profile? |
|---|---|---|
| `/dev/dri` rule in `com.apple.WindowServer.sb` | `scripts/ws-sandbox/ws-sandbox-dri.sh` (mounts the system volume, patches, `bless --create-snapshot`, reboots) | to check: Step102's DRM-through-IOKit path (NMDR user client) may have made it unnecessary for WindowServer; test on the first fresh run with and without it |
| `VTStub.bundle` in `/System/Library/Video/Plug-Ins` | `tools/890m/vtstub/install.sh --system` | **no**: experiment, gated by `/tmp/vtstub.on`; leave it out |

Both need authenticated root disabled (0x800 in csr) and must be redone after every macOS update.

## 2. Dependency graph and stages

```
 BIOS: Secure Boot off (or enrolled, docs/SECURE-BOOT.md), CSM off, Above 4G decoding on
   │
 S0  build the USB (on any Mac, this machine included)  ─────────────────────────────── no target needed
   │   OpenCore 1.0.9+zen5, install-profile config, SMBIOS generated per target, macOS 26 installer, payload volume
   │
 S1  boot the USB → macOS installer → installs to internal disk (the installer reboots 2-3 times by itself;
   │   OpenCore on the USB picks "macOS Installer" automatically)                         needs: OC on USB only
   │
 S2  first boot (still from the USB OpenCore) → Setup Assistant (user account)           manual
   │
 S3  Setup app, stage "efi"   [admin password #1]
   │   dump VFCT → build StrixVFCT; copy the EFI to the internal ESP with the same SMBIOS; full-profile config
   │   (csr 0x0A43, AMFI boot-args); boot entry; ocvalidate; arm the resume daemon               → REBOOT 1
   │
 S4  stage "le + userland"   (resume daemon, then admin password #2 in the app)
   │   NullMoth 2.7.1 upstream install.sh (tarball sha-checked) with NMXAudio held back
   │   → golden overlay: NMXGPU, NMXAccel, NMXAGDC, NVRM, NMXBacklight, StrixS0ix → /Library/Extensions
   │   → 890M plugin + translator, RADV/libdrm, allow list, flip-default daemon, helpers/apps/agents
   │   → StrixSbxMap built with the pins of the files just installed → ESP
   │   → kmutil create AuxKC, kccheck (UUIDs + cave byte windows), recheck after 45 s           → REBOOT 2
   │
 S5  stage "verify"  (resume daemon, no password)
   │   kexts loaded, AuxKC on disk still complete, NMXGPU modeset, WindowServer on the 890M, NVIDIA headless,
   │   Wi-Fi, audio, brightness; optional "system" stage (WindowServer.sb) if the S5 test needs it → REBOOT 3
   │
 done: the app shows a report; the resume daemon removes itself
```

Order rules that matter:

1. SIP and AMFI come from OpenCore (`NVRAM > Add` + `Delete` of `csr-active-config` and `boot-args`), so they only
   change when the machine boots the **full** EFI. S4 must therefore run after a boot from the internal ESP (REBOOT 1);
   it cannot run straight after Setup Assistant.
2. The installer profile (S1) should be the base set only: Lilu, VirtualSMC, SMCBatteryManager, ForgedInvariant,
   USBToolBox + UTBMap, ItlXhciKick (USB lag), VoodooI2C + HID (touchpad), NVMeFix, RestrictEvents, AmdCppc,
   itlmt7925/Native, HoRNDIS + NullEthernet, AppleALC, the kernel patches, and SIP left at the default (csr 0). No
   Strix*, no NVRM, no AMFIPass. If the installer fails, this set is small enough to debug.
3. The NullMoth upstream `install.sh` must run **before** the golden overlay: it writes NVRM/NVRMFB/NVAccel/NVRMAGDC,
   NVK and firmware, and it would replace the 890M plugin and the allow list. The current
   `macos-install-nvidia-2.7.1.sh` gate on NMXGPU `3e1b6619` has to become "NMXGPU = manifest sha" (or be removed:
   the overlay rewrites NMXGPU right after).
4. StrixSbxMap pins cdhashes of files under `/Library/GPUBundles`, so it is built **after** S4 copies them. It goes to
   the ESP in the same stage, and both load on REBOOT 2.
5. One AuxKC relink at the end of S4, not one per kext. A new kext added after the relink triggers kernelmanagerd
   (Step100b).
6. Anything that touches `/System` runs last and on its own reboot, so a failure there can be rolled back by booting
   the previous snapshot (`bless --last-sealed-snapshot` or the OpenCore picker).

### Machine-specific versus shared

| Machine-specific (generated or dumped on the target) | Shared by every GA403WM |
|---|---|
| SMBIOS Serial, MLB, SystemUUID (`macserial` for MacBookPro16,2), ROM (6 bytes; use the Wi-Fi MAC or random) | config.plist minus PlatformInfo, SSDTs, DeviceProperties paths, kernel patches |
| `StrixVFCT.kext` (VFCT dump of this board's VBIOS) | all kexts and userland in the manifest |
| Wi-Fi credentials if Ethernet-mode `itlmt7925` is used (`inject-creds`) | allow list, flip mode, launchd jobs |
| the user's home-folder LaunchAgents (`espmount` path has the user name) | `/System` changes (same macOS build) |
| HiDPI override (embeds the panel EDID; same panel model → same file, but regenerate to be safe) | |

## 3. Delivery options

### (a) USB image only: EFI + payload partition + first-boot script

The USB holds the EFI, the installer and a payload. A first-boot LaunchDaemon, copied onto the new system, does the
rest.

* Pros: no app to write; works offline; one artifact to hand over.
* Cons: nothing can be copied into the new system before Setup Assistant except through the installer itself, so the
  "first-boot script" still has to be started by hand from the USB (Terminal + `sudo`). No progress UI or report;
  errors end up in a log file. Reboot sequencing, admin prompts and verification all become text instructions.
* Effort: low (about 1-2 days on top of the shared work in section 4).

### (b) A macOS installer app or `.pkg` (no USB EFI)

A `.pkg` (or app) installed on a macOS that already boots, which installs everything.

* Pros: a familiar flow; `.pkg` postinstall scripts run as root with one password; it can be downloaded.
* Cons: it does not solve the fresh-install problem: something still has to boot the macOS installer on an AMD
  laptop, which means an OpenCore USB anyway. A `.pkg` is a poor fit for a three-reboot state machine. An unsigned,
  quarantined `.pkg` or app needs right-click → Open (Gatekeeper); a Developer ID signature costs money and does
  not cover the unsigned kexts anyway. Kext approval: with csr 0x0A43 there is no "Allow" prompt, but only after the
  full EFI is booted, which a `.pkg` cannot arrange by itself.
* Effort: medium; it ends up needing the USB of (a) as well.

### (c) Hybrid: USB EFI for the install, then one post-install app that applies and verifies (recommended)

The USB from (a) plus `GA403 Setup.app` on its payload volume. The app is a thin UI over the same stage scripts. A
resume LaunchDaemon carries the state across reboots.

* Pros: the user flow comes close to one click (start the app once, type the password at each stage, confirm each
  reboot). Stages are checked against the manifest. The app can show a pass/fail report and a rollback button. The
  same scripts work without the app (CLI), which keeps it debuggable over SSH or from Linux. Files on a volume we
  made carry no quarantine attribute, so an ad-hoc signed app from the stick should open without a Gatekeeper prompt
  (to confirm on the first run).
* Cons: the most work; two reboots more than the bare minimum, a deliberate trade for safety (section 2, rule 1).
* Effort: medium. Scripts and manifest about 3-5 days, the app about 1-2 days, plus a test install on a spare SSD.

### Licensing in all three options

* This BSD repo carries: the manifest schema, the stage scripts, `kccheck` (section 4.4), the sources of our kexts,
  `efi/` (which stays under its 1401-derived terms, as today), and sha256 values of everything else.
* PolyForm Noncommercial parts are never committed here. The installer takes them in one of three ways, in this
  order of preference:
  1. **Release assets of the fork** (`thanhnndev/nvidia-macos-driver`): one tarball per manifest version,
     `ga403wm-polyform-payload-<ver>.tar.gz`, carrying its own `LICENSE` (PolyForm NC) and the NullMoth notices. The
     manifest names the URL and the sha256. The installer downloads it only after asking.
  2. **A local folder** given to the app ("choose payload folder"), for example the `payload/` that
     `capture-live.sh OUT --copy` produced on this machine.
  3. **The upstream NullMoth 2.7.1 tarball** from `github.com/nullmoth/nvidia-macos-driver` releases, checked
     against `0b28f420…7851` (the value in `macos-install-nvidia-2.7.1.sh:23`), for the parts we do not change.
* Third-party EFI kexts (acidanthera, VoodooI2C, USBToolBox, …) are not redistributed by the repo either:
  `efi/kexts.json` already lists their versions and sha256. The USB builder downloads them from their releases (with
  the owner's approval) or takes them from a local folder.
* Vendor firmware (VFCT/VBIOS, NVIDIA GSP in `nvfw/`) is never published by us: the VFCT is dumped on the target,
  and `nvfw/` comes with the NullMoth package.

## 4. The plan (option c)

### 4.1 File layout

In this repo (BSD):

```
scripts/fresh-install/
  capture-live.sh          prototype, done: hash (and with --copy, collect) the live stack into OUT/
  verify.sh                prototype, done: compare a manifest with the live system or a payload folder
  manifest.example.json    prototype, done: the schema by example
  build-usb.sh             todo: partition + fill a USB from a manifest (S0)
  stage-efi.sh             todo: S3 (VFCT dump, StrixVFCT, SMBIOS, ESP copy, ocvalidate)
  stage-le.sh              todo: S4 (NullMoth upstream, overlay, StrixSbxMap, relink, kccheck)
  stage-verify.sh          todo: S5 (runtime checks, report JSON)
  stage-system.sh          todo: optional /System stage (wraps ws-sandbox-dri.sh)
  resume.sh + com.ga403wm.fresh-install.plist   todo: resume daemon, reads /Library/GA403/state.json
  undo.sh                  todo: roll back one stage from its backup
  kccheck/                 todo: small C tool, LC_UUID + byte-window checks (no python on a fresh macOS)
  profiles/install.json    todo: installer-profile overrides for config.plist (base kexts, csr 0, no AMFI args)
  profiles/full.json       todo: full-profile overrides (today's live config minus trace flags)
  app/                     todo: GA403 Setup.app (SwiftUI, calls the stage scripts through one osascript admin call per stage)
docs/FRESH-INSTALL.md      this file
```

On the USB (built by `build-usb.sh`, never committed):

```
EFI (FAT32, 512 MB)        EFI/BOOT/BOOTx64.efi, EFI/OC/{OpenCore.efi,Drivers,ACPI,Kexts,config.plist}  (install profile)
Install macOS Tahoe        createinstallmedia volume (full installer, works offline); or BaseSystem from macrecovery
GA403-PAYLOAD (APFS)       manifest.json, GA403 Setup.app, scripts/, bsd/ (our kexts + apps, built),
                           thirdparty/ (EFI kexts from upstream), polyform/ (payload tarball or folder),
                           vendor/nullmoth-nvidia-2.7.1.tar.gz, smbios.plist (generated for THIS target, chmod 600)
```

On the target: `/Library/GA403/` holds `state.json`, the manifest copy, stage logs, and backups
(`/Library/GA403/backup/<stage>-<UTC>/`).

### 4.2 Manifest format

JSON, so stock `plutil -extract` can read it on a fresh system (`verify.sh` does this today). One row per component:

| Field | Meaning |
|---|---|
| `id` | unique name (`kext-NMXGPU`, `tree-nvmtl`, `acpi-SSDT-PTS5.aml`) |
| `stage` | `efi`, `le`, `userland`, `launchd`, `system` |
| `order` | install order inside the stage (gaps of 10) |
| `license` | `BSD-3-Clause-Clear`, `PolyForm-Noncommercial-1.0.0`, `third-party`, `Apple-modified`, `generated` |
| `source` | `repo:<path>`, `build:<target>` (from `scripts/build.sh`), `payload:<path>`, `upstream:<url>#sha256` |
| `dest` | absolute path, or `ESP:EFI/OC/...` |
| `kind` | `kext-exe` (sha of the executable), `kext-tree`, `tree` (sha over sorted `sha  path` lines), `file` |
| `sha256` | expected value after install |
| `bundle_id`, `version`, `lc_uuid` | for kexts; `lc_uuid` is what `kccheck` looks for in the AuxKC |
| `after`, `refresh` | dependencies (`gpubundle-NVMTLDriver` refreshes `strixsbxmap-pins`) |
| `machine_specific` | keys generated on the target (config.plist PlatformInfo) |
| `check` | `sha256`, `aux-kc-uuid`, `loaded`, `ocvalidate`, `readable-by:_windowserver`, `kc-windows:<probe file>` |
| `provenance` | free text: fork branch and commit, CI run, cave chain |

Top level: `schema`, `profile`, `macos.build` (the stack is tied to one macOS build; the app refuses another build
unless overridden), `opencore`, `csr_active_config`, `components[]`. `capture-live.sh` writes the same shape from the
live system (93 components today: 45 EFI, 12 AuxKC, 18 userland, 16 launchd, 2 system). On this machine,
`verify.sh` reports `match 85, differ/missing 0, skipped 1` (the AuxKC itself, which is checked through the kext
UUIDs instead).

### 4.3 What each stage does

**S0 build-usb.sh** (on this Mac): erase the stick (only after typing its name), make the 3 partitions, run
`createinstallmedia` from `Install macOS Tahoe.app` (`softwareupdate --fetch-full-installer`, about 17 GB, needs the
owner's OK), or as a fallback `macrecovery.py -b Mac-CFF7D910A743CAAF -m 00000000000000000 -os latest download` (needs
network inside Recovery, which is less certain here). Build our kexts (`scripts/build.sh`). Assemble the
install-profile config from `efi/OC/config.plist` + `profiles/install.json`. Generate the SMBIOS (`macserial`) once
per target and write it to `smbios.plist` on the payload volume, so the USB config and the later internal config use
the same identity. Run `ocvalidate`. Copy the payload and verify it with `verify.sh --payload`.

**S3 stage-efi.sh** (root, from the app): mount the internal ESP, back it up if it has an EFI already (dual boot:
keep `EFI/Microsoft`, `EFI/limine`, see `docs/DUAL-BOOT.md`). Dump the VFCT (see 4.6) and build `StrixVFCT.kext` with
`macos-strixvfct-install.sh`. Copy OC + drivers + SSDTs + EFI kexts. Write the full-profile config (with the SMBIOS
from the stick), run `ocvalidate`. Install the resume daemon. Set `state.json` to `efi-done`, then ask for the reboot.
The user picks the internal OpenCore once (or the BIOS boot order is set).

**S4 stage-le.sh** (root): check that the boot really came from the internal ESP with csr 0x0A43 (`csrutil status`,
`nvram csr-active-config`) and the AMFI boot-args, and stop with a clear message if not. Unpack the NullMoth 2.7.1
tarball (sha-checked) and run its `install.sh` the way `macos-install-nvidia-2.7.1.sh` does (NMXAudio held back).
Copy the golden overlay to `/Library/Extensions` (`chown -R 0:0`, `chmod -R go-w`) and the userland trees and files.
Then `nvmtl-desccache/install.sh` equivalent: plugin + translator, allow list readable by `_windowserver`. Install the
launchd jobs and programs, build StrixSbxMap with the new pins and put it on the ESP. Then one `kmutil create -n aux`
into `AuxiliaryKernelExtensions.kc.ga403`, `kccheck` (all 8 UUIDs + the NMXGPU cave windows, see 4.4), `mv`, wait
45 s, `kccheck` again. Last, `verify.sh --stage le` and `--stage userland`, then ask for the reboot.

**S5 stage-verify.sh** (root, no password: runs from the resume daemon, the app shows the result): run the checks of
4.4 and write `/Library/GA403/report.json`. If every check passes, the daemon removes itself.

### 4.4 Verification checks

Static (before each reboot):

* `verify.sh MANIFEST --stage <s>`: sha256 of every installed file.
* `kccheck AuxKC`: the LC_UUID of NMXGPU, NMXAccel, NMXAGDC, NMXBacklight, NVRM, NVAccel, NVRMFB, NVRMAGDC (and
  StrixS0ix) appears in the collection, and each cave probe window (`offset length` lines, as in
  `/Library/StrixGraphicsFix/nmx-relink.probes`, Step100c) appears exactly once. This replaces the python parts of
  `uuids_in()` (`macos-install-nvidia-2.7.1.sh:76`) and `check_kc()` (`nmx-relink/nmx-relink.sh:24`): a fresh macOS
  has no python3 or otool until the Command Line Tools are installed. `nmx-caves/check.py` is a build-time check: the
  golden NMXGPU passed it when it was made, and the sha match proves it is the same file.
* `ocvalidate` on the written config.plist; `plutil -lint`.
* `sudo -u _windowserver test -r /Library/GPUBundles/nvmtl-allow.txt`.

Runtime (S5, after REBOOT 2):

* `kmutil showloaded`: every bundle id of the manifest's `le` stage plus the enabled EFI kexts, at the manifest
  version.
* AuxKC on disk still passes `kccheck` (kernelmanagerd did not replace it).
* `ioreg -rc NMXAMDFB` present and online; `/usr/bin/log show --last boot --predicate 'sender == "NMXGPU"'` has the
  modeset line; no `*.panic` newer than the stage start in `/Library/Logs/DiagnosticReports`.
* WindowServer on the 890M: the NVMTL log line for WindowServer names RADV STRIX1 (as in Step102b); its CPU use
  after 60 s idle is under a threshold.
* NVIDIA: `ioreg -rc NVRM` present, headless, NVRM hold released (boot-time audit).
* Brightness: NMXBacklight present; Wi-Fi: `itlmt7925Native` interface up; audio: RogAudio HAL device listed;
  `pmset -g` sane (no sleep test here: a sleep test is the owner's call).
* `system_profiler SPDisplaysDataType` shows "AMD Radeon 890M" with 512 MB (DeviceProperties).

### 4.5 Rollback, undo, idempotency

* Every stage writes its backup first, to `/Library/GA403/backup/<stage>-<UTC>/`: the ESP folder, the replaced
  files, and the old AuxKC. `undo.sh <stage>` restores the newest backup, relinks and reboots. That matches the
  `--undo` pattern of today's step scripts.
* If REBOOT 2 does not come up: the OpenCore picker → the USB stick's EFI (install profile, no AuxKC kexts from us,
  SIP default) still boots the installed macOS. From there `undo.sh le` runs, or, as a last resort, deleting
  `/Library/KernelCollections/AuxiliaryKernelExtensions.kc` gives a boot without any third-party AuxKC kexts. Linux
  from the USB is a further route (the repo already has `linux-*` installers and `nmx-relink`).
* The `system` stage: the previous snapshot stays bootable; undo = `ws-sandbox-dri-undo.sh` or
  `bless --last-sealed-snapshot` from Recovery.
* Idempotency: `state.json` records the stage reached and the manifest sha. Each stage first runs `verify.sh` for its
  rows and skips rows that already match, so running the app again after a crash continues instead of redoing work. A
  different manifest version means "upgrade": back up, then apply only the rows that differ.
* The app never deletes a backup. `/Library/NullMoth` already holds about 190 backup folders; cleaning those up is a
  separate decision.

### 4.6 Automated versus needs a person

| Step | Automated | Person |
|---|---|---|
| BIOS (Secure Boot, CSM, Above 4G) | no | yes, once |
| Build the USB | yes (`build-usb.sh`) | approve the downloads (installer, third-party kexts, payload), type the disk name |
| Boot the USB, run the installer | the installer reboots by itself | pick the USB in the boot menu, pick the target disk |
| Setup Assistant | no | yes |
| S3 EFI to internal disk | yes | password #1, confirm the reboot, pick the internal entry once |
| VFCT dump | see below | maybe |
| S4 drivers and userland | yes | password #2, confirm the reboot |
| S5 verify | yes | read the report |
| optional `system` stage | yes | password #3, confirm the reboot |

VFCT dump on a fresh machine: Tahoe no longer publishes "ACPI Tables" (that is why StrixVFCT exists). Options, best
first:

1. The OpenCore DEBUG build on the USB with `Misc > Debug > SysReport = true`. On the first USB boot it dumps every
   ACPI table to `EFI/SysReport/ACPI/` on the stick, and S3 picks up the VFCT there. To verify: that the dump really
   contains VFCT (it is listed in the XSDT on this board).
2. Windows or Linux on the same machine (`/sys/firmware/acpi/tables/VFCT`), the way it was done the first time.
3. The machine owner provides the file.

### 4.7 Risks and open questions

* **No full install has ever been done with this stack** (README: only Recovery from USB was tested on 15.6.1; the
  live system was upgraded in place to Tahoe). The first fresh run should target a spare SSD or an external disk,
  with this disk untouched.
* **kmutil approval.** Expected: no Privacy & Security prompt with `CSR_ALLOW_UNAPPROVED_KEXTS`. If one appears, the
  app shows the user where to click and waits.
* **kernelmanagerd** may rebuild the AuxKC at the first boot that sees new kexts. That is covered by the 45 s check
  and the post-boot check, but S4 might need a second relink pass from the resume daemon (as `nmx-relink.sh` does).
* **The golden payload is tied to macOS 25G241.** A different Tahoe build needs the ABI checks of the trace (StrixAccel
  profile, Wi-Fi native ABI) before the manifest's `macos.build` can change.
* **`graphics-bootstrap` LaunchDaemon** (`/Library/StrixGraphicsFix/bootstrap.sh`) is stale: it lists StrixAccel
  0.1.15 / NVRMEdpBL and its last status is `LOAD_FAILED exit=2`. Leave it out of the fresh profile (and consider
  removing it here).
* **Trace flags** in boot-args (`itlmt_stat`, `itlmt_native_nvtrace`, `strixamp_trace`, `rhv_selftest`,
  `rhv_loglevel=4`) and `debug=0x100`: the full profile should drop them, and a "debug" profile can add them back.
* **NVRM boot hold** costs about 36 s at boot (boot-time audit, 2026-11-05). This is not an installer problem, but
  the S5 report should time the boot so the fix can be measured later.

## 5. Next steps

1. **Capture** (no risk): `scripts/fresh-install/capture-live.sh ~/ga403-payload-25G241 --copy` on this machine, to a
   folder outside the repo. Keep it private (PolyForm parts). Also save the exact NullMoth 2.7.1 tarball again
   (download, with the owner's OK) and check it against `0b28f420…7851`.
2. **Refresh the repo's EFI**: `scripts/export-efi.py` from the live ESP into `efi/OC` (sanitized), add
   `SSDT-ECRAM`, and split `profiles/install.json` / `profiles/full.json`.
3. **Write `kccheck`** (C, about 100 lines) and port the 8-UUID and probe-window checks to it. Test it on the live
   AuxKC; it must agree with today's python checks.
4. **Write the stage scripts** (S3, S4, S5, resume daemon, undo) on top of `verify.sh` and the existing step-script
   helpers (`relink()`, `checks()`), and change the NMXGPU gate in the NVIDIA install step.
5. **Dry run on a spare SSD** (or an external NVMe), CLI only, without the app. Record every manual step.
6. **The app** (SwiftUI wrapper) once the CLI run passes.
7. **Longer term: make NMXGPU buildable.** Port each cave from 1.3 into the fork branch `ga403wm-nmx` as a source
   change, let CI build NMXGPU, and switch the manifest row from "captured" to "CI artifact". That also ends the
   offset bookkeeping in `nmx-caves/check.py`.
