#!/usr/bin/env python3
import copy
import importlib.util
import pathlib
import plistlib
import struct
import unittest

root = pathlib.Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('trial', root / 'tools/strix_gop_trial.py')
trial = importlib.util.module_from_spec(spec)
spec.loader.exec_module(trial)


class ProfileTests(unittest.TestCase):
    def setUp(self):
        config = bytearray(256)
        struct.pack_into('<HH', config, 0, 0x1002, 0x150e)
        config[8] = 0xc1
        struct.pack_into('<HH', config, 0x2c, 0x1043, 0x3998)
        struct.pack_into('<II', config, 0x10, 0x8000000c, 8)
        self.entry = {'TraceStep': '890M-02', 'ProbeVersion': '0.1.2',
                      'PCI,MatchCount': 1, 'Snapshot,InProgress': False,
                      'Console,PhysicalFlag': True, 'Console,RawBase': 0x880000001,
                      'Console,PhysicalBase': 0x880000000, 'Console,Offset': 0,
                      'Console,Rotation': 0, 'Console,Width': 2880, 'Console,Height': 1800,
                      'Console,RowBytes': 11520, 'Console,Depth': 32,
                      'Console,RasterBytes': 20736000,
                      'GPU0': {'PCIConfig256': bytes(config), 'BAR0,OSBase': 0x880000000,
                               'BAR0,OSLength': 0x10000000, 'BAR0,SegmentLength': 0x10000000}}

    def parse(self, entry):
        return trial.boot_profile(plistlib.dumps([entry]))

    def test_valid_boot(self):
        self.assertEqual(self.parse(self.entry)['Offset'], 0)

    def test_invalid_console_and_acquisition(self):
        for key, value in [('Console,PhysicalFlag', False), ('Snapshot,InProgress', True),
                           ('PCI,MatchCount', 0), ('PCI,MatchCount', 2), ('Console,Depth', 30),
                           ('Console,Rotation', 1), ('Console,Offset', 4),
                           ('Console,Width', 16385), ('Console,RowBytes', 11519),
                           ('Console,RasterBytes', 1), ('Console,PhysicalBase', 0x980000000)]:
            with self.subTest(key=key, value=value):
                e = copy.deepcopy(self.entry); e[key] = value
                with self.assertRaises(ValueError): self.parse(e)

    def test_identity_and_bar_mismatch(self):
        for offset in (0, 2, 8, 0x2c, 0x2e, 0x10, 0x14):
            with self.subTest(offset=offset):
                e = copy.deepcopy(self.entry); c = bytearray(e['GPU0']['PCIConfig256'])
                c[offset] ^= 1; e['GPU0']['PCIConfig256'] = bytes(c)
                with self.assertRaises(ValueError): self.parse(e)

    def test_missing_or_discontiguous_resource(self):
        e = copy.deepcopy(self.entry); e['GPU0']['BAR0,SegmentLength'] = 4096
        with self.assertRaises(ValueError): self.parse(e)
        e = copy.deepcopy(self.entry); e['GPU0']['BAR0,OSLength'] = 4096
        e['GPU0']['BAR0,SegmentLength'] = 4096
        with self.assertRaises(ValueError): self.parse(e)

    def test_real_boot_when_present(self):
        p = root / 'out/890m-trace/step02-20261013T090147.620403Z/ioreg.plist'
        if not p.exists(): self.skipTest('Local runtime fixture absent')
        self.assertEqual(trial.boot_profile(p.read_bytes())['Width'], 2880)

    def test_live_virtual_when_present(self):
        p = root / 'out/890m-trace/step02-20261013T090147.620403Z/refresh-1.plist'
        if not p.exists(): self.skipTest('Local runtime fixture absent')
        with self.assertRaises(ValueError): trial.boot_profile(p.read_bytes())


if __name__ == '__main__': unittest.main()
