#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause-Clear
"""Read-only UEFI Secure Boot audit from macOS: firmware key state, signer of every .efi on the ESP, and the
Authenticode SHA-256 of macOS boot.efi (what a db hash entry would need). Changes nothing.
   python3 -I sb-audit.py [/Volumes/ESP]"""
import glob, hashlib, os, plistlib, struct, subprocess, sys

ESP = sys.argv[1] if len(sys.argv) > 1 else "/Volumes/ESP"
GLOBAL = "8be4df61-93ca-11d2-aa0d-00e098032b8c"
SECDB = "d719b2cb-3d3a-4596-a3bc-dad00e67656f"


def nvram_raw(name):
    r = subprocess.run(["nvram", "-x", name], capture_output=True)
    if r.returncode:
        return None
    v = list(plistlib.loads(r.stdout).values())[0]
    return v if isinstance(v, bytes) else None


def sig_list_subjects(data):
    out, hashes, i = [], 0, 0
    while data and i + 28 <= len(data):
        sz, hs, ss = struct.unpack_from("<III", data, i + 16)
        if sz == 0:
            break
        for j in range(i + 28 + hs, i + sz, ss):
            ent = data[j + 16:j + ss]
            if ent[:1] == b"\x30":
                p = subprocess.run(["openssl", "x509", "-inform", "DER", "-noout", "-subject", "-enddate"],
                                   input=ent, capture_output=True)
                out.append(p.stdout.decode().replace("\n", " | ").strip())
            else:
                hashes += 1
        i += sz
    return out, hashes


def pe_info(path):
    d = open(path, "rb").read()
    if d[:2] != b"MZ":
        return None
    pe = struct.unpack_from("<I", d, 0x3C)[0]
    opt = pe + 24
    plus = struct.unpack_from("<H", d, opt)[0] == 0x20B
    dd = opt + (112 if plus else 96)
    coff_ck = opt + 64
    cert_off, cert_sz = struct.unpack_from("<II", d, dd + 32)
    # Authenticode hash: skip checksum, cert directory entry, and the certificate table itself
    end = cert_off if cert_off else len(d)
    h = hashlib.sha256()
    h.update(d[:coff_ck]); h.update(d[coff_ck + 4:dd + 32]); h.update(d[dd + 40:end])
    signers = []
    if cert_off and cert_sz > 8:
        p = subprocess.run(["openssl", "pkcs7", "-inform", "DER", "-print_certs"], input=d[cert_off + 8:cert_off + cert_sz],
                           capture_output=True)
        signers = [l[8:] for l in p.stdout.decode().splitlines() if l.startswith("subject")]
    return h.hexdigest(), signers


print("== firmware state")
for label, var in (("SecureBoot", f"{GLOBAL}:SecureBoot"), ("SetupMode", f"{GLOBAL}:SetupMode")):
    v = nvram_raw(var)
    print(f"  {label}: {v[0] if v else '?'}   (0 = off / user mode)" if v else f"  {label}: ?")
for label, var in (("PK", f"{GLOBAL}:PK"), ("KEK", f"{GLOBAL}:KEK"), ("db", f"{SECDB}:db"), ("dbx", f"{SECDB}:dbx")):
    raw = nvram_raw(var)
    if raw is None:
        print(f"  {label}: not readable / empty")
        continue
    subs, nh = sig_list_subjects(raw)
    print(f"  {label}: {len(subs)} certs, {nh} hashes")
    for s in subs:
        print("     ", s[:150])

print("== ESP binaries")
for f in sorted(glob.glob(os.path.join(ESP, "EFI", "**", "*.efi"), recursive=True)):
    if os.path.basename(f).startswith("._"):
        continue
    info = pe_info(f)
    rel = os.path.relpath(f, ESP)
    if not info:
        print(f"  {rel}: not PE"); continue
    h, sg = info
    print(f"  {rel}: {'signed by ' + '; '.join(s[:60] for s in sg[:2]) if sg else 'UNSIGNED'}  authenticode-sha256={h[:16]}...")

print("== macOS boot.efi (Apple signs with IM4M manifests, not PE signatures)")
for f in ["/usr/standalone/i386/boot.efi"]:
    if os.path.exists(f):
        h, sg = pe_info(f)
        print(f"  {f}: PE signature {'present' if sg else 'ABSENT'}; authenticode-sha256={h}")
