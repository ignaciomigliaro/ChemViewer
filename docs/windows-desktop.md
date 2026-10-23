# Windows desktop port (in development)

The Qt desktop is an actual desktop application, with local windows, file
handling and an accelerated OpenGL molecular viewport. It shares the Swift
ChemCraftCore parsers and geometry algorithms with the Mac application.
This branch starts the Windows-first port; it is not a claim of complete parity
or a replacement for the validated native Mac application.

## Run from source

Windows (PowerShell, Swift 6.1.3 and Python 3.12 installed):

```powershell
swift build --product ChemViewerService
py -3 -m venv .venv-desktop
.venv-desktop/Scripts/python -m pip install -r desktop/requirements.txt
.venv-desktop/Scripts/python desktop/main.py Tests/fixtures/water.xyz
```

Linux (Swift 6.1.3, Python 3.12, OpenGL 3.3 drivers and Qt platform dependencies):

```bash
swift build --product ChemViewerService
python3 -m venv .venv-desktop
.venv-desktop/bin/python -m pip install -r desktop/requirements.txt
.venv-desktop/bin/python desktop/main.py Tests/fixtures/water.xyz
```

The same command works on macOS for development, without changing the existing
SwiftUI/AppKit/Metal application or its canonical installation. A custom service
location can be set with `CHEMVIEWER_SERVICE`.

## Implemented interactions

- New/Open, multiple document tabs, local drag-and-drop, duplicate-file activation,
  per-document camera and edit history, unsaved-change cancellation.
- Instanced, depth-tested spheres and cylinders, element colors, ball-and-stick
  and illustrative space-filling display sizes, labels, Fit and PNG export.
- Drag rotates; Shift-drag or middle-drag pans; wheel zooms. Click selects;
  Ctrl-click extends an ordered selection. Two/three/four atoms measure distance,
  angle and signed dihedral through the shared Swift algorithms.
- Coordinate-table element/Cartesian edits, atom addition/deletion, built-in
  fragments with explicit placement coordinates and attachment to a selected
  host atom, numeric distance/angle edits, Undo/Redo.
- Geometry selector/playback, negative-frequency labels, illustrative normal-mode
  animation on the source frame. Inactive document animation stops.
- Source view preserves original decoded text. Properties distinguishes missing
  energies, charge, multiplicity, IR intensity and Raman activity.
- Energy plot and CSV use absolute source Hartree values, retaining precision
  and gaps for absent energies.
- Export current or all equilibrium geometries through the shared XYZ writer;
  normal-mode display displacement is never exported as equilibrium coordinates.
- Save/reopen `.cvdesktop` projects, including original source, per-frame edited
  coordinates and embedded ORCA-input XYZ companions. Projects can move without
  the original input/companion files. This desktop project schema is separate
  from the existing Mac builder project format.

Geometry changes invalidate associated energy, thermochemistry/path summaries
and affected normal modes; Undo restores the original scientific state. Exports
never clear unsaved-project state. Failed commands do not change the document.
All chemistry work runs in a persistent private child process using JSON lines
on stdin/stdout. There is no network listener, shell interpolation or browser.

## Reproducible checks

```bash
swift build --product ChemViewerService
python3 scripts/check-desktop-service.py --binary .build/debug/ChemViewerService
python3 Tests/gui/desktop/test_desktop.py
```

On Windows use the `.exe` service suffix. GUI tests require an actual desktop or,
for Linux automation, Xvfb with Mesa software OpenGL. They fail on blank rendering;
a passing process exit alone is insufficient.

For Windows software-rendered CI, `QT_OPENGL=software` selects the Qt wheel's
Mesa `opengl32sw.dll`; the PyOpenGL platform adapter loads the same driver so
context and procedure addresses agree. Ordinary Windows runs use system GPU
OpenGL. Physical Windows GPU/HiDPI/installer acceptance is still required.

Build a frozen application with Python, Qt and Swift runtime dependencies:

```bash
python3 -m pip install -r desktop/requirements-build.txt
python3 scripts/package-desktop.py
python3 scripts/check-desktop-package.py --archive dist/ChemViewer-desktop-linux.zip
```

Archive suffixes are `win32`, `linux` or `darwin`. Build on the target operating
system. The relocated-package check strips the developer PATH and exercises the
real GUI, core process, render pixels, selection, edit/undo and PNG export.
These are development ZIPs, not signed installers. Bundled licenses and dependency
versions accompany them. Qt Widgets/OpenGL is dynamically linked through PySide6;
Qt sources: <https://code.qt.io/cgit/qt/>; PySide sources:
<https://code.qt.io/cgit/pyside/pyside-setup.git/>. Qt Quick 3D is not used.

## Remaining parity work

The next ports are full calculation/thermochemistry/NEB presentation and spectra,
Mac builder groups/transform controls and project interoperability, 2D drawing and
chemistry-runtime integration, ChemRefine workflow UI, SSH authentication/file
explorer and BosTMC screening. High-resolution/transparent image and animation
exports, preferences, renderer performance and physical Windows acceptance also
remain. Linux shares this frontend and needs its own distribution/desktop/GPU
acceptance after Windows. Do not label the 1.0 parity gate passed from these
initial desktop tests.
