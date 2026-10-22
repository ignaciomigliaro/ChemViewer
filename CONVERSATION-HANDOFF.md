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

Local 0.10.1 final gates passed: core 31 + three migrated suites; Python 24;
centered actual glyph pixel and projected sphere-center checks; genuine two-step
ChemRefine/PySCF conventional HF/STO-3G H2 result -1.1167593074 Eh with live unsaved
YAML/new-template flushing and detached/editor-server survival; full GIF and
builder/UFF/ChemRefine regressions. User confirmed ORCA is not installed: official
macOS installer/account download remains external, and actual ORCA/MPI execution
is untested. Do not report all backends/models installed: only the isolated
PySCF backend was added; selected missing MLIP extras are provisionable and gated
weights still require user access. No personal scientific files were changed.

## 0.10.2 — native ORCA setup (2026-10-20)

The user supplied `/Users/nacho/Documents/software/orca_6_1_1_macosx_arm64_openmpi411`.
It is an unpacked executable distribution, with a native arm64 driver and
`orca_startup`/`orca_leanscf` helpers. The previous bridge incorrectly required
older `orca_scf`/`orca_gtoint` names. Both complete families now pass; missing
helpers remain blocking. Missing `slurm-header` warnings also block local runs,
because ChemRefine's local script generator requires that header too.

26 Python chemistry integration tests pass; 31 standalone core cases plus three
migrated suites pass; native live-editor/save/detached two-step PySCF workflow
gate passes. Signed ARM64 build24/0.10.2 installed in both Applications copies.
ORCA path persisted in ChemViewer defaults and ~/.zprofile ORCADIR/PATH for new
login shells. User sessions were not killed. The user is personally approving
Gatekeeper prompts for ORCA components; no quarantine/security bypass performed.

UMA environment `/Users/nacho/miniconda3/envs/uma/bin/python` now has the same
pinned ChemRefine installed without replacing fairchem-core 2.23.0/torch 2.13.0.
Dependency check passes; existing HF login authorized uma-s-1p2 weights, cached
under ~/.cache/fairchem. ChemRefine single point on neutral singlet H2 at 0.74 A
gives -1.1608742095228168 Eh, exactly matching independent fairchem ASE inference.
CPU/LBFGS optimization from 0.90 A converged to 0.7411425064135867 A and
-1.1608751163763043 Eh (max force about 0.0005093 eV/A); both pipelines have one
survivor and zero failures. Synthetic inputs, templates and actual logs are in
~/Downloads/chemviewer-h2-orca-uma-20261020; these are not committed.

Native ORCA final validation also PASSED: serial H2 HF/STO-3G TightSCF,
-1.116759307204 Eh, normal termination, one survivor/zero failures. Independent
PySCF differs by 1.9243e-10 Eh. Actual bridge launched run log
`20261020T153513.783701Z-run.log`; successful output and verification JSON are
in the synthetic validation directory. Supersedes previous ORCA-pending notes.
Parallel/MPI remains untested; no mpirun found. Detailed scope and model results
are appended to docs/chemrefine-execution-2026-10-20.md and scientific-validation.

## 0.10.3 — working dashboard actions and step energy summary

WKWebView previously lacked UI delegates for the editor's window.confirm calls,
so bottom-right Run/Resume/recovery could silently cancel. The new scoped
ChemRefineWebDelegate supplies native sheets and a reply handler; an original
workflow_dashboard.js resource intercepts only loopback /api/run at document
start and routes all six actions/targets through native save/check/model/env/
launch/monitor handling. Installing the hook after Alpine initialization had a
first-click race; final document-start routing is tested. Upstream ChemRefine
files are unchanged. Native top panel adds Resume.

The bottom-right Run panel opens to a step table joined from saved config names,
real status/cache and finite steps.csv Hartree rows. It shows each step's minimum
energy with type/conformer/count, status, selectable Eh/kcal/mol/kJ/mol/eV and
Copy table. Missing values stay null; retained unsuccessful-cache values are
labeled previous. Refresh also updates upstream progress to prevent stale zero
survivors after fast runs. Units are display-only; no differences between
incompatible models are inferred. The user's completed workflow was read-only
checked; no personal scientific jobs were launched.

Final native log /private/tmp/chemviewer-0103-native-verified.log contains
DASHBOARD_ACTIONS_PASS + WORKFLOW_RUNNER_PASS. It exercises genuine bottom Run
with live unsaved YAML/template flushing, independent two-step PySCF H2 energies,
native confirmation sheets, cached Resume, targeted Rebuild cache/Rerun errors,
upstream progress freshness, actual visible summary and kcal/mol oracle, and
editor-server closure while the final detached recovery finishes. Python28 and
core31/three migrated suites pass; signed ARM64 build25/0.10.3. Real WK snapshot
~/Downloads/chemviewer-runner-evidence/workflow-dashboard.png inspected. Details
in docs/chemrefine-dashboard-2026-10-20.md. User's pre-existing AGENTS.md edit
was preserved and excluded from this release commit.

Local xTB support: the Mac ORCA package lacked otool_xtb, contrary to an earlier
doc claim (corrected). An original launcher beside ORCA calls existing native
reactOT/bin/xtb 6.7.1. Independent H2 xTB Opt -> ORCA UMA ExtOpt passed with one
survivor/zero failures each under ~/Downloads/chemviewer-xtb-uma-check.

## 0.10.4 — user-configurable UMA Python environments

WorkflowRunner has a persistent optional UMA Python default (ChemViewerUMAPython),
folder/interpreter chooser, actual import checker and explicit Use for UMA steps
control. Typed tilde/environment folders resolve to bin/python without resolving
symlinks out of a venv. Normal editor saving fills only missing FAIRChem
backend_python fields; explicit Apply replaces those workflow overrides. Other
MLIP families and engines are preserved. The selected path is saved into YAML,
so CLI ChemRefine uses it too. No developer UMA path is hardcoded in app code.

Embedded Run panel shows editable per-step MLIP Python paths, disabled during
raw YAML editing. Pending typed fields are flushed before saving/running/applying
a default, so an immediate native button click cannot lose them. Raw YAML is
parsed/emitted if a default needs insertion. The default preference is local;
existing explicit workflow paths remain unchanged until the user applies one.

Final native /private/tmp/chemviewer-0104-native-final.log contains
UMA_ENVIRONMENT_SETTINGS_PASS + DASHBOARD_ACTIONS_PASS + WORKFLOW_RUNNER_PASS.
Checks cover persistence, folder resolution, default/override scoping, explicit
replacement, per-step editing, pending input and raw YAML; actual two-step
PySCF oracle and bottom Run/Resume/recovery gates still pass. Python29, core31
and three migrated suites, strict signature/ARM64 build26/0.10.4 pass. Actual
installed UMA import checker passed fairchem2.23.0/ChemRefine/server packages.
See docs/uma-environment-settings-2026-10-20.md. User's AGENTS.md changes remain
uncommitted and are excluded from this version.

## 0.10.5 — zigzag chains and visual ring palette

Fixed straight terminal chain placement: core suggestedBondAngle uses 120-degree
skeletal geometry and alternation (linear for triple bonds), with collision
clearance fallback. DrawingCanvas terminal drags use the nearest 120-degree
direction; Option permits other snapped angles. New Chain mode previews a
carbon zigzag locally and commits one undoable edit on mouse-up.

SketchRingTemplate holds 14 original explicit templates: benzene; saturated
3–8-membered rings; cyclopentene/cyclohexene/cyclopentadiene; pyridine/pyrrole/
furan/thiophene. Toolbar has original benzene/polygon glyphs, Chain glyph and
More rings visual grid. Formal charge tools moved to More and the neutral
preview caption was simplified; graph charges and transfer remain supported.
Legacy regular-ring API remains. Templates share a vertex when attached; no
automatic bond fusion is claimed.

Final /private/tmp/chemviewer-0105-native.log contains PERSISTENT_LABELS_PASS,
SKELETAL_DRAWING_PASS and DRAWING_LABELS_PASS: actual six-bond C7H16 zigzag
gesture, 120-degree angles, preview-only drag/one Undo, bent terminal horizontal
drags, all 14 rings placed/generated with independent formula expectations,
and existing Draw/labels/PNG/GIF/chirality/periodic-table/3D transfer regressions.
Core33 + three migrated suites, Python29 and strict signed ARM64 build27/0.10.5
pass. Before/after swift test was attempted; local CLT lacks XCTest, standalone
assertions passed. Actual zigzag-chain.png in Downloads drawing evidence was
visually inspected. No user scientific files changed; pre-existing AGENTS.md
edit is preserved/excluded from release. Details: docs/skeletal-drawing-2026-10-20.md.

## 0.10.6 — Draw automatic 3D preview lifecycle

User reported no update with Auto 3D checked. Original unsaved graph unavailable;
do not infer its exact failure cause. Fixed verified stale-preview cases and
strengthened scheduling/render refresh: explicit queued/error/version state,
revision-bound 400ms debounce detached before run cancels old work, immediate
empty-graph clearing, new local preview geometry IDs for same-count structures.
Draw now shows waiting/running/failure/Retry directly in preview; stale geometry
is dimmed and copy/transfer remains blocked until current. Chemical sanitization
is retained: invalid valence produces a visible failure, not fabricated 3D.

Final native /private/tmp/chemviewer-0106-native.log has
AUTO_DRAW_PREVIEW_PASS plus PERSISTENT_LABELS_PASS, SKELETAL_DRAWING_PASS and
DRAWING_LABELS_PASS. Actual rapid gestures auto-generate C6H14; a C2H6O same-count
ethanol/ether change matches the actual Metal scene and new geometry identity;
cancelled results are refused; synthetic invalid fluorine is rejected and
correcting it recovers; Clear removes old geometry. All prior 14 rings and Draw/
labels/PNG/GIF/chirality/picker/3D transfer gates pass. Core33 + migrated3, Python29,
strict signature and ARM64 build28/0.10.6 pass. No personal inputs/calculations
changed; user AGENTS.md remains excluded from release.

## 0.10.7 — configurable SSH files and remote ChemRefine / SLURM

RemoteConnection/RemoteConnectionView adds saved machine-agnostic profiles,
Terminal interactive authentication/private OpenSSH multiplexing, file browser,
automatic SHA-256 cache/refresh, conflict-checked text editing and exclusive-new-
folder workflow uploads. Remote Python accepts an executable or environment
folder; explicit non-login Bash setup is user-configurable. File menu CmdShiftO
and ChemRefine Remote/SLURM button open the same sheet. No credentials saved.

Original remote_bridge.py/remote_agent.py carry data via JSON and fixed quoted
bootstrap, honor SSH config/normal known-host checks, and bound request/cleanup
waits. Remote launch delegates to installed ChemRefine validation/start_run,
requires dispatch: slurm and sbatch/squeue, blocks missing input/template/engine/
header warnings, and leaves local runner restrictions unchanged. Run confirmation,
Resume, manual/Auto status, failures/survivors/cache/logs and actual Hartree rows
(up to20/step, Copy TSV) are provided. Cluster paths/headers/dependencies must be
configured remotely; uploads never rewrite Mac paths or install packages.

Final core33/migrated3, all42 Python (13new remote), strict signature and arm64
build29 pass. REMOTE_CONNECTION_PASS validates actual native sheet/profile/helper;
window-only screenshot inspected. REMOTE_LIVE_PASS uses bundled transport against
ORCD and opens checksum-matched synthetic H2 in native viewer at0.74Å. Real remote
ChemRefine2.0.0, Python and sbatch/squeue verified; supplied ~/home/home absent so
personal profile starts at verified ~. Live upload/list/cache/edit/re-read and
missing-ORCA preflight rejection pass; exact isolated fixture safely removed.
No actual SLURM jobs submitted; real scheduler/engine completion is still untested.
Login-shell inspection initially timed out; explicit Bash setup/lightweight probe
works. No user calculation changed or existing SSH session terminated.

Source tests RemoteConnectionSmokeTest/RemoteLiveSmokeTest are opt-in; live fixture
metadata/evidence resides only in Downloads, not repo. User's AGENTS.md change
remains preserved/excluded. See docs/remote-connections-2026-10-20.md and README.

## 0.10.8 — seamless SSH folder navigation

User reported folder changes slow/requesting new connection. Code diagnosis:
0.10.7 reused authentication/master but spawned local+SSH+remote Python command
for every operation; listing also stat-ed entries for sizes. Replaced app path
with RemoteSSHSession persistent framed RPC and remote_agent --chemviewer-serve
loop. Environment/imports stay warm; key host/Python/setup, not directory.
Native file cache retains basename/SHA-256/atomic replacement. Cached listings
last120s; explicit Refresh folder, Parent path reuse, metadata-light scandir,
connection timings/Disconnect added. No remote service/package installed.

45 Python cases pass; native REMOTE_SESSION_PASS validates reuse, per-request
error recovery, exact cached XYZ, cache/forced refresh and explicit reconnect.
REMOTE_CONNECTION_PASS native sheet captured/inspected. REMOTE_NAVIGATION_PASS
on ORCD measured first1282ms,warm11ms,cached0ms; identical remote PID,2network
requests, no scientific jobs/writes. User authenticated once in Terminal after
yesterday's master expired. The underlying master remains available to the user.

Development acceptance caught/fixed FileHandle length-oriented pipe blocking
and serve argv mistakenly placed outside Bash code. Exact-shell protocol test
now guards flag placement; POSIX read handles short replies. No automatic
mutation replay; stale replies guarded;90sdeadline+bounded child termination.
Strict signed ARM64 build30, core33/migrated3 pass. Previous0.10.7 CI success.
Evidence /private/tmp/chemviewer-0108-{python-final,validated-build,session-final,
navigation-final,sheet}.log; final native rechecks below use release-specific
filenames. User AGENTS.md edit is preserved/excluded from release. Real SLURM
calculation completion remains untested; this release changes transport only.

## 0.10.9 — persistent remote explorer, document tabs and ORCA inputs

DocumentTabs now owns separate WorkspaceStores per local URL / remote host:path.
File/Open multi-select and remote reads enter tabs; duplicate opens activate the
existing tab. DocumentTabStrip is above Image/Abstract/etc, horizontally scrolls
to activation and supports X/Cmd-W with dirty geometry/drawing protection.
RemoteExplorerView stays in the main left pane, lazily expands folders on the
same persistent channel and retains geometry/frequency explorer below. Settings/
SLURM are still available through its gear. Busy expansions queue, cancel/profile
changes guard stale replies. Settings change clears obsolete tree/editor context.

Loaded Image tabs reuse one Metal view/mesh. Main and Abstract camera/zoom/label
snapshots are per file; Draw has versioned preview state. New-source viewport
generations prevent a previous file's snapshot overwriting new bounds. Inactive
vibration/trajectory/Draw workers suspend. Detached renderer/coordinator/text
resources and closed model geometry/source/undo/previews are explicitly cleared.
Parsed open-tab data remains in RAM. No session restore across app quit; explicit
exports/calculation jobs retain their independent lifetime.

Core ORCAInputParser supports ordinary *xyz, inline Angstrom/Bohr (including
%coords Units option before star coordinates), D exponents, charge/spin and
explicit *xyzfile. Native remote opening fetches companions to individual caches
and supplies explicit filename mappings without rewriting source/directory paths.
No-input-geometry templates/internal/%coords can open as Source with limitation
messages. Extended/expressive atom rows and Bohr xyzfile are not converted.
Multiple blocks retain first-block spin/charge with a warning; no input SCF energy
is inferred. ParsedDocument adds optional charge/multiplicity.

Final build31/0.10.9 arm64 strict signature, core41standalone+3migrated, Python45
pass. Local swift test before/after still lacks XCTest (not a passing XCTest run).
DOCUMENT_WORKSPACE_PASS:50switches/one renderer+mesh, independent state/undo,
inactive timers, dirty close, actual Cmd-W, Source templates, Abstract restoration,
detached resources and closed data cleanup. Smooth pointer/label/PNG/GIF regression
passes. All persistent-label/skeletal/14-ring-formula/auto-preview/chiral transfer
native tests pass. Live REMOTE_TREE_PASS verifies tree, child expansion, remote
XYZ and ORCA xyzfile+companion in separate tabs, exact0.74Å synthetic H2/no inferred
energies/no jobs. Test preferences restored; exact isolated remote fixture safely
removed; existing user calculations/login untouched. Window captures inspected.

Evidence: docs/document-workspace-2026-10-21.md and /private/tmp/chemviewer-0109-*
logs; captures in Downloads document/remote evidence folders (excluded). Native
checks caught and fixed stale direct-load camera snapshots and retained closed
references before release. User AGENTS.md edits remain preserved/excluded. Previous
0.10.8 CI completed successfully. No actual remote SLURM calculation validation
was added; this is file/workspace/input-reader scope.

## Remote explorer recovery — 0.10.10 (2026-10-21)

Diagnosed sidebar initialization occurring only onAppear while busy requests
skip loading, plus delayed settings-sheet invalidation and hidden non-molecular
files. A cancellable connection-identity task now waits for busy operations and
loads absent root contents. Profile invalidation lives in the model, independent
of the sheet. All files initially visible, Home/Parent navigation, explicit
loading/empty/filter states, and minimum folder-list height added. Manual
Browse/Refresh remains available after errors without indefinite retries.

Final signed arm64 build32 passes 41 standalone core cases and three migrated
suites (XCTest remains unavailable with this CLT toolchain). Remote Python16
passes. Native REMOTE_EXPLORER_PASS verifies busy mount/reload of missing root
nodes/empty child/connection changes/helper reuse with isolated local fixtures.
REMOTE_SESSION_PASS verifies persistent RPC/cache/recovery/refresh integrity.
Live read-only ORCD sidebar displays the saved folder's10entries/9directories;
window capture inspected. Timing1169ms first/10ms warm/0ms cached, same remote
helper for timing requests. No jobs submitted or personal calculations modified.

Evidence: /private/tmp/chemviewer-0110-final-build.log, *-python.log,
*-explorer-final.log, *-session-final.log and *-live.log; scoped window captures
in Downloads/chemviewer-remote-evidence/{explorer-loading-regression,live-explorer-0110}.png.
User AGENTS.md edits preserved/excluded. Quit/reopen needed for installed update.

## Unified SSH/ChemRefine validation — 0.10.11 (2026-10-21)

Signed arm64 build33:41 standalone core regression cases plus3 migrated suites
pass. Full XCTest remains unavailable with the selected CLT toolchain; core
code was not changed. Python48 passes, including exclusive remote creation,
loopback forwarding/quoting, GUI bootstrap/EOF-owned shutdown, all six launch
actions using supported mocked APIs, and non-SLURM/missing-resource rejection.

Native live REMOTE_WORKFLOW_PASS: an exclusive synthetic water workflow created
on ORCD opens inside ChemRefine with dispatch:slurm, relative paths and no Mac
ORCA injection; remote GUI browse sees its files; form/template drafts are saved
remotely. Native Run and intercepted embedded Resume reject dispatch:local
before submission. Remote native file-picker and GUI window captures inspected.
No actual SLURM job submitted; scientific remote execution remains unvalidated.
Exact synthetic remote folder removed after seed-hash/home/prefix checks and
verification its own GUI process exited. Existing login/calculations untouched.

Local WORKFLOW_RUNNER_PASS and DASHBOARD_ACTIONS_PASS retain actual detached
two-step ChemRefine/PySCF H2 execution, saved draft/template handling, Run/Resume/
targeted rebuild/rerun, recovery monitoring and energy table. HF/STO-3G reported
-1.1167593074Eh. UMA environment/per-step controls and centered labels regressions
pass. Simplified SSH settings REMOTE_CONNECTION_PASS and explorer recovery
REMOTE_EXPLORER_PASS also pass on this Mac.

Evidence: /private/tmp/chemviewer-0111-final-release-build.log, *-python-all.log,
*-remote-final.log, *-local-final.log, *-settings-final.log, *-explorer-final.log;
Downloads/chemviewer-remote-evidence/{remote-chemrefine-tab,remote-workflow-picker,
remote-browser}.png. Local calculation evidence path is recorded in local-final.
User AGENTS.md changes preserved and excluded from release commits.

## Multiplex forwarding fix and explorer controls — 0.10.12 (2026-10-21)

Reproduced the user's disconnect with healthy HTTP200 and live GUI process while
the multiplexed forwarding setup child had already exited0. The old2-second
monitor treated successful setup as failure. Explicit -O forward/-O cancel now
tracks master-owned bindings; only the foreground GUI child is monitored as a
persistent process. Readiness waits for successful control-command completion.
An independent live proof cancels the exact listener while the GUI child remains
alive and leaves the user's SSH master untouched. No connection safety settings
changed. The previous0.10.11 startup test ended before its monitor caught this;
that startup gate did not establish sustained stability.

Explorer now persists Name/Extension sorting, keeps folders first, groups mixed-
case extensions, naturally orders numeric names, and sorts recursive children.
Double-clicking labels enters a folder; disclosure arrows still expand the tree.
Root navigation can wait behind active RPC without opening a new SSH login.

Build34/0.10.12 signed arm64:41 standalone core assertions +3 migrated suites pass;
Python48 pass. XCTest unavailable with selected CLT (core not changed). Native
REMOTE_EXPLORER_PASS verifies ordering/persistence and a real double-click located
from rendered text in its own window, folder entry and cached return on one helper,
plus existing busy-load/identity/missing-node checks. Capture inspected. Initial
accessibility-based test could not locate SwiftUI's lazy label; replaced with
window-scoped Vision text location and actual AppKit mouse events.

Final live REMOTE_WORKFLOW_PASS holds a valid unsaved draft20seconds across monitor
polls, verifies draft and HTTP survival after setup exits, remote form/template
saving, remote picker, SLURM defaults/local-dispatch rejection and forwarding
closure. An initial test draft used an invalid space-containing step name; fixed
the synthetic draft to valid underscores, then the full test passed. No actual
SLURM jobs submitted. REMOTE_SESSION_PASS retains persistent RPC/cache/integrity.
Exact synthetic remote fixtures removed with home/prefix/seed-hash guards and
owned-GUI-exit verification; personal calculations/login unchanged.

Evidence: /private/tmp/chemviewer-0112-final-build.log, *-python.log,
*-explorer2.log, *-remote-final.log, *-session-final.log, *-forward-proof.log;
Downloads/chemviewer-remote-evidence/{explorer-loading-regression,
remote-chemrefine-tab,remote-workflow-picker}.png (not committed).
AGENTS.md user changes preserved/excluded. Quit/reopen installed app for update.

## 0.11.0 / build35 — BossTMC catalyst screening (2026-10-21)

User requested a BossTMC tab for an HPC-hosted BosTMC property CSV with 43 columns
and singlets/doublets/triplets/quartets/quintets/sextets/refcode structure folders.
Implemented native tab with source-host background SQLite index, SSH/local source
and optional index-cache path, AND property screening, scalar/array/text/missing
criteria, sort/columns/pages, selected native Metal preview, copyable raw descriptors,
associated XYZ/Psi4/MOL2 source, independent viewer documents and streamed CSV export.
CSV energies/units remain raw; charge/multiplicity propagate to candidate documents.
Distinct CSV spin rows sharing XYZ do not merge; normal document identity unchanged.
No Psi4 results parser or activity predictor is claimed.

New files: BossTMCStore.swift, BossTMCView.swift, BossTMCSmokeTest.swift,
Resources/bostmc_catalog.py, python_tests/test_bostmc.py. The remote bridge embeds
the catalog resource into the existing persistent agent; no separate SSH login
per query and no full dataset download. Indexing is a source-host background
process, not a SLURM calculation; users choose a cache path appropriate to the HPC.

Validation:66 Python tests (18 new), signed arm64 mandatory build/core 41+3,
native BossTMC charge/spin and preview acceptance, document workspace regression,
persistent remote-session regression, real SSH synthetic catalog/filter/XYZ/source
lookup/CSV export with final verified cleanup; no scheduler jobs submitted.
Evidence: `/private/tmp/chemviewer-bostmc-python-release.log`,
`chemviewer-bostmc-release-native.log`, `chemviewer-bostmc-documents.log`,
`chemviewer-bostmc-remote-session.log`, `chemviewer-bostmc-hpc-final.log`,
`chemviewer-bostmc-release35-final.log`; native screenshot in
`~/Downloads/chemviewer-bostmc-evidence/bostmc-native.png`.

Pending: user has not supplied the actual CSV and dataset-root paths (async
question already asked). Actual schema encodings, real-record provenance and
production-size performance remain to validate. Do not claim actual BosTMC
screening succeeded from synthetic fixtures. Prior actual personal ChemRefine
workflow directories remain untouched. User's preexisting AGENTS.md edits are
excluded from the release commit.

Release v0.11.0 is installed in both Applications locations and published:
annotated tag points to a6fe227; main 4cd9ca1 adds whitespace-only cleanup.
Remote main and peeled tag were verified. Only the preexisting AGENTS.md edit
remains outside the commit. A supplementary attempt to locate/clean the first
synthetic HPC fixture timed out after45seconds; that initial fixture/cache may
remain. The final explicitly tracked test fixture was successfully cleaned.
Do not remove any user workflow directories to address this; only an exact
synthetic CSV/seed match and verified cache metadata may be removed.

## 0.11.1 / build36 — local BosTMC, SSH files, clean filters and graphs (2026-10-22)

User approved local downloaded CSV plus SSH files, removing full-molecule list/
XYZ/MOL2/geometric detail filters, readable labels, two-ended ranges and selected-
molecule property graphs. Actual source: ~/Documents/BosTMC/BOSTMC-complete.csv,
2.7 GB, 43 columns, 263,235 records. XYZ is embedded, so local native previews work
without SSH. New independent filesRemote toggle keeps remote source lookup only
on demand; native dropdowns and sliders use cached source-derived options/ranges.
Graphs show full-catalog histograms with selected marker, separate α/β orbital
levels in Eh, and dipole components in D. Scalar metal charge/spin fields retained.

Compact schema-v2 SQLite stores scalar columns and raw source record offsets;
bulky cells read by seek on selection/export, preserving all 43 original fields.
Do not remove/change the original CSV; reindex if changed. Import 33 s /283 MB;
backend first page 4 ms, tested filters 100–130 ms, histogram 29 ms. No Python analytical
package or new database dependency. Local mode suggests actual CSV when present.

Validation: 71 Python tests; mandatory signed arm64/core 41+3; actual-catalog native
acceptance, independent full CSV count/filter/raw-field/coordinate/dipole oracles,
synthetic native catalog charge/spin/source regression and persistent-session check.
Evidence in /private/tmp/bostmc-* and chemviewer-bostmc-hybrid-release36-final.log;
actual data and captures remain local, not committed. No HPC calculation submitted.
Saved BossTMCRoot points to /orcd/data/hjkulik/001/OpenTMC/gather_outputs/outputs_for_group.
A read-only live resolver request timed out after20s; actual HPC-output lookup is
not claimed. No source changes or scheduler submissions were made.
Existing AGENTS.md user edits must remain excluded from release commits.

Final native evidence: /private/tmp/bostmc-hybrid-actual-release3.log (also release2)
passes actual data plus both slider drags. Earlier release.log missed a synthetic
drag; test harness now explicitly activates/layouts its window before events.
Live resolver log: /private/tmp/bostmc-hybrid-live-resolve.log timed out20s. Source
CSV checksum/content not rewritten; independent scanner verifies all raw fields at
three IDs and exact combined8042 matches. Source index remains ready for the user.
