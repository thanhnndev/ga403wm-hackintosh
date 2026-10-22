#!/usr/bin/env python3
import copy
import importlib.util
import pathlib
import struct
import sys
import unittest

root = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root / 'tools'))
spec = importlib.util.spec_from_file_location('profile', root / 'tools/strix_abi_profile.py')
profile = importlib.util.module_from_spec(spec); spec.loader.exec_module(profile)


class Tests(unittest.TestCase):
    def layout(self, base):
        return {'classes': {name: {'size': 32, 'nslots': 3, 'super_sym': '__parent',
                                  'slots': ['__known_symbol', hex(base + 32), None]}
                            for name in profile.CLASSES}}

    def test_rebasing_does_not_change_fingerprint_input(self):
        self.assertEqual(profile.normalize(self.layout(0x100), 0x100, 0x200),
                         profile.normalize(self.layout(0x200), 0x200, 0x300))

    def test_private_target_outside_family_rejected(self):
        x = self.layout(0x100); x['classes'][profile.CLASSES[0]]['slots'][1] = '0x301'
        with self.assertRaises(ValueError): profile.normalize(x, 0x100, 0x200)

    def test_interior_null_or_changed_terminal_layout_rejected(self):
        for offset in (0, 2):
            x = self.layout(0x100); x['classes'][profile.CLASSES[0]]['slots'][offset] = None if offset == 0 else '__new_slot'
            with self.assertRaises(ValueError): profile.normalize(x, 0x100, 0x200)

    def test_missing_size_rejected(self):
        x = self.layout(0x100); x['classes'][profile.CLASSES[0]]['size'] = None
        with self.assertRaises(ValueError): profile.normalize(x, 0x100, 0x200)

    def test_uuid_bounds(self):
        class Fake: pass
        f = Fake(); f.entries = {'family': (0, 0)}; f.m = bytearray(56)
        struct.pack_into('<II', f.m, 16, 1, 24); struct.pack_into('<II', f.m, 32, 0x1b, 24)
        f.m[40:56] = bytes(range(16))
        self.assertEqual(profile.family_uuid(f, 'family'), bytes(range(16)).hex())
        f.m = f.m[:-1]
        with self.assertRaises(ValueError): profile.family_uuid(f, 'family')


if __name__ == '__main__': unittest.main()
