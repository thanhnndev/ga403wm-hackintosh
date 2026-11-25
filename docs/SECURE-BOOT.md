# Turning BIOS (UEFI) Secure Boot back on with OpenCore

Research done 2026-10-18 on the ASUS GA403WM (OpenCore DBG-109, config `SecureBootModel=Disabled`, `Vault=Optional`).
Read-only audit tool: `python3 -I tools/secureboot/sb-audit.py` (changes nothing).
Sources: OpenCore `Docs/Configuration.pdf` ("UEFI Secure Boot", "Apple Secure Boot", `FixupAppleEfiImages`, Vault) and
`Utilities/ShimUtils/README.md`, read through Context7 (/acidanthera/opencorepkg).

## Two different things called "secure boot"

| | UEFI Secure Boot (BIOS) | OpenCore `SecureBootModel` (Apple Secure Boot) |
|---|---|---|
| What it checks | Authenticode signature (or hash) of every `.efi` the firmware loads | Apple's IM4M manifests for boot.efi / kernel / kext collections |
| Where | Firmware (PK/KEK/db) | OpenCore, macOS side |
| Fits this machine | **Yes**, with signing | **No**: unsigned kexts (NMXGPU, StrixAccel, NVIDIA, IO80211 injection) are refused; OpenCore docs say so ("Things to consider (a)(b)") |

The request is the first one. Keep `SecureBootModel=Disabled`, `ApECID=0`, `Vault=Optional` (a Secure vault would block every
`config.plist`/kext edit we make several times a day; Vault only protects non-PE files, which UEFI SB does not cover anyway).

## What the audit found (this machine, before any change)

* `SecureBoot=0`, `SetupMode=0`: the firmware is in **User Mode with our own keys already enrolled** (sbctl-style names):
  PK `CN=Platform Key`, KEK `CN=Key Exchange Key` + Microsoft KEK 2011/2023, db `CN=Database Key` + Microsoft UEFI CA 2011/2023,
  Windows Production PCA 2011, Windows UEFI CA 2023, Option ROM CA 2023. All custom keys are valid until 2031-08-31.
  So nothing has to be enrolled for the OpenCore files: only signing is missing. Windows (`bootmgfw.efi`) and Limine
  (`limine_x64.efi`, already signed by `CN=Database Key`) will keep working.
* UNSIGNED on the ESP: `EFI/BOOT/BOOTx64.efi`, `EFI/OC/OpenCore.efi`, `Drivers/HfsPlus.efi`, `Drivers/OpenRuntime.efi`,
  `Drivers/ResetNvramEntry.efi`, `Tools/NullMothSafe.efi`. With Secure Boot on the firmware refuses every one of them.
* **Apple's own EFI files carry no PE signature at all** (empty certificate table; Apple authenticates them with IM4M
  manifests instead): `/usr/standalone/i386/boot.efi` (identical to the Preboot copy) and `apfs.efi`.
  We cannot sign them (Preboot/system volume are sealed), and the firmware cannot match them to a certificate.

## The two traps specific to macOS

1. **boot.efi.** With `SecureBootModel=Disabled`, OpenCore starts boot.efi through the firmware, which will answer
   "Security Violation". Fix: enrol boot.efi's Authenticode SHA-256 as a `db` hash entry
   (`sb-audit.py` prints it; today `395d1eba98b45bfc060f704f6bf362986a1730241755bd904a77288c6dfa826e`).
   `FixupAppleEfiImages` must stay off (OpenCore doc: in-memory fixed images are incompatible with UEFI SB because the
   hash no longer matches the file). It is not set today. The hash changes whenever Apple ships a new boot.efi, so after a macOS
   update the audit must be re-run and a new hash appended (or Secure Boot switched off for that one boot).
2. **apfs.efi / JumpStart.** `UEFI/APFS/EnableJumpstart=true` makes OpenCore load Apple's unsigned `apfs.efi` out of the APFS
   container, which Secure Boot blocks, so no macOS entry could be listed. Fix: copy `/usr/standalone/i386/apfs.efi` to
   `EFI/OC/Drivers/apfs.efi`, **sign that copy with our db key**, add it to `UEFI/Drivers`, and set `EnableJumpstart=false`
   (this is the "install apfs.efi manually" route in OpenCore's UEFI Secure Boot chapter). Refresh the copy after big macOS updates.

## Plan (do in this order; every step is reversible by turning Secure Boot off in the BIOS)

0. **Before anything**: in Windows run `manage-bde -status`. If C: is BitLocker/device-encrypted, save the recovery key first;
   changing Secure Boot state can trigger a recovery prompt. Keep a bootable Linux (CachyOS) at hand: it holds the signing key.
1. **Sign from CachyOS** (the db private key lives there; mount the ESP, `sbctl status` must show the keys as installed):
   ```bash
   # untested here: paths assume the ESP is mounted at /efi or /boot/efi
   ESP=/boot/efi
   cp /usr/standalone/i386/apfs.efi ...   # from macOS; copy it to $ESP/EFI/OC/Drivers/apfs.efi beforehand
   for f in EFI/BOOT/BOOTx64.efi EFI/OC/OpenCore.efi EFI/OC/Drivers/HfsPlus.efi EFI/OC/Drivers/OpenRuntime.efi \
            EFI/OC/Drivers/ResetNvramEntry.efi EFI/OC/Drivers/apfs.efi EFI/OC/Tools/NullMothSafe.efi; do
     sudo sbctl sign -s "$ESP/$f"
   done
   sudo sbctl verify
   ```
   Back up `EFI/OC` first (`cp -a`). Signing rewrites the PE with a certificate table; it does not change the code.
   OpenCore reads the ESP binaries as before; `config.plist`, ACPI and kexts are not signature-checked.
2. **From macOS** (config edit, backup first as always): `UEFI/Drivers` add `apfs.efi`, `UEFI/APFS/EnableJumpstart=false`,
   keep `SecureBootModel=Disabled`. Do not enable Vault. This is safe with Secure Boot still off, so test one normal boot now.
3. **Enrol the boot.efi hash** into db. Either of:
   * BIOS: Secure Boot → Key Management → db → Append, choosing the hash/`.efi` if the ASUS menu offers it (not verified on this firmware);
   * Linux with `efitools` and the KEK key: build an `EFI_CERT_SHA256` list from the hash above, sign it with `KEK.key`/`KEK.pem`
     (`sign-efi-sig-list -k KEK.key -c KEK.pem db hash.esl hash.auth`) and write it with `efi-updatevar -a -f hash.auth db`.
4. BIOS: enable Secure Boot (keep user keys; do not reset to factory keys, that would drop our db key and the signed files stop booting).
5. Boot test in this order, each from the firmware boot menu: Windows, CachyOS (Limine), then OpenCore → macOS.
   Expected failure messages: firmware "Security Violation"/black screen for an unsigned OC file; OpenCore log
   "OCB: ... Security Violation" for boot.efi (hash missing) or no macOS entry (apfs.efi missing).
   If macOS fails: BIOS Secure Boot off, boot, fix, retry. Nothing on disk needs undoing besides the two config values.
6. After the first success, add `sb-audit.py` to the macOS-update checklist (boot.efi hash may change; apfs.efi copy may need refresh).

## What this does and does not give you

* Gives: the firmware only runs OpenCore, its drivers and the OS loaders we signed/enrolled. An attacker cannot swap
  `OpenCore.efi` or add a driver on the ESP without our key.
* Does not give: protection of `config.plist`/kexts/ACPI (that needs Vault=Secure, which we do not want), and macOS itself
  stays at SIP custom (kext signing off, AMFI relaxed), so the OS side is not hardened by this.
* Costs: re-sign after every OpenCore update, re-enrol boot.efi hash after some macOS updates, signing needs a Linux boot.
  A macOS-side signer (`osslsigncode`/`sbsigntools`) is not installed; installing one needs a download and your OK.

## Open questions for the owner

1. Is Windows on BitLocker/device encryption? (recovery key before step 4)
2. Does the ASUS BIOS offer "Append hash"/"Add from file" under db key management, or must the hash go in from Linux (efitools)?
3. OK to install a macOS signing tool (MacPorts `osslsigncode`) so OpenCore files can be re-signed without rebooting into Linux?
