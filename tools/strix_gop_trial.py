#!/usr/bin/env python3
"""Build/profile Step03 from a validated physical boot snapshot. Never install/load."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import pathlib
import plistlib
import re
import shutil
import struct
import subprocess
import sys


def boot_profile(raw):
    entries = plistlib.loads(raw)
    if len(entries) != 1:
        raise ValueError('Expected exactly one probe snapshot')
    e = entries[0]
    if e.get('TraceStep') != '890M-02' or e.get('ProbeVersion') != '0.1.2':
        raise ValueError('Require validated Step02 probe0.1.2')
    if e.get('PCI,MatchCount') != 1 or e.get('Snapshot,InProgress') is not False:
        raise ValueError('Require one target and a complete snapshot')
    if e.get('Console,PhysicalFlag') is not True:
        raise ValueError('Virtual live console cannot provide a physical GOP profile')
    g = e['GPU0']; config = g['PCIConfig256']
    if len(config) != 256 or (*struct.unpack_from('<HH', config), config[8],
        *struct.unpack_from('<HH', config, 0x2c)) != (0x1002, 0x150e, 0xc1, 0x1043, 0x3998):
        raise ValueError('Unexpected physical PCI identity')
    base, length = g['BAR0,OSBase'], g['BAR0,OSLength']
    lo, hi = struct.unpack_from('<II', config, 0x10)
    if (lo & 7) != 4 or ((hi << 32) | (lo & ~15)) != base:
        raise ValueError('BAR0 config/descriptor mismatch')
    if g['BAR0,SegmentLength'] != length:
        raise ValueError('Require contiguous physical BAR0')
    physical = e['Console,PhysicalBase']; raw_base = e['Console,RawBase']
    if not (raw_base & 1) or (raw_base & ~3) != physical:
        raise ValueError('Inconsistent physical console flag/base')
    if e['Console,Offset'] != 0 or e['Console,Rotation'] != 0:
        raise ValueError('Only unrotated zero-offset console supported')
    w, h, stride = e['Console,Width'], e['Console,Height'], e['Console,RowBytes']
    if not (0 < w <= 16384 and 0 < h <= 16384 and w * 4 <= stride <= 0xffffffff and stride % 4 == 0):
        raise ValueError('Invalid raster geometry')
    if e['Console,Depth'] != 32:
        raise ValueError('Only32bpp XRGB trial supported')
    raster = stride * h; rounded = (raster + 4095) & ~4095
    if e['Console,RasterBytes'] != raster or physical < base or physical % 4096 or rounded > base + length - physical:
        raise ValueError('Raster escapes BAR0 or inconsistent length')
    if base <= 0 or length <= 0 or base + length > 0xffffffffffffffff:
        raise ValueError('Invalid physical resource range')
    return {'BAR0Base': base, 'BAR0Length': length, 'Offset': physical - base,
            'Width': w, 'Height': h, 'Stride': stride, 'Depth': 32, 'Rotation': 0,
            'PixelFormat': 'XRGB8888'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('snapshot', type=pathlib.Path)
    args = parser.parse_args()
    root = pathlib.Path(__file__).resolve().parents[1]
    out = root / 'out/890m-trace' / ('step03-build-' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S.%fZ'))
    out.mkdir(parents=True)
    manifest = {'step': '890M-03', 'status': 'FAILED', 'installed': False, 'runtime_tested': False}
    try:
        raw = args.snapshot.read_bytes()
        profile = boot_profile(raw)
        (out / 'boot-snapshot.plist').write_bytes(raw)
        manifest['snapshot_sha256'] = hashlib.sha256(raw).hexdigest()
        manifest['profile'] = profile
        for command, name in [(['sw_vers'], 'os'), (['uname', '-v'], 'kernel'),
                              (['git', 'rev-parse', 'HEAD'], 'git-head'),
                              (['git', 'status', '--short'], 'git-status')]:
            result = subprocess.run(command, cwd=root, capture_output=True, text=True, check=True)
            (out / (name + '.txt')).write_text(result.stdout)
        with (out / 'build.stdout.txt').open('w') as stdout, (out / 'build.stderr.txt').open('w') as stderr:
            result = subprocess.run(['bash', 'scripts/build.sh', 'StrixGOP'], cwd=root,
                                    stdout=stdout, stderr=stderr)
        manifest['build_exit'] = result.returncode
        if result.returncode: raise ValueError('Build failed; preserved stderr/stdout')
        bundle = out / 'StrixGOP.kext'
        shutil.copytree(root / 'build/StrixGOP.kext', bundle)
        info = bundle / 'Contents/Info.plist'
        plist = plistlib.loads(info.read_bytes())
        personality = plist['IOKitPersonalities']['StrixGOP']
        personality['BootGOPProfile'] = profile
        personality['AdoptBootGOP'] = True
        info.write_bytes(plistlib.dumps(plist))
        binary = bundle / 'Contents/MacOS/StrixGOP'
        def run(command, name):
            result = subprocess.run(command, capture_output=True, text=True, check=True)
            (out / name).write_text(result.stdout)
            return result.stdout
        headers = run(['otool', '-hv', str(binary)], 'macho-header.txt')
        imports = set(run(['nm', '-uj', str(binary)], 'imports.txt').splitlines())
        exports = set(run(['nm', '-gUj', str(binary)], 'exports.txt').splitlines())
        if 'X86_64' not in headers or not re.search(r'\bKEXT_?BUNDLE\b', headers) or '_kmod_info' not in exports:
            raise ValueError('Invalid kext binary structure')
        if re.search(r'___cxa_atexit|___cxa_throw|___gxx_personality', '\n'.join(imports)):
            raise ValueError('Forbidden C++ runtime import')
        defined = set()
        for collection in ('BootKernelExtensions.kc', 'SystemKernelExtensions.kc'):
            defined.update(run(['nm', '-gUj', '/System/Library/KernelCollections/' + collection],
                               collection + '.symbols.txt').splitlines())
        missing = sorted(imports - defined)
        manifest['import_count'] = len(imports); manifest['missing_defined_symbols'] = missing
        if missing: raise ValueError('Missing kernel/family symbols')
        manifest['binary_sha256'] = hashlib.sha256(binary.read_bytes()).hexdigest()
        manifest['source_hashes'] = {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
                                    for p in sorted((root / 'kexts/StrixGOP').glob('*'))}
        manifest['source_hashes']['tools/strix_gop_trial.py'] = hashlib.sha256(pathlib.Path(__file__).read_bytes()).hexdigest()
        manifest['status'] = 'PROFILED-LINKED-runtime-pending'
    except Exception as exc:
        manifest['error'] = str(exc)
    (out / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(manifest['status'] + ': ' + str(out.relative_to(root)))
    if 'error' in manifest: print(manifest['error'], file=sys.stderr)
    return 0 if manifest['status'] == 'PROFILED-LINKED-runtime-pending' else 1


if __name__ == '__main__':
    sys.exit(main())
