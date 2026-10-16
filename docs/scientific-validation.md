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
