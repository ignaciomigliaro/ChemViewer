# Architecture

## Decision

The Mac application uses SwiftUI/AppKit for system integration and Metal for
rendering. Scientific parsing, models and geometry algorithms live in the shared
ChemCraftCore Swift module. ChemViewerPortable uses that same core to generate
an offline browser viewer on Windows, Linux and macOS. Optional Python helpers
provide chemistry, drawing, plotting, catalog and workflow integration; the
separate reference_parser.py remains an independent validation oracle.

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

## 0.9.0 — fragment builder, UFF and local ChemRefine

Added 258 original generated fragments/metal centers, searchable categories, immediate click-to-attach, current-selection fragments and saved XYZ fragments, all-element click placement, removal of unused X sites, genuine cancellable RDKit UFF with fixed atoms/undo/stale-result protection, and the actual separately installed local ChemRefine GUI embedded in WebKit with seed/config/template export and result import. See [building and local workflows](building-and-local-workflows.md) for usage, scientific limits and evidence. User chose UFF/ChemRefine first; UMA is deferred until model access exists. Local runtime is installed under Application Support/ChemViewer/chemistry-venv. ORCA calculations require configuring an installed executable; GUI bootstrap/validation are tested, not an unavailable ORCA calculation.

## 0.9.1 — free placement, preview gallery and ChemRefine tab

Fragment selection now arms placement on empty space as well as attachment to
atoms. Mouse coordinates are unprojected onto the current camera plane; insertion
preserves framing so the fragment centroid stays at the clicked location. New
molecules have an empty editable canvas. Selected/imported fragments without H/X
can still be placed freely; H/X is required only for attachment.

Command-B and the + toolbar button open a popup gallery with searchable categories
and lazy, cached thumbnails rendered by the native Paton Metal renderer. The
original seven templates are included alongside the 258 fragment/metal entries
(265 choices); the sidebar catalog is removed. Command-Shift-B opens remaining
Build & Edit controls (custom fragments, atoms, transforms, UFF and exports).
Right-click or Finish placement ends placement.

ChemRefine is now a dedicated main tab (Command-6), with its local editor spanning
the workspace and no modal sheet or explorer/edit sidebar. It retains workflow
creation, new workflow, browser opening and result import. Starting a workflow
selects this tab; UFF and the chemistry runtime are unchanged.

Validation: 28 standalone core regressions and three migrated suites passed.
A real packaged Mac test opened the preview popup, rendered organic/metal previews,
placed fragments by actual mouse down/up on an initially empty canvas, repeated
placement after rotation/zoom, checked world and projected click coordinates,
verified unchanged framing, undo and inactive-click safety, and loaded the live
local ChemRefine editor in the dedicated tab. Local evidence stays in Downloads.

The ChemRefine tab retains its WKWebView for the current server session across tab changes. The native acceptance test switches to Image and back, verifies the same web view and JavaScript state survive, and checks the real editor still renders. This preserves unsaved workflow form edits while viewing/building structures.

The final gallery-to-edit-panel regression exposed an intermediate empty-scene update that consumed camera preservation before inserted atoms reached the renderer. Preservation now remains armed until atom data changes, so the first placement after opening/closing editing controls still matches the click. The packaged mouse/projection test passes this sequence. Edit controls also prefer X over H when initializing a fragment attachment site, preserving coordination donor stoichiometry.

## 0.9.2 — builder depth and camera stability (2026-10-20)

Reproduced the reported disappearing fragments: the old empty-canvas unprojection
used Metal NDC Z=0 (the near clip plane), putting the first fragment ~833.37 Å from
the empty scene's origin. Earlier gates checked projected X/Y but missed depth
and raster visibility. Placement now analytically intersects the orthographic ray
with camera-space Z=0. It avoids near-plane placement and inverse-projection
cancellation when zoomed out.

After insertion, the orbit pivot is rebased to the mean atom position with pan
compensation; molecular coordinates and click-screen positions are preserved.
Rotation therefore pivots around the built structure rather than the empty
canvas origin. Scroll zoom is pointer-anchored, uses separate precise-device and
wheel sensitivities, limits per-event jumps and ignores trackpad momentum after
release. Pinch magnification uses the same zoom path. A visible Fit all button is
available in the placement banner. Offscreen preview/export renderers no longer
consume live viewport commands.

The native placement gate now checks reasonable empty-scene world coordinates,
actual nonwhite rendered pixels through four zoom-out steps, restoration and two
zoom-in steps, pointer anchor precision, a large trackpad-delta bound, stable
orbit centroid under mouse dragging, and unchanged geometry. It retains popup,
attachment-site, fit, undo and persistent ChemRefine-tab checks. Local PNGs/logs
are under Downloads and /private/tmp, not committed. No existing geometry files
are automatically repositioned: old assemblies placed at differing zoom levels
may contain unintended relative depth and should be rebuilt or reviewed.

## 0.9.3 — editable elements and periodic-table atom tool (2026-10-20)

Build is now a dedicated dropdown in the native menu bar, in-window menu bar,
and toolbar. Fragment Library (Cmd-B), Add Atom (Cmd-Shift-A), Build & Edit
(Cmd-Shift-B) and Finish Placement are available together. The existing fragment
gallery, thumbnails and camera/zoom behavior remain available.

Add Atom opens all 118 elements arranged as a periodic table, with separate
lanthanide/actinide rows and an X dummy-site button. Choose Replace element or
Add bonded atom, then choose an element. A left click on an atom substitutes its
element without moving coordinates in Replace mode. Bond mode retains the
existing attachment algorithm: use an available terminal H/X site, otherwise
add along a least-crowded direction. Clicking empty space places a single atom
in either mode. The active placement banner lets you switch mode or reopen the
table; right-click finishes. These are starting geometries; no new bond-order
or chemical-valence inference is introduced by this UI.

Coord now provides editable element fields as well as Cartesian coordinates.
Symbols are case-insensitive and atomic numbers are accepted. Apply normalizes
symbols, commits one undoable edit, and invalidates the edited geometry's energy.
Empty or unknown symbols disable Apply and coordinate copying until corrected.
The core BuildingProject replacement operation validates symbols and atom index,
preserving atom order, positions, project groups, selection, charge and spin.

## 0.10.0 — Draw workspace and persistent measurements (2026-10-20)

Measurements are now per-frame pinned atom selections in WorkspaceStore, separate
from active selection. SelectionInspector toggles membership, lists visible
labels, removes each independently and offers Hide all. Right-click deselects
without removing pins. Geometry snapshots include pins; unrelated atom additions
preserve them, topology changes remap surviving unique atom identities by exact
position/element, and Undo restores the prior annotations. Geometry changes
recompute values. Default collisions receive separate normalized label offsets;
all labels remain individually draggable and are rendered in PNG/GIF exports.
The old single-selection renderer API remains for existing tests/export callers.
Pins are session state per geometry, not saved in .cvproject files.

Draw (Cmd-7) sits immediately after ChemRefine and uses the full content area.
MolecularSketch in ChemCraftCore holds explicit atom/bond connectivity, bond
orders, formal charges, wedge/dash direction, tetrahedral/E/Z metadata and
explicit hydrogen/radical information. The native AppKit canvas supports atoms,
bond dragging/connection, 3–8-membered rings/benzene, move/pan/zoom/fit, erase,
charges and one-gesture undo. MolecularDrawingStore retains the draft across tab
changes and keeps an independent 100-entry undo/redo history, JSON save/open,
SMILES import, Clean 2D and optional debounced automatic 3D generation.

The packaged drawing_bridge.py runs in the existing local chemistry runtime.
RDKit sanitizes explicit connectivity, depicts imported structures, adds H,
embeds a deterministic ETKDGv3 conformer and uses UFF where parameterized.
Disconnected components are separated. Wedge/dash and imported E/Z/chirality,
explicit H and radical counts survive round trips. Isotopes are rejected because
the viewer Atom model cannot preserve them. Missing UFF parameters or iteration
limits are explicit in status. This is one starting conformer, not a conformer
search or a quantum-chemistry optimization. No MolDraw code/assets/services are
bundled. The native preview uses the existing Paton Metal renderer.

Generation runs in a cancellable child process with a 45-second limit, private
temporary files and generation/revision guards. Edits cancel stale work and
prevent old results from replacing a newer draft. A stale preview is marked and
cannot be transferred. Use 3D in Viewer transfers the explicit-H geometry and
charge with user-selected multiplicity as an undoable current-frame edit; merely
sketching or generating a preview leaves the viewer document unchanged.

Measurement tracking also spans trajectory frames with the same atom count and
element ordering: enabling/removing a pin updates every compatible frame, and
values are recomputed for the current coordinates. Frames with different atom
ordering/composition keep separate pin sets. The native gate checks two frames
with independently known 2.0/2.3 Å distances and propagates removal to both.

## 0.10.1 — centered captions and native ChemRefine execution (2026-10-20)

AtomCaptionAnnotation uses CoreText glyph-path bounds to center visible text ink
on the projected atom center. It draws directly into the transparent overlay;
the same method serves the viewport, PNG and GIF. This replaces the old +5/+5
pixel offset and avoids ascender/descender padding shifting labels optically.

WorkflowRunner adds native Run ChemRefine, Check workflow, Create missing
templates, Install required backends, Choose ORCA and log/folder controls.
ChemistryRuntime flushes the live Alpine form's pending YAML debounce, saves the
actual input.yaml, then saves an open template editor against that new config.
This ordering supports newly added unsaved steps. Raw YAML remains the source
when raw-edit mode is active. Existing workflows can be opened in the local GUI.

workflow_bridge.py uses the pinned ChemRefine validation/scaffold/provisioning/
agent_tools APIs. Required local input/template/executable/resource-budget
findings block launch. It checks complete ORCA core components, rejects Linux/
Windows binaries on macOS, requires mpirun for parallel ORCA templates and
checks writable output/scratch directories. The configured ORCA directory is
passed through PATH/ORCADIR, with an explicit workflow executable taking priority.
Python backend requirements come from each selected engine's registered
backend_requirement. Missing backends can be installed into ChemRefine-managed
isolated environments; no unrelated MLIP stack is installed. Model checkpoints
and selected MLIP calculators/weights are checked before pipeline launch.
Unavailable access/weights/imports block the run; models produced by an earlier
training step remain deferred to that step's normal runtime contract.

Execution uses ChemRefine's real detached start_run API. The pipeline owns its
lock, scheduling, caches and scientific outputs and survives editor/helper/app
closure. Native monitoring reads actual ChemRefine status/log tails, recognizes
successful, failed/empty and unexpectedly stopped drivers, and can reconnect to
the saved last run after reopening the workflow. Old monitor responses cannot
replace a newer run's status. Setup cancellation terminates its child process
group; cancellation is not offered during the combined Run preflight/launch,
avoiding a race that could conceal an already detached calculation. The native
button runs the full pipeline from step 1; the embedded editor retains its
Resume/recovery actions. ORCA and gated model credentials are not bundled.

## ORCA 6.1 package readiness — 0.10.2

The native workflow bridge accepts either complete helper family beside the
ORCA driver: `orca_startup`/`orca_leanscf` (the supplied 6.1.1 packages) or
`orca_scf`/`orca_gtoint` (older layouts). Helpers must be executable; a partial
family still blocks launch. This is an installation check, not a guarantee that
every optional ORCA module or MPI runtime is available. Missing ChemRefine
`slurm-header` warnings now block local runs too: its local scheduler still
requires the header when generating the job script. Scaffold creates missing
headers without replacing user templates.

## Embedded workflow dashboard — 0.10.3

ChemRefineWebDelegate supplies WKUIDelegate confirmation/alert/prompt sheets and
a scoped WKScriptMessageHandlerWithReply. The document-start workflow_dashboard
resource intercepts local /api/run requests before editor initialization,
then routes action/target to WorkflowRunner.launchFromEditor. This flushes live
YAML/templates and reuses native checks, environment, detached launch and
monitoring. The integration does not modify upstream ChemRefine files.

workflow_summary reads finite Hartree rows from actual steps.csv, joins them to
configured step names and real run/cache states, and reports each step's minimum
plus count/conformer/energy type. Missing data stays null, unsuccessful-cache
results are marked previous, and unit conversion is display-only. The embedded
summary refresh also refreshes the original status table to avoid stale state
after drivers that finish before the editor's first poll. Clipboard output uses
plain tab-separated display values through the native handler.

## User-selected UMA Python — 0.10.4

WorkflowRunner persists an optional UMA interpreter default, resolves typed
environment directories/tilde without resolving executable symlinks, and exposes
a native picker/import checker/explicit apply control. The normal save path
flushes pending per-step inputs and fills only missing FAIRChem backend_python
values; explicit apply replaces the current workflow's FAIRChem overrides.
Non-FAIRChem families and other engines are untouched. Raw YAML is parsed and
re-emitted only if a default needs insertion. The embedded Run panel exposes
per-step MLIP Python fields backed by the real options, not local display state.
The bridge check-python action runs the selected interpreter with subprocess
arguments and reports real imports/version/prefix/server dependencies. No UMA
installation path is hardcoded in application code.

## Skeletal layout and ring catalog — 0.10.5

SketchLayout in ChemCraftCore supplies terminal bond angle selection, atomic
zigzag-chain insertion and explicit SketchRingTemplate elements/bond orders.
MolecularDrawingCanvas keeps chain previews local until mouse-up and commits
one graph edit, reusing drawing Undo/3D generation. Terminal bond drags snap to
120-degree directions (linear for triple bonds), with Option override. The
SwiftUI toolbar renders original vector ring/chain glyphs and a visual ring
popover. Formal charge tools move to More without altering graph semantics.

## Draw preview lifecycle — 0.10.6

MoleculeDrawingStore publishes queued/error/version state. Debounced automatic
generation captures the drawing revision and detaches its completed debounce
Task before run() cancels previous work. Revision/generation guards still
prevent cancelled/stale jobs from replacing new geometry. Empty graphs clear
preview immediately. previewFrame uses a monotonically changing local geometry
ID, ensuring the Metal preview recomputes bounds for same-atom-count changes
without modifying main viewer frame identities or orbit rotation. DrawView
displays queued/running/error states directly in the preview panel, dims stale
geometry and retains its existing current-preview guard for transfer/copy.

## Remote files and workflows — 0.10.7

RemoteConnection owns saved Codable profiles, the remote browser/editor and
cancelable requests. Original remote_bridge.py invokes system OpenSSH with
argument arrays, BatchMode, a private multiplex socket and normal host-key
verification. Interactive authentication is delegated to a generated Terminal
command. The helper is shipped as source and executed in-memory by the selected
remote Python; no service is installed. Explicit non-login Bash setup avoids
another login startup sequence. Python paths may designate environment folders.

Structured JSON carries paths/data separately from shell commands. The fixed
bootstrap and executable are shell-quoted; profile setup is deliberately
user-authored Bash. Transfers verify SHA-256 and atomically replace a cache file
keyed by host/full path, retaining its original basename for parser detection.
Editor saves compare the loaded digest and use atomic replacement; symlinks are
refused for editing. Uploads validate relative names and create an exclusive new
workflow folder. No local executable paths are silently rewritten for a cluster.

remote_agent.py delegates validation/start/status/results to the remote installed
ChemRefine API. Remote launch requires explicit slurm dispatch and available
sbatch/squeue, and blocks missing input/template/executable/header warnings.
The existing local runner retains its local-only restriction. The detached
remote controller survives disconnects and owns the pipeline lock; canceling a
viewer request does not promise cancellation of submitted calculations. Request
and cleanup deadlines bound unresponsive SSH processes; no cluster-wide cancel
or scancel action is exposed.

## Persistent remote channel — 0.10.8

RemoteSSHSession owns one OpenSSH child with persistent stdin/stdout. The fixed
bootstrap enables remote_agent's newline-framed --chemviewer-serve loop inside
Python's argv, not as an argument to the outer Bash command. Directory changes
and workflow operations are serialized RPCs; Python imports/environment setup
remain warm. No additional remote service, port or package is installed.

RemoteConnection invokes the local helper only to prepare the initial SSH
arguments, interactive authentication or an upload manifest. It decodes remote
file contents, checks SHA-256 and atomically replaces its native cache. Session
identity includes host/Python/setup, excludes directory, and changes only when
connection settings change or the channel is explicitly closed/lost. No failed
mutation is automatically replayed. Cancellation closes only the owned channel;
stale replies cannot replace a new session. A 90-second watchdog closes the
child, with bounded termination escalation for that child only.

Pipe reads use POSIX read so short responses return immediately rather than
waiting for a length-sized FileHandle read to fill. A background dispatch queue
keeps stream IO/JSON decoding off the main thread. The helper catches per-request
errors and remains available for later RPCs. Directory listing uses scandir and
entry types rather than stat-ing every entry for file sizes. A bounded cache
keeps listing results for 120 seconds; Refresh bypasses it and mutations clear
it. The Parent button uses the returned parent path for cache reuse.

## Document workspace and persistent explorer — 0.10.9

DocumentTabs owns one WorkspaceStore per source identity (local URL or host/path).
Only the active store is injected into ContentView and commands. Models retain
per-file source/frames, undo/redo, selections, pinned measurements, appearance,
drawing graph and view state. Menu bindings resolve the current store at use
time rather than capturing a closed document. Opening an existing identity
selects it; close guards unsaved geometry/drawing state and explicitly clears
heavy data, including cached drawing results/history. Last-close leaves an empty
workspace. Tab layout/state is not persisted across application quit.

MoleculeMetalView compares document identity and viewport generation before
swapping a shared scene: saves old camera/label placement and restores the new
file's state. New source URLs reset initialization while same-file reload keeps
the view. Captures from an obsolete load generation cannot overwrite a new
file's state. Abstract follows the same file view; Draw has separately versioned
preview state. Dismantled views clear delegate, buffers, pipelines, drawables and
coordinator references; Source text previews clear detached text storage. Loaded
Image tab switches reuse a Metal view/mesh, and inactive playback/trajectory/Draw
workers are suspended. Parsed data/undo remain in RAM until close.

RemoteExplorerView uses lazily fetched tree nodes on the existing persistent RPC
channel. Folder expansion queues while another request owns the channel; cancel/
profile changes invalidate queued or stale updates. Settings/SLURM remain in the
existing sheet; file selection enters DocumentTabs directly. Remote xyzfile inputs
fetch explicit companions through the same session and pass filename→cache URL
mappings to the parser, avoiding source-path rewriting or directory traversal in
cache writes. Source/geometry values are retained; no calculation is executed.

ORCAInputParser lives in ChemCraftCore. It tokenizes quoted filenames/comments,
reads ordinary Cartesian rows/Fortran exponents and explicit charge/spin, converts
inline Bohr using0.529177210903Å and delegates XYZ parsing to the existing reader.
ParsedDocument has optional charge/multiplicity. Unsupported coordinate forms
are source-only or explicitly rejected, never fabricated. Input geometries do
not inherit calculation energies from companion comment lines.

## Explorer loading — 0.10.10

Connection identity invalidation now belongs to RemoteConnection.profile rather
than the settings sheet. RemoteExplorerView uses a cancellable task keyed by
profile/host/Python/setup, waits for busy requests, and loads missing root nodes
once per task. Failed requests keep an explicit manual Browse/Refresh retry;
there is no indefinite reconnect loop. Recursive rows share their root model.
All-file default, Home/Parent navigation and minimum list height avoid hidden
files and collapsed folder contents. Existing persistent SSH/cache is reused.

## Unified remote workflow editor — 0.10.11

LocalWorkflowView is the ChemRefine destination shell, preserving the local
runtime/browser and embedding RemoteWorkflowView for SSH execution. Connection
settings now contain only profiles/authentication/environment/text editing;
submission, status and upload actions moved to ChemRefine. Successful first RPC
on a newly established channel selects SSH mode, without overriding subsequent
explicit local selection on every request. File-menu workflow actions route to
remote path pickers while SSH mode is selected.

RemoteWorkflowRuntime owns a foreground SSH GUI wrapper, an SSH -N loopback-only
forward and a separately cached WKWebView. The wrapper passes an explicit config
to `python -m chemrefine gui --no-browser --port 0`; its stdin EOF terminates only
its own GUI child. Token URLs remain in private temporary logs/browser state,
not console/status/settings. Tunnel/server failure invalidates the editor;
profile identity changes stop its processes. Existing system SSH multiplexing
and host-key checks remain in force. No remote server installation is needed.

Remote folder/file pickers share persistent JSON RPC with the explorer. Creating
from a structure sends inputs to a new exclusive remote directory with SLURM,
relative paths and no Mac executable defaults. Upload retains its dedicated
local chooser by explicit name. Remote web /api/run requests are intercepted
and routed through native save + remote dispatch/scheduler/file preflight for
all supported launch actions/targets. Native Run/Resume follows the same path;
status reads saved results without saving pending drafts. Actual form/template
save runs against the remote GUI API, never the local chemistry runtime.

## SSH forwarding ownership and explorer ordering — 0.10.12

Reproduction demonstrated that a multiplexed `ssh -N -L` can exit0 while the
master still serves HTTP200. Version0.10.11 incorrectly monitored this setup
process as a persistent child and stopped the healthy GUI on its2-second poll.
The bridge now prepares explicit `ssh -O forward` and matching `-O cancel`
commands. Runtime waits for successful setup completion, probes HTTP readiness,
monitors only the owned foreground GUI session and cancels the exact forwarding
binding at stop. It never stops the user's SSH master or submitted jobs.

ExplorerOrder persists Name/Extension selection. Root and recursively expanded
folders share a directory-first comparator, lowercase extension grouping and
localized natural filename ordering. A double-click on the label changes the
root; the disclosure arrow retains tree expansion. Root navigation queues behind
an ongoing shared request with identity/cancellation guards, and keeps folder
caching/persistent RPC. Sorting itself makes no network requests.

## BosTMC catalog and candidate documents — 0.11.0

`BosTMCView` / `BosTMCStore` implement a dedicated native screening workspace,
with a shared source-host catalog, criteria, paginated table, selected-record
Metal preview, and raw descriptor/source inspector. The ordinary geometry sidebar
and navigation-key interception are disabled in this tab. A candidate preview
does not mutate the active molecular document. Opening a candidate uses a
`DocumentTabs` identity suffix derived from dataset settings and CSV row ID:
reopening the same record deduplicates, while distinct spin records remain
independent even when they point at the same XYZ. CSV integral charge and positive
multiplicity are applied after asynchronous parsing under a viewport generation
guard; geometry edits are not overwritten. Provenance is recorded as a document
warning; CSV descriptor energies are not injected into XYZ frame energies.

Original stdlib-only `bostmc_catalog.py` streams CSV into a private SQLite index
on the source host. Fingerprints use CSV absolute path, size and modification
nanoseconds. A background process and file lock serialize index creation; an
atomic rename publishes only complete indexes. Raw source strings coexist with
numeric shadow columns/indexes. Source changes invalidate the fingerprint;
malformed records fail rather than silently shifting descriptors. Optional
source-host cache location supports HPC storage policies. No source files are
modified and no scheduler job is submitted by indexing.

`remote_bridge.py` embeds this resource ahead of `remote_agent.py`; the existing
persistent SSH RPC handles catalog start/status/query/detail/files/export.
Local mode invokes the same resource with JSON request/response files. Generation
checks reject stale query/preview responses after source or selection changes.
Result pages contain at most 200 rows (native default 50); selected XYZ retrieval
uses the existing verified remote-file cache. Filters use bound SQL parameters
and whitelisted columns. Array aggregates parse JSON/Python literals and exclude
known atom/index keys from structured records; ambiguous structures need explicit
dataset validation. Filtered exports stream batches of 500 and retain all raw columns.
Associated Psi4 outputs are displayed as text, not parsed scientific results.

## BosTMC hybrid source and compact catalog — 0.11.1

CSV location and structure-file location are independent. `remote` selects the
catalog transport; `filesRemote` selects structure/output transport for a local
catalog. Local descriptors, statistics, filters and graphs never require SSH.
Embedded XYZ is parsed immediately from the selected CSV record; associated source
lookup is explicit. Filename-based geometries use `bostmc-resolve` with a small
refcode/multiplicity/filename record on the SSH host, requiring no remote CSV or
remote catalog index. The existing persistent transport/checksum cache is reused.

Schema fingerprint v2 stores scalar strings/numeric indexes in a compact candidates
table and source byte offsets/lengths in `payloads`. A binary-line CSV iterator
tracks multiline UTF8/CRLF records correctly. Large XYZ/MOL2/list cells remain in
the read-only source CSV; detail/export reconstruct the complete raw record through
a bounded seek. This avoids duplicating gigabytes of molecular content inside
SQLite pages used for queries. Source fingerprint checks reject a changed CSV.
Existing schema-v1 indexes are retained but not reused by v2.

Import collects finite numeric ranges/counts and categorical options once. Text
indexes use matching NOCASE comparisons; default refcode ordering uses its index.
Histogram requests aggregate 24 bins locally and are cached per source/property.
Graphs always identify the full-catalog population and selected raw descriptor;
orbital α/β levels and dipole components have separate units/plots. A native
Canvas avoids additional plotting or database dependencies. UI labels/grouping
are display metadata; filtering/export keys and raw values are unchanged.

## SSH master recovery without session destruction — 0.11.2

`remote_bridge.control_path` reads a validated per-host `.active` marker inside
the existing private owner-only control directory. Absent a marker, the original
stable socket is used, preserving compatibility. The marker admits only the
host-hash plus a 12-digit random hex suffix; symlinks/path traversal are refused.

Explicit authentication allocates a fresh socket, uses ControlMaster=yes,
ControlPersist=8h, ConnectTimeout=12, ServerAliveInterval=15 and CountMax=2.
A private pending file is atomically published as `.active` only after ssh -fN
success. Failure/cancellation cleans the pending file and leaves the previous
selection unchanged. Old sockets/masters are neither unlinked nor terminated.
Existing editor forwarding cancellation retains its originally prepared arguments.
Normal directory requests continue reusing one persistent helper. No remote action
or submitted calculation is replayed during recovery. The user SSH config is not
modified, and authentication remains exclusively interactive in Terminal.

## 0.12.0 — portable presentation boundary and release gates

The native SwiftUI/AppKit/Metal executable remains a macOS-only target. The
manifest now declares ChemCraftCore and ChemViewerPortable on every supported
host and adds the native executable only on macOS. PortableDocument exports a
versioned JSON presentation model and base64-embedded standalone HTML; source
text enters the DOM through textContent, never HTML interpretation. The Canvas
renderer owns only camera/display state, while shared parsers, source-frame
association, element colors, inferred bonds and XYZ writing remain in the core.
Browser distance uses equilibrium coordinates and has an independent water oracle.
It is a preview interface, not a complete replacement for the native app.

Apple-only simd imports were removed from the scientific/building module. Small
Double-precision VectorMath operations use standard-library SIMD3 and have
Cartesian/right-hand-rule oracles plus the original fragment rigid-transform
regressions. Existing macOS Float coordinate / Double energy boundaries remain.
Explicit app resource lists avoid shipping interpreter-generated bytecode; the
build replaces its generated resource bundle instead of retaining removed assets.

BosTMC type/view names and visible labels are corrected. Existing UserDefaults
keys, cache paths and document identity suffixes intentionally retain their legacy
spelling to preserve installed state and document deduplication. The synthetic
native catalog test now seeds a loaded document before checking that candidates
create independent tabs, avoiding an incorrect assumption about blank-tab reuse.

CI is a single dependency graph with a fail-closed release-gate. Core coverage
uses LLVM line data; Python helper coverage includes branches. Per-module floors
and source inventories must match. Every push, PR and merge-group receives the
checks. Protected main enforces PR/strict status/linear history and blocks force
pushes/deletion. See release-process.md for the exact support and approval policy.

Native packaging correction: all renderer, plotting and remote-helper lookups
now use ChemistryResources.bundle, preferring Contents/Resources. A packaged app
never falls back to SwiftPM's generated absolute development path; an incomplete
app returns missing-resource errors rather than the accessor's fatal trap.
`--resource-smoke-test` validates containment/all assets without starting the GUI.
The relocated ZIP gate also removes one temporary helper and verifies refusal.
This corrects a real crash in the separately downloaded CI app that was hidden
by local build-tree fallback, despite successful signing and compilation.
