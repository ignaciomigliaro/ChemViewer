# Measurement overlays and smooth interaction — 0.5.0

## User-visible changes

With exactly two, three or four atoms selected, the selection panel offers
Show bond length / Show angle / Show dihedral. This enables an on-molecule
annotation: dashed measurement guides, a numeric label, and for dihedrals two
illustrative planes. The signed dihedral also has an explicit numeric panel
readout and Copy value action. Selection order defines A–B–C–D; B is the angle
vertex and B–C is the dihedral axis. Degenerate dihedrals stay undefined rather
than displaying an invented angle. The overlay is off initially and clears
when there is no applicable selection. Its preference persists during the session.

Native overlays follow camera transforms, resize and local drag previews, and
are included in PNG export. They measure the actual displayed atom positions,
including a mode's instantaneous displacement if animation is enabled. Existing
editor values continue to refer to stored coordinates; the panel states this
distinction. Overlay drawing never changes the scientific geometry.

The user clarified that inversion affected mouse-driven view rotation. The
horizontal yaw sign is corrected so dragging a visible front point to the
right moves it right. Upward dragging moves it upward. Camera left/right rail
buttons are aligned with that visual convention. Scientific coordinate-axis
rotation math and the ±X/Y/Z geometry buttons retain the existing right-hand
Cartesian convention; they were not the controls the user identified.

## Drag/rendering architecture

Previously every pointer update published a new full document and geometry
revision, reran view/layout/inspector work, and reinferred bonds. Each draw also
rebuilt all sphere/cylinder triangles on the CPU and uploaded expanded vertex
arrays. These were confirmed source-level hot paths, not an assumed GPU defect.

A gesture now freezes group membership and keeps pointer preview positions in
the Metal view. It draws at the display's supported refresh rate (up to the
requested 120 Hz) while dragging, without publishing document edits. Mouse-up
commits the final displacement once, using the existing energy invalidation
and one-step Undo logic. Disabling dragging, clearing selection or changing
geometry cancels the local preview appropriately. Camera transforms remain
stable throughout a coordinate drag.

Each viewport creates one unit sphere mesh and one unit cylinder mesh once.
Draw calls instance those meshes using compact position/basis/color data.
The GPU performs the per-instance transformations. Selected-atom membership is
a Set; inferred bonds are cached by the SwiftUI coordinator until atom data
change. Bonds remain fixed during a local preview and are inferred again on
commit, preserving the previous post-edit connectivity behavior.

The on-molecule measurement view ignores hit testing. PNG export composites the
same annotation snapshot over the same GPU frame, at drawable pixel resolution.
No screenshot of another application is used for image export.

## Measurements and test evidence

A local packaged-app benchmark used the same independently generated 500-carbon
grid, 25 explicit draw requests, five warmup samples omitted, and pauses between
samples. Both versions reported 26 completed GPU frames (including initial
presentation), so the timing reduction did not result from skipped drawing.

| CPU draw-submission wall time | Previous renderer | Final 0.5.0 run |
|---|---:|---:|
| Median | 17.0457 ms | 1.1681 ms |
| 95th percentile | 17.7615 ms | 1.3203 ms |

An earlier optimized run measured 0.7299 ms median. These are local CPU draw-call
measurements, not guaranteed frame rates or photon/input-latency measurements.
Background/display scheduling varies. Very large-system performance and human
trackpad feel still need broader evaluation.

The new packaged smooth-interaction check passed numeric distance 1.54000 Å,
angle 120.000°, signed dihedral 116.565°, all overlay toggles, annotated PNG
exports, exact screen-pointer tracking, one mouse-up commit/Undo, and one mesh
build per view. It sent 120 pointer-move handler events with zero document
publications; the final loop took 0.1158 ms total for that small fixture. This
isolates event-processing work and does not claim real-world mouse latency.
The camera check verifies horizontal and vertical grab direction independently,
while ensuring the stored geometry remains unchanged.

Nineteen existing standalone scientific core cases and all four packaged
workflows (render/GPU, energy/Matplotlib, manipulation, smooth interaction) passed.
No core algorithm changed in this revision. Actual XCTest remains unavailable
under this Mac's Command Line Tools, as previously documented. Pointer-handler
and image evidence are local automated checks, not exhaustive manual acceptance.

Local evidence is under `/Users/nacho/Downloads/chemviewer-smooth-work`: benchmark
logs, workflow logs, and `evidence/{distance,angle,dihedral}.png` plus actual
window captures. The final exported images and four-atom UI were visually
inspected; fixtures are independently generated.

```
bash scripts/build-macos.sh
dist/ChemViewer.app/Contents/MacOS/ChemViewer -ApplePersistenceIgnoreState YES --smooth-smoke-test --capture-window --smooth-evidence /Users/nacho/Downloads/chemviewer-smooth-work/evidence
dist/ChemViewer.app/Contents/MacOS/ChemViewer -ApplePersistenceIgnoreState YES --render-benchmark
```

Earlier documentation describing per-frame triangle rebuilding or per-move
published drag previews is historical and superseded by this implementation.
Fragment construction/manual bonds and the broader feature-parity limits remain
unchanged. Clipboard integration checks continue to use a private pasteboard.

## 0.7.3 — stable view while selecting atoms

A native regression reproduced selection resizing the 3D canvas: the bottom inspector was inserted/removed and had variable height for 1/2/3/4 selections, changing projection and apparent molecule position without a camera reset. The inspector now has a stable 140-point scrollable area, with an empty-selection hint. Its content can scroll horizontally in narrow split/builder layouts without changing the canvas. The status row also has a fixed height. Separately, camera dragging now waits for movement over 3 points; small click jitter does not rotate/pan. Atom manipulation retains its existing 1-point activation threshold. Selection colors and measurement edits remain functional.

The native smooth regression now exercises a real click with subpixel movement, then 1/2/3/4 selections and clearing, and verifies viewport object identity, bounds, camera rotation and all projected atom positions in window coordinates (0.05-point tolerance). This supplements the existing local atom-drag/undo, guide/PNG and mouse-camera direction checks.

0.7.3 validation: before-fix native regression failed with “Selection resized the 3D canvas”. After the fix, the extended smooth/selection, energy/editing and manipulation workflows passed; 23 standalone core cases and three migrated suites also passed. Signed arm64 app installed at ~/Applications/ChemViewer.app. Evidence: Downloads/chemviewer-selection-work. Physical human input feel remains for user confirmation; the programmatic mouse/jitter and screen-projection checks passed.

## 0.7.4 — draggable measurement labels

Enable Show bond length/angle/dihedral, then drag the white numeric label box to move it away from the structure. The hand cursor identifies the draggable area. Only the label receives those drag events; clicks outside it continue to select atoms or rotate/drag the molecule, and right-click still clears selection. The numeric measurement and its atom guides remain tied to the selected atoms. Reset label restores automatic placement.

Offsets are stored locally per geometry and ordered atom selection, as fractions of viewport width/height. Reselecting the same measurement restores its placement during the current view session. PNG capture uses the live placement; the independent GIF renderer copies the offset map and applies the same normalized offset at its output resolution while recomputing each frame's value. Export still fits all frames once, so absolute pixel placement can differ with aspect ratio/framing. Labels stay inside image bounds. New file/view sessions and atom-count changes clear positions; working project files do not serialize label positions. Dragging a label does not change coordinates, selection, animation or camera and does not add geometry undo entries.

Native regression coverage uses mouse handlers on 2/3/4-atom label boxes, verifies 70×30-point label motion, pass-through away from the box, unchanged numeric values/geometry/camera, retained placement on reselection, PNG exports, offset preservation through both GIF renderer copies, an actual moved-dihedral GIF, reset, and prior smooth camera/selection/drag checks. Scientific core tests remain unchanged. Manual pointer feel and all output sizes still require user acceptance.

0.7.4 final validation: 23 standalone core cases and three migrated suites passed. Expanded native smooth/label-drag, annotation/GIF and manipulation workflows passed. Moved-label PNGs were visually inspected; actual moved-dihedral GIF exported and reopened. Signed arm64 app installed at ~/Applications/ChemViewer.app. Evidence: Downloads/chemviewer-label-placement-work. Relaunch existing windows to use the update. The user’s TS.inp and calculation files were not edited.
