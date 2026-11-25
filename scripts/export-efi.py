#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 thanhnndev and contributors
"""Export a working EFI/OC folder into efi/OC for publishing, with every machine identifier removed.

    python scripts/export-efi.py [--src Y:/EFI/OC] [--dst efi/OC]

What it does
  * config.plist: PlatformInfo.Generic SystemSerialNumber / MLB / SystemUUID / ROM are replaced by obvious placeholders.
    The rest of the file is copied byte for byte (the replacement is textual, the file is not re-serialized).
  * ACPI/*.aml are copied.
  * Kexts are NOT copied. efi/kexts.json is written with bundle id, version and SHA-256 of every third-party kext (and
    nested plug-in) found in <src>/Kexts, so a user can verify the binaries they download from upstream. The kexts of
    this repository (bundle id com.itlmt7925.*) are left out: they are built from source.
  * Misc.Entries is emptied: its device paths carry the SSD's NVMe EUI-64 and the GPT partition GUID, which identify the
    machine (and are useless on another one). Add your own entries after installing.
  * Backups (config.plist.bak-*, orig-backup/) and OpenCore binaries are not copied.
  * Finally every written file is searched for the original identifiers (plain, upper/lower case, hex, base64 and the
    UTF-16 form); the script fails and removes the output if any is still there.

Nothing sensitive is printed: only lengths and file names.
"""
import argparse, base64, hashlib, json, os, plistlib, re, shutil, sys

PLACEHOLDER = {
    "SystemSerialNumber": "CHANGE_ME_SN",         # 12 chars like a real serial, fails ocvalidate on purpose
    "MLB": "CHANGE_ME_MLB_000",                    # 17 chars like a real board serial
    "SystemUUID": "00000000-0000-0000-0000-000000000000",
}
ROM_PLACEHOLDER = bytes(6)


def read_identifiers(cfg):
    g = cfg.get("PlatformInfo", {}).get("Generic", {})
    ids = []
    for k in ("SystemSerialNumber", "MLB", "SystemUUID"):
        v = g.get(k)
        if isinstance(v, str) and v and v != PLACEHOLDER[k]:
            ids.append(v.encode())
    rom = g.get("ROM")
    if isinstance(rom, (bytes, bytearray)) and any(rom):
        ids.append(bytes(rom))
    return ids


def variants(raw):
    out = {raw, raw.upper(), raw.lower()}
    try:
        t = raw.decode()
        out |= {t.encode("utf-16-le"), t.upper().encode("utf-16-le")}
    except UnicodeDecodeError:
        pass
    out |= {raw.hex().encode(), raw.hex().upper().encode(), base64.b64encode(raw)}
    return {v for v in out if len(v) >= 6}


def scrub_text(xml, cfg):
    """Replace the four values inside <key>Generic</key><dict>...</dict> without touching anything else."""
    m = re.search(r"<key>Generic</key>\s*<dict>", xml)
    if not m:
        raise SystemExit("PlatformInfo.Generic not found")
    start = m.end()
    depth, i = 1, start
    for t in re.finditer(r"<dict>|</dict>", xml[start:]):
        depth += 1 if t.group() == "<dict>" else -1
        if depth == 0:
            i = start + t.start()
            break
    block = xml[start:i]
    for k, v in PLACEHOLDER.items():
        block, n = re.subn(r"(<key>%s</key>\s*<string>)[^<]*(</string>)" % k, lambda mm: mm.group(1) + v + mm.group(2), block)
        if n != 1:
            raise SystemExit("key %s: expected 1 match, got %d" % (k, n))
    b64 = base64.b64encode(ROM_PLACEHOLDER).decode()
    block, n = re.subn(r"(<key>ROM</key>\s*<data>)[^<]*(</data>)", lambda mm: mm.group(1) + b64 + mm.group(2), block)
    if n != 1:
        raise SystemExit("key ROM: expected 1 match, got %d" % n)
    return scrub_entries(xml[:start] + block + xml[i:])


DEVICE_PATH_ID = re.compile(r"NVMe\(0x[0-9A-Fa-f]+,[0-9A-Fa-f-]+\)|GPT,[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}")


def scrub_entries(xml):
    """Empty Misc.Entries (device paths with the disk's NVMe EUI-64 / partition GUID); the rest stays byte for byte."""
    m = re.search(r"(<key>Misc</key>.*?<key>Entries</key>\s*)<array>", xml, re.S)
    if m:
        start = m.end()
        depth = 1
        for t in re.finditer(r"<array>|</array>|<array/>", xml[start:]):
            if t.group() == "<array>":
                depth += 1
            elif t.group() == "</array>":
                depth -= 1
            if depth == 0:
                xml = xml[:m.end(1)] + "<array/>" + xml[start + t.end():]
                break
        else:
            raise SystemExit("Misc.Entries: unbalanced <array>")
    leak = DEVICE_PATH_ID.search(xml)
    if leak:
        raise SystemExit("a disk identifier is still in config.plist (outside Misc.Entries); remove it by hand: %s..." % leak.group()[:8])
    return xml


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def kext_entry(kdir, rel):
    info = os.path.join(kdir, "Contents", "Info.plist")
    if not os.path.isfile(info):
        return None
    with open(info, "rb") as f:
        p = plistlib.load(f)
    exe = p.get("CFBundleExecutable")
    exe_path = os.path.join(kdir, "Contents", "MacOS", exe) if exe else None
    return {
        "path": rel,
        "bundle_id": p.get("CFBundleIdentifier"),
        "version": p.get("CFBundleShortVersionString") or p.get("CFBundleVersion"),
        "executable_sha256": sha256(exe_path) if exe_path and os.path.isfile(exe_path) else None,
    }


def manifest(src):
    out = []
    kroot = os.path.join(src, "Kexts")
    for name in sorted(os.listdir(kroot)):
        if not name.endswith(".kext"):
            continue
        kdir = os.path.join(kroot, name)
        e = kext_entry(kdir, "Kexts/" + name)
        if e and (e["bundle_id"] or "").startswith("com.itlmt7925."):
            continue                      # built from this repository, not a third-party binary
        if e:
            out.append(e)
        plug = os.path.join(kdir, "Contents", "PlugIns")
        if os.path.isdir(plug):
            for pn in sorted(os.listdir(plug)):
                pe = kext_entry(os.path.join(plug, pn), "Kexts/%s/Contents/PlugIns/%s" % (name, pn))
                if pe:
                    out.append(pe)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default="Y:/EFI/OC")
    ap.add_argument("--dst", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "efi", "OC"))
    a = ap.parse_args()
    src, dst = a.src, os.path.normpath(a.dst)

    cfg_path = os.path.join(src, "config.plist")
    with open(cfg_path, "rb") as f:
        raw = f.read()
    cfg = plistlib.loads(raw)
    ids = read_identifiers(cfg)
    needles = set()
    for i in ids:
        needles |= variants(i)

    xml = raw.decode("utf-8")
    scrubbed = scrub_text(xml, cfg)

    if os.path.isdir(dst):
        shutil.rmtree(dst)
    os.makedirs(os.path.join(dst, "ACPI"))
    written = []
    p = os.path.join(dst, "config.plist")
    with open(p, "w", encoding="utf-8", newline="") as f:
        f.write(scrubbed)
    written.append(p)
    acpi = os.path.join(src, "ACPI")
    for n in sorted(os.listdir(acpi)):
        if n.lower().endswith((".aml", ".dsl")):
            shutil.copy2(os.path.join(acpi, n), os.path.join(dst, "ACPI", n))
            written.append(os.path.join(dst, "ACPI", n))

    mp = os.path.normpath(os.path.join(dst, "..", "kexts.json"))
    with open(mp, "w", encoding="utf-8", newline="\n") as f:
        json.dump({"note": "Third-party kexts used on the reference machine (SHA-256 of the executable); they are not redistributed. itlmt7925, ItlXhciKick and ItlDiag are built from this repository.",
                   "kexts": manifest(src)}, f, indent=2)
        f.write("\n")
    written.append(mp)

    bad = []
    for path in written:
        data = open(path, "rb").read()
        for n in needles:
            if n in data:
                bad.append(os.path.basename(path))
                break
    if bad:
        shutil.rmtree(dst, ignore_errors=True)
        os.remove(mp)
        raise SystemExit("identifier still present in: %s (output removed)" % ", ".join(bad))

    new = plistlib.loads(scrubbed.encode())
    g = new["PlatformInfo"]["Generic"]
    assert g["SystemSerialNumber"] == PLACEHOLDER["SystemSerialNumber"] and g["ROM"] == ROM_PLACEHOLDER
    print("identifiers checked: %d (lengths %s)" % (len(ids), ",".join(str(len(i)) for i in ids)))
    print("wrote %d files under %s" % (len(written), os.path.dirname(mp)))


if __name__ == "__main__":
    main()
