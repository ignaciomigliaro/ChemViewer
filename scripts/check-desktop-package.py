#!/usr/bin/env python3
"""Relocate a desktop ZIP and run its actual GUI without developer PATH."""
import argparse
import json
import os
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--archive", required=True)
parser.add_argument("--evidence", default=".build/desktop-package-evidence")
args = parser.parse_args()
evidence = Path(args.evidence).resolve(); evidence.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix="ChemViewer relocated desktop ü ") as temporary:
    base = Path(temporary)
    with zipfile.ZipFile(args.archive) as archive: archive.extractall(base)
    folder = base / "ChemViewerDesktop"
    executable = folder / ("ChemViewerDesktop.exe" if sys.platform == "win32" else "ChemViewerDesktop")
    service = folder / "_internal" / ("ChemViewerService.exe" if sys.platform == "win32" else "ChemViewerService")
    if sys.platform != "win32":
        executable.chmod(executable.stat().st_mode | 0o111); service.chmod(service.stat().st_mode | 0o111)
    env = os.environ.copy()
    for key in ("CHEMVIEWER_SERVICE", "PYTHONPATH", "PYTHONHOME", "SWIFT_EXEC", "SWIFT_ROOT", "SDKROOT", "DYLD_LIBRARY_PATH", "LD_LIBRARY_PATH"):
        env.pop(key, None)
    env["PATH"] = os.path.join(env.get("SystemRoot", "C:\\Windows"), "System32") if sys.platform == "win32" else "/usr/bin:/bin"
    report = evidence / "packaged-acceptance.json"
    result = subprocess.run([str(executable), str(folder / "examples/water.xyz"), "--acceptance-report", str(report)],
                            cwd=base, env=env, capture_output=True, timeout=110)
    (evidence / "packaged-stdout.log").write_bytes(result.stdout)
    (evidence / "packaged-stderr.log").write_bytes(result.stderr)
    if result.returncode or not report.exists():
        raise SystemExit(f"Packaged desktop failed ({result.returncode}); inspect {evidence}")
    payload = json.loads(report.read_text())
    if not payload["ok"]: raise SystemExit(str(payload))
    print("Relocated desktop passed real render, picking, measurement, edit, undo and PNG acceptance with developer PATH removed.")
