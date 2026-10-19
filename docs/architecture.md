# Architecture

## Decision

The long-term implementation is a native Apple Silicon application using
SwiftUI/AppKit for macOS integration and Metal for rendering. Scientific parsing
and models live in a UI-independent Swift module. A small Python implementation
acts only as an independent validation oracle.

This choice favors native file dialogs, Retina rendering, keyboard/window
behavior, ARM64 performance, and a self-contained `.app`. It carries more
up-front rendering work than Qt or Electron but avoids Wine and a bundled browser
runtime. Repairing the official Mac build remains preferable if target-machine
evidence proves it can deliver parity reliably. The official b638m artifacts
were acquired for static inspection. Their strings identify ARM as Free Pascal
3.2.2 and Intel as Free Pascal 3.2.0; both use
Lazarus LCL/Cocoa and TAChart. They have only Apple system dylib/framework load
commands. Without proprietary Pascal source, a durable repair of widget or
application logic is unlikely; target-Mac crash evidence remains necessary
before closing Strategy A.

## Modules

```text
ChemViewerApp (SwiftUI/AppKit; product name `ChemViewer`)
    ├── Data Explorer and inspectors
    ├── document/window state
    └── MolecularMTKView
            └── Metal shaders

ChemCraftCore (platform-neutral Swift)
    ├── molecule/trajectory/mode models
    ├── parser registry
    ├── XYZ parser
    ├── ORCA parser
    └── bond inference

Validation tools (Python stdlib)
    └── independent extraction and corpus assertions
```

## Data model and units

- Cartesian positions and normal-mode displacements: ångström-compatible
  floating-point values as printed by the source file.
- Energies: Hartree in the stored scientific model; UI conversions will be
  explicit rather than destructive.
- Frequencies: cm⁻¹, with negative values retained as imaginary modes.
- Intensities/activities: stored separately because ORCA/Gaussian quantities
  are not interchangeable.
- Frames are immutable values at parser boundaries. UI selection and animation
  state do not modify parsed scientific values.

## Parser contract

Every parser must:

1. Preserve source values and units.
2. Reject malformed mandatory records instead of inventing data.
3. Return warnings for partial optional sections.
4. Be callable off the main thread.
5. Have at least one independently checked fixture before being marked tested.

The registry selects parsers from extension plus bounded content signatures.
Future parsers should implement the same output model, with format-specific
metadata attached through typed extensions rather than UI conditionals.

## Geometry editing

`ChemCraftCore.GeometryEditor` implements value-semantic Cartesian operations
independently of SwiftUI: atom replacement, selected-atom translation, distance
measurement, and bond-length adjustment along the observed bond direction. The
coordinate sheet edits a draft and commits atomically, while `WorkspaceStore`
retains the previous frame for undo. Angle, dihedral, fragment-side selection,
and export remain separate acceptance-tested increments.

## Rendering

The initial renderer uses point-sprite sphere impostors and Metal line bonds.
It already supports rotation, pan, zoom, Retina drawable sizing, animated
normal coordinates, and scaled normal-mode arrows. Planned evolution:

1. Instanced tessellated spheres/cylinders with depth and MSAA.
2. Atom/bond ID picking pass.
3. Periodic cells, labels, vectors, and multiple structures.
4. Marching-cubes compute pipeline for cube/MO/density isosurfaces.
5. Off-screen supersampled image and frame-sequence export.

Large-file parsing and surface construction must use detached tasks with
cancellation and bounded memory. GPU buffers are rebuilt only when the selected
frame, representation, or animation phase requires it.

## Packaging

Swift Package Manager provides repeatable compilation and unit tests.
`scripts/build-macos.sh` builds ARM64, assembles the app bundle, copies resource
bundles, ad-hoc signs for local use, and verifies the result. Release packaging
will add hardened-runtime entitlements, Developer ID signing, notarization, and
stapling after the target Mac is available.

## Command Line Tools validation path

The local packaging script can use the existing scientific assertion cases through an explicit standalone runner when XCTest is absent; CI stays on genuine XCTest. `AppSmokeTest` is opt-in via `--smoke-test` and exercises the live SwiftUI/Metal app. Renderer initialization failures surface as user-visible errors instead of a silent empty viewport. `ParsedDocument.vibrationalFrameIndex` binds frequency vectors to their source geometry; workspace load generations reject stale asynchronous completions and edited geometries cannot animate old normal modes.

## Rendering/UI revision (0.2.0)

The Metal renderer now draws sphere/cylinder meshes with a depth attachment and MSAA, preserves paused phase, and supports PNG readback. Workspace retains exact decoded source text from the same background read used for parsing. SwiftUI exposes five reference-style views, summary navigation, native menus and camera controls. See `rendering-and-ui-2026-10-19.md` for architecture, attribution and limits.

## 0.3.0 energy and geometry workflows

ChemCraftCore owns EnergyUnit/EnergyRecord/XYZCommentEnergy and tested distance/angle transforms. Workspace retains per-frame undo and original source provenance while clearing energy for modified geometry. CalculationAbstractView, SelectionInspector and GeometryNavigationKeys expose the native UI. EnergyLandscapeView serializes explicit Hartree/coordinate data; MatplotlibRunner runs the bundled Python resource off the UI thread in a separate configured environment. See `energy-and-editing-2026-10-19.md`.

## 0.4.0 manipulation and thermochemistry

ChemCraftCore now owns ORCA thermochemistry records, section/frame provenance, complete H−E/G−E sums, symmetric angle rotations, graph fragment membership and rigid axis rotations. Workspace stages drag previews against an immutable base and commits one undo entry on mouse-up. The Metal view converts pointer displacements through the inverse camera transform. ClipboardSupport defaults to the user clipboard for explicit actions and accepts a private pasteboard for tests. Abstract numeric/copy presentation and ManipulationToolbar expose these operations. Details: `thermochemistry-and-manipulation-2026-10-19.md`.

## 0.5.0 local interaction / instanced renderer

Local Metal-view previews now consume pointer events without publishing Workspace geometry changes until mouse-up. Static unit sphere/cylinder buffers are drawn with per-instance transforms/colors; coordinator connectivity is cached until atom data change. Native hit-transparent MeasurementOverlayView draws selected 2/3/4-atom guides/labels, and the same snapshot is composited into exported GPU PNGs. Numeric values reuse GeometryEditor conventions. See `measurements-and-smooth-drag-2026-10-19.md`; earlier per-frame mesh/per-move document descriptions are superseded.

## 0.6.0 appearance and animation export

`MolecularAppearance` supplies the licensed Paton CPK palette. Metal handles native HLS radial gradients and fog. `MolecularMTKView.encodeMolecule` is shared by live drawable and independent offscreen MSAA/depth rendering. `AnimationExportView` snapshots the active camera and scientific frame/mode data; `AnimationExporter` fixes bounds across the animation, and the serial `GIFWriter` actor uses ImageIO with atomic final replacement. See [implementation and limits](paton-and-gif-2026-10-19.md).

## 0.6.1 — uniform shading by distance

At the user’s request, depth fog is disabled for both atoms and bonds. The shared native render path now sends zero fog weight, so farther objects retain the same element colors and surface gradient as nearer objects. This applies to the viewport, PNGs and GIFs. Paton palette, outlines and radial shading remain. Verify by rotating a deep structure and comparing near/far atoms of the same element. This supersedes the 0.6.0 depth-fog behavior.

0.6.2: Offscreen `renderAnimationFrame` optionally composites `MeasurementAnnotation` in an AppKit-compatible bitmap context. Projection uses the offscreen camera and output dimensions; numeric labels use the precise sample positions. `AnimationExporter` validates selected indices/trajectory identity layout and scales ImageIO delays by playback speed. The dialog defaults to half speed.

## 0.7.0 unified builder and classic shell

See [the migration architecture and reconciliation](moleculeview-integration-2026-10-19.md). Core IntegratedBuilding namespaces the original algorithms; BuildingProject bridges project JSON and core atoms. Workspace snapshots now include groups/selections and support topology changes and redo. The newer ORCA energy/thermochemistry parser remains authoritative; the original parser supplements earlier per-frame modes and printed facts and provides Gaussian geometry fallback. SwiftUI classic controls and optional BuilderPanel retain the instanced Metal view. Source excerpts preserve original text and recenter for source links.

## 0.7.1 — left explorer restored by default

The geometry/frequency Result Explorer is visible on the left at startup again, as requested. Its geometry selection, per-frame frequency selection and arrow navigation are retained; View → Result Explorer or the sidebar toolbar button still toggles it. The optional right-hand builder remains available with +/Cmd-B. This supersedes 0.7.0’s initially hidden explorer. Verify by opening a multi-geometry ORCA output and browsing geometries and modes from the left panel.

## 0.7.2 — optional frequency vectors

Frequency displacement vectors default to off. The toolbar Vectors checkbox, native Display → Displacement Vectors menu, and classic in-window Display → Frequency Vectors menu share the same toggle. Select a normal mode and toggle vectors without changing animation or coordinates.

## 0.7.3 — stable view while selecting atoms

A native regression reproduced selection resizing the 3D canvas: the bottom inspector was inserted/removed and had variable height for 1/2/3/4 selections, changing projection and apparent molecule position without a camera reset. The inspector now has a stable 140-point scrollable area, with an empty-selection hint. Its content can scroll horizontally in narrow split/builder layouts without changing the canvas. The status row also has a fixed height. Separately, camera dragging now waits for movement over 3 points; small click jitter does not rotate/pan. Atom manipulation retains its existing 1-point activation threshold. Selection colors and measurement edits remain functional.

The native smooth regression now exercises a real click with subpixel movement, then 1/2/3/4 selections and clearing, and verifies viewport object identity, bounds, camera rotation and all projected atom positions in window coordinates (0.05-point tolerance). This supplements the existing local atom-drag/undo, guide/PNG and mouse-camera direction checks.

## 0.7.4 — draggable measurement labels

Enable Show bond length/angle/dihedral, then drag the white numeric label box to move it away from the structure. The hand cursor identifies the draggable area. Only the label receives those drag events; clicks outside it continue to select atoms or rotate/drag the molecule, and right-click still clears selection. The numeric measurement and its atom guides remain tied to the selected atoms. Reset label restores automatic placement.

Offsets are stored locally per geometry and ordered atom selection, as fractions of viewport width/height. Reselecting the same measurement restores its placement during the current view session. PNG capture uses the live placement; the independent GIF renderer copies the offset map and applies the same normalized offset at its output resolution while recomputing each frame's value. Export still fits all frames once, so absolute pixel placement can differ with aspect ratio/framing. Labels stay inside image bounds. New file/view sessions and atom-count changes clear positions; working project files do not serialize label positions. Dragging a label does not change coordinates, selection, animation or camera and does not add geometry undo entries.

Native regression coverage uses mouse handlers on 2/3/4-atom label boxes, verifies 70×30-point label motion, pass-through away from the box, unchanged numeric values/geometry/camera, retained placement on reselection, PNG exports, offset preservation through both GIF renderer copies, an actual moved-dihedral GIF, reset, and prior smooth camera/selection/drag checks. Scientific core tests remain unchanged. Manual pointer feel and all output sizes still require user acceptance.

## 0.7.5 — macOS application icon

The app now ships an original generated blue/teal molecular icon instead of the generic application placeholder. Packaging/ChemViewerIcon.png is the transparent master; scripts/build-icon.sh creates all ten standard/Retina PNG slots (16–1024 physical pixels) and Packaging/ChemViewer.icns. The macOS build copies the ICNS into Contents/Resources, and CFBundleIconFile references it before code signing. This is app identity artwork, not a chemically interpreted structure. Verify the installed icon in Finder and the Dock after relaunch; macOS may cache an older icon on a running app. No scientific/rendering behavior changes.

## 0.8.0 — detected NEB reaction profiles and optional markers

The energy sheet now auto-selects a complete ORCA NEB/NEB-TS path-summary dataset, separate from Cartesian optimization history. It defaults to a reactant/refined-TS/product diagram; all images and ordinary PES lines are also selectable. Forward/reverse barriers use the explicit refined TS and printed relative energies, not the highest CI or rounded-Hartree subtraction. Structures are taken only from validated optional companion files. All scatter markers can be turned off. PDF/SVG/PNG/CSV/JSON exports include provenance. See docs/neb-reaction-profiles-2026-10-19.md for scientific semantics, implementation, tests and limitations.

## 0.8.1 — transparent GIFs and box-free atom captions

GIF export now defaults to **Transparent background**; clear that checkbox for the previous white background. Atom-number, element and combined captions have no painted background in the viewport, PNGs or GIFs. Transparent GIF measurement text also omits its white box, while its numeric value, guide lines and moved placement are retained. The live draggable measurement-label box remains for normal viewing. Camera angle, scientific coordinates, playback speed and label offsets are unchanged.

The independent Metal export targets clear to RGBA zero and preserve alpha through readback. MSAA coverage colors are unpremultiplied in linear space to avoid dark fringes. Caption/measurement compositing clears its bitmap before drawing. GIF supports binary transparency, not partial opacity; export thresholds coverage at 50 percent, retaining opaque white atoms rather than color-keying white. Subtle semitransparent guide planes cannot retain fractional opacity in GIF.

GIFWriter now uses ImageIO to quantize each independent frame, then streams GIF89a image blocks with local palettes, an infinite-loop extension, explicit delay and disposal-to-background (method 2). Independent full-image frames prevent the differential-frame/disposal interaction that otherwise causes stale atom trails or disappearing stationary atoms. No Python installation is required for export. Existing temp-file cancellation and atomic final replacement remain.

Validation: 25 standalone core cases and the three integrated suites passed during the signed arm64 build. Expanded native animation tests verify transparent corners, frame-by-frame masks against independently rendered alpha images, preserved white atoms, an opaque-white option, all three caption modes with zero white-background pixels, timing/loops/cancellation/measurements and unchanged document/camera. Independent Pillow compositing checked all 12 frequency frames at every pixel: disposal 2, no trails or missing opaque atoms, and no caption boxes. The smooth/label-placement workflow is also checked. Evidence is outside the repository in Downloads/chemviewer-transparent-work.

### ORCA XYZ trajectory comments (0.8.2)
`XYZCommentEnergy` recognizes the complete `Coordinates from ORCA-job <name> E <number>` comment separately from generic named fields. This format produces Hartree records and frame energies while preserving original comments and source lines. Generic whitespace-separated `E` comments are not assigned units.

## GitHub Swift 6.1 compatibility fix
Actions run 39299377644 failed while type-checking `ManipulationToolbar.scopeIcon` on Xcode 16.4 / Swift 6.1.2 ARM64. Local Swift 6.3.3 had accepted the same Canvas expression. Extracted drawing into a typed GraphicsContext helper, separated trigonometric/CGFloat arithmetic, and replaced nested ternaries with a scope switch. Icon geometry and colors are unchanged. Local debug build passes; remote CI will verify the actual older toolchain.
