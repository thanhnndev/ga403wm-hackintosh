#!/usr/bin/env python3
import copy
import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest
spec=importlib.util.spec_from_file_location('pat_wc',Path(__file__).resolve().parents[1]/'tools/pat_wc.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)

class PatWcTests(unittest.TestCase):
    def fixture(self):
        return {'Kernel':{'Patch':[dict(Identifier='kernel',MinKernel='24.0.0',Find=m.FIND,Mask=m.MASK,Enabled=True,Replace=m.ORIGINAL,Count=0)]},'untouched':b'private-fixture'}
    def test_only_pa6_changes(self):
        self.assertEqual([i for i,(a,b) in enumerate(zip(m.table(m.ORIGINAL),m.table(m.CORRECTED))) if a!=b],[6])
        self.assertEqual(m.table(m.CORRECTED),(6,1,7,0,6,1,1,0))
    def test_apply_undo_preserves_all_other_fields(self):
        with tempfile.TemporaryDirectory() as d:
            f=Path(d)/'config.plist';p=self.fixture();f.write_bytes(plistlib.dumps(p))
            backup=m.change(f);self.assertEqual(plistlib.loads(backup.read_bytes()),p)
            actual=plistlib.loads(f.read_bytes());expected=copy.deepcopy(p);expected['Kernel']['Patch'][0]['Replace']=m.CORRECTED
            self.assertEqual(actual,expected);self.assertIsNone(m.change(f));m.change(f,True)
            self.assertEqual(plistlib.loads(f.read_bytes()),p)
    def test_refuses_ambiguous_and_all_wb(self):
        p=self.fixture();p['Kernel']['Patch']*=2
        with self.assertRaises(ValueError):m.select(p)
        p=self.fixture();p['Kernel']['Patch'][0]['Replace']=bytes.fromhex('89c0b806060606ba060606060f309090')
        with self.assertRaises(ValueError):m.select(p)
    def test_kernel_mask(self):
        with tempfile.TemporaryDirectory() as d:
            f=Path(d)/'kernel';real=bytes.fromhex('89c081e2ffff00ff81ca000001000f30')
            f.write_bytes(real+b'gap'+real);self.assertEqual(m.kernel_matches(f),[0,len(real)+3])
            f.write_bytes(b'none');self.assertEqual(m.kernel_matches(f),[])

unittest.main()
