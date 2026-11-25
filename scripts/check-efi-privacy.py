#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 thanhnndev and contributors
"""Fail if efi/OC/config.plist carries anything but the placeholder platform identifiers (run in CI and before a commit).

    python scripts/check-efi-privacy.py [path/to/config.plist ...]
"""
import plistlib, re, sys

# NVMe EUI-64 and GPT partition GUID inside OpenCore device paths identify the machine's disk
DEVICE_PATH_ID = re.compile(rb"NVMe\(0x[0-9A-Fa-f]+,[0-9A-Fa-f-]+\)|GPT,[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}")

EXPECT = {
    "SystemSerialNumber": "CHANGE_ME_SN",
    "MLB": "CHANGE_ME_MLB_000",
    "SystemUUID": "00000000-0000-0000-0000-000000000000",
    "ROM": bytes(6),
}


def main(paths):
    bad = 0
    for path in paths:
        with open(path, "rb") as f:
            raw = f.read()
        cfg = plistlib.loads(raw)
        if DEVICE_PATH_ID.search(raw):
            print("%s: carries a disk identifier (NVMe EUI-64 / GPT partition GUID in a device path, e.g. Misc.Entries)" % path)
            bad += 1
        g = cfg.get("PlatformInfo", {}).get("Generic", {})
        for k, want in EXPECT.items():
            if g.get(k) != want:
                print("%s: PlatformInfo.Generic.%s is not the placeholder" % (path, k))
                bad += 1
        sec = cfg.get("Misc", {}).get("Security", {})
        if sec.get("PasswordHash") or sec.get("PasswordSalt"):
            print("%s: Misc.Security carries a password hash / salt" % path)
            bad += 1
    if bad:
        sys.exit(1)
    print("ok: %d file(s) carry placeholders only" % len(paths))


if __name__ == "__main__":
    main(sys.argv[1:] or ["efi/OC/config.plist"])
