#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause-Clear
"""Prepare a panel override using the EDID actually published by StrixGOP.

Does not install, restart WindowServer, or change modes. Keep scale/name keys.
"""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess


def validate_edid(data):
    if not isinstance(data, bytes) or len(data) < 128 or len(data) % 128:
        raise ValueError('EDID must contain complete 128-byte blocks')
    if data[:8] != b'\x00\xff\xff\xff\xff\xff\xff\x00':
        raise ValueError('Invalid EDID signature')
    if len(data) != (data[126] + 1) * 128:
        raise ValueError('EDID extension count does not match length')
    if any(sum(data[i:i + 128]) % 256 for i in range(0, len(data), 128)):
        raise ValueError('Invalid EDID block checksum')
    return int.from_bytes(data[8:10], 'big'), int.from_bytes(data[10:12], 'little')


def has_pq(data):
    for start in range(128, len(data), 128):
        block = data[start:start + 128]
        if block[0] != 2:
            continue
        end = block[2]
        if end == 0:
            continue
        if not 4 <= end <= 127:
            raise ValueError('Invalid CTA data block boundary')
        offset = 4
        while offset < end:
            header = block[offset]
            size = header & 31
            nxt = offset + 1 + size
            if nxt > end:
                raise ValueError('Truncated CTA data block')
            if header >> 5 == 7 and size >= 3 and block[offset + 1] == 6 and block[offset + 2] & 4:
                return True
            offset = nxt
    return False


def prepare(override, registry):
    """Exactly one matching AppleBacklightDisplay beneath StrixGOP is required."""
    matches = []
    def visit(node, under_gop=False):
        if isinstance(node, list):
            for child in node:
                visit(child, under_gop)
        elif isinstance(node, dict):
            under_gop |= node.get('IOObjectClass') in ('StrixGOPFramebuffer', 'AMDStrixGOPFramebuffer')
            if under_gop and node.get('IOObjectClass') == 'AppleBacklightDisplay':
                matches.append(node)
            visit(node.get('IORegistryEntryChildren', []), under_gop)
    visit(registry)
    if len(matches) != 1:
        raise ValueError('Need exactly one StrixGOP AppleBacklightDisplay')
    edid = matches[0].get('IODisplayEDID')
    vendor, product = validate_edid(edid)
    if (vendor, product) != (0x4c83, 0x419c):
        raise ValueError('Not the reviewed ATNA40CU05-0 panel')
    if (override.get('DisplayVendorID'), override.get('DisplayProductID')) != (vendor, product):
        raise ValueError('Override identity differs from live panel')
    old = override.get('IODisplayEDID')
    if old is not None and validate_edid(old) != (vendor, product):
        raise ValueError('Previous EDID identity differs')
    if len(edid) != 256 or not has_pq(edid):
        raise ValueError('Live driver does not publish the expected PQ CTA block')
    result = dict(override)
    result['IODisplayEDID'] = edid
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--override', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--registry-plist', type=Path)
    args = parser.parse_args()
    if args.override.resolve() == args.output.resolve() or args.output.exists():
        parser.error('Output must be a new candidate file, separate from installed override')
    raw = args.override.read_bytes()
    registry = (args.registry_plist.read_bytes() if args.registry_plist else
                subprocess.check_output(['ioreg', '-a', '-l', '-r', '-c', 'StrixGOPFramebuffer']))
    old = plistlib.loads(raw)
    new = prepare(old, plistlib.loads(registry))
    args.output.write_bytes(plistlib.dumps(new, fmt=plistlib.FMT_XML))
    print(json.dumps({'status': 'PREPARED-not-installed', 'changed_keys': [k for k in new if new[k] != old.get(k)],
                      'old_sha256': hashlib.sha256(raw).hexdigest(),
                      'candidate_sha256': hashlib.sha256(args.output.read_bytes()).hexdigest(),
                      'edid_bytes': len(new['IODisplayEDID']), 'pq_advertised': True,
                      'physical_hdr_validated': False}, indent=2))


if __name__ == '__main__':
    main()
