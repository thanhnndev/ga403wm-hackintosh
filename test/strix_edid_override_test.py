#!/usr/bin/env python3
import importlib.util
from pathlib import Path
import unittest
spec = importlib.util.spec_from_file_location('override', Path(__file__).resolve().parents[1] / 'tools/strix_edid_override.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


def edid(pq=True):
    b = bytearray(256)
    b[:8] = bytes.fromhex('00ffffffffffff00')
    b[8:12] = bytes.fromhex('4c839c41')
    b[126] = 1
    b[127] = -sum(b[:127]) % 256
    b[128:136] = bytes([2, 3, 8, 0, 0xe3, 6, 4 if pq else 1, 1])
    b[255] = -sum(b[128:255]) % 256
    return bytes(b)


class OverrideTests(unittest.TestCase):
    def registry(self, data):
        return [{'IOObjectClass': 'StrixGOPFramebuffer', 'IORegistryEntryChildren':
                 [{'IOObjectClass': 'AppleBacklightDisplay', 'IODisplayEDID': data}]}]

    def old(self):
        return {'DisplayVendorID': 0x4c83, 'DisplayProductID': 0x419c,
                'DisplayProductName': 'Built-in OLED', 'scale-resolutions': [b'preserve-me'], 'IOGFlags': 4}

    def test_preserves_every_other_key(self):
        old = self.old()
        new = m.prepare(old, self.registry(edid()))
        self.assertEqual({k: v for k, v in new.items() if k != 'IODisplayEDID'}, old)
        self.assertEqual(new['IODisplayEDID'], edid())

    def test_bad_checksum_rejected(self):
        data = bytearray(edid()); data[255] ^= 1
        with self.assertRaises(ValueError): m.prepare(self.old(), self.registry(bytes(data)))

    def test_no_pq_rejected(self):
        with self.assertRaises(ValueError): m.prepare(self.old(), self.registry(edid(False)))

    def test_wrong_identity_rejected(self):
        old = self.old(); old['DisplayProductID'] = 1
        with self.assertRaises(ValueError): m.prepare(old, self.registry(edid()))

    def test_ambiguous_and_unrelated_display_rejected(self):
        registry = self.registry(edid())
        with self.assertRaises(ValueError): m.prepare(self.old(), registry * 2)
        registry[0]['IOObjectClass'] = 'OtherFramebuffer'
        with self.assertRaises(ValueError): m.prepare(self.old(), registry)

    def test_truncated_cta_rejected(self):
        data = bytearray(edid()); data[130] = 6; data[255] = 0
        data[255] = -sum(data[128:255]) % 256
        with self.assertRaises(ValueError): m.prepare(self.old(), self.registry(bytes(data)))


if __name__ == '__main__': unittest.main()
