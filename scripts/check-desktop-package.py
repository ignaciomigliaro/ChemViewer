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
    # Only this relocated temporary copy is mutated. Missing service must fail
    # explicitly, never load a development-tree executable or silently stay blank.
    service.unlink()
    negative_report = evidence / "missing-service.json"
    negative = subprocess.run([str(executable), str(folder / "examples/water.xyz"), "--acceptance-report", str(negative_report)],
                              cwd=base, env=env, capture_output=True, timeout=110)
    (evidence / "missing-service-stderr.log").write_bytes(negative.stderr)
    if negative.returncode != 1 or not negative_report.exists():
        raise SystemExit("Missing-service negative acceptance did not fail explicitly")
    failure = json.loads(negative_report.read_text())
    if failure["ok"] or not any("chemistry process" in error.lower() or "chemviewerservice" in error.lower() for error in failure["errors"]):
        raise SystemExit("Missing-service error was not surfaced: " + str(failure))
    print("Relocated desktop passed real render, picking, measurement, edit, undo and PNG acceptance with developer PATH removed.")
