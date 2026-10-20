# ChemViewer continuation handoff

Date updated: 2026-10-16

This file packages the working context needed to continue the project on an
Apple Silicon Mac. The user's original, complete project request is included
beside this file as `PROJECT-BRIEF.txt`.

## User and objective

The user is a computational chemistry researcher working with machine
learning, molecular dynamics, quantum mechanics, and scientific software. The
objective is a reliable, scientifically accurate native Apple Silicon
application with practical feature parity with Windows ChemCraft. It must not
be considered complete merely because it launches.

The work must preserve licensing and must not bypass registration, trial, or
license checks. Do not redistribute ChemCraft binaries, proprietary assets, or
recovered source. Use documented formats, authorized black-box observations,
and original implementation code.

## Work completed in the Windows session

An original Swift/Metal project named ChemViewer was created in this directory. It currently
contains:

- a SwiftUI macOS application and ChemCraft-style data explorer;
- a Metal atom/bond renderer with rotate, pan, and zoom;
- multi-frame XYZ parsing;
- ORCA Cartesian geometry, final-energy, vibrational-frequency, normal-mode
  displacement, and IR-table parsing;
- normal-mode animation and red imaginary-mode marking;
- IR sticks and Gaussian/Lorentzian broadening;
- macOS file importer and Finder/open-document URL handling;
- background parsing;
- Swift tests and an independent Python reference oracle;
- an ARM64 `.app` assembly/signing script;
- a read-only official-app diagnostic collection script;
- architecture, feature inventory, parity, diagnostics, reverse-engineering,
  and scientific-validation documents.
- recovered Windows GUI automation with direct reference observations;
- click/multi-click atom selection and distance/angle/dihedral readouts;
- trajectory play/pause and Windows-compatible right-drag rotation;
- native Apple Silicon GitHub Actions packaging.

This is a Milestone 3 implementation slice. It is not full feature parity or a
daily-use release.

## How the current GUI and vibration system work

The SwiftUI interface has a hierarchical calculation/geometry/frequency list
on the left and a Metal viewport on the right. The renderer currently draws
atom point-sprite impostors and line bonds. It infers bonds from covalent radii.

A parsed mode contains one Cartesian displacement vector per atom. The display
position is evaluated as:

```text
r_i(t) = r_i(0) + amplitude * q_i * sin(display_phase)
```

The display phase uses a fixed visible animation rate; it is not the physical
vibrational frequency. The scientific wavenumber remains attached to the mode
and is shown in the UI. Negative frequencies remain negative and are marked as
imaginary. Their animation is a visualization of the unstable normal
coordinate, not a physical periodic vibration.

The installed ORCA reference fixture labels the plotted third IR-table column
as `T**2`. The implementation retains the raw source value for relative
rendering and does not invent an undocumented unit conversion.

## Verified environment evidence

The Windows evidence host provided REA 6.5.0, Ghidra 12.1.4, Node, Python,
Git, CMake, WSL Ubuntu, and .NET. It did not provide Swift/Xcode. The bundled
Windows-control helper could not initialize, but the project-local
pywinauto/PyAutoGUI/Pillow fallback completed an evidence-backed GUI audit.
See `docs/windows-gui-audit.md` and `docs/gui-feature-inventory.md`.

REA was registered with Codex. Its setup backed up the Codex configuration to
`C:\Users\Ignac\.codex\config.toml.rea.backup`. REA native deep analysis still
requires a supported Ghidra/IDA provider and a fresh MCP connection.

### Windows reference artifact

- Path on evidence host: `C:\Chemcraft\Chemcraft.exe`
- Size: 12,841,472 bytes
- SHA-256: `79fe75015a1e48c4df29e7bac4c3c05e67057bf3a0ed03a7b77fe85528d4f05a`
- REA artifact Evidence:
  `ev_0c9f0c954791b774000004a1abebd6fd536c0ecfbc398824ba4a445307e48c84`
- REA native classification Evidence:
  `ev_dcac80936b8e7436946ddb1cb064e398bf50862b4015ab61dcf6273942cf024d`
- Observed as unsigned native PE32+ x86-64 with 15 sections and no CLR.
- Static PE evidence shows an Enigma protection/virtualization boundary,
  including `enigma_ide_x64.dll!EP_RegHardwareID`.
- Do not unpack the protector or trace registration/license operations.

### Official macOS b638m artifacts

The artifacts themselves are deliberately excluded from this transfer ZIP.
Download fresh copies from the official website on the Mac.

- ARM DMG SHA-256:
  `603e4e9c2a6b7d2e4cffdd9686490327200dde637065b9e3ed78020689387814`
- Intel DMG SHA-256:
  `967100f1d25eb877287b94e47829832aefad9ac48ccbb36f6ba48e163ec2169b`
- ARM executable SHA-256:
  `c3a83812708d942afb59e9f2f13ad5448d4be9bee20c22129f81cfdc99e86441`
- Intel executable SHA-256:
  `645bdf5291073f2e29edc101365b9803c43ecca360bc664597991169cc88a6f0`
- ARM is thin arm64, built with Free Pascal 3.2.2 and Lazarus LCL/Cocoa.
- Intel is thin x86-64, built with Free Pascal 3.2.0 and Lazarus LCL/Cocoa.
- Each declares the same 13 Apple-only linked frameworks/libraries.
- ARM has an ad-hoc/linker signature (`0x20002`), no CMS certificate, and no
  hardened-runtime flag. Intel has no `LC_CODE_SIGNATURE` command.
- Missing third-party dylibs are therefore unlikely to explain the published
  instability. The actual crash cause is unknown without target-Mac reports.

## Tests completed on Windows

The following command passed the portable scientific/artifact regressions:

```powershell
py -3 -m unittest discover -s .\python_tests -v
```

The tests validate:

1. the installed ORCA water compound-job output: final O/H/H geometry, final
   energy `-76.360968646 Eh`, nine modes, frequencies 1606.12, 3678.02, and
   3777.72 `cm^-1`, raw IR values, and a normal-mode vector component;
2. the official ARM/Intel Mach-O architectures, linked-dependency counts,
   hashes, and signature shape, when those local artifacts are available.

Both shell scripts pass `bash -n`, and `Packaging/Info.plist` parses as XML.
GitHub Actions run `38922066239` built commit `42e3cbd` on a native Apple
Silicon `macos-15` runner. All seven Swift tests passed, the release executable
was verified as arm64, the ad-hoc bundle signature passed strict verification,
and the `ChemViewer-macos-arm64` artifact was uploaded. This is CI evidence,
not a substitute for a physical-Mac GUI launch.

Private repository: `https://github.com/ignaciomigliaro/ChemViewer`

## First commands on the Apple Silicon Mac

Install Xcode 15 or newer and its command-line tools. Then, from this directory:

```bash
xcode-select -p
swift --version
bash scripts/build-macos.sh
open dist/ChemViewer.app
```

The build script runs `swift test`, builds ARM64 release code, assembles the
application bundle, includes the SwiftPM Metal resource bundle, signs locally
with an ad-hoc signature, and verifies it.

Download the official ARM and Intel beta bundles from:

- https://chemcraftprog.com/MacVersion.html

Run the read-only diagnostic script separately against each installed bundle:

```bash
bash scripts/collect-macos-diagnostics.sh /Applications/Chemcraft.app
```

Do not clear quarantine or disable Gatekeeper/SIP as a first diagnostic step.
Capture the exact launch result and any `.ips` crash report. Test the Intel
build under Rosetta separately and record Rosetta availability.

## Immediate continuation priorities

1. Compile and run all Swift tests. Fix compiler/API issues before adding more
   uncompiled code.
2. Launch the new app with a small XYZ file and an ORCA frequency output.
3. Verify continuous normal-mode animation, Retina sizing, camera gestures,
   shader-bundle lookup, and imaginary-mode presentation.
4. Run both official builds and collect crash reports/signing/quarantine
   evidence with the provided script.
5. Compare official ARM versus Intel behavior using the reproduction matrix in
   `docs/macos-diagnostics.md`.
6. Run the acceptance matrix in `docs/macos-gui-acceptance-tests.md` and record
   interactive results separately from CI.
7. Add checked-in test fixtures only when independently generated or clearly
   redistributable.
8. Prioritize ORCA 6 optimization, OptTS/frequency, NEB, IRC, scan, orbital,
   cube, and Hessian workflows.
9. Add depth-correct instanced spheres/cylinders, trajectory graphs,
   geometry editing, and volumetric isosurfaces in bounded, tested slices.

## Important limitations

- A CI-built ARM64 `.app` artifact exists, but it has not yet been launched on
  the user's physical Apple Silicon Mac.
- No target-Mac runtime or crash evidence exists yet.
- The current renderer is a prototype without depth testing or bond picking;
  CPU screen-space atom picking is implemented but not yet run on a Mac.
- ORCA support covers one observed layout family, not every ORCA version and
  calculation type.
- Most other chemistry formats, molecular orbitals, volumetric surfaces,
  editing, reaction pathways, export, and advanced properties remain pending.
- Windows GUI coverage is substantial but still partial: IR-spectrum activation,
  a displacement-vector incident, imaginary-mode reference behavior, PES, and
  NEB remain unresolved.
- Keep every status in `docs/feature-parity.md` honest; do not mark a feature
  complete until its scientific and interactive acceptance tests pass.

## Suggested continuation request

```text
Continue the ChemViewer project using AGENTS.md, PROJECT-BRIEF.txt, and
CONVERSATION-HANDOFF.md. First inspect the current Mac/Xcode environment, run
the Swift tests and build script, launch the generated app, fix all build or
runtime defects, and collect read-only diagnostics for the official ARM and
Intel ChemCraft builds. Preserve the clean-room and licensing boundaries and
update the evidence and parity documents with verified results.
```

## Mac continuation — 2026-10-19

User's active project is `/Users/nacho/Documents/software/ChemViewer` (the SwiftUI/Metal project), not the older Downloads/MoleculeView prototype. Full Xcode is absent; Command Line Tools Swift 6.3.3 builds the app successfully. `scripts/build-macos.sh` now runs an explicit standalone adaptation of the checked-in core regression assertions when XCTest is absent; CI requires actual XCTest. Eleven core methods pass. The locally signed ARM64 `dist/ChemViewer.app` passed its `--smoke-test` with real Metal pipelines and completed GPU frames, XYZ open/export, coordinate undo, selection, negative-mode animation and pause.

Fixed confirmed CRLF parsing truncation and hardened frequency geometry association, incomplete vectors, nonfinite coordinates, stale async loads and cross-frame undo. Native real-water ORCA values match the independent Python oracle. Read `docs/mac-validation-2026-10-19.md` before updating statuses. Manual GUI acceptance and broader Chemcraft parity remain incomplete. Logs are in Downloads/chemviewer-validation.

## Latest: native Mac visual/UI update, 0.2.0

User requested xyzrender-like molecules and the reference Chemcraft GUI/workflows. Replaced point/line rendering with depth-tested MSAA sphere/cylinder meshes; added publication/soft/large-sphere/stick display schemes, viewport PNG export, frozen mode phase and narrow-pane fitting. Implemented Image/Abstract/Source/Coord/Image/Abs, summary navigation, source text, embedded coordinate edits, camera rail and native menus. All 11 standalone core cases and the expanded packaged live-GPU smoke check passed. Real window screenshots were inspected under Downloads/chemviewer-validation. Full parity and fragment construction are still unfinished. Read `docs/rendering-and-ui-2026-10-19.md` before continuing. Preserve all earlier uncommitted parser/build fixes.

## Latest: 0.3.0 energy and editing workflows

Implemented source-linked ORCA SCF/final-energy records, explicit/unitless XYZ energy handling, Abstract energy/structure views, and Matplotlib energy profiles (PDF/SVG/600-dpi PNG/CSV/JSON/script export, internal-coordinate axes and thumbnails). Unlimited left-click atom toggling, arrow geometry navigation with explorer scrolling/text-focus protection, two distance movement modes and three-atom angle editing are connected to native controls. Edits invalidate energy and energy-bearing comments; per-frame Undo survives navigation and restores metadata. Python Matplotlib 3.9.4 is installed in Application Support/ChemViewer/plotting-venv; setup script supplied. Sixteen standalone core cases, three Matplotlib tests, and both packaged live-window workflow checks pass locally. Full XCTest unavailable; no full-parity claim. Read `docs/energy-and-editing-2026-10-19.md`; evidence under Downloads/chemviewer-energy-work. Preserve previous uncommitted fixes.

## Latest: 0.4.0 thermochemistry and manipulation

User clarified angle editing: B remains the vertex, move C only or A/C equally. Implemented that picker, right-click deselection, clean Abstract with numeric copy/H/G/full-correction sums and optional source details, coordinate TSV/XYZ clipboard actions, and four reference-style drag buttons. Actual atom/connected-fragment/whole-geometry drags, boundary-pair fragment identification, ±world-axis rotation/translation and selectable pivot are connected; one undo per gesture. ORCA thermochemistry preserves section/frame/temperature and derives full H−E rather than mistaking kBT for the full correction. Nineteen core cases, actual installed ORCA thermochemistry values, and all three packaged GUI/GPU workflow checks passed. Initial general-clipboard test replaced clipboard contents before defer could restore; disclosed to user and replaced with private named pasteboard tests. Read `docs/thermochemistry-and-manipulation-2026-10-19.md`. Prior changes remain uncommitted; preserve them.

## Latest: 0.5.0 measurements and interaction performance

Added optional 2/3/4-atom distance/angle/signed-dihedral overlays, PNG annotation export, and dihedral panel readout. User clarified inversion meant mouse view rotation; corrected horizontal grab yaw and camera rail directions, preserving Cartesian geometry rotation math. Drag previews are now local to the Metal view with one mouse-up document commit; no per-move UI publications. Sphere/cylinder meshes are built once and GPU-instanced; coordinator caches bonds. Local 500-atom CPU draw median improved 17.05 → 1.17 ms (earlier optimized run 0.73 ms). New packaged check passed 120 preview events with zero geometry publications, pointer tracking, overlays/PNG and horizontal/vertical grab rotation. Nineteen core cases and all four packaged workflows passed. See `docs/measurements-and-smooth-drag-2026-10-19.md`; logs/screenshots under Downloads/chemviewer-smooth-work. Keep all earlier uncommitted work.

## 2026-10-19 — ChemViewer 0.6.0 Paton/GIF continuation

Default appearance is xyzrender · Paton, a native MIT-attributed Metal adaptation with upstream palette, HLS gradients, common radii, thin outlines, single black bonds and fog. Prior styles remain in the toolbar/Display menu. File → Export Animation as GIF… and the toolbar export trajectory/frequency GIFs with current active-window yaw/pitch, fixed all-frame fit (zoom/pan intentionally refitted), size/fps/loop/ping-pong/progress/cancel. `AnimationExportView.swift`, `MolecularAppearance.swift` and shared offscreen renderer are new. No external GIF dependency is required. Read docs/paton-and-gif-2026-10-19.md for implementation, scientific semantics, checks and limits. Source remains uncommitted; preserve earlier work.

0.6.0 final validation: 19 standalone core cases and all five packaged workflows passed. Final shader build repeated animation/base/smooth successfully; independent Pillow reopened both GIFs. Installed and signature-verified at ~/Applications/ChemViewer.app, opened with Downloads/chemviewer-animation-work/trajectory.xyz. Tests use private pasteboards; no clipboard changes. Screenshot capture failed for the GIF sheet despite successful sheet presentation; do not claim human visual acceptance. Details and evidence filenames are in the Paton/GIF release document.

## 0.6.1 — uniform shading by distance

At the user’s request, depth fog is disabled for both atoms and bonds. The shared native render path now sends zero fog weight, so farther objects retain the same element colors and surface gradient as nearer objects. This applies to the viewport, PNGs and GIFs. Paton palette, outlines and radial shading remain. Verify by rotating a deep structure and comparing near/far atoms of the same element. This supersedes the 0.6.0 depth-fog behavior.

0.6.1 validation: 19 standalone core cases and packaged animation/style/GIF workflow passed. Signed arm64 build installed at ~/Applications/ChemViewer.app. Existing running windows retain their prior binary until relaunched.

## 0.6.2 — measurement labels and slower GIFs

Select 2 atoms for length, 3 for angle (B is the vertex in A→B→C), or 4 for a signed dihedral, in order. Choose File → Export Animation as GIF… and enable **Include measurement label and guides**. The current ordered selection supplies one measurement per GIF. Its numeric value and projected guides are recomputed from each frame's actual coordinates, including sinusoidal frequency displacements. Labels use Å or degrees, retain the viewer’s angle, and use the same guide/dihedral-plane drawing as the native view. The toggle starts enabled when the viewer’s measurement overlay was enabled. Labels require stable atom ordering and matching element sequences across trajectory frames. If a selected angle/dihedral is undefined in a frame, export reports an error rather than writing a misleading value; temporary output is removed and any existing destination remains intact.

Playback speed offers Normal, Half, Quarter and Eighth; Half is the new dialog default. Frame-rate choices now include 1 and 2 fps. Every frame is retained; GIF delay is `1 / (fps × speed)`, with an approximate loop duration shown. GIF centisecond quantization/player behavior may slightly change actual timing. These choices apply to both trajectories and frequencies. Display speed remains illustrative, not physical vibrational time. Coordinates, amplitude and camera orientation are unchanged.

0.6.2 final local results: 19 standalone core cases, expanded packaged annotation/GIF checks and base viewer smoke checks passed. Independent Pillow decoded all 12 frames at 100 ms normally versus 400 ms at quarter speed (1.2 s versus 4.8 s). Angle/dihedral PNGs were visually inspected for guide alignment. Native selection, camera, cancellation and scientific frame data remain covered. Signed arm64 app installed at ~/Applications/ChemViewer.app. Relaunch to load 0.6.2. Human dialog/playback acceptance remains pending.

## 2026-10-19 — unified ChemViewer 0.7.0

User requested MoleculeView's GUI and missing implemented tools merged into ChemViewer, retaining Paton and all recent features, then retiring the old app. See docs/moleculeview-integration-2026-10-19.md for the full reconciliation. New core IntegratedBuilding/BuildingProject encapsulate original project-owned parsing/building/state logic. New GUI BuilderPanel/ClassicControls and expanded WorkspaceStore integrate fragments, topology edits, 100-entry per-frame undo/redo/group snapshots, legacy projects, explicit ORCA geometry export, captions/H visibility, live speed, camera roll/pan and per-frame modes/facts. Main app defaults to classic white workspace, explorer/builder initially hidden; Cmd-B/+ opens builder, View toggles explorer. No proprietary code was copied. Prior uncommitted work is preserved; no push/commit performed.

## 0.7.0 final verification and retirement outcome

23 core assertion methods passed using the explicit standalone runner; all three migrated original parser/editing/state suites passed. All six packaged native workflows passed: merge, base, energy, manipulation, smooth interaction and annotated/slow GIF export. The installed signed arm64 app independently passed the merge check after retirement of the old source folder. `swift test` was attempted before/after; both remain unavailable because this host lacks XCTest/full Xcode (this is not reported as XCTest passing). `git diff --check` passes. No commit/push was performed.

Installed: `/Users/nacho/Applications/ChemViewer.app`, version 0.7.0 (build 9). Active source: `/Users/nacho/Documents/software/ChemViewer`. Old `/Users/nacho/Downloads/MoleculeView` and both app copies were moved together to `/Users/nacho/.Trash/MoleculeView-retired-2026-10-19`; no MoleculeView.app remains in the searched active Downloads/Applications locations. No old app was running and its historical worker had finished. Recoverable source-only tar and verified complete Git bundle are in `/Users/nacho/Downloads/chemviewer-migration-backups`, with SHA256 manifest. User calculation inputs and Chemcraft installations were left untouched.

Native evidence/logs are in `/Users/nacho/Downloads/chemviewer-merge-work`. Actual window-server screenshot capture was unavailable (`could not create image from window`). `merged-layout-offscreen.png` caches the real SwiftUI controls but cannot capture the Metal layer (it appears black); `merged-molecule.png` is the separate real GPU output and renders white correctly. These were inspected separately and are not described as a desktop screenshot. Full human GUI ergonomics and broad real-calculation coverage remain pending.

## 0.7.1 — left explorer restored by default

The geometry/frequency Result Explorer is visible on the left at startup again, as requested. Its geometry selection, per-frame frequency selection and arrow navigation are retained; View → Result Explorer or the sidebar toolbar button still toggles it. The optional right-hand builder remains available with +/Cmd-B. This supersedes 0.7.0’s initially hidden explorer. Verify by opening a multi-geometry ORCA output and browsing geometries and modes from the left panel.

0.7.1 validation: 23 standalone core cases, three migrated suites and packaged energy/navigation workflow passed. Signed arm64 app installed at ~/Applications/ChemViewer.app; relaunch existing windows to load the restored default.

## 0.7.2 — optional frequency vectors

Frequency displacement vectors default to off. The toolbar Vectors checkbox, native Display → Displacement Vectors menu, and classic in-window Display → Frequency Vectors menu share the same toggle. Select a normal mode and toggle vectors without changing animation or coordinates.

## 0.7.3 — stable view while selecting atoms

A native regression reproduced selection resizing the 3D canvas: the bottom inspector was inserted/removed and had variable height for 1/2/3/4 selections, changing projection and apparent molecule position without a camera reset. The inspector now has a stable 140-point scrollable area, with an empty-selection hint. Its content can scroll horizontally in narrow split/builder layouts without changing the canvas. The status row also has a fixed height. Separately, camera dragging now waits for movement over 3 points; small click jitter does not rotate/pan. Atom manipulation retains its existing 1-point activation threshold. Selection colors and measurement edits remain functional.

The native smooth regression now exercises a real click with subpixel movement, then 1/2/3/4 selections and clearing, and verifies viewport object identity, bounds, camera rotation and all projected atom positions in window coordinates (0.05-point tolerance). This supplements the existing local atom-drag/undo, guide/PNG and mouse-camera direction checks.

0.7.3 validation: before-fix native regression failed with “Selection resized the 3D canvas”. After the fix, the extended smooth/selection, energy/editing and manipulation workflows passed; 23 standalone core cases and three migrated suites also passed. Signed arm64 app installed at ~/Applications/ChemViewer.app. Evidence: Downloads/chemviewer-selection-work. Physical human input feel remains for user confirmation; the programmatic mouse/jitter and screen-projection checks passed.

## 0.7.4 — draggable measurement labels

Enable Show bond length/angle/dihedral, then drag the white numeric label box to move it away from the structure. The hand cursor identifies the draggable area. Only the label receives those drag events; clicks outside it continue to select atoms or rotate/drag the molecule, and right-click still clears selection. The numeric measurement and its atom guides remain tied to the selected atoms. Reset label restores automatic placement.

Offsets are stored locally per geometry and ordered atom selection, as fractions of viewport width/height. Reselecting the same measurement restores its placement during the current view session. PNG capture uses the live placement; the independent GIF renderer copies the offset map and applies the same normalized offset at its output resolution while recomputing each frame's value. Export still fits all frames once, so absolute pixel placement can differ with aspect ratio/framing. Labels stay inside image bounds. New file/view sessions and atom-count changes clear positions; working project files do not serialize label positions. Dragging a label does not change coordinates, selection, animation or camera and does not add geometry undo entries.

Native regression coverage uses mouse handlers on 2/3/4-atom label boxes, verifies 70×30-point label motion, pass-through away from the box, unchanged numeric values/geometry/camera, retained placement on reselection, PNG exports, offset preservation through both GIF renderer copies, an actual moved-dihedral GIF, reset, and prior smooth camera/selection/drag checks. Scientific core tests remain unchanged. Manual pointer feel and all output sizes still require user acceptance.

0.7.4 final validation: 23 standalone core cases and three migrated suites passed. Expanded native smooth/label-drag, annotation/GIF and manipulation workflows passed. Moved-label PNGs were visually inspected; actual moved-dihedral GIF exported and reopened. Signed arm64 app installed at ~/Applications/ChemViewer.app. Evidence: Downloads/chemviewer-label-placement-work. Relaunch existing windows to use the update. The user’s TS.inp and calculation files were not edited.

## 0.7.5 — macOS application icon

The app now ships an original generated blue/teal molecular icon instead of the generic application placeholder. Packaging/ChemViewerIcon.png is the transparent master; scripts/build-icon.sh creates all ten standard/Retina PNG slots (16–1024 physical pixels) and Packaging/ChemViewer.icns. The macOS build copies the ICNS into Contents/Resources, and CFBundleIconFile references it before code signing. This is app identity artwork, not a chemically interpreted structure. Verify the installed icon in Finder and the Dock after relaunch; macOS may cache an older icon on a running app. No scientific/rendering behavior changes.

0.7.5 validation: packaged build passed 23 standalone core cases and the three integrated suites; all ten icon slots were extracted and verified, bundle icon reference matches the ICNS, installed signature passes, and NSWorkspace resolved the installed app to the new icon (visually inspected at Downloads/chemviewer-icon-work/macOS-resolved-icon.png). Installed version 0.7.5 build 14; LaunchServices registration refreshed.

## 0.8.0 — detected NEB reaction profiles and optional markers

The energy sheet now auto-selects a complete ORCA NEB/NEB-TS path-summary dataset, separate from Cartesian optimization history. It defaults to a reactant/refined-TS/product diagram; all images and ordinary PES lines are also selectable. Forward/reverse barriers use the explicit refined TS and printed relative energies, not the highest CI or rounded-Hartree subtraction. Structures are taken only from validated optional companion files. All scatter markers can be turned off. PDF/SVG/PNG/CSV/JSON exports include provenance. See docs/neb-reaction-profiles-2026-10-19.md for scientific semantics, implementation, tests and limitations.

0.8.0 final results: 25 standalone core cases, the three migrated parser/editing/project suites, and all six Matplotlib plotting tests passed. The final packaged native NEB check passed on the original user TS.out (11 rows; forward/reverse/reaction 86.35/2.66/83.69 kcal/mol; all three matched endpoint/TS structures; auto defaults, reaction/full-band renders, optimization toggle and sheet). Existing packaged energy/editing/navigation/Matplotlib workflow passed. Direct swift test remains blocked by absent XCTest/full Xcode; no XCTest pass is claimed. The reaction diagram was visually inspected; final version labels use two decimals. The initial companion String file reader blocked on this Mac; switching to the existing bounded Data(mappedIfSafe) read path resolved it, and the original-file native check passed repeatedly afterward.

Signed arm64 ChemViewer 0.8.0 build 15 is installed at ~/Applications/ChemViewer.app, preserving its icon. Read-only input TS.out and companion files were not modified or committed. Generated reaction diagram and full-band PDF/SVG/600-dpi PNG/data/script bundles are in Downloads/chemviewer-neb-work/TS-reaction-diagram and TS-full-neb-path. Logs are beside them. Source remains uncommitted; no GitHub push performed.

## Version-control policy — 2026-10-19

User explicitly authorized committing and pushing every completed version going forward. AGENTS.md records the persistent release workflow: validated source/tests/assets/docs commit, annotated version tag, push branch/tag, verify remote, no force pushes or tag replacement. The current cumulative source is being published as v0.8.0; earlier locally installed builds were not separately checkpointed and are not represented as invented historical source commits. Prior statements that these changes remain uncommitted describe earlier work and are superseded by this release checkpoint. Personal calculation files and generated local evidence remain outside the repository.

## 0.8.1 — transparent GIFs and box-free atom captions

GIF export now defaults to **Transparent background**; clear that checkbox for the previous white background. Atom-number, element and combined captions have no painted background in the viewport, PNGs or GIFs. Transparent GIF measurement text also omits its white box, while its numeric value, guide lines and moved placement are retained. The live draggable measurement-label box remains for normal viewing. Camera angle, scientific coordinates, playback speed and label offsets are unchanged.

The independent Metal export targets clear to RGBA zero and preserve alpha through readback. MSAA coverage colors are unpremultiplied in linear space to avoid dark fringes. Caption/measurement compositing clears its bitmap before drawing. GIF supports binary transparency, not partial opacity; export thresholds coverage at 50 percent, retaining opaque white atoms rather than color-keying white. Subtle semitransparent guide planes cannot retain fractional opacity in GIF.

GIFWriter now uses ImageIO to quantize each independent frame, then streams GIF89a image blocks with local palettes, an infinite-loop extension, explicit delay and disposal-to-background (method 2). Independent full-image frames prevent the differential-frame/disposal interaction that otherwise causes stale atom trails or disappearing stationary atoms. No Python installation is required for export. Existing temp-file cancellation and atomic final replacement remain.

Validation: 25 standalone core cases and the three integrated suites passed during the signed arm64 build. Expanded native animation tests verify transparent corners, frame-by-frame masks against independently rendered alpha images, preserved white atoms, an opaque-white option, all three caption modes with zero white-background pixels, timing/loops/cancellation/measurements and unchanged document/camera. Independent Pillow compositing checked all 12 frequency frames at every pixel: disposal 2, no trails or missing opaque atoms, and no caption boxes. The smooth/label-placement workflow is also checked. Evidence is outside the repository in Downloads/chemviewer-transparent-work.

## v0.8.2 — ORCA XYZ trajectory energies
The reported XYZ uses `Coordinates from ORCA-job <name> E <value>`, which the named-field parser previously skipped because it required `:` or `=`. Added a narrowly anchored ORCA-comment recognizer, retaining Hartree units, source text/line and frame association. Generic unitless comments retain their previous behavior. All 12 frames in the user-provided trajectory matched an independent last-token energy oracle within 1e-12 Eh; no personal calculation data was added to the repository. Synthetic regressions cover multiple frames, D exponents, provenance and invalid/non-ORCA comments. Release build passed 26 standalone core regression cases and three migrated suites; `swift test` before/after remains unavailable because this CLT installation lacks XCTest.

Packaged native energy-workflow smoke test passed: multi-XYZ energies, Abstract/source links, editing/undo and energy invalidation, packaged Matplotlib exports and plot sheet. Installed signed v0.8.2 in `/Users/nacho/Applications/ChemViewer.app`.

## Installed-app update workflow

Found `/Applications/ChemViewer.app` at 0.8.0 while `~/Applications/ChemViewer.app` was 0.8.2, explaining stale launches. Added `scripts/install-macos.sh`: build/check then update the canonical /Applications bundle and any existing user Applications copy; `--no-build` installs an already validated build. Refreshes LaunchServices registration without closing user windows. AGENTS.md requires this installation step for future local releases. No application behavior/version change.

## GitHub Swift 6.1 compatibility fix
Actions run 39299377644 failed while type-checking `ManipulationToolbar.scopeIcon` on Xcode 16.4 / Swift 6.1.2 ARM64. Local Swift 6.3.3 had accepted the same Canvas expression. Extracted drawing into a typed GraphicsContext helper, separated trigonometric/CGFloat arithmetic, and replaced nested ternaries with a scope switch. Icon geometry and colors are unchanged. Local debug build passes; remote CI will verify the actual older toolchain.

Follow-up run 39306699269 passed Swift compilation/tests and then exposed a separate Matplotlib source-build failure in bundled FreeType. CI now explicitly selects Python 3.12 with setup-python and requires binary wheels for plotting dependencies. This avoids reliance on the runner default Python and native source compilation.

## 0.9.0 — fragment builder, UFF and local ChemRefine

Added 258 original generated fragments/metal centers, searchable categories, immediate click-to-attach, current-selection fragments and saved XYZ fragments, all-element click placement, removal of unused X sites, genuine cancellable RDKit UFF with fixed atoms/undo/stale-result protection, and the actual separately installed local ChemRefine GUI embedded in WebKit with seed/config/template export and result import. See [building and local workflows](docs/building-and-local-workflows.md) for usage, scientific limits and evidence. User chose UFF/ChemRefine first; UMA is deferred until model access exists. Local runtime is installed under Application Support/ChemViewer/chemistry-venv. ORCA calculations require configuring an installed executable; GUI bootstrap/validation are tested, not an unavailable ORCA calculation.

Final local gate passed: 27 core cases, three migrated suites, five Python chemistry tests, and packaged native builder/UFF/WebKit acceptance including attachment of every catalog entry. Verified actual embedded ChemRefine page rendering and visually inspected its snapshot. Installed signed ARM64 v0.9.0 build 18 in both /Applications and ~/Applications. No personal structures, runtime environments, credentials, vendor code or generated local evidence are included in the commit. CI now runs chemistry tests with the pinned runtime setup.

Remote run 39323777153 passed XCTest/build, plotting, the pinned chemistry setup and all five chemistry tests, bundle verification and artifact upload. Final interaction fix clears armed placement when the builder closes or drag mode starts; packaged acceptance passed again, and test teardown now exits with a meaningful status after stopping its own local server.

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

Final 0.9.1 local gate: release ARM64 build/signature, 28 standalone core cases, three migrated suites, new native gallery/empty-click/tab acceptance, retained builder/UFF acceptance and smooth interaction/measurement/GIF-placement acceptance all passed. Installed both /Applications/ChemViewer.app and ~/Applications/ChemViewer.app. Popup thumbnails use one shared renderer with a bounded image cache rather than a Metal view per card.

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

Final local 0.9.2 gate passed: 28 standalone core cases and three migrated suites; native placement/depth/rendered-zoom/orbit test (3,528 initial nonwhite pixels, 232 after four 0.7× zoom-outs, 3,528 restored, 8,461 after two 1.25× zoom-ins); native smooth dragging/selection/labels test; and the full transparent-GIF/style/frequency/trajectory export test. Inspected actual viewport PNGs. Signed ARM64 0.9.2 build 20 is installed in both Applications locations. Core scientific data and personal geometry files were not edited.

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

Local 0.9.3 release gate passed: 29 core cases + three migrated suites, native
atom/periodic-table/Coordinates workflow, fragment/camera workflow, smooth
interaction workflow and complete builder/UFF/ChemRefine workflow. See
`docs/atom-editing-2026-10-20.md` for exact evidence and limits. No personal
calculations or previously built structures were modified.

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

Final local 0.10.0 gate passed: 31 standalone core regressions plus three migrated
building suites; 13 chemistry Python tests (five existing and eight drawing);
native drawing/persistent-label/trajectory tracking gate; native smooth
interaction and transparent-GIF suites; existing atom editing, fragment/camera
and full builder/UFF/ChemRefine workflows. Signed ARM64 build 22 is the validated
bundle. Latest drawing evidence: /private/tmp/chemviewer-0100-tracking.log; other
logs /private/tmp/chemviewer-0100-*.log. Personal calculation files were unchanged.
