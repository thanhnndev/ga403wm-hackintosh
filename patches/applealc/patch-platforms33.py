#!/usr/bin/env python3
# GA403WM AppleALC port: S4 (woofer 0x17 -> DAC1) + M2 (second DMIC 0x13).
# Reads pristine Platforms33.xml from the pinned AppleALC reference, applies two
# surgical changes, writes the result. Idempotent; asserts structure first.
#
# S4 mirrors Linux alc285_fixup_speaker2_to_dac1 (build/linux-alc269.c):
#   snd_hda_override_conn_list(codec, 0x17, {0x02}) -- pin 23 must take DAC 2,
#   not DAC 3. Upstream Platforms33 routes [23,3] (pin 0x17 <- DAC 0x03, stream
#   ch 5/6); the amps' DSP does the tweeter/woofer crossover, so both speaker
#   pins share DAC 0x02 ch 1/2, exactly like Linux (both speakers on 0x02).
#
# M2 mirrors ALC236 Platforms69 ([8,35,19] second-DMIC path, bare NodeIDs):
#   adds input path ADC 8 <- mixer 35 <- pin 19 (0x13). Pin default for 0x13 is
#   enabled separately in the PinConfigs entry (0x90a60160, same assoc 1 as
#   0x12's 0x90a60170, forming the array pair; cf. ALC256_FIXUP_ASUS_MIC).
import plistlib
import sys
from pathlib import Path

REF = Path(__file__).resolve().parent.parent.parent / (
    "build/AppleALC-reference/Resources/ALC285/Platforms33.xml")
OUT = Path(__file__).resolve().parent / "Platforms33.xml"


def load(path: Path):
    raw = path.read_bytes()
    try:
        return plistlib.loads(raw)
    except Exception:
        wrapped = (b'<?xml version="1.0" encoding="UTF-8"?>\n'
                   b'<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
                   b'"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
                   b'<plist version="1.0">\n' + raw + b'\n</plist>\n')
        return plistlib.loads(wrapped)


def node_ids(path):
    """A path is a list of node dicts; return [nodeid, ...]."""
    return [n["NodeID"] for n in path]


def paths(group):
    """Flatten two levels: group -> subgroups -> paths (lists of node dicts)."""
    out = []
    for sub in group:
        assert isinstance(sub, list) and sub, sub
        for path in sub:
            assert isinstance(path, list) and path, path
            assert all(isinstance(n, dict) and "NodeID" in n for n in path), path
            out.append(path)
    return out


def main() -> int:
    doc = load(REF)
    pmap = doc["PathMaps"][0]["PathMap"]
    assert len(pmap) == 2, f"expected 2 path groups, got {len(pmap)}"
    in_group, out_group = pmap
    in_paths, out_paths = paths(in_group), paths(out_group)

    in_ids = sorted(node_ids(p) for p in in_paths)
    assert [7, 36, 18] in in_ids, f"input mic path missing: {in_ids}"
    assert [8, 35, 25] in in_ids, f"input jack path missing: {in_ids}"
    out_ids = sorted(node_ids(p) for p in out_paths)
    assert [20, 2] in out_ids, f"speaker path [20,2] missing: {out_ids}"
    assert [23, 3] in out_ids, f"speaker path [23,3] missing: {out_ids}"
    assert [33, 3] in out_ids, "headphone path [33,3] changed upstream?"

    # --- S4: pin 23 (0x17) takes DAC 2, ch 1/2 (was DAC 3, ch 5/6) ---
    for path in out_paths:
        if node_ids(path) == [23, 3]:
            pin, dac = path
            assert pin["NodeID"] == 23 and dac["NodeID"] == 3
            chans = dac["Amp"]["Channels"]
            assert [(c["Bind"], c["Channel"]) for c in chans] == [(1, 5), (2, 6)], chans
            chans[0]["Channel"] = 1
            chans[1]["Channel"] = 2
            dac["NodeID"] = 2
            # keep mute/volume flags as-is (all false on the DAC side here)

    # --- M2: append bare [8,35,19] input path (ALC236/Platforms69 pattern) ---
    # as its own subgroup: [[nodes...]].
    assert all(node_ids(p) != [8, 35, 19] for p in in_paths), "already patched?"
    in_group.append([[{"NodeID": 8}, {"NodeID": 35}, {"NodeID": 19}]])

    # sanity: no other group touched
    assert sorted(node_ids(p) for p in paths(out_group)) == [[20, 2], [23, 2], [33, 3]]

    OUT.write_bytes(plistlib.dumps(doc, fmt=plistlib.FMT_XML, sort_keys=False))
    print(f"wrote {OUT} (S4: [23,3]->[23,2] ch1/2; M2: +[8,35,19])")
    return 0


if __name__ == "__main__":
    sys.exit(main())
