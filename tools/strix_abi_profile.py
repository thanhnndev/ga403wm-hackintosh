#!/usr/bin/env python3
"""Record an OS-specific IOAccel profile without regenerating/installing headers."""
import argparse
import hashlib
import json
import pathlib
import struct
import subprocess
import sys
import tempfile

from ioaccel_layout import KC

ROOT = pathlib.Path(__file__).resolve().parents[1]
CLASSES = ['IOGraphicsAccelerator2', 'IOAccelDisplayMachine', 'IOAccelDisplayPipe',
           'IOAccelEventMachine2', 'IOAccelEventMachineFast2', 'IOAccelTask', 'IOAccelMemory',
           'IOAccelSysMemory', 'IOAccelVidMemory', 'IOAccelResource2', 'IOAccelMemoryMap']


def family_uuid(kc, bundle):
    _, header = kc.entries[bundle]
    ncmds = struct.unpack_from('<I', kc.m, header + 16)[0]
    end = header + 32 + struct.unpack_from('<I', kc.m, header + 20)[0]
    if end > len(kc.m): raise ValueError('Truncated commands')
    offset = header + 32
    result = None
    for _ in range(ncmds):
        if offset + 8 > end: raise ValueError('Truncated command')
        cmd, size = struct.unpack_from('<II', kc.m, offset)
        if size < 8 or offset + size > end: raise ValueError('Invalid command size')
        if cmd == 0x1b:
            if size != 24 or result is not None: raise ValueError('Invalid/duplicate UUID')
            result = bytes(kc.m[offset + 8:offset + 24]).hex()
        offset += size
    if result is None: raise ValueError('Missing family UUID')
    return result


def normalize(layout, text_start, text_end):
    normalized = {}
    for name in CLASSES:
        entry = layout['classes'][name]
        if entry.get('error') or not entry.get('size') or entry.get('nslots') != len(entry.get('slots', [])):
            raise ValueError('Incomplete class: ' + name)
        # KC symbol spacing includes an8-byte terminal zero before the next
        # symbol; the declaration generator also excludes that padding slot.
        source_slots = list(entry['slots'])
        if not source_slots or source_slots[-1] is not None:
            raise ValueError('Unexpected terminal vtable layout in ' + name)
        source_slots.pop()
        slots = []
        for value in source_slots:
            if value is None: raise ValueError('Unresolved slot in ' + name)
            if value.startswith('0x'):
                address = int(value, 16)
                if not text_start <= address < text_end:
                    raise ValueError('Unnamed target outside family text in ' + name)
                value = 'private-text-offset:' + hex(address - text_start)
            slots.append(value)
        normalized[name] = {'size': entry['size'], 'nslots': len(slots), 'terminal_padding_slots': 1,
                            'super_symbol': entry['super_sym'], 'slots': slots}
    return normalized


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--kc', type=pathlib.Path, default=pathlib.Path('/System/Library/KernelCollections/SystemKernelExtensions.kc'))
    ap.add_argument('--boot-kc', type=pathlib.Path, default=pathlib.Path('/System/Library/KernelCollections/BootKernelExtensions.kc'))
    ap.add_argument('--os-build', help='Required when inspecting a foreign OS collection')
    ap.add_argument('--out', required=True, type=pathlib.Path)
    args = ap.parse_args()
    if (args.kc != pathlib.Path('/System/Library/KernelCollections/SystemKernelExtensions.kc') or
        args.boot_kc != pathlib.Path('/System/Library/KernelCollections/BootKernelExtensions.kc')) and not args.os_build:
        raise ValueError('Foreign collection inspection requires --os-build; never label it with the host build')
    family = 'com.apple.iokit.IOAcceleratorFamily2'
    build = args.os_build or subprocess.check_output(['sw_vers', '-buildVersion'], text=True).strip()
    if not build or any(c not in '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz' for c in build):
        raise ValueError('Invalid OS build identifier')
    kc = KC(str(args.kc))
    if kc.cpu != 0x1000007: raise ValueError('Only x86_64 private ABI extraction supported')
    segments = kc.kext_segments(family)
    text = ([s for s in segments if s[0] == '__TEXT_EXEC'] or [s for s in segments if s[0] == '__TEXT'])[0]
    with tempfile.TemporaryDirectory(prefix='strix-abi-') as td:
        layout_path = pathlib.Path(td) / 'layout.json'
        command = [sys.executable, str(ROOT / 'tools/ioaccel_layout.py'), '--kc', str(args.kc),
                   '--symbols-from', str(args.boot_kc), '--out', str(layout_path)]
        for cls in CLASSES: command.extend(['--class', cls])
        result = subprocess.run(command, capture_output=True, text=True)
        if result.returncode: raise ValueError(result.stderr or 'Layout extraction failed')
        layout = json.loads(layout_path.read_text())
    classes = normalize(layout, text[1], text[1] + text[2])
    canonical = json.dumps(classes, sort_keys=True, separators=(',', ':')).encode()
    report = {'schema': 1, 'os_build': build, 'architecture': 'x86_64', 'family': family,
              'family_uuid': family_uuid(kc, family), 'layout_sha256': hashlib.sha256(canonical).hexdigest(),
              'generated_header_sha256': hashlib.sha256((ROOT / 'kexts/StrixAccel/IOAccelFamily2_decl.h').read_bytes()).hexdigest(),
              'classes': classes, 'profile_state': 'EXTRACTED-not-runtime-validation',
              'support_note': 'A new extraction is evidence only; review/regenerate declarations and runtime gate before enabling another OS.'}
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(report, indent=2) + '\n')
    print(build + ' profile: ' + str(args.out))


if __name__ == '__main__': main()
