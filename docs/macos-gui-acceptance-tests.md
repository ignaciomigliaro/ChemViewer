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
