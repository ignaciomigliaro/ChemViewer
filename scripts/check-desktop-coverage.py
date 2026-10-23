#!/usr/bin/env python3
"""Fail closed on desktop source inventory and per-module branch/line floors."""
import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("report")
args = parser.parse_args()
floors = json.loads((ROOT / "Tests/desktop-coverage-floors.json").read_text())
floors.pop("_note", None)
sources = {p.name for p in (ROOT / "desktop").glob("*.py")}
if sources != set(floors): raise SystemExit("Desktop coverage policy does not match source inventory")
report = json.loads(Path(args.report).read_text())
measured = {Path(name).name: data["summary"]["percent_covered"] for name, data in report["files"].items() if Path(name).parent.name == "desktop"}
if set(measured) != sources: raise SystemExit("Desktop report is missing or has unexpected source modules")
failed = []
for name, floor in floors.items():
    if name == "gl_platform.py" and sys.platform != "win32": continue
    if measured[name] + 1e-8 < floor: failed.append(f"{name}: {measured[name]:.2f}% < {floor}%")
if failed: raise SystemExit("\n".join(failed))
print("All platform-appropriate desktop module coverage floors passed.")
