# Feature parity matrix

Status meanings: **Implemented** has source; **Tested** passed a meaningful test;
**Partial** handles a bounded subset; **Blocked** lacks required environment or
artifact; **Not started** has no implementation. “Implemented” does not imply
parity or daily-use readiness.

| Capability | macOS implementation | Test status | Gap / next acceptance test |
|---|---|---|---|
| Native ARM64 app bundle | Implemented build/package script | Blocked: no macOS host | Build, launch, reopen on Apple Silicon |
| macOS open panel | Implemented | Blocked: no macOS host | Open/deny/cancel and security-scoped URLs |
| XYZ single/multi-frame | Implemented | Swift test not run | Build on Mac; compare 23 installed XYZ files |
| ORCA Cartesian geometry | Implemented | Oracle tested | Compile Swift; compare all installed ORCA files |
| ORCA energies | Position-based frame association implemented | Oracle tested; new Swift test not run | Large multi-job/optimization corpus comparison |
| ORCA frequencies | Last compound-job section implemented for observed layout | Oracle tested; new Swift test not run | ORCA 5/6, NumFreq, OptTS, imaginary cases |
| ORCA mode vectors | Implemented for observed block layout | Oracle tested | Block paging, large molecules, missing modes |
| ORCA IR intensity | Implemented for observed layout | Oracle tested | Unit labels and additional ORCA variants |
| Metal atoms/bonds | Implemented prototype | Blocked: no macOS host | Depth, picking, Retina, 10k/100k atom benchmarks |
| Rotate/pan/zoom | Implemented; right-drag now matches Windows rotation, Option-drag pans | Blocked: no macOS host | Gesture/trackpad regression |
| Vibration animation | Implemented | Blocked: no macOS host | Visual/vector comparison against Windows |
| Displacement-vector arrows | Implemented in Metal | Swift/UI test not run | Direction/scale comparison against Windows |
| Imaginary-mode marking | Implemented | Swift test not run | Real TS fixture and sign convention |
| Geometry trajectory controls | Partial: frame selection and 0.5 s play/pause | Not tested | Mac playback, energies, convergence graphs |
| Atom selection | Implemented CPU screen-space picking and four-atom ordered selection | Swift/UI test not run | Retina/depth/overlap picking tests on Mac |
| Distance/angle/dihedral readout | Implemented with Windows sign/order convention | Python oracle passed; Swift test not run | Mac click-selection acceptance test |
| Bond selection | Not started | — | GPU ID-picking tests |
| Cartesian coordinate editing/undo | Partial: coordinate table and undo | Swift test not run | Mac UI test, export, multi-step undo |
| Internal-coordinate editing | Core bond-length operation only | Swift test not run | Angle/dihedral and fragment-side transforms |
| Fragments and symmetry | Not started | — | Clean-room fragment DB and symmetry tests |
| Gaussian parser | Not started | — | Geometry/frequency/fchk fixtures |
| Q-Chem/NWChem/GAMESS/Molpro/ADF | Not started | — | Per-format fixture matrix |
| CIF/PDB/SDF/Molden/VASP/QE | Not started | — | Per-format structural tests |
| Cube/volumetric parser | Not started | — | Grid/unit/endian validation |
| MO/density/ESP surfaces | Not started | — | Marching-cubes numerical/visual tests |
| Orbital energy diagrams | Not started | — | Occupancy/spin/energy comparisons |
| IR spectrum plots | Partial: sticks plus Gaussian/Lorentzian broadening | Swift test not run | Export and Windows contour comparison |
| Raman spectrum plots | Not started | — | Activity-to-intensity conversion and laser units |
| TDDFT/UV-vis/CD/NMR | Not started | — | Property-specific fixtures |
| PES/IRC/NEB | Not started | — | ORCA 6 reaction-path validation |
| Tables and data export | Not started | — | Round-trip and unit tests |
| Image/animation export | Not started | — | Pixel/metadata/frame tests |
| xTB integration | Not started | — | Version capture and reference calculations |
| Official Mac ARM repair | Static artifact inspected; runtime blocked | Missing target Mac/crashes | Run diagnostic collection on target Mac |
| Official Mac Intel/Rosetta | Static artifact inspected; runtime blocked | Missing target Mac | Architecture and workflow matrix |
| Windows GUI reference audit | Partial, evidence-backed | Menus, XYZ, camera, measurements, ORCA modes/trajectory, orbital dialog, exports, Gaussian PES tree and IRC roots observed | Focus-safe IRC retest, IR activation, vector incident, complete NEB and ORCA OptTS fixture remain |
| Deep REA native audit | Partial: Ghidra 12.1.4 analyzed immutable PE | Protector blocks feature mapping | Authorized runtime evidence or unprotected vendor build |

## Release gate

A feature can move to **complete** only when its implementation is exercised on
Apple Silicon, scientific outputs match an independent oracle/reference within
documented tolerances, interactive behavior has a reproducible GUI procedure,
and limitations are recorded. The present repository does not meet the release
gate for daily full-parity use.

## Local Mac validation update (2026-10-19)

The table above contains historical Windows-session statuses. ARM64 packaging and strict signature checks now pass on this Mac. Eleven standalone core regression methods and the packaged live-Metal integration check pass; genuine XCTest is still unavailable under Command Line Tools. XYZ/ORCA parsing, Windows line endings, frequency geometry binding, negative-mode data, coordinate undo, selection propagation and animation/pause have automated local evidence. Human-visible rendering/gesture/dialog rows remain pending; no full-parity release is claimed. See `mac-validation-2026-10-19.md`.

## Rendering and interface revision (0.2.0)

Image/Abstract/Source/Coord/Image/Abs are now implemented; summary navigation, source viewing, coordinate Apply/Undo, camera controls and display schemes are exposed. GPU atoms/bonds now have true depth, shaded meshes and antialiasing. Viewport PNG export and order-independent atom overlap passed packaged automated checks. Actual tab screenshots were inspected; physical gesture/dialog acceptance and large-system performance remain pending. Fragment building and the remaining scientific feature matrix are still incomplete. See `rendering-and-ui-2026-10-19.md`.

## 0.3.0 energy/editing update

Implemented: ORCA SCF/final-energy provenance, XYZ comment energies with explicit unit selection, Abstract energy/structure browsing, arrow navigation, unlimited selection, second-only/symmetric distance editing, A–B–C angle editing, per-geometry Undo and Matplotlib energy-profile export. Sixteen core cases, three plotting tests and packaged control/GPU workflow checks pass locally. Full manual gesture/dialog acceptance, multidimensional PES inference and bonded-fragment propagation remain outside this update. Details: `energy-and-editing-2026-10-19.md`.

## 0.4.0 update

Implemented and locally exercised: ORCA enthalpy/Gibbs/ZPE extraction and complete-correction sums, clean numeric Abstract copying, coordinate TSV/XYZ copying, right-click deselection, symmetric angle editing, atom/connected-fragment/whole-geometry dragging, boundary-pair fragment detection, ±X/Y/Z rigid rotation/translation, pivot choice and one-step gesture undo. Nineteen core cases and all three packaged workflow checks pass. Fragment construction/manual bonds and arbitrary ring subgroups remain unfinished. See `thermochemistry-and-manipulation-2026-10-19.md`; historical earlier table statuses are superseded only for these bounded features.

## 0.5.0 update

Optional bond-length/angle/signed-dihedral overlays and PNG annotations are implemented and locally exercised. Four-atom measurement has an explicit panel readout. Mouse grab rotation is corrected, per-event document updates removed, and static GPU-instanced meshes replace CPU triangle regeneration. Nineteen core cases and four packaged workflow checks pass. Local 500-atom CPU submission median 17.05 → 1.17 ms; broad large-system/manual input acceptance remains pending. See `measurements-and-smooth-drag-2026-10-19.md`.

## 0.6.0 update

Paton is the default native appearance; all prior styles remain selectable. Multi-geometry and normal-mode GIF export now share the Metal renderer and preserve the current viewing angle, with fixed full-animation framing, configurable size/rate, looping, ping-pong and cancellation. The Paton implementation adapts xyzrender styling rather than invoking its SVG engine. Programmatic native-Mac export and interaction checks are recorded in [the release notes](paton-and-gif-2026-10-19.md); broad manual acceptance and full parity remain pending.

## 0.6.1 — uniform shading by distance

At the user’s request, depth fog is disabled for both atoms and bonds. The shared native render path now sends zero fog weight, so farther objects retain the same element colors and surface gradient as nearer objects. This applies to the viewport, PNGs and GIFs. Paton palette, outlines and radial shading remain. Verify by rotating a deep structure and comparing near/far atoms of the same element. This supersedes the 0.6.0 depth-fog behavior.

## 0.6.2 — measurement labels and slower GIFs

Select 2 atoms for length, 3 for angle (B is the vertex in A→B→C), or 4 for a signed dihedral, in order. Choose File → Export Animation as GIF… and enable **Include measurement label and guides**. The current ordered selection supplies one measurement per GIF. Its numeric value and projected guides are recomputed from each frame's actual coordinates, including sinusoidal frequency displacements. Labels use Å or degrees, retain the viewer’s angle, and use the same guide/dihedral-plane drawing as the native view. The toggle starts enabled when the viewer’s measurement overlay was enabled. Labels require stable atom ordering and matching element sequences across trajectory frames. If a selected angle/dihedral is undefined in a frame, export reports an error rather than writing a misleading value; temporary output is removed and any existing destination remains intact.

Playback speed offers Normal, Half, Quarter and Eighth; Half is the new dialog default. Frame-rate choices now include 1 and 2 fps. Every frame is retained; GIF delay is `1 / (fps × speed)`, with an approximate loop duration shown. GIF centisecond quantization/player behavior may slightly change actual timing. These choices apply to both trajectories and frequencies. Display speed remains illustrative, not physical vibrational time. Coordinates, amplitude and camera orientation are unchanged.

## 0.7.0 MoleculeView integration

The full reconciliation of the two independent apps' implemented features is in [moleculeview-integration-2026-10-19.md](moleculeview-integration-2026-10-19.md). Fragment templates/import/attachment, topology editing, legacy/new saved projects, redo, bond-axis numeric transforms, captions/H visibility, live speed, Gaussian geometries, earlier compound-job mode association and classic shell are now in ChemViewer, retaining its previous analysis, editing, rendering and GIF features. This unifies the implemented features of both apps; it does not claim complete Chemcraft parity.

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

### 0.8.2 XYZ energies
ORCA trajectory comments with whitespace-separated `E <value>` are recognized in addition to `Energy=` fields. Tested with synthetic frame/provenance and exponent regressions and every energy in the reported 12-frame trajectory; user data remains local.

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

## Draw and persistent labels — 0.10.0

| Capability | Implementation | Validation / boundary |
|---|---|---|
| Multiple persistent distance/angle/dihedral labels | Per-frame pins independent of selection; individual remove/drag; PNG and GIF | Native four-label/deselect/tab/drag/export and geometry-update/undo gate |
| Full Draw tab beside ChemRefine | Native 2D canvas and Paton 3D preview | Native mouse-drawn ethanol and benzene → real RDKit 3D + completed Metal frames |
| Explicit drawing chemistry | Single/double/triple bonds, rings, elements, charge, wedge/dash | Core graph and Python formula/geometry/stereo oracles |
| Local 2D → 3D | RDKit ETKDGv3 + optional UFF, explicit H | One conformer; full conformer search and quantum optimization not claimed |
| Drawing import/save | SMILES, Clean 2D, own graph JSON, copy SMILES/XYZ | Chiral/E/Z/explicit-H/radical round-trip tests; no MolDraw design-file compatibility |
| Persistent draft and cancellation | Independent drawing history; background revision-checked process | Native tab/undo/redo/auto-preview/immediate-cancel/undoable viewer transfer |

Pins persist in the current open session per geometry. Loading another document
starts a fresh annotation set; .cvproject does not yet serialize labels. Deleting
an annotated atom removes the affected annotation, with geometry Undo restoring
it. Unsupported isotopic input is rejected rather than losing isotope metadata.

## Centered captions and executable ChemRefine workflows — 0.10.1

| Capability | Status/evidence | Boundary |
|---|---|---|
| Atom numbers/element labels centered on spheres | Native pixel bounds for H/I/Cl/O12/Ru123 and projected atom centers; actual PNG inspected; GIF regression passed | Common renderer path for viewport/PNG/GIF, no caption background boxes |
| Native Run ChemRefine | Actual detached two-step PySCF calculation, energy/result files, live log/status, server-shutdown survival | Full run from step 1; recovery/Resume remains in embedded editor |
| Save current editor before run | Native unsaved basis change and new second step/template tested | YAML saved before template so newly added steps resolve correctly |
| Workflow readiness | 11 Python runner tests; missing inputs/templates/ORCA/weights/backends and GPU budget refusal | Checks declared engine requirements; custom Python templates can have additional imports/runtime requirements |
| Backend installation | Real isolated PySCF backend provisioned; selected missing extras only | UMA/other gated weights still require user access; unused backends are not preinstalled |
| ORCA execution | Blocked on this Mac: user confirmed not installed | Official installer/account download required; no real ORCA/MPI calculation claimed |

## ORCA 6.1 installation compatibility — 0.10.2

- Complete 6.1.1 helper layout accepted; legacy helper layout retained.
- Missing required job header blocks execution before a driver is launched,
  including local dispatch.
- Chemistry integration suite: 26 tests passed, including both helper layouts
  and missing-header launch refusal. ARM64 build/core and native workflow gates
  passed. See the current execution validation record for actual engine runs.

Actual native serial ORCA 6.1.1 H2 HF/STO-3G pipeline now passes: normal
termination, one survivor, zero failures, -1.116759307204 Eh; independent
PySCF reference differs by 1.9243e-10 Eh. UMA CPU single point independently
matches fairchem and stretched-H2 optimization converges. These supersede the
0.10.1 ORCA installation blocker; parallel ORCA/MPI remains untested.

## ChemRefine dashboard — 0.10.3

Bottom-right Run/Resume/recovery now display native confirmations and use the
same live-editor save/check/model/ORCA environment path as native Run. Optional
step targets are preserved for targeted actions; run locks remain owned by
ChemRefine. A step summary shows names/fallback Step N, engine/status, minimum
reported energy, units, energy type and conformer/count. Missing results stay
blank; prior unsuccessful-cache rows are labeled previous. Unit selector and
copy table supplement existing per-conformer results. Upstream files unchanged.

## UMA environment selection — 0.10.4

Native persisted default/picker/check/apply and editable per-step MLIP paths are
implemented. Default-only filling preserves explicit overrides and other engine
families; explicit apply intentionally replaces current workflow UMA paths.
Raw YAML insertion and pending typed-input flushing are supported. The actual
installed UMA interpreter/imports were checked successfully; model readiness is
still performed at run time. See uma-environment-settings-2026-10-20.md.

## Skeletal drawing improvements — 0.10.5

Tested zigzag carbon-chain dragging and 120-degree terminal extensions, local
preview/one Undo, visible benzene/saturated ring glyphs and a 14-template ring
palette including unsaturated/heterocyclic structures. All 14 placed templates
passed native local 3D generation with independent expected formulas. Formal
charge editing is under More; source charge data is retained. This adds regular
ring/vertex attachment, not automatic bond-fused rings or full ChemDraw parity.

## Draw preview reliability — 0.10.6

Native-tested automatic rapid chain edits, same-count ethanol/ether isomer
changes verified against actual Metal scene atoms/geometry ID, cancelled-result
refusal, invalid-valence error/recovery and clearing old geometry. Queue, running
and generation errors are visible in the 3D panel; stale geometry is dimmed and
transfer remains disabled. This does not generate a valid conformer for invalid
chemical connectivity; such inputs are reported and can be corrected/retried.

## SSH access and remote SLURM — 0.10.7

Implemented configurable saved SSH profiles; interactive Terminal authentication;
remote directory browser; automatic file caching/refresh; explicit text editing;
new-folder workflow uploads; remote environment/preflight checks; detached
ChemRefine Run/Resume; manual/10-second status refresh and copied Hartree results.
Unit transport/API tests use local fixtures and mocked dispatch, not a scheduler.
A native macOS sheet acceptance test passes; live ORCD authentication, Python/
ChemRefine 2.0.0, scheduler-command availability and home listing were verified.
See remote-connections-2026-10-20.md for final transfer evidence and limitations.
No actual SLURM calculation has been submitted/validated by this release; cluster
headers, engine paths and dependencies remain user-configured. This is cached
file access, not a mounted remote filesystem, and companion files are not synced.

## Remote navigation responsiveness — 0.10.8

Tested persistent SSH/Python RPC channel, two-minute recent-folder cache with
explicit Refresh, reduced directory metadata work, connection/timing indicator
and explicit Disconnect. Native tests verify reuse/error recovery/cache/refresh/
file integrity/reconnection. Live ORCD same-process requests measured1282ms first,
11ms warm and <1ms cached in one sample; folder/server conditions may differ.
Authentication expiry still needs login. No new SLURM scientific execution
validation is claimed; no jobs were submitted for these performance checks.

## File workspace — 0.10.9

Native-tested persistent remote tree with geometry/frequency explorer retained,
XYZ/output/ORCA-input document tabs, local multi-file opening/dedup and remote
host/path dedup.50loaded switches share one renderer/mesh while preserving
camera/zoom/labels/selection and independent edits/undo/drawings. Inactive workers
pause; detached GPU/text state and closed document data are cleared. Cmd-W closes
the active tab; unsaved geometry/drawing close is guarded. Data remains in RAM
for open tabs; tab/session restoration after quit is not implemented.

ORCA *xyz Cartesian, inline Bohr conversion, charge/spin and explicit xyzfile
companions are parsed. Live ORCD test opened remote XYZ and an input with its
companion as separate tabs without a modal. Templates/internal/%coords can show
Source; expression/annotated rows and Bohr xyzfile are not converted. Multi-input
charge/spin apply to the first block with a visible warning. No input energies
or real SLURM execution are inferred/claimed. See document-workspace-2026-10-21.md.
