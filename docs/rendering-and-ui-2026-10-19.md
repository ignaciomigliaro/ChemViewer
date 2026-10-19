# Rendering and interface update — 2026-10-19

ChemViewer 0.2.0 replaces the original fixed-size point sprites and thin line
bonds. The new native Metal renderer uses triangulated spheres and cylinders,
a depth32Float attachment, depth writes/comparison, and four-sample antialiasing
when supported. Picking uses projected world-space atom radii and front depth.
Narrow panes fit both dimensions; pausing a mode preserves its current phase.
Source coordinates and vibrational vectors remain unchanged by styling.

## xyzrender reference

Inspected https://github.com/aligfellow/xyzrender at commit
`828e721e40b18f1944c87f949ce224af812dc649`, including its README, package
requirements, default/paton presets, license, and caffeine example images.
It is a Python SVG renderer with NumPy, graph/chemistry, and image dependencies,
rather than a native interactive Metal backend. ChemViewer therefore implements
its own realtime geometry with a white canvas, dark bonds, shaded outlined
atoms, and pale carbon inspired by that reference. Soft spheres uses the
paton-inspired C/H/N palette. Sticks and Large spheres are additional display
schemes. Large spheres uses approximate graphical radii; it is not a source of
van der Waals radii or a physical surface calculation.

The adapted palette's MIT notice is in `third-party/xyzrender-LICENSE.txt` and
is copied into every app bundle. No xyzrender rendering engine or Python
runtime is bundled, and identical SVG output, inferred bond orders, fog,
aromaticity, and orbital surfaces are not claimed. Every input hydrogen stays
visible. Bond connectivity is still the existing distance-based inference.

## Implemented interface behavior

The Windows GUI audit, not proprietary implementation code, supplied the tab
names and workflow reference. Image shows the molecule, Abstract shows known
parsed geometries/energies/frequencies with working navigation, Source shows
original selectable input text, Coord provides editable Cartesian coordinates
and Apply, and Image/Abs shows the viewport beside the summary. Coordinate undo
refreshes the embedded editor. Nonfinite edits are rejected before rendering.

A compact top toolbar, right camera rail, bottom status/measurements, and native
File/Edit/View/Display/Tools commands expose the implemented actions. Controls
without valid input are disabled. Cmd+1 through Cmd+5 select views. PNG export
saves the actual viewport at its current drawable resolution, including the
current camera, style, selection and mode phase. It does not export the GUI.

## Reproduction and evidence

```
bash scripts/build-macos.sh
dist/ChemViewer.app/Contents/MacOS/ChemViewer --smoke-test \
  --capture-window --render-evidence /Users/nacho/Downloads/chemviewer-validation \
  --preview-file /Users/nacho/Downloads/xyzrender-reference/examples/structures/caffeine.xyz
```

On the local ARM64 Mac, the build and signature/architecture checks passed.
Eleven existing core regression methods passed through the standalone runner;
XCTest remains unavailable with Command Line Tools. The packaged live-window
check passed shader loading, GPU completion, XYZ roundtrip, coordinate undo,
selection, original source retention, PNG capture, order-independent occlusion
(front O/rear N), mounting all five tabs, and negative-mode animation/pause.

The GPU PNGs and real window screenshots are local evidence in
`/Users/nacho/Downloads/chemviewer-validation`: `molecular-preview.png`,
`water-render.png`, `overlap-a.png`, `overlap-b.png`, `workspace-window.png`,
`tab-Source.png`, `tab-Coord.png`, `tab-Abstract.png`, and `tab-Image-Abs.png`.
The final window captures were visually inspected. An earlier discarded
`workspace-preview.png` was an invalid AppKit compositing attempt, not a true
window screenshot; do not use it as evidence. No reference screenshots or
vendor fixtures are committed.

## Remaining limits

This is a bounded rendering/UI improvement, not full Chemcraft parity. Fragment
building/attachment, fragment dragging, manual bond-order editing, orbital and
cube surfaces, and further output formats remain unfinished. Abstract contains
only currently parsed values; no thermochemistry or job metadata is invented.
Manual pointer/trackpad/dialog acceptance tests and large-system performance
benchmarks remain pending. Meshes are currently rebuilt on each frame, so the
new renderer is not yet validated for very large structures. Camera orientation
and per-view UI state are not yet persisted when switching tabs.
