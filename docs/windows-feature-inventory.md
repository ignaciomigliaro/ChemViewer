# Windows reference feature inventory

Evidence labels: **D** official documentation, **C** installed sample corpus,
**A** shipped-artifact inspection, **G** direct GUI observation. GUI evidence
was collected on 2026-10-16 with UIA/Win32 inspection plus calibrated visual
fallbacks for custom-drawn controls. Documentation establishes advertised
behavior, not correctness for every file.

## Interface and files

| Area | Reference behavior | Evidence | Audit state |
|---|---|---|---|
| Data Explorer | Hierarchical jobs, geometries, modes, orbitals, and properties | D + G | Observed for XYZ, ORCA optimization/frequency, Gaussian fchk and IRC |
| View modes | Image, Abstract, Source, Coord, Image/Abstract | D + G | Observed; availability varies by input |
| File operations | Clear, open/reopen, multiple files, save structures/images | D + G | Open, XYZ save and JPEG save observed |
| Interaction | Select atoms; rotate, translate, Z-translate; numeric geometry measurement | D + G | Rotation/zoom/toolbars and 2/3/4-atom measurements observed |
| Clipboard | Structure and image copy/paste | D | Documented; GUI pending |
| Windows | Multiple application windows and cross-window structure tools | D | Documented; GUI pending |
| Input corpus | 246 installed samples across 39 named families | C | Inventoried |

## Molecular visualization

| Feature | Reference behavior | Evidence | Audit state |
|---|---|---|---|
| Representations | Configurable atoms/bonds, quick and publication schemes, 2D styles | D + installed schemes | Partially corroborated |
| Projection/camera | Isometric/perspective, best view, configurable rotation center | D | Documented |
| Colors/labels | Element styling, atomic/bond labels, auxiliary lines and captions | D | Documented |
| Measurements | Distances, angles, dihedrals, planes/vectors | D | Documented |
| Properties | Charges, spin density, valence, bond order, dipole, force vectors | D | Documented |
| Image output | Saved images, clipboard, publication-oriented rendering | D | Documented |
| Animation | Rotation, vibration, scan; GIF or bitmap/JPEG frames | D | Documented |

## Structure editing

| Feature group | Reference behavior | Evidence | Audit state |
|---|---|---|---|
| Atom/bond editing | Add/change/delete atoms and bonds; rebond/clear bonds | D | Documented |
| Coordinate editing | Cartesian text mode, translation, inversion, transforms | D | Documented |
| Internal coordinates | Set distances/angles/dihedrals and build Z-matrices | D | Documented |
| Fragments | Built-in/custom fragments, copy/paste, unite, drag/rotate groups | D + `fragments2.bin` present | Partially corroborated |
| Cleanup | Standard bond lengths/angles and overlap removal | D | Documented |
| Symmetry | Apply point groups and principal axes | D | Documented |
| Comparison | RMSD, superposition, merge/combine structures | D | Documented |

## Computational chemistry data

| Feature group | Reference behavior | Evidence | Audit state |
|---|---|---|---|
| Optimizations | Steps, forces, convergence, energy plots, common orientation | D + C | Documented; formats pending |
| PES/IRC | 1D/2D scan plots, scan animation, IRC graphs | D + C | Documented; formats pending |
| Frequencies | Mode list, animation, displacement vectors, IR/Raman spectrum | D + ORCA case | Parser evidence available |
| Hessian analysis | Frequencies from Gaussian `.fch` and ORCA `.hess`; isotope masses | D | Documented |
| Orbitals | MO selection, energies, isosurfaces, mapped planes, both signs | D + C | Documented; pending analysis |
| Volumetrics | Cube/TAPE41 surfaces and mapped properties | D + C | Documented; pending analysis |
| Excited states | TDDFT/UV-visible and CD spectra where provided | D + C | Documented; pending analysis |
| NMR | Shielding/shift and spin-spin related displays/utilities | D + C | Documented; pending analysis |
| Electronic analysis | Mulliken/NBO-like atomic and bond properties, SCF plots | D + C | Documented; pending analysis |
| Export | Coordinates, tables, graph contours, images, animations | D + G | XYZ and JPEG observed; graph/animation export pending |

## Documented/bundled format families

The installed corpus contains ADF, CFOUR, CIF, CRYSTAL, Dalton, Firefly,
GAMESS-US, GAMESS-UK, Gaussian, GROMACS, HyperChem, Jaguar, KCED, MDL,
Molcas, Molden, MolDraw, Molpro, MSI, NBO, NWChem, ORCA, PDB, Priroda, PSI,
Q-Chem, Quantum Espresso, SDF, SHELX, Spartan, Tinker, Turbomole, VASP, xTB,
and generic structures/trajectories. A directory name is only a candidate
support claim. Each family remains unverified until representative values are
parsed and compared in both applications.

## Built-in computation

Official documentation describes an external xTB-backed module for single-point
energy, Mulliken charges, orbitals, optimization, optimization+frequencies, and
relaxed scans. It writes scratch files and launches xTB; it is not evidence that
the Windows executable contains an electronic-structure engine. Native parity
should integrate an independently installed xTB executable with explicit paths,
captured versions, streamed logs, cancellable processes, and no hidden unit
conversion.

## Official sources used

- <https://www.chemcraftprog.com/help.html>
- <https://www.chemcraftprog.com/help/ccbasicinfo.html>
- <https://www.chemcraftprog.com/help/filemenu.html>
- <https://www.chemcraftprog.com/help/editmenu.html>
- <https://www.chemcraftprog.com/help/viewmenu.html>
- <https://www.chemcraftprog.com/help/toolsmenu.html>
- <https://chemcraftprog.com/help/computationalmodule.html>
- <https://chemcraftprog.com/help/harmonicfreqscomputationtool.html>
- <https://chemcraftprog.com/help/spectrumwindow.html>
