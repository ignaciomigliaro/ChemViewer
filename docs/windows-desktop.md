# Windows desktop port (in development)

The Qt desktop is an actual desktop application, with local windows, file
handling and an accelerated OpenGL molecular viewport. It shares the Swift
ChemCraftCore parsers and geometry algorithms with the Mac application. Its
workspace shell now follows the native Mac layout: document tabs, the eight
primary modes, classic tool strip, left result explorer, white image canvas,
camera rail, stable selection inspector, status row and optional builder panel.
This is still an in-progress port, not a claim of complete functional parity or
a replacement for the validated native Mac application.

## Run from source

Windows (PowerShell, Swift 6.1.3 and Python 3.12 installed):

```powershell
swift build --product ChemViewerService
py -3 -m venv .venv-desktop
.venv-desktop/Scripts/python -m pip install -r desktop/requirements.txt
.venv-desktop/Scripts/python desktop/main.py Tests/fixtures/water.xyz
```

Linux (Swift 6.1.3, Python 3.12, OpenGL 3.3 drivers (or OpenGL 3.0 with ARB instancing) and Qt platform dependencies):

On Ubuntu 24.04, install `python3-venv libegl1 libgl1-mesa-dri libxcb-cursor0
libxkbcommon-x11-0 libxcb-icccm4 libxcb-keysyms1 libxcb-xinerama0 libxcb-shape0
libglib2.0-0t64 libdbus-1-3`. Automated GUI runs additionally need `xvfb xauth`.

```bash
swift build --product ChemViewerService
python3 -m venv .venv-desktop
.venv-desktop/bin/python -m pip install -r desktop/requirements.txt
.venv-desktop/bin/python desktop/main.py Tests/fixtures/water.xyz
```

The same command works on macOS for development, without changing the existing
SwiftUI/AppKit/Metal application or its canonical installation. A custom service
location can be set with `CHEMVIEWER_SERVICE`.

![Windows Qt desktop using the Apple-style ChemViewer workspace and independently authored water fixture](images/native-qt-desktop.png)

The screenshot is the actual frozen implementation running on Windows 11 at
96 DPI. It is not a mockup. The same workflow also passes Qt's bundled Mesa
OpenGL 3.0/GLSL 1.30 software path.

## Interface alignment with the Mac application

- Image, Abstract, Source, Coord, Image/Abs, ChemRefine, Draw and BOS-TMC use
  the same order and fixed tab geometry as the Apple workspace.
- The compatibility shell takes its dimensions directly from the SwiftUI views:
  35-point document strip, fixed 100/115-by-39 mode tabs, 45-point toolbar,
  37-point camera rail, 140-point inspector and 30-point status row. Menus use
  the Mac order: File, Edit, Build, View, Display, Tools, Compute and Help.
- Toolbar artwork is dependency-free monochrome vector drawing corresponding to
  the Mac SF Symbols. It does not depend on Windows emoji or a locally installed
  icon font, so the packaged executable cannot substitute colored emoji or boxes.
- Result geometries and frequencies live in the left explorer instead of an
  always-open form column. Build & Edit is hidden until requested.
- Image keeps one renderer, a narrow camera rail, a fixed 140-point selection
  inspector and a 30-point status row, so selection does not resize the view.
- Abstract contains the calculation summary and absolute-Hartree energy plot;
  Image/Abs reuses the same live renderer beside that panel.
- The empty window has the same new/open workspace entry points.
- ChemRefine, Draw and BOS-TMC tabs are present but explicitly report their
  current porting boundary. They do not imitate successful Mac-only work.

## Implemented interactions

- New/Open, multiple document tabs, local drag-and-drop, duplicate-file activation,
  per-document camera and edit history, unsaved-change cancellation.
- Instanced, depth-tested spheres and cylinders; the native Mac Paton CPK table,
  HLS gradient, thin black bonds, display radii and outline threshold; Publication,
  Soft spheres, Large spheres and Sticks alternatives; hydrogen visibility;
  centered element/number captions; Fit and PNG export.
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
for Linux automation, Xvfb with Mesa software OpenGL. The suite currently contains
16 desktop GUI workflows and 15 service regressions.
Per-module line/branch floors are enforced from
`Tests/desktop-coverage-floors.json`. They fail on blank rendering;
a passing process exit alone is insufficient.

For Windows software-rendered CI, `QT_OPENGL=software` selects the Qt wheel's
Mesa `opengl32sw.dll`. Its older GL 3.0 implementation uses the GLSL 1.30/ARB
instancing path; modern contexts use GLSL 3.30. Both retain instanced meshes and
depth-tested rendering. The PyOpenGL platform adapter loads the same driver so
context and procedure addresses agree. Ordinary Windows runs use system GPU
OpenGL. HiDPI and installer acceptance are still required.

### Current Windows source acceptance

On 2026-10-29 the 16 GUI workflows passed on Windows 11 build 26300, 96 DPI,
Python 3.9.13, PySide6 6.8.3, NumPy 2.0.2 and PyOpenGL 3.1.9. The normal GPU
report records OpenGL 3.3.0 on an NVIDIA GeForce RTX 5070 Ti and shader path
330. The software report records Mesa 3.0, llvmpipe and shader path 130. Both
reports completed rendering, analytic picking, the 0.95720 Å measurement,
coordinate edit/undo and PNG/full-window capture without an application error.
An additional `QT_SCALE_FACTOR=1.5` NVIDIA run completed the same gate with all
tabs, toolbar controls, explorer, inspector and camera rail visible. This checks
Qt scaling and clipping, but does not replace a physical high-density display.

The source UI was paired with the immutable service from successful Actions run
40026145513: service SHA-256
`ba76bcc8dec81d7d8d780299606db4461fedd6c9f3f47f3dc60dee48e7055963`.
That isolates this visual-shell change from parser drift. A newly frozen package
from the changed source also passes the relocated, developer-PATH-stripped gate
on the NVIDIA OpenGL path. Removing only the temporary relocated service copy
produces the required explicit failure rather than a fallback. After the direct
Mac-UI constant and complete 119-element Paton-renderer translation, the
78,676,938-byte ZIP has
SHA-256
`86e1f8a37d7fb8423adf7edd4db813c03a65d3bedbdfa48378a174bc8d28c097`.
This local package deliberately reuses the immutable validated service because
Swift is absent on this host; a hosted build of that service from the merged
source and cross-platform checks are still required before release.

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
exports, preferences, renderer performance, HiDPI and installed-package acceptance
also remain. Linux shares this frontend and needs its own distribution/desktop/GPU
acceptance after Windows. Do not label the 1.0 parity gate passed from these
initial desktop tests.
