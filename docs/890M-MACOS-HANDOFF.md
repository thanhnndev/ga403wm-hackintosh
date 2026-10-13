# Radeon 890M: macOS handoff

Branch: `research/890m-cobalt64`. Start here when continuing on macOS.
Research rationale: [port research](890M-COBALT64-PORT-RESEARCH.md).
Step-by-step history: [890M trace](890M-TRACE.md).

## Current state

Latest2026-10-13: first runtime0.1.0 captured valid VFCT/VBIOS matching Linux,
but PCI snapshot was too early or otherwise unavailable. Later IORegistry
contains890M; GOP candidate matches its BAR0. Probe0.1.1 now staged with a
PCI publish notification retry; reboot pending. Run collect after reboot,
require ProbeVersion0.1.1 and PCI,MatchCount1 before framebuffer work.
Previous bundle backup: `EFI/OC/Kexts-backup/StrixProbe.kext.20261013-0836`.

Update2026-10-13: macOS link and offline defined-symbol review completed;
StrixProbe staged on ESP with `strix-probe=1`, config backup
`config.plist.pre-strixprobe-20261013-0832`. Reboot pending. Owner reports
Hybrid mode; current hiding properties preserved. See the latest Step02 trace.
After reboot run `bash scripts/macos-strix-probe-collect.sh` first.
The original build instructions and pre-staging state below remain historical.

- Step 01 **PASS** on the real Linux captures: VFCT contains the 21504-byte
  VBIOS for PCI1002:150e at65:00.0, byte-for-byte equal to the debugfs dump.
  AtomBIOS identifies the eDP path; EDID decodes 2880×1800 at60/120Hz.
- Step 02 **object compilation verified**, not yet linked or loaded on macOS.
  `StrixProbe` is a diagnostic IOResources service, enabled only by
  `strix-probe=1`; it does not bind to/open the GPU or initialize any engine.
- Current EFI still hides the iGPU. Leave that configuration intact for the
  first diagnostic census; PCI enumeration does not require graphics matching.
- No GPU register writes, kext installation, EFI changes or GPU power changes
  have been performed for this work.

Raw Linux fixtures and per-run evidence are local under ignored `out/`.
Reference repositories/SDK clones under `ref/` and `build/` are also ignored.
The committed trace includes results, hashes and pinned reference commits;
macOS does not need these Linux fixtures to build Step 02.

## Next action on macOS: build and capture evidence

In the existing repo, with local work saved first:

```sh
git fetch origin
git switch research/890m-cobalt64
git pull --ff-only origin research/890m-cobalt64
bash scripts/macos-strix-probe-build.sh
```

If this is a fresh checkout:

```sh
git clone --branch research/890m-cobalt64 https://github.com/thanhnndev/ga403wm-hackintosh.git
cd ga403wm-hackintosh
bash scripts/macos-strix-probe-build.sh
```

Needs Python3 and Xcode command line tools. The build uses the repo's normal
MacKernelSDK workflow (clones it into `build/MacKernelSDK` if absent); an existing
SDK can be selected with `MACKERNELSDK`. The probe is excluded from a default
`scripts/build.sh` build and built only when explicitly requested.

No sudo is needed. The wrapper does **not** install/load a kext, edit EFI or reboot.
It preserves a timestamped `out/890m-trace/step02-build-*/` directory containing:

- Build stdout/stderr, macOS/kernel/compiler versions and Git state.
- SDK commit, source/binary hashes, bundle plist validation and Mach-O header.
- Unresolved symbols and the exact built bundle archive.
- `manifest.json` with build/validation exit codes and explicit runtime status.

Success means `LINKED-symbol-review-pending`, **not** a hardware pass.
Return the printed status and trace directory. On failure, inspect
`build.stderr.txt` and `build.stdout.txt` there. Keep the failure trace and create
a new attempt after any fix; do not replace old evidence.

## Instructions for the agent continuing this work

1. Read this handoff, the research and trace before modifying code.
2. Review the macOS build trace. Confirm x86_64 KEXT_BUNDLE, the kmod descriptor,
   absence of `__cxa_atexit`/exception-runtime dependencies, and that unresolved
   symbols are provided by the target kernel or declared OSBundleLibraries.
   Successful linking alone does not prove symbol availability at load time.
3. Record every attempt under Step 02: environment, source/build identity,
   commands, observations, status and next gate. Distinguish offline, compile,
   link, load and hardware results. Preserve failed attempts.
4. Prepare a concrete separate test configuration only after symbol review.
   Do not run a generic install script blindly: StrixProbe is not yet listed in
   production Kernel/Add. Keep current iGPU hiding properties and production
   graphics settings unchanged for the initial diagnostic. Do not load Cobalt64.
5. Runtime trial uses `strix-probe=1`. Removing that boot argument disables the
   diagnostic service's matching. Keep a known-working config for recovery.
   This test plan is still pending; no runtime install has been validated.
6. After a successful load, capture the service with:

   ```sh
   bash scripts/macos-strix-probe-collect.sh
   ```

   It saves ioreg, a capture manifest and VFCT.bin when available. Review
   `PCI,MatchCount`/`PCI,Status`, BAR descriptors, hiding properties, console
   dimensions/base/stride and `VFCT,Status`. Require exactly one target.
   `captured-owner-unverified` means the console was read, not proved to belong
   to 890M. VFCT/PCI absent at this boot snapshot may be a publication-timing
   issue; do not infer absence of the hardware/table.
7. Parse any captured VFCT offline with `tools/890m_inspect.py --vfct PATH`.
   Do not equate a Linux firmware allocation/address with macOS ownership.
8. Only after baseline review consider framebuffer adoption or controlled
   indirect register access. IP discovery, MMIO, PSP/SMU/SDMA/GFX init, native
   DCN35/eDP, power management and Metal integration remain later milestones.

Synthetic parser tests can run without Linux fixtures:

```sh
python3 test/890m_inspect_test.py -v
```

The two local-capture checks will skip when fixtures are absent. Do not rerun
`890m_step01.py` with default Linux paths on macOS and call missing fixtures a
port failure. Existing Wi-Fi ABI research is separate under
`abi/native-wifi/24H32/round10/`; retain it while working on this branch.
