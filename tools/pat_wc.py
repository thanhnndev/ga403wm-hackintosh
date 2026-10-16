#!/usr/bin/env python3
"""Restore XNU's PA6 write-combining slot in the Sequoia Algrey AMD PAT patch.

Changes only PAT entry 6 (UC- -> WC); does not use Shaneee's all-WB table.
No runtime MSR writes. Apply / undo are effective after reboot.
"""
import argparse
import datetime
from pathlib import Path
import plistlib
import shutil

ORIGINAL = bytes.fromhex('89c0b806010700ba060107000f309090')
CORRECTED = bytes.fromhex('89c0b806010700ba060101000f309090')
FIND = bytes.fromhex('89c081e2ffff00ff81ca000000000f30')
MASK = bytes.fromhex('ffffffffffffffffffff00000000ffff')


def table(code):
    if len(code) != 16 or code[:3] != b'\x89\xc0\xb8' or code[7] != 0xba or code[12:] != b'\x0f\x30\x90\x90':
        raise ValueError('unexpected PAT replacement instructions')
    return tuple(code[3:7] + code[8:12])


def select(config):
    matches = [x for x in config['Kernel']['Patch'] if x['Identifier'] == 'kernel'
               and x['MinKernel'] == '24.0.0' and x['Find'] == FIND and x['Mask'] == MASK
               and x['Enabled']]
    if len(matches) != 1 or matches[0]['Replace'] not in (ORIGINAL, CORRECTED):
        raise ValueError('expected exactly one enabled Sequoia Algrey PAT patch with known bytes')
    return matches[0]


def kernel_matches(path):
    blob = path.read_bytes(); pos = 0; found = []
    while True:
        pos = blob.find(FIND[:8], pos)
        if pos < 0:
            return found
        raw = blob[pos:pos+len(FIND)]
        if len(raw) == len(FIND) and all((a & m) == (b & m) for a,b,m in zip(raw,FIND,MASK)):
            found.append(pos)
        pos += 1


def change(path, undo=False):
    original = path.read_bytes()
    config = plistlib.loads(original); patch = select(config)
    target = ORIGINAL if undo else CORRECTED
    if patch['Replace'] == target:
        print(f'{path}: already {"original" if undo else "PA6 WC"}')
        return None
    stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    backup = path.with_name(path.name + '.pre-pat-pa6-' + stamp)
    # Never overwrite a backup. Preserve unrelated fields and current configuration.
    with backup.open('xb') as stream:
        stream.write(original)
    patch['Replace'] = target
    encoded = plistlib.dumps(config, sort_keys=False)
    # Check the complete roundtrip before replacing the live file.
    if plistlib.loads(encoded) != config:
        raise ValueError('plist roundtrip mismatch')
    stage = path.with_name(path.name + '.pat-pa6-new')
    with stage.open('xb') as stream:
        stream.write(encoded)
    try:
        shutil.copymode(path, stage)
        if path.read_bytes() != original:
            raise ValueError('configuration changed during staging; refusing to overwrite')
        stage.replace(path)
        assert select(plistlib.loads(path.read_bytes()))['Replace'] == target
    except BaseException:
        if stage.exists(): stage.unlink()
        raise
    print(f'{path}: PAT entries {table(target)}; backup {backup.name}; reboot required')
    return backup


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--config', type=Path, default=Path('efi/OC/config.plist'))
    p.add_argument('--apply', action='store_true')
    p.add_argument('--undo', action='store_true')
    p.add_argument('--kernel', type=Path)
    args = p.parse_args()
    if args.apply and args.undo: p.error('choose apply or undo')
    patch = select(plistlib.loads(args.config.read_bytes()))
    print('Configured PAT entries:', table(patch['Replace']))
    if args.kernel:
        hits = kernel_matches(args.kernel)
        print('Masked kernel pattern matches:',len(hits))
        if not hits: raise SystemExit('STOP: no matching PAT instructions in this kernel')
    if args.apply or args.undo: change(args.config,args.undo)


if __name__ == '__main__': main()
