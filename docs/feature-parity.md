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
