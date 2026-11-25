#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Cave registry check for the hand-patched NMXGPU: every cave's code range and every writable word it reaches.
# Step100c lost a boot because the irqfix state array (ST[], 0x927010..0x9270c8) ran into the Step99 flip state at
# 0x9270a0: each REGION note was right on its own, nothing compared them. This tool does:
#   1. code ranges in REGISTRY must not overlap;
#   2. data ranges in REGISTRY must not overlap (one owner per word);
#   3. every rip-relative reference from a cave into __DATA/__bss must land in that cave's own data ranges (or in
#      SHARED, words a cave reads that belong to NMXGPU itself), found by disassembling the patched binary.
# Run it on any NMXGPU before a patch is installed; the installers call it and refuse on a failure.
#   check.py NMXGPU            exit 0 = consistent
import re, subprocess, sys

# name: (code ranges, data ranges). Data ranges are [start, end) byte ranges in borrowed BSS (dead CI/KV dpm statics).
REGISTRY = {
    'ibprobe (Step89)':   ([(0x5aa5a0, 0x5aab70)], []),
    'wcsplit (Step90)':   ([(0x5aac00, 0x5ab300)], []),
    'userptr (Step92)':   ([(0x5ab300, 0x5ab738)], [(0x926c73, 0x926c74)]),   # amdgpu_hmm_register.__print_once
    'ibprep (Step93)':    ([(0x5ab740, 0x5ab760)], []),
    'cstrace (Step95)':   ([(0x5ab760, 0x5abe80)], [(0x926fe0, 0x926fe8)]),
    'flip import (99)':   ([(0x506580, 0x507180)], [(0x9270a0, 0x927200)]),
    'flip (Step98/99)':   ([(0x507190, 0x508220)], [(0x9270a0, 0x927200)]),
    'irqfix (Step100c)':  ([(0x509100, 0x50a630)], [(0x927208, 0x9272c0)]),
    'mmfix (Step97b)':    ([(0x50a730, 0x50a9a0)], [(0x926ff8, 0x926ffc)]),
    'mmfix2 (Step100)':   ([(0x50a9a0, 0x50abc0)], [(0x926f98, 0x926fa8)]),
    'fadt (Step112c)':    ([(0x50ac10, 0x50ac20)], []),
}
# NMXGPU's own globals that caves read (or use as designed); not borrowed, never registered as a cave's data
SHARED = {
    0x89a0e8: 'wcsplit: __DATA word at dmi_fields+0xa08',
    0x8f6b0c: 'amdgpu_dpm (module parameter)',
    0x925af0: 'intrs (interrupt event source list)',
    0x925e30: 'hz',
    0x98b268: 'fbs+8 (nmx_fb table)',
    0x99bc68: 'g_open_node+0x4208',
    0x9b9950: 'nmx_irq_dispatched',
    0x9ba204: 'nmx_wbinvd_before_submit',
}
# the flip import cave and the flip cave share one state struct (one owner, two code ranges)
SAME_OWNER = {frozenset(('flip import (99)', 'flip (Step98/99)'))}
DATA_START, DATA_END = 0x89a000, 0x9bb000   # __DATA vmaddr..end; refs below are __TEXT/__const (strings, code),
                                            # refs past the end are cave strings decoded as instructions


def fail(msg):
    print('FAIL:', msg)
    return 1


def main(path):
    bad = 0
    names = list(REGISTRY)
    for kind, idx in (('code', 0), ('data', 1)):
        for i, a in enumerate(names):
            for b in names[i + 1:]:
                if frozenset((a, b)) in SAME_OWNER and kind == 'data':
                    continue
                for s1, e1 in REGISTRY[a][idx]:
                    for s2, e2 in REGISTRY[b][idx]:
                        if s1 < e2 and s2 < e1:
                            bad |= fail(f'{kind} {a} {s1:#x}..{e1:#x} overlaps {b} {s2:#x}..{e2:#x}')
    dis = subprocess.run(['otool', '-tv', path], capture_output=True, text=True, check=True).stdout.splitlines()
    rx = re.compile(r'^([0-9a-f]{16})\t(.*)$')
    lines = [(int(m.group(1), 16), m.group(2)) for m in map(rx.match, dis) if m]
    rip = re.compile(r'(-?0x[0-9a-f]+)\(%rip\)')
    refs = {}
    for k, (at, text) in enumerate(lines[:-1]):
        m = rip.search(text)
        if not m:
            continue
        owner = next((n for n, (code, _) in REGISTRY.items() if any(s <= at < e for s, e in code)), None)
        if owner is None:
            continue
        tgt = lines[k + 1][0] + int(m.group(1), 16)
        if not DATA_START <= tgt < DATA_END:
            continue
        refs.setdefault(owner, set()).add((tgt, at))
    for owner, rs in sorted(refs.items()):
        data = REGISTRY[owner][1]
        for tgt, at in sorted(rs):
            if tgt not in SHARED and not any(s <= tgt < e for s, e in data):
                bad |= fail(f'{owner} at {at:#x} reaches {tgt:#x}, outside its registered data {[(hex(s), hex(e)) for s, e in data]}')
        lo = min(t for t, _ in rs); hi = max(t for t, _ in rs)
        print(f'{owner}: {len(rs)} data refs, {lo:#x}..{hi:#x}')
    print('cave registry: ' + ('FAILED' if bad else 'consistent'))
    return bad


if __name__ == '__main__':
    sys.exit(main(sys.argv[1]))
