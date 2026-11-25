#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 thanhnndev and contributors
"""Run offline step01 and preserve commands, source/input hashes and outcomes."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--vbios", type=Path, default=ROOT / "out/890m/vbios.bin")
    p.add_argument("--vfct", type=Path, default=ROOT / "out/890m/VFCT.bin")
    p.add_argument("--edid", type=Path, default=ROOT / "out/890m-user/card2-eDP-2.edid")
    p.add_argument("--out", type=Path, default=ROOT / "out/890m-trace")
    args = p.parse_args()
    started = datetime.now(timezone.utc).isoformat()
    destination = args.out / ("step01-" + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ"))
    destination.mkdir(parents=True, exist_ok=False)
    manifest = {"step": "890M-01", "started_utc": started, "euid": os.geteuid(),
                "inputs": {}, "sources": {}, "commands": [], "gpu_access": False}
    for filename in ("tools/890m_inspect.py", "tools/890m_step01.py", "test/890m_inspect_test.py"):
        manifest["sources"][filename] = sha(ROOT / filename)
    for command in (["git", "rev-parse", "HEAD"], ["git", "status", "--short", "--branch"]):
        result = subprocess.run(command, cwd=ROOT, text=True, capture_output=True)
        manifest["commands"].append({"argv": command, "exit_code": result.returncode,
                                     "stdout": result.stdout, "stderr": result.stderr})
    inspect = [sys.executable, str(ROOT / "tools/890m_inspect.py")]
    missing_required = False
    for name in ("vbios", "edid", "vfct"):
        path = getattr(args, name)
        try:
            checksum = sha(path)
        except OSError as error:
            manifest["inputs"][name] = {"path": str(path), "status": "unavailable", "reason": str(error)}
            if name != "vfct":
                missing_required = True
        else:
            manifest["inputs"][name] = {"path": str(path), "status": "readable", "sha256": checksum}
            inspect.extend(["--" + name, str(path)])
    jobs = [("tests", [sys.executable, str(ROOT / "test/890m_inspect_test.py"), "-v"])]
    if not missing_required:
        jobs.append(("inspect", inspect))
    failed = missing_required
    for name, command in jobs:
        result = subprocess.run(command, cwd=ROOT, text=True, capture_output=True)
        (destination / (name + ".stdout.txt")).write_text(result.stdout)
        (destination / (name + ".stderr.txt")).write_text(result.stderr)
        if name == "inspect" and result.returncode == 0:
            (destination / "report.json").write_text(result.stdout)
        manifest["commands"].append({"argv": command, "exit_code": result.returncode,
                                     "stdout_file": name + ".stdout.txt", "stderr_file": name + ".stderr.txt"})
        failed |= result.returncode != 0
    full = manifest["inputs"]["vfct"]["status"] == "readable"
    manifest["status"] = "FAIL" if failed else "PASS" if full else "PARTIAL-vfct-unavailable"
    manifest["finished_utc"] = datetime.now(timezone.utc).isoformat()
    (destination / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"{manifest['status']}: {destination}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
