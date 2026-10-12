# nullmoth-readback — diagnostics and one conditional fix for NullMoth 1.14.2

Written against `nullmoth/nvidia-macos-driver` tag `v1.14.2` (`1083a98db33a0bb824290556de255f9a95ca5403`), which is also upstream `main`'s head
as of 2026-10-12. Background, decision table and runbook: [`docs/WINDOWSERVER-READBACK.md`](../../docs/WINDOWSERVER-READBACK.md).

```
files/plugin/nvmtl_surfstat.h             new: per-IOSurface statistics (plain C, unit-tested on the host)
files/kexts/NVRM/accel/nvsv_pend.h        new: pending-page-off table keyed by resource (plain C, unit-tested on the host)
0001-plugin-surfstat.patch                hooks in NVMTLDevice.m / NVMTLObjects.m / nvmtl_vk.{c,h}; off unless /Library/NullMoth/surfstat-request exists
0002-nvaccel-diagnostics.patch            debug.nvaccel_ss_* counters + distinct dirty-refusal statuses (still "non-zero = refused")
0003-nvaccel-pend-release-on-free.patch   the only behavioural change: drop a freed resource's pending entries — apply only if the counters call for it
apply.sh                                  checks the checkout is v1.14.2 and clean, dry-runs on a throw-away worktree, then applies
```

```sh
git clone --branch v1.14.2 https://github.com/nullmoth/nvidia-macos-driver ~/nvmtl-readback
bash patches/nullmoth-readback/apply.sh ~/nvmtl-readback --check            # nothing changes
bash patches/nullmoth-readback/apply.sh ~/nvmtl-readback                    # 0001 + 0002
bash patches/nullmoth-readback/apply.sh ~/nvmtl-readback --with-fix         # 0001 + 0002 + 0003 (on a fresh checkout)
make -C test/readback test                                                  # host tests, no GPU needed
```

`files/` is the single source of the new headers: `apply.sh` copies them into the checkout and `test/readback` compiles the same files. The patches
only modify upstream files. Applying them to a fresh v1.14.2 checkout reproduces the reviewed tree byte for byte (checked when they were generated).

Not compiled here: the Objective-C and kext sources need Apple SDKs. The C changes in `nvmtl_vk.c` and the bodies of the changed Objective-C methods were
syntax-checked on Linux against stub headers (no new diagnostics compared with the unpatched file, 296 identical pre-existing stub errors); the kext
changes were reviewed by reading only. Treat the first Mac build as the real compile.

Rollback: `scripts/macos-readback-plugin-install.sh --undo`, `scripts/macos-readback-nvaccel-install.sh --undo`, reboot. Statistics off at once:
`sudo rm /Library/NullMoth/surfstat-request`.
