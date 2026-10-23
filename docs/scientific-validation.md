# Scientific validation

## Rules

- Preserve values and units exactly at parse time.
- Never synthesize coordinates, energies, intensities, orbitals, or scan points.
- Treat IR intensity, Raman activity, oscillator strength, and rendered
  animation amplitude as distinct quantities.
- Retain imaginary frequencies as negative values.
- Compare scientific values before visual presentation or unit conversion.
- Require a regression test and a traceable fixture before marking a parser
  feature tested.

## Current validated case

Fixture: installed authorized ORCA water compound-job output.

| Quantity | Expected | Actual | Tolerance | Result |
|---|---:|---:|---:|---|
| Final atom count | 3 | 3 | exact | Pass |
| Final elements | O,H,H | O,H,H | exact | Pass |
| Final energy (Eh) | -76.360968646 | -76.360968646 | 1e-9 | Pass |
| Mode count | 9 | 9 | exact | Pass |
| Mode 6 (cm⁻¹) | 1606.12 | 1606.12 | 0.01 | Pass |
| Mode 7 (cm⁻¹) | 3678.02 | 3678.02 | 0.01 | Pass |
| Mode 8 (cm⁻¹) | 3777.72 | 3777.72 | 0.01 | Pass |
| Mode 6 IR value | 45.965085 | 45.965085 | 1e-6 | Pass |
| Mode 6 O-z vector | -0.070076 | -0.070076 | 1e-6 | Pass |

The observed ORCA table labels `45.965085` as `T**2`. The model retains that
source value for relative IR rendering; no physical-unit conversion is inferred
from the fixture.

Commands executed on the Windows evidence host include the ORCA oracle and a
static Mach-O artifact regression:

```text
py -3 -m unittest discover -s python_tests -v
```

All four portable test methods pass: the independent Python scientific oracle,
compound-job and geometry-energy regressions, and the static ARM/Intel Mach-O
inventory check. Swift tests exist for XYZ, ORCA
frequency/vector parsing, imaginary-mode classification, energy parsing, bond
inference, spectral broadening, compound-job section selection, positional
energy association, Cartesian translation, bond-length editing, and the
Windows distance/angle/dihedral convention, but remain
**not run** until a Swift/macOS toolchain is available. Visual agreement with
Windows ChemCraft also remains pending.

## Windows GUI measurement oracle

Clean-room fixtures were measured independently and in the Windows reference
GUI. The GUI displayed an O-H distance of `0.95720` Angstrom, an H-O-H angle
of `104.520` degrees, and a signed four-carbon dihedral of `116.565` degrees.
The pytest oracle reproduces these values at the displayed precision; all four
GUI harness tests pass. The values are stored in
`Tests/references/windows/gui-scientific-reference.json` and are Swift core
acceptance tests for ChemViewer.

## Planned validation set

1. ORCA 6 optimization, OptTS/frequency, NEB, IRC, relaxed scans, orbitals, and
   `.hess` isotope recomputation.
2. Gaussian optimization/frequency, formatted checkpoint, cube, TDDFT, NMR.
3. Multi-frame XYZ and large trajectory stress cases.
4. Q-Chem, NWChem, GAMESS, Molpro, ADF, VASP, and Quantum Espresso samples.
5. Cross-check of coordinates, energies, units, mode vectors, intensities,
   spectra contours, and exported structures against Windows ChemCraft.

## Local Mac results (2026-10-19)

The previously unrun core cases now pass via the Command Line Tools standalone runner, extended to 11 methods. Genuine XCTest remains unavailable locally. Native Swift parsing of the authorized CRLF water output now matches the independent Python oracle for all six three-atom geometries, source energy, nine modes, frequency and mode-vector checks. Regression coverage includes line endings, geometry binding, missing compound-job matrices/intensities, incomplete vectors and nonfinite coordinates. Details and tolerances are in `mac-validation-2026-10-19.md`.

## Rendering-only changes (0.2.0)

Eleven standalone core regression cases still pass. Styling leaves source coordinates, energies, frequencies and vectors unchanged. A packaged GPU test checks front oxygen/rear nitrogen occlusion with both atom orders. Large spheres is a graphical approximation and must not be used as a physical van der Waals surface. The new Abstract view reports only existing parsed properties. Details: `rendering-and-ui-2026-10-19.md`.

## 0.3.0 validation

Sixteen standalone Swift core cases and three Matplotlib tests passed. New independent oracles cover CODATA energy conversions, XYZ energy units/provenance/export, distinct SCF versus final energy, symmetric/fixed distance coordinates, and analytic 60° angle coordinates with preserved adjacent lengths. Packaged checks confirm edited geometries/export do not retain old calculated energies and Undo restores them. Figures retain input order and missing-data gaps. See `energy-and-editing-2026-10-19.md` for actual test commands, synthetic-fixture provenance and scope.

## 0.4.0 update

Nineteen standalone core cases pass, including analytic symmetric angle/rigid transform oracles and full thermochemistry corrections. Installed ORCA water H/G/temperature/frame mapping and final-electronic-energy sums passed separately. Mouse-handler tests validate rigid atom membership and one Undo per drag; corrected clipboard tests use a private named pasteboard. Primary source, fixture values, precision and the initial clipboard-test incident are documented in `thermochemistry-and-manipulation-2026-10-19.md`.

## 0.5.0 update

Measurement overlays reuse existing distance/angle/dihedral functions with visible positions and preserve source/editor coordinates. Packaged evidence verifies 1.54000 Å, 120.000°, and signed 116.565°, overlay toggles, PNG composition and unchanged coordinates during camera rotation. Local preview tests check exact pointer tracking, zero per-move document publications and one commit/Undo. Core algorithms remain unchanged; nineteen standalone cases pass. Performance details and limits are in `measurements-and-smooth-drag-2026-10-19.md`.

## 0.6.0 GIF scientific semantics

Trajectory GIFs use parsed coordinates in order with no interpolation. Frequency frames use p + A·d·sin(2πi/N); synthetic signed-mode extrema are checked against 1.32 and .48 Å for a .9 Å base, .7 displacement and .6 display amplitude. Display speed is explicitly illustrative. Camera copying and constant envelope fitting do not transform scientific coordinates. Independent ImageIO reopen validates GIF metadata, frame variation and size; all styles render on the native GPU. Details: paton-and-gif-2026-10-19.md.

## 0.6.1 — uniform shading by distance

At the user’s request, depth fog is disabled for both atoms and bonds. The shared native render path now sends zero fog weight, so farther objects retain the same element colors and surface gradient as nearer objects. This applies to the viewport, PNGs and GIFs. Paton palette, outlines and radial shading remain. Verify by rotating a deep structure and comparing near/far atoms of the same element. This supersedes the 0.6.0 depth-fog behavior.

0.6.2 measurement GIF regression: exported frequency lengths are checked at .9 Å equilibrium and 1.32 Å positive displacement. Synthetic perpendicular vectors independently establish a 1 Å length, 90° angle and |90°| dihedral. Encoded GIF guides are checked by teal-pixel detection. A 10 fps export at quarter speed must decode to .4 s/frame with unchanged frame count and sinusoidal coordinates. The camera/document, cancellation, palette and ordinary GIF checks remain enabled. Manual dialog readability across all resolutions remains a human acceptance item.

## 0.7.0 integrated builder validation

Original parser/editing/project regression suites now run inside the namespaced migrated code. New core cases independently check 1.52 Å ethane attachment, 8-atom composition, inserted indices and remapped groups, 90° rigid transforms, invalid projects/dummy exports and Gaussian coordinates. Spatial bond search is compared with the former all-pairs distance definition on a synthetic 120-atom fixture. Calculation energies/modes are invalidated by topology edits; Undo restores prior scientific state. Per-frame earlier modes are associated only with their preceding job geometry. See the migration document for coverage and limits.

## 0.8.0 — detected NEB reaction profiles and optional markers

The energy sheet now auto-selects a complete ORCA NEB/NEB-TS path-summary dataset, separate from Cartesian optimization history. It defaults to a reactant/refined-TS/product diagram; all images and ordinary PES lines are also selectable. Forward/reverse barriers use the explicit refined TS and printed relative energies, not the highest CI or rounded-Hartree subtraction. Structures are taken only from validated optional companion files. All scatter markers can be turned off. PDF/SVG/PNG/CSV/JSON exports include provenance. See docs/neb-reaction-profiles-2026-10-19.md for scientific semantics, implementation, tests and limitations.

## Native ORCA and UMA validation — 0.10.2 (2026-10-20)

Native ORCA 6.1.1 at
`/Users/nacho/Documents/software/orca_6_1_1_macosx_arm64_openmpi411/orca`
completed the independently generated neutral-singlet H2 single point at 0.74 A,
using serial conventional HF/STO-3G with TightSCF. The actual workflow bridge
launched ChemRefine's detached driver; ORCA printed `ORCA TERMINATED NORMALLY`,
and ChemRefine recorded one survivor, zero failures and completed pipeline.
Its steps.csv energy is -1.116759307204 Eh. Independent PySCF 2.14.0 conventional
RHF/STO-3G gives -1.1167593073964255 Eh; absolute difference 1.9243e-10 Eh.

The user approved each macOS component prompt (driver, bundled tools library,
startup, guess, leanscf and properties as encountered). No security controls or
quarantine attributes were modified. ORCA runs in its unpacked folder. Terminal
login-shell configuration sets ORCADIR/PATH; ChemViewer's chosen executable is
persisted. Both installed app copies are 0.10.2/build24; quit/reopen to refresh a
running session. Parallel ORCA/OpenMPI is not installed or tested by this work;
this validation uses one CPU. Other methods may invoke additional helpers that
macOS still asks the user to approve.

The existing Conda UMA environment (fairchem-core 2.23.0, torch 2.13.0, ASE 3.29.0)
was connected to the same pinned ChemRefine source; dependency check passes.
Existing Hugging Face authentication authorized `uma-s-1p2` (omol head, CPU).
H2 single point at 0.74 A: -1.1608742095228168 Eh, identical to independent
fairchem ASE inference (-31.58899624105755 eV converted with ASE's Hartree).
UMA LBFGS optimisation starting at 0.90 A converged to 0.7411425064135867 A and
-1.1608751163763043 Eh with max force about 0.0005093 eV/A (target 0.01).
Both actual ChemRefine runs have one survivor and zero failures. UMA and
HF/STO-3G are different models: their absolute energies are not compared as an
accuracy claim. The UMA workflow explicitly selects the user's existing Python
via options.backend_python; it does not replace fairchem/torch or install every
optional backend. Weights remain in the user's normal fairchem cache.

Reproducible synthetic inputs, templates, outputs, preserved failed attempts and
verification JSON: `~/Downloads/chemviewer-h2-orca-uma-20261020`. These and vendor
binaries/credentials are excluded from git. Local release checks: 26 Python
chemistry tests, 31 standalone core cases plus three migrated suites, signed
ARM64 build, and actual native two-step PySCF runner/editor gate all passed.
Logs: `/private/tmp/chemviewer-0102-{python,build,native}.log`. Genuine XCTest is
unavailable with the selected local Command Line Tools; CI uses full Xcode.

## ChemRefine dashboard acceptance — 0.10.3 (2026-10-20)

The embedded Run action was invoked through the actual editor launch function,
with its real native confirmation sheet accepted by the native test. Unsaved
6-31G -> STO-3G changes and a newly added second step/template were flushed
before launch. Both independent H2 conventional HF/STO-3G steps completed with
-1.1167593074 Eh, one survivor and zero failures. Actual bottom Resume, targeted
Rebuild cache and Rerun errors also passed through confirmations/native routing
and completed. The final recovery driver survived termination of its editor
server. Per-action target dispatch for all six actions is covered by Python
tests; Rebuild NMS requires a real NMS-configured workflow and is not claimed
scientifically exercised here.

The actual WK-rendered step table showed Step 1 and refine with their real
energies/status and units. Its kcal/mol display matched the independent core
CODATA conversion oracle; the original upstream progress table was also checked
for fresh successful-cache/survivor state after a fast run. A direct WK snapshot
was visually inspected at ~/Downloads/chemviewer-runner-evidence/workflow-dashboard.png.
A prior desktop capture showed the user's editor instead and is not visual
evidence of this feature.

Final local gates: 28 Python chemistry integration tests; 31 standalone core
cases plus three migrated suites; signed ARM64 release build; native action/
confirmation/editor-save/energy-table and unit-conversion acceptance. Genuine
XCTest is unavailable in the selected local Command Line Tools. Evidence:
/private/tmp/chemviewer-0103-python.log, chemviewer-0103-build.log,
chemviewer-0103-native-verified.log; synthetic real-pyscf-D85B504E under
~/Downloads/chemviewer-runner-evidence. No personal calculation was rerun.

## UMA Python settings validation — 0.10.4 (2026-10-20)

29 Python chemistry integration tests pass, including selected interpreter/folder
resolution, import-check dispatch and invalid paths. The actual installed UMA
environment passed the new checker: Python environment prefix was correct,
fairchem-core 2.23.0 and compatible ChemRefine imported, and ExtOpt server
packages were available. This import check does not claim a new UMA calculation.

Native acceptance passed persistent-setting/directory resolution, default-only
filling, preserved explicit overrides, non-FAIRChem/other-engine exclusion,
explicit replacement, actual visible per-step editing, pending-input flushing
and raw YAML insertion. The original live editor config and user preferences
were restored after synthetic checks. The same test then passed actual bottom
Run/Resume/targeted recovery, unsaved editor/template saving, a real two-step
PySCF H2 HF/STO-3G oracle (-1.1167593074 Eh), energy table/unit conversion and
detached recovery/editor-server survival. Core31 and three migrated suites,
strict signature and ARM64 release build pass. No personal calculation was run.
Evidence: /private/tmp/chemviewer-0104-python.log, chemviewer-0104-build.log,
chemviewer-0104-native-final.log; real-pyscf-CECAC37C under
~/Downloads/chemviewer-runner-evidence. No vendor binaries or model credentials
are part of the source release.

## Skeletal drawing — 0.10.5

Core33/three migrated suites and Python29 pass. Native mouse gestures verify
120-degree zigzag chains with 48-unit bond lengths, one Undo and C7H16 3D
generation. All 14 explicit ring templates passed native placement and RDKit
3D generation with independent expected formulas (including pyridine C5H5N,
pyrrole C4H5N, furan C4H4O and thiophene C4H4S). Existing native Draw, charged
atom editing, chirality, UFF/Metal preview and persistent label/PNG/GIF tests
also pass. Selected local CLT still lacks XCTest; genuine before/after attempts
were recorded, and the standalone adapter executed actual core assertions.
See skeletal-drawing-2026-10-20.md for exact scope and evidence.

## Draw automatic preview — 0.10.6

Native AUTO_DRAW_PREVIEW_PASS checks real RDKit automatic generation and actual
Metal scene updates: rapid edits produce hexane C6H14; ethanol-to-dimethyl-ether
changes retain C2H6O/9 atoms but update the displayed atom sequence and geometry
identity; an obsolete cancelled result cannot replace current geometry. An
intentionally over-valent fluorine is rejected and reported, then correction
automatically recovers. Clearing the graph immediately removes the old preview.
The existing 14-ring, chain/Undo, persistent labels/PNG/GIF, chirality, periodic
picker and 3D transfer tests pass too. Core33/three migrated suites, Python29
and signed ARM64 build pass. Evidence: /private/tmp/chemviewer-0106-native.log,
chemviewer-0106-python.log and chemviewer-0106-build.log. The user's original
unsaved failing drawing was unavailable; no specific invalid valence is inferred
for that session from the synthetic rejection test.

## Remote transport — 0.10.7

No parser, energy conversion or geometry algorithm changed. Remote transfers
must preserve source bytes/SHA-256; cached files go through the existing parser.
Thirteen hermetic tests cover quoting, environment-folder resolution, cached
refresh, changed-file edit refusal, upload isolation, missing-input/SLURM/local-
dispatch refusal, supported Run/Resume calls, actual CSV energy/name retention,
environment inspection and timed-out process cleanup. Mocked launch is explicitly
not a calculation or scheduler-success assertion. Native remote-sheet acceptance
checks persisted profiles, bundled authentication helper and invalid-host errors.
Core33 plus three migrated suites and all 42 Python chemistry/drawing/workflow/
remote cases pass; strict signed ARM64 packaging passes. Live ORCD evidence and
limits are in remote-connections-2026-10-20.md. No user calculations were rerun.

## Persistent remote transport — 0.10.8

All 45 Python regressions pass (16 remote). New cases exercise multiple requests
and error recovery in one actual helper process, and execute the exact generated
SSH shell command locally without sending stdin EOF. This catches passing the
serve flag to Bash rather than Python. Native REMOTE_SESSION_PASS verifies one
process for parent/child/error/read, exact XYZ bytes and basename in the native
cache, cache-only returns, explicit refresh after directory changes, and
disconnect/reconnect. The real native pipe test caught a length-buffered read
stall during development; release uses immediate POSIX pipe reads.

Packaged REMOTE_NAVIGATION_PASS on authenticated ORCD measured initial1282ms,
warm uncached11ms and cached0ms (integer timing), with identical remote helper PID
and exactly two network requests. It listed the saved starting directory only;
no jobs, chemistry calculations or remote file writes were performed. This is a
single live timing sample, not a universal performance bound. REMOTE_CONNECTION_PASS
checks the actual updated sheet; its window capture was inspected. Signed arm64
build, 33 standalone core cases and three migrated suites pass; local XCTest is
still unavailable under CLT. No scientific parser/model/conversion changed.

## ORCA inputs and document isolation — 0.10.9

Eight additional independent core cases cover Cartesian elements/indexing and
charge/spin;2Bohr→1.058354421806Å (1e-6Float tolerance); Fortran exponents; quoted
XYZ references; relative-file and explicit remote-cache mapping; source-only
templates/internal forms; rejection of nonfinite/unclosed/invalid-spin/ambiguous
units; and multiple input geometries without fabricated energies. Core41cases
pass through the explicit standalone adapter, plus3migrated suites. Before/after
swift test attempts still fail because local CLT lacks XCTest; these are not
reported as successful XCTest runs.45Python cases pass.

Native DOCUMENT_WORKSPACE_PASS covers50loaded switches with one renderer/mesh,
view/selection/label restoration, inactive timers, independent edit/undo/drawing
state, dirty-close refusal, actual Cmd-W dispatch, template Source, Abstract
restoration and closed-document data cleanup. Existing smooth-pointer/label/
PNG/GIF regression and full persistent-label/skeletal-drawing/auto-preview/chiral
import regressions pass. Live REMOTE_TREE_PASS verifies persistent root/child
listing and separate remote XYZ/input tabs with explicit companion retrieval,
exact0.74Å synthetic H2 and no inferred energies. No jobs were submitted; real
SLURM chemistry completion remains outside this validation. Detailed evidence:
document-workspace-2026-10-21.md.

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

## BosTMC screening — 0.11.0 / build35 (2026-10-21)

The 18 new independent `python_tests.test_bostmc` cases plus 48 existing chemistry,
drawing, workflow and remote tests pass (66 total). Oracles cover quoted/multiline
CSV/BOM, all 43 supplied headers, duplicate-refcode spin rows, exact raw energy
strings, numeric AND filters, missing/nonfinite exclusions, array same-entry
bounds and structured bond/index separation, sorted pages, injection rejection,
source-change invalidation, malformed rows, inline XYZ, spin-directory file
lookup, background startup and a 1050-row streamed export. Array descriptors retain
their source encoding and units; nested tuple encodings containing mixed indices
and values require dataset-specific inspection before scientific use.

Native `--bostmc-smoke-test` passes on this Mac with synthetic FeN6 (seven atoms,
independent 2 Å coordinates), singlet/triplet CSV records and artificial energies.
It verifies exact energy text, combined filters, source text, independent/deduplicated
viewer documents, charge 2/spin 1 and spin 3 propagation, and unchanged input CSV.
Native document-workspace regression verifies 50 switches and unchanged view/edit
state. Persistent remote-session loopback verifies helper reuse and recovery.
The mandatory signed arm64 build passes 41 standalone core assertions plus 3
migrated suites; XCTest is unavailable in the installed Command Line Tools.
No core parser changed for this feature.

A real authenticated SSH test indexed an exclusively created synthetic catalog,
combined electronic/geometric criteria, preserved raw energy precision and spin
records, resolved the singlet XYZ/Psi4 files, SHA-verified selected geometry bytes,
and exported filtered CSV. Its final run verified cleanup of the exact synthetic
dataset and private index. No calculation or scheduler submission occurred.
Local evidence is under `/private/tmp/chemviewer-bostmc-*` and
`~/Downloads/chemviewer-bostmc-evidence/bostmc-native.png`; it is not shipped.

Limits: the actual BosTMC CSV/root paths are pending. No real catalyst descriptor
has been independently checked; production-scale timing/quota behavior and exact
array encodings remain unvalidated. Screening criteria select records, not proven
catalytic activity. Psi4 `.dat` is source inspection only.

## Local BosTMC actual-catalog validation — 0.11.1 / build36 (2026-10-22)

The user's explicitly provided `~/Documents/BosTMC/BOSTMC-complete.csv` contains
263,235 rows, 43 headers, complete embedded XYZ, and MOL2/per-atom lists (2.7 GB).
A streaming v2 import took 33.085s and produced 283.3 MB of SQLite data. Direct Python
backend measurements: first page 0.0037s; square-planar filter 0.1295s (72,751 matches);
gap 1–3 eV filter 0.1041s (47,618); first raw detail 0.0007s; gap histogram 0.0294s.
These are single-run backend timings on this Mac, not GUI/SSH latency promises.

An independent complete CSV scan verifies 263,235 rows and 8,042 combined square-
planar/gap 1–3 eV matches, all 43 raw fields at first/middle/last sampled IDs, first
36-atom XYZ with Ni x=-1.0222118919Å, and the first dipole vector norm against its
CSV magnitude. Native actual-catalog acceptance covers local filtering, category
choices/ranges, embedded preview without SSH, orbital descriptors, histogram count,
two slider-handle drags, and unchanged source size/mtime. Synthetic native catalog
regression retains exact coordinates/energies and independent charge/spin documents.

Python 71 tests pass (previous 66 plus 5 compact-index, statistics/histogram, UTF8/
multiline raw-offset/export, no-remote-CSV resolution and query-plan oracles).
Mandatory signed arm64 build retains 41 standalone core assertions plus 3 migrated
suites; selected CLT lacks XCTest and no core parser changed. Private evidence:
`/private/tmp/bostmc-local-performance.log`, `bostmc-local-independent.log`,
`bostmc-hybrid-python-final.log`, `bostmc-hybrid-actual-release3.log`,
`bostmc-hybrid-synthetic-release.log`, `bostmc-local-native.png`, and
`chemviewer-bostmc-hybrid-release36-final.log`. Actual CSV/data/captures are not shipped.

Graphs preserve CSV units and values; histogram population is the full catalog,
missing/nonfinite values are excluded, no cross-property normalization/activity
ranking is inferred. New actual remote BosTMC output lookup remains unvalidated
because the live SSH request timed out; synthetic resolver and persistent-session
regression cover the wire path. Source CSV must remain available for deferred cells.

One repeated synthetic slider drag was missed before explicit test-window
activation. The harness now activates/layouts its own window before delivery;
both handles passed in two consecutive native runs (release2/release3 logs).
No success is inferred from the earlier failed run. Local source/filter/graph
checks passed in that run as well. The final live SSH resolver check exceeded
20 seconds; local XYZ selection/filtering needs no SSH and remained functional.

## SSH timeout diagnosis / recovery — 0.11.2 / build37 (2026-10-22)

Independent read-only probes reproduced 8–10 s trivial-command timeouts through both
ChemViewer's private master and the user's configured master. Both masters answered
local -O check; debug logs reached mux session IDs without remote command output.
A nonmultiplexed connection reached the server and required keyboard-interactive
MFA, so a new interactive master was prepared. Its successful authentication marker
was published; nevertheless plain printf timed out 10 s and SFTP pwd timed out 12 s.
No ChemViewer helper, CSV, Python environment or calculation is needed to reproduce
these stalls. This local evidence does not establish a cluster-wide outage or
identify the exact remote service/filesystem cause. The longer plain printf probe also timed out after95 seconds; remote browsing
success remains unverified.

The product defect fixed here is explicit authentication reusing a stalled socket.
Python 73 tests pass: new oracles verify conditional/atomic active-socket publication,
failed-auth rollback, preservation of the old socket, matching future SSH arguments,
keepalive arguments and rejection of unsafe markers. Native REMOTE_SESSION_PASS
verifies persistent helper reuse, error recovery, cache refresh and exact XYZ bytes.
Mandatory signed arm64 build retains 41 standalone core checks plus 3 migrated suites;
XCTest is unavailable under selected CLT. Scientific parsers/calculations unchanged.
No remote jobs or user masters were stopped, and no run was resubmitted.

Private evidence: /private/tmp/chemviewer-ssh-probe-{custom,configured,independent}.log,
chemviewer-ssh-recovery-{live,python,native,build}.log and
chemviewer-ssh-session-startup-long.log. Credentials/keys are never stored by the
recovery mechanism. Official reference for keepalive/control semantics:
https://man.openbsd.org/ssh_config . ORCD escalation reference:
https://orcd-docs.mit.edu/accessing-orcd/ssh-troubleshooting/ .

## 0.12.0 — portability baseline (2026-10-23)

Real Swift6.1.3 XCTest on Linux arm64 (Docker official swift image) passes47cases (44core +3migrated suites);
three migrated parser/editing/state suites and six real executable tests pass on
Linux and Mac. The selected Mac CLT lacks XCTest; before/after genuine attempts
fail explicitly, while the standalone adapter passes44 core assertions. No
claim of local Mac XCTest success is made. Hosted Windows XCTest47 has also passed. Final all-platform gate results are
linked from [PR1](https://github.com/ignaciomigliaro/ChemViewer/pull/1).

The Python redistributable suite passes91tests with3explicit optional licensed-
corpus/artifact skips, including the coverage-gate self-tests. All seven
helper modules are measured (approximately83% combined line/branch coverage).
The previous full discovery depended unconditionally on a missing proprietary
water output: those two exact-corpus checks are now optional and a checked-in
synthetic negative-mode/energy/vector oracle is mandatory. No licensed fixture
is redistributed. Per-file floors retain lower legacy coverage honestly.

Portable export tests retain source units, missing optional values, separate IR/
Raman properties, negative frequency, source frame, full Double energy and source
text including Unicode/closing-script content. Water oracles verify0.95720Å
distance and two inferred bonds; exported XYZ round-trips frames/energy without
overwrite. Fragment math is checked against independent Cartesian dot/cross,
3D7-unit-length and signed-axis oracles, plus existing rigid-body invariance.

Five actual Chromium checks exercise canvas pixels, rotate/fit, click measurement,
resize, downloads, trajectory playback, negative-mode animation/equilibrium export,
text injection isolation, offline networking and source-only inputs. Synthetic
fixture screenshots in docs/images demonstrate the portable interface; they are
not reference-app captures or quantum predictions. Physical Windows/Linux desktop
interaction and full UI parity remain unexecuted. Native physical Mac smoke
results and final hosted CI evidence are recorded in CONVERSATION-HANDOFF.md.

Hosted Linux testing exposed a hard-coded /private/tmp SSH control path. It now
uses the host temporary directory on Linux while retaining the short canonical
Mac path for existing masters/socket limits. Hermetic tests check private
permissions and symlink refusal. Platform-specific ORCA/CUDA preflight branches
are now tested with explicit platform/file-probe mocks on both hosts; no engine
is executed. This preserves coverage floors instead of lowering them on Linux.

Hosted run[40004224822](https://github.com/ignaciomigliaro/ChemViewer/actions/runs/40004224822)
passes the complete Linux/Windows/Mac matrix, Python science/coverage and native
Mac packaging gates at candidate16a3702. Downloaded Mac portable artifact was
hash-verified and tested independently after relocation; all5browser cases pass
after explicit render synchronization in the picking harness. This adds no
physical Windows/Linux or full-interface parity claim. The final commit's own
required CI results are linked on PR1 before its version tag is published.

A separate native download test then exposed a release-blocking resource bug:
RemoteConnection and its smoke helpers called Bundle.module directly, whose
generated accessor searched the app root or the build machine's absolute path,
while packaged assets live in Contents/Resources. The signed CI app crashed
before its GUI opened. All native lookups now share the packaged resource
resolver, and a new headless relocated-archive/negative-helper gate prevents
local fallback from masking this defect. Earlier build/signature success is
not native runtime acceptance. Final physical downloaded-app retest is required.

Post-fix candidate6a3da93 passes the complete required hosted run
[40005895948](https://github.com/ignaciomigliaro/ChemViewer/actions/runs/40005895948),
including the native archive's contained-resource/missing-helper gate. Native
artifact12524422347 (SHA-2560e08496bb83ff5cabc3d2e575070994926b04a51b3fbf107010cbbbe5f903237)
was downloaded and independently passed native REMOTE_SESSION and BOSTMC workflows
on this physical Mac. Its general render smoke reached the shader-location
assertion but falsely rejected /tmp versus /private/tmp aliases. The assertion
now canonicalizes both paths and requires a directory boundary; final physical
render acceptance uses that correction, without relaxing resource containment.

## Qt desktop port — development acceptance

The Windows-first branch adds 14 real-service protocol regressions and 15
Qt/OpenGL GUI regressions. Service oracles include water O–H 0.95720 Å,
H–O–H 104.52°, signed dihedral 116.56505°, explicit numeric geometry edits,
negative frequency −250 cm⁻¹, separate missing Raman/IR intensity 7.5, exact
Double Hartree energy, original-source retention and invalidation/undo. They
also check failed-request rollback, document isolation, non-overwrite export,
trajectory export and portable project/embedded-companion round trips.

`Tests/fixtures/desktop-imaginary.out` is independently authored synthetic
ORCA-style text, not a real quantum calculation. Its arbitrary negative mode
and energy test parsing/display only and do not establish physical accuracy of
a computed H2 transition state. The water/dihedral fixtures retain the existing
independent geometric oracles.

All 15 desktop tests passed on the physical Apple Silicon Mac using real Qt
windows and OpenGL framebuffers. They inspect molecular pixels, picking,
measurement, coordinate edit/undo/redo, per-document camera/playback lifetime,
trajectory/equilibrium export, negative-mode animation/invalidation, builder
project reload and source-only inputs. This does not establish physical Windows
or Linux interactive acceptance. CI now requires service, GUI and relocated
frozen-package checks on each platform; results are recorded in the handoff.

Desktop line+branch coverage is approximately 87% on the development Mac, with
per-module floors and exact source inventory in `Tests/desktop-coverage-floors.json`.
The platform-specific software-OpenGL adapter must execute on Windows; its
absence from Mac/Linux execution is explicit in the policy. Linux arm64 Mesa
validation caught and reproduced a QPainter-to-3D GL-state regression after label
rendering; the viewport now resets blend/scissor/depth-write state before drawing.
