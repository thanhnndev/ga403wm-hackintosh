# Contributing

Reports and patches are welcome, especially: results on other Zephyrus G14 / Strix Point laptops (`ItlXhciKick`, the EFI),
other MT7925 machines (the Wi-Fi driver), and the open items in [docs/ROADMAP.md](docs/ROADMAP.md).

> This project is vibe-coded (written mostly by an AI, tested on one laptop). Pull requests written with AI help are fine;
> say so, and say what you tested on real hardware.

## Branches: where development happens

| Branch | State |
|---|---|
| **`main`** | **The only long-lived branch.** Always buildable; every push builds the kexts in CI. |
| `track/<nn>-<name>` | Short-lived topic branch for one roadmap workstream (for example `track/04-wifi-throughput`, numbers from [docs/ROADMAP.md](docs/ROADMAP.md)). Open a pull request into `main`; delete the branch after merging. |
| `v0.<n>` (tags) | Releases cut from `main`. |

Driver work on NullMoth's NVIDIA driver is done in a fork and sent upstream first; this repository only carries the machine
patch until it is merged.

Start new work from `main`: `git switch main && git pull && git switch -c track/<nn>-<name>`. If you take a roadmap item, update
its row (state, "Doing now") in the same pull request.

Current state, open issues and how to collect data: [docs/HANDOFF.md](docs/HANDOFF.md).

* **macOS:** `bash scripts/build.sh` builds `build/*.kext` locally (needs Xcode command line tools).
* **Linux / Windows:** the kexts cannot be built there (they need the macOS SDK). Push the branch and let CI build it:
  `gh workflow run build.yml --ref <branch>`, then `gh run download <run-id> -n kexts` (artifacts carry empty Wi-Fi
  credentials; inject yours locally with `scripts/inject-creds.ps1`).
* The per-machine state (which kext is on the ESP, current boot-args, bisect notes) lives outside the repo; the
  `efi/` tree is the sanitized reference configuration.

## Before you post a log, a config or a kext

* **Redact** serial numbers, MLB, SystemUUID, ROM, Wi-Fi passphrases, your MAC address and the SSIDs/BSSIDs of other
  networks. NVRAM logs contain the last two.
* Never commit a `config.plist` with your SMBIOS values. `scripts/export-efi.py` writes `efi/` from a working EFI with
  placeholders, and `scripts/check-efi-privacy.py` (also run in CI) fails if real values slipped in.
* Never commit a kext whose `Info.plist` has `itl_psk*` filled in.

## Building and testing

```bash
cd test && clang++ -std=c++17 -I../kexts/itlmt7925 wpa_test.cpp ../kexts/itlmt7925/itl_wpa.cpp -o wpa_test && ./wpa_test
bash scripts/build.sh            # macOS with Xcode command line tools
```

The driver can only be exercised on hardware. Please say in the pull request which machine, macOS build and boot
environment (Recovery or installed) you tested on, and attach the redacted `itlk*` / `itls0` / `itlz0` output.

## Code

* Hardware behaviour is ported from the Linux `mt76` driver; cite the Linux function in a comment next to the port and keep
  the MediaTek copyright notice.
* No patching of Apple binaries, no raw writes to registers the Linux driver does not touch, without a written reason.
* Keep the files under the Clear BSD License (`SPDX-License-Identifier: BSD-3-Clause-Clear` on top); `efi/` is the exception, see `NOTICE.md`.

## Releasing (maintainers)

1. Run the `build-kexts` workflow by hand (Actions → Run workflow) on `main` and check that kexts, apps and `AmdCppcPolicy` build.
   Run `opencore` too if the patch changed.
2. Update [.github/release-body.md](.github/release-body.md) (known problems, what changed).
3. `git tag v1 && git push origin v1`: the `build-kexts` workflow rebuilds everything, builds the patched OpenCore, adds the
   sanitized `EFI-reference.zip` and `SHA256SUMS.txt`, and publishes the GitHub release. Kexts in a release always carry
   **empty** Wi-Fi credentials.
