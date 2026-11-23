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
# M2 (v2, 2026-11-23): pin 19 (0x13) joins the internal-mic device as a second
#   path ADC 9 <- mixer 34 <- pin 19; see the M2 block below. Pin default for
#   0x13 is set in the PinConfigs entry to 0x90a60171 (assoc 7 seq 1, pairing
#   with 0x12's 0x90a60170 = assoc 7 seq 0).
import copy
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

    # --- M2: pin 19 (0x13, the array's third mic, mono) as a second path of the internal-mic device ---
    # Measured on the live codec (alc-verb): 0x13 is input 4 of mixer 0x22 (34), which feeds ADC 0x09 (9); it is NOT an
    # input of mixer 0x23 (35), so the earlier [8,35,19] device could never carry sound. Selector 0x24 (36, ADC 7) offers
    # 0x12/0x13 but picks one. To record all three mics at once AppleHDA must run ADC 7 and ADC 9 together, so the new
    # path joins device [0] next to [7,36,18], the way device [0] of the outputs pairs two speaker paths. Amp settings
    # copy the existing ADC/mixer nodes. No upstream AppleALC input device pairs two ADCs this way: experiment.
    assert all(node_ids(p) not in ([8, 35, 19], [9, 34, 19]) for p in in_paths), "already patched?"
    mic_dev = [d for d in in_group if any(node_ids(p) == [7, 36, 18] for p in d)]
    assert len(mic_dev) == 1, mic_dev
    mic_path = [p for p in mic_dev[0] if node_ids(p) == [7, 36, 18]][0]
    adc_amp, sel_amp = copy.deepcopy(mic_path[0]["Amp"]), copy.deepcopy(mic_path[1]["Amp"])
    mic_dev[0].append([{"Amp": adc_amp, "NodeID": 9}, {"Amp": sel_amp, "NodeID": 34}, {"NodeID": 19}])

    # sanity: no other group touched
    assert sorted(node_ids(p) for p in paths(out_group)) == [[20, 2], [23, 2], [33, 3]]

    OUT.write_bytes(plistlib.dumps(doc, fmt=plistlib.FMT_XML, sort_keys=False))
    print(f"wrote {OUT} (S4: [23,3]->[23,2] ch1/2; M2: mic device + [9,34,19])")
    return 0


if __name__ == "__main__":
    sys.exit(main())
