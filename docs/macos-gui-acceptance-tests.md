# ChemViewer macOS GUI acceptance tests

These tests translate observed Windows reference behavior into release gates
for the independent macOS app. Automated core tests may establish scientific
values, but interactive rows require an actual Apple Silicon GUI run.

## Required Apple Silicon matrix

Record Mac model, macOS version, Xcode/Swift version, display scale, build SHA,
and whether the app came from a local build or GitHub artifact. Test at Retina
scale and, when available, an external display.

| ID | Expected ChemViewer behavior | Fixture | Acceptance criterion | Current state |
|---|---|---|---|---|
| CV-GUI-001 | Launch native app and show empty workspace | none | arm64 executable; no crash; responsive window | Pending Mac |
| CV-GUI-002 | Open from toolbar, Cmd+O, Finder, and drag/drop | `water.xyz` | all routes produce the same 3 atoms; cancel is harmless | Partial source; drag/drop pending |
| CV-GUI-003 | Render atoms/bonds at Retina resolution | `methane.xyz` | correct 5 atoms/4 bonds; no clipping or blurry scaling | Pending Mac |
| CV-GUI-004 | Rotate with drag and right-drag; pan with Option-drag; wheel zoom | `methane.xyz` | each gesture changes only intended camera state; right-drag matches Windows rotation | Implemented; pending Mac |
| CV-GUI-005 | Select one to four atoms with click plus Shift/Cmd-click | `water.xyz`, `dihedral.xyz` | selection highlight and ordered identities are stable | Implemented; pending Mac |
| CV-GUI-006 | Display distance, angle, and signed dihedral | same | 0.95720 A, 104.520 degrees, 116.565 degrees within 1e-5/1e-3/1e-3 | Core implemented; Swift/GUI pending |
| CV-GUI-007 | Edit Cartesian coordinates and undo | `water.xyz` | committed coordinate changes geometry; undo restores exact values | Partial source; pending Mac |
| CV-GUI-008 | Browse a multi-frame trajectory and play/pause | deterministic multi-XYZ plus ORCA optimization | frame count/order exact; 0.5 s playback cycles without UI blocking | Implemented; pending Mac |
| CV-GUI-009 | Parse ORCA compound optimization/frequency | authorized hashed reference file | final energy -76.360968646 Eh; 9 modes; key frequencies exact within 0.01 cm^-1 | Oracle pass; Swift/Mac pending |
| CV-GUI-010 | Animate the 1606.12 cm^-1 normal mode | ORCA reference | continuous symmetric motion; pause freezes; amplitude changes display only | Source implemented; pending Mac |
| CV-GUI-011 | Mark and animate imaginary mode | clean-room negative-mode fixture | negative value remains negative/red; no real-frequency reinterpretation | Unit source exists; real OptTS fixture needed |
| CV-GUI-012 | Toggle displacement arrows | mode fixture | arrow origin/direction follows source vectors; toggle never crashes | Source implemented; pending Mac |
| CV-GUI-013 | Show IR sticks and broadened curves | ORCA reference | source positions/intensities preserved; Gaussian/Lorentzian HWHM semantics pass | Core implemented; pending Mac |
| CV-GUI-014 | Open/save structure | `water.xyz` | exported XYZ reparses with identical symbols/coordinates | Save not implemented |
| CV-GUI-015 | Export image | `water.xyz` | requested pixel size, background, and antialiasing are deterministic | Not implemented |
| CV-GUI-016 | Load MO/density grid and render signed isosurfaces | clean-room cube/fchk fixture | grid dimensions/units exact; +/- lobes and isovalue controls visible | Not implemented |
| CV-GUI-017 | IRC/PES/NEB navigation and energy plot | licensed-to-use redistributable fixtures | frame order, reaction coordinate, absolute/relative energy and barriers match oracle | Not implemented |
| CV-GUI-018 | Large-system responsiveness | generated 10k and 100k atom cases | no main-thread parsing stall; documented memory/frame-time limits | Pending |

## Procedure and evidence

For every interactive case:

1. Record input path and SHA-256.
2. Start from a new app launch and document all clicks/shortcuts.
3. Capture before/after screenshots and app/system logs.
4. Record displayed and parsed numeric values separately.
5. Repeat once after relaunch and once from the packaged `.app`.
6. Mark pass only when both scientific and interaction criteria pass.

GitHub Actions on `macos-15` can compile and execute Swift unit tests natively
on Apple Silicon and produce an ad-hoc-signed artifact. It cannot validate
human-visible Metal output or normal macOS interaction; those rows remain
pending until observed on the physical Mac.

## Automated local evidence (2026-10-19)

The packaged `--smoke-test` passed in a real local SwiftUI window with live Metal frame completion. This supplies partial automated evidence for CV-GUI-001/002/003/005/007/011/012: programmatic file opening, actual shader/pipeline loading, selection propagation, coordinate undo and negative-mode animation/pause were exercised. It does not mark native dialog clicking, Finder routing, visual/vector agreement, Retina appearance, or gestures passed. Native parsing separately passed the CV-GUI-009 numeric reference; GUI labels still need inspection. See `mac-validation-2026-10-19.md`.

## 0.2.0 visual checks

The five tabs were activated in a real packaged window and their screenshots inspected. CV-GUI-003 now also has GPU evidence for depth-order independence, shader loading and PNG capture; CV-GUI-015 has a successful current-resolution PNG path (save-dialog interaction and configurable export size remain pending). Check Cmd+1…5, coordinate Apply/Undo, split-pane fitting, all display styles, camera rail, and File → Export Image as PNG manually. Full pointer/gesture acceptance remains open. Details: `rendering-and-ui-2026-10-19.md`.

## 0.3.0 added acceptance procedures

On multi-XYZ, verify Abstract energy rows, selected structure, arrow browsing and explorer scrolling. Choose the unit for unlabelled comment energies. Left-click at least five atoms without modifiers, toggle one off, and Clear. Select two atoms, apply each distance mode and verify the fixed atom/midpoint; Undo. Select three atoms and edit A–B–C angle; verify B is the vertex and both adjacent distances are unchanged. Navigate away/back and Undo. Plot energy versus geometry index, selected distance and selected angle; change units/reference, update, and export all files. On ORCA, follow SCF and final-energy source links to exact highlighted lines. Local packaged routing/rendering checks and synthetic screenshots passed; manual hardware/dialog acceptance remains pending. Details: `energy-and-editing-2026-10-19.md`.

## 0.4.0 added procedures

Right-click must clear all atoms without rotating. Select A/B/C and test C-only versus symmetric A/C angle edits about B. Enable hand/Atom and drag one atom, then Undo once; only that atom changes. Select a bonded A/B pair, choose Fragment, check B-side highlighting, drag/rotate with attachment pivot and verify outside atoms stay fixed. Test each ±axis button and whole-geometry dragging. In Abstract copy numeric E/H/G and sums, verify the chosen electronic base, and expand details only when needed. In Coord copy pending edits as TSV and XYZ. Automated mouse-handler/clipboard/visual checks passed with synthetic fixtures; full human pointer/trackpad/button acceptance remains pending. See `thermochemistry-and-manipulation-2026-10-19.md`.

## 0.5.0 added procedures

Select 2/3/4 atoms and toggle the corresponding measurement overlay; inspect the guide, label, signed dihedral and annotated PNG. Clear selection and confirm guides disappear. Drag each manipulation scope and confirm the molecule tracks the pointer continuously, final coordinates match the preview and one Undo restores it. With dragging disabled, pull a front atom right/up and confirm the view follows right/up; coordinates must remain unchanged. Packaged pointer-handler, overlay, GPU and PNG checks pass locally; manual trackpad feel and broad large-molecule testing remain pending. Details: `measurements-and-smooth-drag-2026-10-19.md`.

## 0.6.0 added procedures

Confirm a fresh app defaults to xyzrender · Paton and change all five styles. Open multi-XYZ, rotate to a recognizable non-default angle, export a looping GIF with and without forward/backward playback; inspect playback externally and confirm its angle matches. Repeat for an ORCA frequency at a visibly nonzero amplitude. Check dimensions/speed, cancellation, replacing an existing GIF, and no changes to the viewer camera/geometry. Test entry from each tab. Export fits the full animation once and does not preserve zoom/pan; this is intentional and must be clear in the sheet. Programmatic checks do not replace these human acceptance steps. See paton-and-gif-2026-10-19.md.

## 0.6.1 — uniform shading by distance

At the user’s request, depth fog is disabled for both atoms and bonds. The shared native render path now sends zero fog weight, so farther objects retain the same element colors and surface gradient as nearer objects. This applies to the viewport, PNGs and GIFs. Paton palette, outlines and radial shading remain. Verify by rotating a deep structure and comparing near/far atoms of the same element. This supersedes the 0.6.0 depth-fog behavior.

## 0.6.2 — measurement labels and slower GIFs

Select 2 atoms for length, 3 for angle (B is the vertex in A→B→C), or 4 for a signed dihedral, in order. Choose File → Export Animation as GIF… and enable **Include measurement label and guides**. The current ordered selection supplies one measurement per GIF. Its numeric value and projected guides are recomputed from each frame's actual coordinates, including sinusoidal frequency displacements. Labels use Å or degrees, retain the viewer’s angle, and use the same guide/dihedral-plane drawing as the native view. The toggle starts enabled when the viewer’s measurement overlay was enabled. Labels require stable atom ordering and matching element sequences across trajectory frames. If a selected angle/dihedral is undefined in a frame, export reports an error rather than writing a misleading value; temporary output is removed and any existing destination remains intact.

Playback speed offers Normal, Half, Quarter and Eighth; Half is the new dialog default. Frame-rate choices now include 1 and 2 fps. Every frame is retained; GIF delay is `1 / (fps × speed)`, with an approximate loop duration shown. GIF centisecond quantization/player behavior may slightly change actual timing. These choices apply to both trajectories and frequencies. Display speed remains illustrative, not physical vibrational time. Coordinates, amplitude and camera orientation are unchanged.

## 0.7.0 merged-app procedures

Inspect the in-window File/Edit/View/Display/Tools/Compute/Help strip, classic tabs/toolbar/footer and white canvas. Open +/Cmd-B, build methane and attach methyl to a terminal H; confirm 8-atom ethane, selected inserted fragment and 1.52 Å C–C distance. Undo/Redo and inspect restored groups and selection. Import an XYZ fragment with X site; attach/remove dummies, duplicate/delete/insert/replace, numeric ordered selection and connected/imported-group selection. Set a bonded pair as axis, select a fragment and rotate/translate; verify outside atoms remain fixed. Save/reopen .cvproject and legacy .mvproject and check atoms/groups/selection/charge/multiplicity. Export XYZ/ORCA and reject unresolved dummy sites. Test H hiding and all captions in viewer/PNG/GIF, camera roll/pan and GIF angle. Open Gaussian geometry, compound-job ORCA modes/facts and verify source jumps. Repeat all earlier energy, plotting, drag, measurement and GIF workflows. Human ergonomic/trackpad and broad file coverage remain pending regardless of native programmatic checks.

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

### 0.8.2 ORCA XYZ energy regression
Open an ORCA XYZ trajectory whose comments use `Coordinates from ORCA-job <name> E <value>`. Confirm each geometry has its Hartree energy and the energy plot includes all frames. The reported 12-frame file passed a full parser-to-frame comparison against independently extracted comment values. Release build: 26 standalone core regression cases and three migrated suites passed; XCTest is unavailable in CLT.

Packaged native energy-workflow smoke test passed: multi-XYZ energies, Abstract/source links, editing/undo and energy invalidation, packaged Matplotlib exports and plot sheet. Installed signed v0.8.2 in `/Users/nacho/Applications/ChemViewer.app`.

## GitHub Swift 6.1 compatibility fix
Actions run 39299377644 failed while type-checking `ManipulationToolbar.scopeIcon` on Xcode 16.4 / Swift 6.1.2 ARM64. Local Swift 6.3.3 had accepted the same Canvas expression. Extracted drawing into a typed GraphicsContext helper, separated trigonometric/CGFloat arithmetic, and replaced nested ternaries with a scope switch. Icon geometry and colors are unchanged. Local debug build passes; remote CI will verify the actual older toolchain.

Follow-up run 39306699269 passed Swift compilation/tests and then exposed a separate Matplotlib source-build failure in bundled FreeType. CI now explicitly selects Python 3.12 with setup-python and requires binary wheels for plotting dependencies. This avoids reliance on the runner default Python and native source compilation.

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

Free placement preserves camera framing until explicitly requested otherwise. Fit and Center / Front View now recalculate geometry bounds, so freely placed fragments can be centered/fitted afterward. The final packaged native test verifies projected coordinates before fit and centered coordinates after fit, plus workflow DOM-state retention across tab changes.

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

## CV-GUI-ATOM — periodic table and editable coordinate elements (0.9.3)

1. Build → Add Atom (Cmd-Shift-A): verify all 118 buttons and the f-block rows.
   Cancel must leave the document unchanged.
2. Choose Fe and click empty space: exactly one atom appears. Select Ru in
   Replace mode and click Fe: atom count and coordinates stay fixed. Undo/Redo
   restores Fe/Ru, and the camera does not change.
3. Switch to Add bonded atom, choose Cl, click Ru: Ru stays and a bonded Cl is
   inserted at a finite covalent distance. Undo removes this edit. Right-click
   finishes and subsequent clicks return to selection.
4. Coord: type an invalid element; Apply and both copy buttons are disabled.
   Type ` pt ` (or atomic number 78), Apply: Pt replaces the element without
   moving any coordinate. Undo restores the original element and source energy.
5. Build → Fragment Library and + still open the preview gallery; placement,
   fit/zoom/orbit and edit controls remain functional.

Automated native gate: launch a separate dist app with fixture water.xyz and
`--atom-editing-smoke-test -ApplePersistenceIgnoreState YES`. It activates the
actual NSButton periodic cells, sends mouse events to the live Metal viewport,
and types into the actual Coordinates NSTextField before invoking the default
Apply action with Return.

## CV-GUI-DRAW-LABELS — persistent measurements and 2D builder (0.10.0)

1. Select two atoms, enable Show bond length, right-click. Select another pair,
   enable its label, right-click: both labels stay visible. Repeat for angle
   and dihedral. Drag each label independently; default rectangles should not
   conceal one another. Remove one using the Visible labels row; others remain.
2. Edit geometry: label values recompute. Append an unrelated atom: labels
   survive. Undo restores annotations with geometry. Switch Abstract/Image and
   verify pins remain. PNG and GIF can include every pinned label.
3. Draw (beside ChemRefine, Cmd-7): click a C start, drag to extend C, select O
   and drag the second C to O. The explicit graph is ethanol. Try move, erase,
   charges, bond orders, rings, Undo and Redo.
4. Generate 3D (or enable Auto 3D preview): verify formula C2H6O, nine explicit-H
   atoms and an interactive Metal 3D view. The original viewer document remains
   unchanged until Use 3D in Viewer. Applying and undoing restores the original.
5. Change O to N: automatic generation must give the current C2H7N result.
   Immediately cancel another generation: no orphan/stale result is applied.
6. Import chiral SMILES `N[C@@H](C)C(=O)O`, generate 3D, verify chirality remains.
   Draw periodic table must set the drawing element without arming the viewer's
   separate placement tool. Benzene ring → 3D must give C6H6.
7. Switch tabs and return: draft and preview remain. Save/open drawing JSON,
   Clean 2D, Copy SMILES/XYZ. Invalid valence produces a visible error and keeps
   the current viewer structure; stale previews cannot be accepted.

Native automated gate: `--drawing-labels-smoke-test` with an independently
launched dist app and fixture water.xyz. It exercises live mouse events, child
processes, GPU completion, per-label manipulation, GIF generation and tab state.
Manual saved-drawing dialog and general visual-fidelity checks remain separate.

## CV-GUI-RUNNER — centered captions and local ChemRefine execution (0.10.1)

1. Enable atom numbers/elements/element+number captions. Check labels are centered
   within spheres at rotated views, in PNG and in transparent GIF.
2. ChemRefine → Create or Open workflow. Check workflow must save the current form
   (including pending text debounce) and show blocking missing files/executables.
3. Create missing templates must preserve existing files. Choose ORCA selects
   an installed executable; Get ORCA opens the official installer instructions.
   A partial ORCA package and missing parallel MPI must be reported before jobs.
4. Install required backends must install only missing selected engine extras.
   Missing/gated model weights must block launching pipeline jobs.
5. Edit an existing step and add a new step with an unsaved template. Run must
   save the latest YAML first, then the new template, and execute both steps.
6. Observe the real log and result tree. Closing the editor server must not stop
   the detached calculation. Successful status requires cached survivor results,
   not merely an exited process. Failed/empty steps must not report success.
7. Reopen the workflow after restarting the app: monitor the saved run rather
   than rerunning it. Use the embedded Resume action for cache-aware recovery.

Native automated gate: `--workflow-runner-smoke-test` with water.xyz and
`-ChemViewerLastRunConfig ""` to isolate test startup from a user's saved run.
It tests actual glyph pixels, saved unsaved form/template content, backend
readiness, two real H2 PySCF steps, editor-server shutdown, native status and the
independent conventional HF/STO-3G (no density fitting) -1.1167593074 Eh oracle.
The test requires the isolated pyscf backend; it does not pretend ORCA is present.

## Remote connections — 0.10.7

- CV-REMOTE-001: File → Remote files & SLURM; save/select profiles; authenticate
  interactively in Terminal; check environment; browse folders; choose a known
  XYZ/output and open it in the native viewer. Verify exact original bytes and
  geometry, then refresh after a controlled remote change. Cancel an unavailable
  host and verify the window remains responsive. No passwords go into profiles.
- CV-REMOTE-002: Upload a dedicated input folder to a new remote directory; edit
  input.yaml and a template; explicitly save; reject saving after another writer
  changes the file. Use workflow selects its YAML. Preflight must reject local
  dispatch, missing scheduler commands, engine paths, input or template files.
- CV-REMOTE-003: With a real provisioned cluster workflow/header/allocation, Run
  requires confirmation; Resume uses existing results; Refresh/Auto shows lock,
  failures/survivors/cache/logs and exact source energies. Close/reopen and inspect
  the same config without launching a duplicate driver. This final real SLURM
  calculation acceptance is **not yet executed**; current live acceptance covers
  transport/native opening and negative preflight without any submitted jobs.

Automated flags: --remote-connection-smoke-test (native sheet/bundled helper,
no login) and --remote-live-smoke-test (opt-in staged synthetic fixture metadata
in Downloads/chemviewer-remote-evidence/live-fixture.json). Final synthetic
fixture was removed after validation; recreate it deliberately before rerunning.

## Persistent remote navigation — 0.10.8

CV-REMOTE-004: Authenticate once; navigate parent/child folders repeatedly. The
footer must retain the same channel while its request count increases. Return
to a recently visited folder: no network request. Create/change a controlled
fixture locally in loopback acceptance; Refresh folder must reveal it. A failed
folder request must not break later requests. Disconnect and Browse must create
a new helper without canceling detached calculations.

Automated --remote-session-smoke-test exercises native persistent streams and
cache/refresh/reconnect with a local synthetic helper; --remote-navigation-smoke-test
is opt-in read-only live timing using the saved authenticated connection. The
existing --remote-connection-smoke-test covers the native sheet.

## Document workspace — 0.10.9

CV-WORKSPACE-001: Connect/Browse once. Remote tree stays beside the viewer while
expanding folders/opening xyz,out,inp. Existing geometry/frequency lists remain.
Open multiple local files, select tabs, reopen an existing file: no duplicate
tab. Source-only ORCA template displays original text and a limitation message.
CV-WORKSPACE-002: Rotate/zoom/select and place labels in A; edit/undo in B. Repeated
switches preserve each file's state, stop inactive playback/workers, retain one
loaded Image renderer/mesh. Abstract/Draw previews use the correct document.
Close dirty geometry/drawing: cancel/discard guard. Save project then close.
Cmd-W closes one active document; last-close leaves an empty workspace.
CV-WORKSPACE-003: Remote input with an explicit XYZ companion opens the referenced
geometry in its own file tab; selecting the already-open XYZ activates its tab.
No silent energy assignment; no source files rewritten. Close releases loaded
data/undo and detached renderer/text resources.

Flags: --document-workspace-smoke-test (synthetic native model/render lifecycle),
--remote-tree-smoke-test (opt-in isolated live fixture metadata in Downloads).
Retain existing --smooth-smoke-test and --drawing-labels-smoke-test regressions.

## Explorer initialization — 0.10.10

CV-REMOTE-EXPLORER-001: Show the sidebar while a request is busy; after it ends,
folder contents must load without reopening settings. Change a connection:
previous-host contents clear, replacement folder loads. Reopen with a root but
missing nodes: reload. Directories and ordinary text files are initially visible.
Home and Parent navigate without another authentication prompt while the master
is valid. Empty folders and filtered-only files have explanatory messages.
Native regression flag: --remote-explorer-smoke-test (isolated loopback).

## Unified ChemRefine destination — 0.10.11

CV-SSH-WORKFLOW-001: Connect once, select ChemRefine. SSH/SLURM destination follows
new connection; explicit This Mac selection remains available. Open/New use a
remote picker, including parent/home navigation. Create from independent structure:
new remote folder, relative seed/templates, dispatch:slurm, no Mac ORCA/UMA paths.
CV-SSH-WORKFLOW-002: Remote editor file buttons browse cluster files; modify form
and template then Save. Native and embedded Run/Resume save drafts and share the
remote scheduler/file/dispatch gate. Change a synthetic workflow to local dispatch:
both must refuse without launch. Status refresh must not save drafts. No real
job is required for this acceptance; scheduler science is a separate gate.
CV-SSH-WORKFLOW-003: Switch This Mac/SSH and Image/ChemRefine without losing editor
state. Profile change/tunnel loss closes old editor and permits reopening. Close
editor releases only its own GUI/tunnel; user SSH master and detached jobs survive.
Settings sheet has profiles/authentication/environment controls, no submission
panel. Upload local inputs belongs to ChemRefine More menu.

--remote-workflow-smoke-test is opt-in live ORCD acceptance: creates only synthetic
inputs and rejects local dispatch, never submits SLURM jobs. Guarded cleanup uses
Downloads/chemviewer-remote-evidence/live-workflow-test.json (not committed).
--workflow-runner-smoke-test checks the retained local runtime/dashboard against
actual isolated H2/PySCF. --remote-connection-smoke-test captures simplified settings;
--remote-explorer-smoke-test retains busy/loading/identity regression coverage.

## Forward ownership and folder ordering — 0.10.12

CV-SSH-WORKFLOW-004: With an authenticated shared SSH connection, open the remote
editor. Keep a valid unsaved form edit for at least20seconds (past multiple
monitor polls); its draft and HTTP access must survive the forwarding setup
process exiting0. Close editor: exact loopback forward is canceled; the shared
SSH master and user jobs survive. Failed setup must report an error, not ready.
CV-REMOTE-ORDER-001: Choose Extension beside Show all files. Mixed-case extensions
group together, folders remain first and b2.out precedes b10.out. Switch Name,
then back; selection persists. Check both root and expanded children.
CV-REMOTE-ORDER-002: Double-click a rendered folder label to enter it. Parent/Home
return using the same helper/cache. Disclosure arrow still expands tree. An
ongoing request must not silently swallow a double-click navigation request.

--remote-explorer-smoke-test now locates the rendered synthetic folder label in
its own window and sends native double-click events, alongside ordering/cache/
persistence assertions. --remote-workflow-smoke-test now holds a valid unsaved
draft20seconds, probes HTTP, and checks closure. Prior0.10.11 startup acceptance
ended too early to catch the2-second false-disconnect monitor; that evidence did
not establish sustained editor stability. No actual cluster calculation submitted.

## BosTMC screening — 0.11.0

CV-BOSTMC-001: Select BosTMC, choose This Mac or an authenticated SSH profile,
choose a CSV and root containing spin folders. Optionally choose a source-host
index cache directory. Index CSV; show progress without freezing the window.
Close/reopen or switch tabs while indexing; an interrupted process must report
failure/retry rather than a ready partial index. Source CSV/XYZ must be unchanged.

CV-BOSTMC-002: Add metal exact Fe, gap range 1–2 eV, geometry and coordination-number
criteria against a known fixture. Apply and check AND semantics with independent
expected rows. Check missing/NaN exclusions, one-sided bounds, text filters,
array any/all/mean and unit labels. A reversed/invalid range must show an error.
Verify column choices, numeric ordering, previous/next pages and CSV export with
all original columns/precision. Edit the source CSV; reindex must reflect it.

CV-BOSTMC-003: Select a candidate, verify atom identities/coordinates and full raw
properties; inspect associated Psi4 source without confusing it with parsed
energies. Choose another XYZ if several are found. Open in viewer: charge and
multiplicity must follow the CSV. Open the same row twice: one document; open a
different spin row sharing refcode/XYZ: separate document with its own multiplicity.
Change filters or quickly select rows during transfer: late data must not replace
the current selection. Switch ordinary document tabs and confirm camera/edits.

Automated native fixture acceptance and synthetic real-SSH acceptance pass for
this release; actual BosTMC record checks and large production-catalog timing
remain pending the real source paths. Native test flag: `--bostmc-smoke-test`.

## BosTMC hybrid sources and graph controls — 0.11.1

CV-BOSTMC-004: Choose a local CSV with Structure/output files on SSH enabled.
Index and filter while SSH is disconnected: local descriptors/embedded XYZ and
graphs must work. Set remote root and connection, then Find SSH outputs; no remote
copy of the CSV is required. For filename-only CSV rows verify XYZ fetch from the
correct spin/refcode folder. Original all-local/remote-CSV modes must still work.

CV-BOSTMC-005: Menus show readable scalar names/units and category dropdowns; no
XYZ/MOL2 or full-molecule lists in filter menus. Move both range handles separately,
verify the typed limits and no query until Apply. Set exact one-sided/negative
limits and invalid/reversed values; validate expected records/errors. Export keeps
all original columns/strings. Geometry choices come from the catalog, not a fixed
list of assumed geometries.

CV-BOSTMC-006: Select a row and inspect Graphs. Histogram counts must sum to the
finite full-catalog population; selected-property line must match the CSV scalar.
Switch property, missing-value record, then source: no stale graph survives source
change. Orbital levels preserve separate α/β Eh values; dipole component signs and
D values match source. Properties retains source precision. Source CSV size/mtime
must remain unchanged. Native flag `--bostmc-local-smoke-test` exercises the actual
user-supplied catalog; `--bostmc-smoke-test` retains synthetic compatibility checks.

## SSH recovery — 0.11.2

CV-SSH-RECOVERY-001: With a stalled private master, select Authenticate in Terminal.
Confirm a new socket rather than reuse of the old one. Complete authentication,
then Browse. Repeated folders still use one helper. A failed/cancelled login must
leave the previous selected socket unchanged. Existing editor/master/job lifetimes
must be preserved; do not resubmit calculations to test recovery.

CV-SSH-RECOVERY-002: A completed MFA is not sufficient for browsing success: test
a trivial command, then the configured Python/listing. If both ordinary SSH and
SFTP stall, retain an explicit external-session blocker rather than claiming an
app regression fixed the remote service. Hermetic publication/failure tests and
native transport regression pass; actual live browsing is currently blocked.

## Packaged resources and downloaded-app isolation — 0.12.0

CV-PACKAGE-001: Run `python3 scripts/check-macos-package.py --archive
dist/ChemViewer-macos-arm64.zip` after packaging. It must resolve all resources
inside the relocated app and reject its temporary copy with remote_bridge.py
removed. This headless check is automated and is not a GUI pass.

CV-PACKAGE-002: Independently download the CI app artifact, verify its hash and
signature, extract away from the source tree, then run its `--smoke-test` on the
physical Mac. Verify launch, opening, Metal frames, source and image export.
Do not accept source-build fallback as proof that the distributed app works.
The first0.12.0 download failed before launch due to direct Bundle.module lookup;
only a passing post-fix downloaded artifact can close this regression.

For synthetic GUI flags after a deliberate crash, pass
`-ApplePersistenceIgnoreState YES` to that test process to leave existing saved
state untouched. Deliver an explicit `open -a /exact/test/ChemViewer.app` event
after starting the instance if no window appears. Do not use `open -F`, clear
saved user state or terminate a running user app. Capture stdout and stderr
together; several native assertions report to stderr. Canonicalize paths before
checking bundle containment because macOS aliases /tmp and /private/tmp.
