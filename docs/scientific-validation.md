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
