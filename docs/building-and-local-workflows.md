# Fragment building and local workflows — ChemViewer 0.9.0

Open the popup **Fragment Library** with Command-B or the **+** toolbar button. Choose a preview, then left-click empty canvas to place a fragment or an atom to attach it. The gallery includes the original seven templates as well as 258 fragment/metal entries. Command-Shift-B opens **Build & Edit** controls. The existing Paton rendering styles,
frequency/geometry explorer, measurements, GIF exports and editing controls remain.

## Build by clicking

Search the popup gallery or choose a category, then click a structure preview. This arms
placement immediately: left-click empty space to place an independent fragment, or an atom to attach it. Placement also works in a new, empty molecule.
Right-click finishes placement and clears selection. The toggle can also stop
placement. **Add fragment** inserts a separate molecule instead.

Clicking a terminal H/X replaces it. Clicking a heavy atom uses its first
available terminal H/X site, avoiding an extra bond on saturated carbon. When no
such site exists, placement samples 96 directions and chooses the least crowded
initial direction. Review connectivity/valence and optimize where appropriate;
this is a construction heuristic, not a chemical-validity or minimum-energy claim.
The **Leaving site** picker selects which incoming H/X is removed.

The original, generated catalog has **258 entries**: 72 organic/ligand fragments
and 186 metal-center templates (31 metals × six geometries). Categories include
alkyl, aromatic, oxygen, nitrogen, sulfur/phosphorus, linkers and coordination
donors. Metal templates provide linear, trigonal planar, tetrahedral, square
planar, trigonal bipyramidal and octahedral X sites. They are geometrical starting
points, not oxidation-state, ligand-field or spin-state assignments. Set charge
and multiplicity explicitly. Donor templates retain NH3/H2O/PR3 stoichiometry;
their X sites are independent coordination attachment placeholders.

**Use selected atoms** copies the current selection as an incoming fragment;
include a terminal H or X to define its attachment site. **Save fragment…** stores
an XYZ in `~/Library/Application Support/ChemViewer/Fragments` by default; **My
saved fragments…** loads one. Import XYZ continues to support external fragments.

The **Element** picker includes all 118 elements plus X. **Insert** adds an isolated
atom, **Replace** changes selected atoms, and **Click to add this atom** attaches
the chosen element at a clicked host. **Remove unused X sites** removes construction
dummies in one undoable edit before cleanup/calculation.

## Genuine UFF cleanup

**Clean geometry · UFF** runs RDKit UFF in a separate local process. **Keep selected
atoms fixed** constrains their Cartesian coordinates. Cleanup reports initial and
final UFF energies in kcal/mol and distinguishes convergence from the iteration
limit. It supports Cancel and one-step geometry Undo. Moving to another geometry,
editing the structure or changing charge/multiplicity while it runs prevents a
stale result being applied.

UFF uses inferred connectivity/bond orders from the explicit XYZ atoms and charge.
It does not add missing hydrogens. Remove X sites first. Invalid bonding or missing
UFF atom-type parameters produces an error and preserves the original geometry.
Many metal complexes need a more suitable potential or QM method. UFF energy is
not substituted for an electronic SCF energy; edits invalidate existing energies.

## ChemRefine integration

The dedicated **ChemRefine** tab (Command-6) starts local workflow creation: choose a destination to create a unique workflow
folder with the current `seed.xyz`, `input.yaml`, templates and local dispatch.
It launches the installed, unmodified [ChemRefine](https://github.com/sterling-group/ChemRefine)
GUI on token-protected loopback and displays its real Builder/input.yaml/Structure,
validation, template and run controls in the main ChemRefine tab. This is the
local editor, not the static online playground. **Open in browser** is available.
Switching tabs does not stop the local workflow server or jobs.
Reopen the existing workflow, or choose **New workflow from current geometry…**
to export another seed. **Open result…** loads an output/XYZ back into ChemViewer.

The starter is an ORCA `! XTB2 Opt` step. Set the actual ORCA executable under
Executables, or select/configure another installed engine, then Validate, Save
and Run. Engine executables, external model weights, remote clusters and credentials
are not installed by this integration. The editor and validation were tested
locally; an ORCA computation was not claimed without an available ORCA executable.
The local GUI supports further workflow configuration and resume through ChemRefine.

ChemRefine remains a separately installed AGPL-3.0-or-later program; no upstream
implementation/assets are copied into ChemViewer. Its package supplies its own
local GUI assets. The package source commit is pinned by `setup-chemistry.sh`.

## Runtime and reproducibility

The isolated Python 3.12 environment is installed at
`~/Library/Application Support/ChemViewer/chemistry-venv` on this Mac. It contains
RDKit 2026.09.1, ASE 3.29.0 and the pinned ChemRefine revision with GUI dependencies.
On another Mac with Python 3.12:

```bash
bash scripts/setup-chemistry.sh
```

Override the interpreter with `CHEMVIEWER_CHEMISTRY_PYTHON` if needed. Fragment
coordinates are original deterministic RDKit ETKDG output (`randomSeed=517`), with
explicit connection sites and analytic metal-center coordinates. Regenerate with
`scripts/generate-fragments.py` using this environment. Generated coordinates do
not imply optimized energies. After installation, UFF and the local editor do not
need a model download. UMA is deferred at the user's request until model access is
available; no UMA optimization has been implemented or claimed tested here.

## Validation

- 27 standalone Swift core regression cases and three migrated building suites.
  Full XCTest remains unavailable in the local CLT environment; CI runs XCTest.
- Five Python tests: UFF water angle 104.51°, bond length, energy decrease,
  convergence/frozen atom, dummy rejection, all catalog attachment coordinates,
  donor stoichiometry and ChemRefine GUI token/schema behavior.
- Packaged native Mac acceptance: attach all 258 catalog entries; click fragment
  and element placement; undo; real UFF cleanup/frozen atom/cancel; embedded
  ChemRefine startup and actual page rendering checked through WebKit.
- Real local ChemRefine HTTP bootstrap and validation of the generated starter
  workflow passed. Local screenshot/evidence stays in Downloads, not the repository.

The ChemRefine tab retains its WKWebView for the current server session across tab changes. The native acceptance test switches to Image and back, verifies the same web view and JavaScript state survive, and checks the real editor still renders. This preserves unsaved workflow form edits while viewing/building structures.
