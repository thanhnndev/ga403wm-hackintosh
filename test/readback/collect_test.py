#!/usr/bin/env python3
"""Tests the decision logic of scripts/macos-ws-readback-collect.py on synthetic counter snapshots (no Mac needed)."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("collect", Path(__file__).resolve().parents[2] / "scripts/macos-ws-readback-collect.py")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


def snap(**kw):
    return {"debug." + k: v for k, v in kw.items()}


class Analyse(unittest.TestCase):
    def test_stock_kernel_reports_missing_diagnostics_and_stale_copies(self):
        a = snap(nvaccel_iop_ok=0, nvaccel_iop_flips=0, nvaccel_iop_flip_stale=0, nvaccel_vm_alloc=100, nvaccel_res_new=100)
        b = snap(nvaccel_iop_ok=300, nvaccel_iop_flips=100, nvaccel_iop_flip_stale=280, nvaccel_vm_alloc=100, nvaccel_res_new=100)
        lines, findings = m.analyse(a, b, 10.0, 40.0)
        text = "\n".join(lines)
        self.assertIn("40.0 frames/s", text)
        self.assertIn("NOT installed", text)
        self.assertTrue(any(f.startswith("R1") for f in findings))

    def test_pend_full_points_at_patch_0003(self):
        a = snap(nvaccel_ss_dirty_ok=0, nvaccel_ss_dirty_pend_full=0, nvaccel_ss_pend_high=0, nvaccel_ss_pend_count=0, nvaccel_iop_ok=0, nvaccel_iop_flips=0)
        b = snap(nvaccel_ss_dirty_ok=100, nvaccel_ss_dirty_pend_full=900, nvaccel_ss_pend_high=512, nvaccel_ss_pend_count=512, nvaccel_iop_ok=10, nvaccel_iop_flips=400)
        lines, findings = m.analyse(a, b, 10.0, None)
        self.assertTrue(any(f.startswith("R3") and "pending table is full" in f for f in findings))
        self.assertTrue(any(f.startswith("R4") for f in findings))
        self.assertIn("90.0% refused", "\n".join(lines))

    def test_other_reason_does_not_claim_the_fix_applies(self):
        a = snap(nvaccel_ss_dirty_ok=0, nvaccel_ss_dirty_no_cache=0, nvaccel_iop_ok=0, nvaccel_iop_flips=0)
        b = snap(nvaccel_ss_dirty_ok=10, nvaccel_ss_dirty_no_cache=500, nvaccel_ss_pend_high=3, nvaccel_ss_pend_count=2, nvaccel_iop_ok=0, nvaccel_iop_flips=100)
        _, findings = m.analyse(a, b, 10.0, 20.0)
        r3 = [f for f in findings if f.startswith("R3")]
        self.assertEqual(len(r3), 1)
        self.assertIn("no_cache", r3[0])
        self.assertIn("does NOT address", r3[0])

    def test_healthy_window(self):
        a = snap(nvaccel_ss_dirty_ok=0, nvaccel_iop_ok=0, nvaccel_iop_flips=0, nvaccel_ss_share_ok=0)
        b = snap(nvaccel_ss_dirty_ok=1000, nvaccel_iop_ok=0, nvaccel_iop_flips=500, nvaccel_ss_share_ok=10, nvaccel_ss_pend_high=40, nvaccel_ss_pend_count=20)
        _, findings = m.analyse(a, b, 10.0, 10.0)
        self.assertEqual(findings, [])

    def test_rewire_hypothesis_needs_a_clear_excess(self):
        a = snap(nvaccel_vm_alloc=100, nvaccel_res_new=100, nvaccel_iop_ok=0, nvaccel_iop_flips=0)
        _, none = m.analyse(a, snap(nvaccel_vm_alloc=105, nvaccel_res_new=100, nvaccel_iop_ok=0, nvaccel_iop_flips=0), 10.0, 0.0)
        self.assertFalse(any(f.startswith("H6") for f in none))
        _, some = m.analyse(a, snap(nvaccel_vm_alloc=900, nvaccel_res_new=300, nvaccel_iop_ok=0, nvaccel_iop_flips=0), 10.0, 0.0)
        self.assertTrue(any(f.startswith("H6") for f in some))

    def test_log_counts(self):
        text = "x NullMoth: surface 5 dirty refused (0x80000013) - copy-out\n" * 3 + "y NullMoth: item 7: surface 1 plane 0: family VRAM import refused (-1000072003) - private\n"
        self.assertEqual(m.log_findings(text), {"dirty refused (0x80000013)": 3, "family VRAM import refused (-1000072003)": 1})


if __name__ == "__main__":
    unittest.main()
