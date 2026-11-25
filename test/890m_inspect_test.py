#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 thanhnndev and contributors
"""Synthetic format/selection/error tests; optional checks against local captures."""
import importlib.util
from pathlib import Path
import random
import struct
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("inspect890", ROOT / "tools/890m_inspect.py")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


def checksum(data, offset=-1):
    data[offset] = 0
    data[offset] = (-sum(data)) & 255
    return data


def rom():
    data = bytearray(512)
    data[:3] = b"\x55\xaa\x01"
    struct.pack_into("<H", data, 0x48, 0x60)
    struct.pack_into("<HBB", data, 0x60, 36, 2, 2)
    data[0x64:0x68] = b"ATOM"
    struct.pack_into("<H", data, 0x80, 0x90)
    struct.pack_into("<HBB", data, 0x90, 50, 2, 1)
    struct.pack_into("<H", data, 0x90 + 4 + 22 * 2, 0xd0)
    struct.pack_into("<HBBHBB", data, 0xd0, 28, 1, 5, 2, 1, 0)
    struct.pack_into("<HHH", data, 0xd8, 0x3114, 24, 0x211e)
    struct.pack_into("<H", data, 0xd8 + 12, 2)
    data[0xe8:0xec] = b"\xff\x00\x00\x00"
    return bytes(checksum(data))


def vfct(images):
    data = bytearray(76)
    data[:4] = b"VFCT"
    struct.pack_into("<I", data, 52, 76)
    for bus, vendor, product, image in images:
        data.extend(struct.pack("<IIIHHHHII", bus, 0, 0, vendor, product, 0x1043, 0x3998, 0xc1, len(image)))
        data.extend(image)
    struct.pack_into("<I", data, 4, len(data))
    return bytes(checksum(data, 9))


def panel():
    base = bytearray(128)
    base[:8] = b"\x00\xff\xff\xff\xff\xff\xff\x00"
    base[18:20] = b"\x01\x04"
    base[24] = 2
    base[126] = 1
    # Independently encode known panel 60Hz DTD geometry (10 kHz clock units).
    d = bytearray(18)
    struct.pack_into("<H", d, 0, 65227)
    ha, hb, va, vb = 2880, 100, 1800, 1848
    d[2:8] = bytes((ha & 255, hb & 255, (ha >> 8) << 4 | hb >> 8,
                     va & 255, vb & 255, (va >> 8) << 4 | vb >> 8))
    d[8:12] = bytes((32, 8, 0x88, 0))
    d[17] = 0x1b
    base[54:72] = d
    ext = bytearray(128)
    ext[:8] = bytes((0x70, 0x20, 24, 2, 0, 0x22, 0, 20))
    t = (652264 - 1).to_bytes(3, "little") + bytes((0x85,)) + struct.pack(
        "<8H", 2879, 99, 31, 7, 1799, 23, 7, 7)
    ext[8:28] = t
    # byte 28 is legal trailing zero padding; byte29 is DisplayID checksum.
    ext[29] = (-sum(ext[1:29])) & 255
    return bytes(checksum(base) + checksum(ext))


class ParserTests(unittest.TestCase):
    def test_atom_edp(self):
        result = m.atom_bios(rom())
        self.assertEqual(result["display_paths"][0]["connector"], "eDP")

    def test_atom_invalid_pointer(self):
        data = bytearray(rom())
        struct.pack_into("<H", data, 0x80, 511)
        with self.assertRaises(m.ParseError):
            m.atom_bios(checksum(data))

    def test_atom_path_count_outside_table(self):
        data = bytearray(rom()); data[0xd6] = 255
        with self.assertRaises(m.ParseError):
            m.atom_bios(checksum(data))

    def test_vfct_exact_selection(self):
        images = m.vfct_images(vfct([(0x64, 0x1002, 0x150e, rom()),
                                   (0x65, 0x1002, 0x150e, rom())]))
        with self.assertRaises(m.ParseError):
            m.select_vfct(images, 0x1002, 0x150e)
        self.assertEqual(m.select_vfct(images, 0x1002, 0x150e, (0x65, 0, 0))["bus"], 0x65)
        with self.assertRaises(m.ParseError):
            m.select_vfct(images, 0x1002, 0x7550)

    def test_vfct_bad_length_and_checksum(self):
        valid = vfct([(0x65, 0x1002, 0x150e, rom())])
        for bad in (valid[:-1], valid + b"\x00", valid[:10] + b"X" + valid[11:]):
            with self.assertRaises(m.ParseError):
                m.vfct_images(bad)

    def test_vfct_image_bounds(self):
        data = bytearray(vfct([(0x65, 0x1002, 0x150e, rom())]))
        struct.pack_into("<I", data, 76 + 24, 0xffffffff)
        with self.assertRaises(m.ParseError):
            m.vfct_images(checksum(data, 9))

    def test_panel_exact_timings(self):
        modes = m.edid(panel())["timings"]
        self.assertEqual(len(modes), 2)
        self.assertEqual([t["vtotal"] for t in modes], [3648, 1824])
        self.assertEqual([t["pixel_clock_khz"] for t in modes], [652270, 652264])
        self.assertAlmostEqual(modes[1]["refresh_hz"], 120.000294, places=5)
        self.assertTrue(modes[1]["preferred"])
        self.assertFalse(modes[1]["hsync_positive"])

    def test_edid_count_and_checksums(self):
        data = panel()
        for bad in (data[:128], data + bytes(128), data[:200] + b"X" + data[201:]):
            with self.assertRaises(m.ParseError):
                m.edid(bad)

    def test_displayid_inner_checksum(self):
        data = bytearray(panel()); data[128 + 29] ^= 1
        data[128:] = checksum(data[128:])
        with self.assertRaisesRegex(m.ParseError, "section checksum"):
            m.edid(data)

    def test_type7_invalid_geometry(self):
        with self.assertRaises(m.ParseError):
            m.displayid_type7(bytes(20))

    def test_all_truncations(self):
        for fn, data in ((m.atom_bios, rom()), (m.edid, panel()),
                         (m.vfct_images, vfct([(0x65, 0x1002, 0x150e, rom())]))):
            for length in range(len(data)):
                with self.assertRaises(m.ParseError):
                    fn(data[:length])

    def test_random_input_fails_cleanly(self):
        rng = random.Random(890)
        for fn in (m.atom_bios, m.edid, m.vfct_images):
            for _ in range(200):
                with self.assertRaises(m.ParseError):
                    fn(rng.randbytes(rng.randrange(0, 2048)))

    @unittest.skipUnless((ROOT / "out/890m/vbios.bin").exists(), "local capture absent")
    def test_captured_vbios(self):
        result = m.atom_bios((ROOT / "out/890m/vbios.bin").read_bytes())
        self.assertEqual(result["image_length"], 21504)
        self.assertEqual(len(result["display_paths"]), 5)
        self.assertEqual(result["display_paths"][0]["connector"], "eDP")

    @unittest.skipUnless((ROOT / "out/890m-user/card2-eDP-2.edid").exists(), "local capture absent")
    def test_captured_panel(self):
        result = m.edid((ROOT / "out/890m-user/card2-eDP-2.edid").read_bytes())
        self.assertEqual(result["name"], "ATNA40CU05-0")
        self.assertEqual([t["vtotal"] for t in result["timings"]], [3648, 1824])


if __name__ == "__main__":
    unittest.main()
