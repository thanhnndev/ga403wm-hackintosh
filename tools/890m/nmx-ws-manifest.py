#!/usr/bin/env python3
"""Record the three reviewed display batch artifacts without installing them."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--gpu-kext', type=Path, required=True)
parser.add_argument('--accel-kext', type=Path, required=True)
parser.add_argument('--plugin', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
images = {
    'NMXGPU': args.gpu_kext/'Contents/MacOS/NMXGPU',
    'NMXAccel': args.accel_kext/'Contents/MacOS/NMXAccel',
    'NVMTLDriver': args.plugin,
}
manifest = {'os_build': subprocess.check_output(['sw_vers', '-buildVersion'], text=True).strip(), 'images': {}}
if manifest['os_build'] != '25G241':
    parser.error('unreviewed OS profile')
for name, path in images.items():
    uuid_text = subprocess.check_output(['xcrun', 'dwarfdump', '--uuid', str(path)], text=True)
    uuids = re.findall(r'UUID: ([0-9A-Fa-f-]+) \(x86_64\)', uuid_text)
    if len(uuids) != 1:
        parser.error(f'{name}: expected exactly one x86_64 UUID')
    manifest['images'][name] = {'path': str(path.resolve()), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'uuid': uuids[0]}
args.output.write_text(json.dumps(manifest, indent=2)+'\n')
print(args.output)
