#!/usr/bin/env python3
"""Freeze the native Qt frontend plus real Swift service on the current host.

PyInstaller resolves service dependencies as binaries, including Swift DLLs.
No Python/Swift developer installation should be required by the final folder;
CI must verify that in a relocated folder with developer PATH removed.
"""
import argparse
import importlib.metadata
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--no-build", action="store_true")
parser.add_argument("--service", help="Use an explicitly validated ChemViewerService binary instead of building one")
parser.add_argument("--build-path", default=str(ROOT / ".build"))
parser.add_argument("--output-dir", default=str(ROOT / "dist"))
args = parser.parse_args()
build_path = Path(args.build_path).resolve()
output_dir = Path(args.output_dir).resolve()
if args.service:
    service = Path(args.service).resolve()
else:
    swift_build = ["swift", "build", "--scratch-path", str(build_path)]
    if not args.no_build:
        subprocess.run(swift_build + ["-c", "release", "--product", "ChemViewerService"], cwd=ROOT, check=True)
    bin_dir = Path(subprocess.check_output(swift_build + ["-c", "release", "--show-bin-path"], cwd=ROOT, text=True).strip())
    service = bin_dir / ("ChemViewerService.exe" if sys.platform == "win32" else "ChemViewerService")
if not service.exists(): raise SystemExit("Missing release service: " + str(service))
command = [sys.executable, "-m", "PyInstaller", "--noconfirm", "--clean", "--onedir", "--windowed",
           "--name", "ChemViewerDesktop", "--distpath", str(output_dir / "desktop"),
           "--workpath", str(build_path / "desktop-freeze"), "--specpath", str(build_path),
           "--paths", str(ROOT / "desktop"), "--add-binary", str(service) + os.pathsep + ".",
           "--hidden-import", "gl_platform" if sys.platform == "win32" else "OpenGL.platform.darwin" if sys.platform == "darwin" else "OpenGL.platform.glx",
           "--collect-submodules", "OpenGL.arrays", "--exclude-module", "PySide6.QtQuick3D",
           "--exclude-module", "PySide6.QtWebEngineCore", str(ROOT / "desktop/main.py")]
subprocess.run(command, cwd=ROOT, check=True)
folder = output_dir / "desktop/ChemViewerDesktop"
# Preserve original upstream license files alongside the dynamically linked Qt.
licenses = folder / "third-party-licenses"; licenses.mkdir(exist_ok=True)
packages = ["PySide6-Essentials", "shiboken6", "PyOpenGL", "numpy", "pyinstaller"]
manifest = {}
for package in packages:
    distribution = importlib.metadata.distribution(package)
    manifest[package] = distribution.version
    for file in distribution.files or []:
        if ("license" in str(file).lower() or "copying" in str(file).lower()) and str(file).split("/")[0].endswith(".dist-info"):
            source = Path(distribution.locate_file(file))
            if source.is_file():
                target = licenses / package / str(file).split("/", 1)[1]
                target.parent.mkdir(parents=True, exist_ok=True); shutil.copy2(source, target)
(folder / "dependencies.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
shutil.copy2(ROOT / "docs/windows-desktop.md", folder / "README.md")
examples = folder / "examples"; examples.mkdir(exist_ok=True)
for name in ("water.xyz", "methane.xyz", "energy-path.xyz", "desktop-imaginary.out"):
    shutil.copy2(ROOT / "Tests/fixtures" / name, examples / name)
archive = shutil.make_archive(str(output_dir / ("ChemViewer-desktop-" + sys.platform)), "zip", folder.parent, folder.name)
print(archive)
