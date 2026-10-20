# Editable elements and atom placement — 2026-10-20

ChemViewer 0.9.3 (build 21), local Apple Silicon macOS GUI.

- `bash scripts/build-macos.sh`: passed 29 standalone core regressions and
  three migrated building suites; release ARM64 binary and strict signature
  verification passed. The new core regression checks replacement of Fe with
  Ru/atomic number/Pt/Og/X, unchanged positions/IDs/groups/selection/charge/spin,
  original project preservation, and rejection of empty/unknown symbols and
  invalid atom indices.
- `swift test` before/after core edits: this Command Line Tools host still lacks
  XCTest. The standalone adapter executes the checked-in assertions locally;
  GitHub's full-Xcode runner executes XCTest separately.
- `--atom-editing-smoke-test`: passed. All 118 native element buttons are
  present; actual button activation selects Fe/Ru/Cl and dismisses the table.
  Actual Metal mouse events place Fe in empty space, replace Fe with Ru without
  moving its coordinates/camera, add bonded Cl, undo/redo, and finish with
  right-click. Native text editing in Coord rejects `NoSuchElement`, accepts
  ` pt `, applies via the Return-key default action, preserves position,
  clears stale energy and restores the element/energy through Undo.
- `--fragment-placement-smoke-test`: passed popup/previews, first and repeated
  placement, camera-plane depth, zoom visibility, pointer anchoring, orbit,
  Fit, undo, inactive-click behavior and persistent local ChemRefine-tab state.
- `--smooth-smoke-test`: passed selection, 2/3/4-atom labels, draggable labels,
  native coordinate dragging with one commit/undo, camera direction and camera
  preservation. 120 local pointer moves caused zero document publications.
- `--builder-chemistry-smoke-test`: passed the 258 catalog attachment entries,
  legacy bonded-element placement, undo, real UFF convergence/frozen atoms/
  cancellation and the embedded local ChemRefine GUI.

Native logs are in `/private/tmp/chemviewer-atom-native.log` (the final run is
ATOM_EDITING_PASS) and `/private/tmp/chemviewer-093-{placement,smooth,chemistry}.log`.
Local screenshots remain under Downloads, outside the repository. The periodic
cells were visually inspected in the native cache capture; the capture's
transparent SwiftUI background is not evidence of a black application theme.

No new valence model or bond-order editor is claimed. Bond mode uses the
existing terminal H/X attachment rules and least-crowded direction fallback.
Charge/multiplicity are preserved when changing an element. Coordinates use
explicit Apply; calculations are not rerun by changing an element.
