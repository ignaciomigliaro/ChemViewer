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
