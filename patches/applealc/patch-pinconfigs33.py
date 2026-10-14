#!/usr/bin/env python3
# GA403WM AppleALC port, M2 part 2: enable DMIC pin 0x13 in the ALC285
# LayoutID-33 PinConfigs entry.
#
# Upstream entry (Resources/PinConfigs.kext/Contents/Info.plist, CodecID
# 283902597, LayoutID 33) disables 0x13:
#   (01 37 1c f0)(01 37 1d 00)(01 37 1e 00)(01 37 1f 40)  -> 0x400000f0
# Patched to an internal-mic pin in the same association as 0x12, forming the
# array pair (cf. Linux ALC256_FIXUP_ASUS_MIC {0x13, 0x90a60160}):
#   (01 37 1c 60)(01 37 1d 01)(01 37 1e a6)(01 37 1f 90)  -> 0x90a60160
# 0x12 stays 0x90a60170 (assoc 1, seq 7); 0x13 becomes assoc 1, seq 6.
#
# Usage: patch-pinconfigs33.py <PinConfigs-Info.plist>  (edits in place)
import plistlib
import sys
from pathlib import Path

CODEC = 283902597
LAYOUT = 33
# (verb-nid byte, payload byte) rows for NID 0x13, before -> after
PATCH = {
    (0x37, 0x1C): (0xF0, 0x60),
    (0x37, 0x1D): (0x00, 0x01),
    (0x37, 0x1E): (0x00, 0xA6),
    (0x37, 0x1F): (0x40, 0x90),
}


def main() -> int:
    path = Path(sys.argv[1])
    doc = plistlib.loads(path.read_bytes())
    arr = doc["IOKitPersonalities"]["as.vit9696.AppleALC"]["HDAConfigDefault"]
    matches = [e for e in arr if e.get("CodecID") == CODEC and e.get("LayoutID") == LAYOUT]
    assert len(matches) == 1, f"expected 1 entry, got {len(matches)}"
    entry = matches[0]
    cd = bytearray(bytes(entry["ConfigData"]))
    assert len(cd) % 4 == 0
    changed = 0
    for i in range(0, len(cd), 4):
        key = (cd[i + 1], cd[i + 2])
        if key in PATCH and cd[i] == 0x01:
            want_old, want_new = PATCH[key]
            if cd[i + 3] == want_new:
                continue  # already patched
            assert cd[i + 3] == want_old, f"unexpected byte at {i}: {cd[i+3]:#x}"
            cd[i + 3] = want_new
            changed += 1
    assert changed in (0, 4), f"partial patch? changed={changed}"
    entry["ConfigData"] = bytes(cd)
    if changed:
        path.write_bytes(plistlib.dumps(doc, fmt=plistlib.FMT_XML, sort_keys=False))
    print(f"{path.name}: layout-33 0x13 -> 0x90a60160 ({'patched' if changed else 'already ok'})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
