#!/usr/bin/env python3
"""Provide NMXGPU's existing PCI ROM fallback with the board's VFCT image.

Firmware stays local. By default write a candidate config; --apply also validates
it with ocvalidate and backs up/replaces the selected live config.
"""
import argparse
import hashlib
import os
from pathlib import Path
import plistlib
import shutil
import struct
import subprocess
import tempfile
import time

GPU_PATH = 'PciRoot(0x0)/Pci(0x8,0x1)/Pci(0x0,0x0)'


def extract_vbios(raw):
    if len(raw) < 76 or raw[:4] != b'VFCT':
        raise ValueError('Not a VFCT table')
    if struct.unpack_from('<I', raw, 4)[0] != len(raw) or sum(raw) & 255:
        raise ValueError('Invalid VFCT length/checksum')
    offset = struct.unpack_from('<I', raw, 52)[0]
    if not 76 <= offset < len(raw):
        raise ValueError('Invalid VBIOS image offset')
    images = []
    while offset + 28 <= len(raw):
        # Firmware can terminate its image list with a zero-filled header.
        if not any(raw[offset:]):
            break
        bus, dev, fn, vendor, device, _, _, _, length = struct.unpack_from('<IIIHHHHII', raw, offset)
        end = offset + 28 + length
        if not length or end > len(raw):
            raise ValueError('Truncated/empty VFCT image')
        if (bus, dev, fn, vendor, device) == (101, 0, 0, 0x1002, 0x150e):
            images.append(raw[offset + 28:end])
        offset = end
    if len(images) != 1:
        raise ValueError('Expected exactly one 101:0:0 1002:150e image')
    rom = images[0]
    if len(rom) < 0x4a or rom[:2] != b'\x55\xaa':
        raise ValueError('Invalid option ROM signature')
    header = struct.unpack_from('<H', rom, 0x48)[0]
    if not header or rom[header + 4:header + 8] not in (b'ATOM', b'MOTA'):
        raise ValueError('Invalid ATOM BIOS header')
    return rom


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('config', type=Path)
    parser.add_argument('vfct_plist', type=Path, help='StrixVFCT.kext/Contents/Info.plist')
    parser.add_argument('output', type=Path, help='Candidate config (contains private machine data)')
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--ocvalidate', type=Path)
    args = parser.parse_args()
    if args.output.resolve() == args.config.resolve():
        parser.error('Candidate must differ from live config')
    original = args.config.read_bytes()
    cfg = plistlib.loads(original)
    vfct = plistlib.loads(args.vfct_plist.read_bytes())
    rom = extract_vbios(vfct['IOKitPersonalities']['StrixVFCT']['ACPI Tables']['VFCT'])
    gpu = cfg['DeviceProperties']['Add'][GPU_PATH]
    if gpu.get('name') != b'#display\x00' or gpu.get('IOName') != '#display':
        raise ValueError('Expected cobalt #display identity; refusing a different setup')
    if gpu.get('vbios', rom) != rom:
        raise ValueError('A different vbios is already installed')
    gpu['vbios'] = rom
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open('wb') as f:
        os.chmod(args.output, 0o600)
        plistlib.dump(cfg, f)
    if args.ocvalidate:
        subprocess.run([str(args.ocvalidate.resolve()), str(args.output)], check=True)
    if args.apply:
        if not args.ocvalidate:
            raise ValueError('--apply requires --ocvalidate')
        if args.config.read_bytes() != original:
            raise ValueError('Live config changed during preparation')
        backup = args.output.parent / ('config-before-vbios-' + str(time.time_ns()) + '.plist')
        backup.write_bytes(original)
        backup.chmod(0o600)
        fd, staging = tempfile.mkstemp(prefix='.config-vbios-', dir=args.config.parent)
        try:
            with os.fdopen(fd, 'wb') as f:
                f.write(args.output.read_bytes())
                f.flush()
                os.fsync(f.fileno())
            shutil.copymode(args.config, staging)
            os.replace(staging, args.config)
        finally:
            if os.path.exists(staging):
                os.unlink(staging)
        print('Applied. Backup:', backup)
    print('VBIOS bytes:', len(rom), 'SHA256:', hashlib.sha256(rom).hexdigest())


if __name__ == '__main__':
    main()
