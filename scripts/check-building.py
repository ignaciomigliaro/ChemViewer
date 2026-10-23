#!/usr/bin/env python3
"""Run the three original migrated suites with assertions enabled on every OS."""
from pathlib import Path
import subprocess
import sys
root = Path(__file__).resolve().parents[1]
build = root / '.build' / 'building-tests'
build.mkdir(parents=True, exist_ok=True)
for suite in ('Parser', 'Editing', 'State'):
    binary = build / (suite + ('Tests.exe' if sys.platform == 'win32' else 'Tests'))
    subprocess.run(['swiftc', '-module-cache-path', str(build/'module-cache'),
        str(root/'Sources/ChemCraftCore/VectorMath.swift'),
        str(root/'Sources/ChemCraftCore/IntegratedBuilding.swift'),
        str(root/f'Tests/IntegratedBuilding/{suite}Tests.swift'), '-o', str(binary)], cwd=root, check=True)
    subprocess.run([str(binary)], cwd=root, check=True)
