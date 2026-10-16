# GUI feature inventory

Status meanings: **Observed** means exercised in the Windows reference;
**Visible** means a control or menu was seen but its result was not validated;
**Partial** means only a bounded part of the workflow was exercised; **Pending**
means no direct GUI evidence yet.

## Primary interface

| Area | Observable controls and behavior | Status |
|---|---|---|
| Result explorer | Job, optimization, geometry, frequency, and generated-orbital tree nodes | Observed |
| View tabs | Image, Abstract, Source, Coord, Image/Abs | Observed |
| Camera | isometry/perspective, rotation center, best view, center, camera copy/paste, axes | Visible; right-drag/wheel/toolbars observed |
| Display schemes | GaussView; Basic; CPK; Simple; atom/stick; Publication; seven 2D; Quick; Hyperchem; Spartan; Mixed; customize/default | Visible |
| Toolbars | scroll buttons, auxiliary designations, image tools, geometry editor | Visible |
| Multiple windows | cross-window RMSD, reorder, and structure merge commands | Visible |

## File and export controls

| Area | Observable controls and behavior | Status |
|---|---|---|
| Open | Open, reopen, multiple files, drag-oriented Windows shell dialog | Open observed |
| Structure save | XYZ/XMOL, multi-XYZ, MFJ/MOBCAL, SDF, Tinker, MDL Mol | XYZ observed; others visible |
| Image save | Bitmap, JPEG, GIF, Metafile; proportional sizing; crop; anti-alias enlargement; transparency where supported | JPEG observed |
| Clipboard | copy/paste structure; anti-aliased and bugs-free image copy commands | Visible |
| Animation export | molecule rotation, frequencies, scan, trajectory, custom, animated GIF from frames | Visible |

## Geometry and editing

| Area | Observable controls and behavior | Status |
|---|---|---|
| Atom selection | click plus Ctrl-click; selected atom identities shown | Observed |
| Measurements | distance, angle, signed dihedral; all bonds/angles overlays | Observed |
| Atom/bond editing | add atom, fragment, bond; delete; set types/captions; rebond and clear | Visible |
| Drag modes | individual atoms Ctrl+1, fragments Ctrl+2, molecules Ctrl+3 | Visible |
| Coordinates | Cartesian display in Angstrom/Bohr, translation, random displacement, overlap cutting | Coord view observed; edits visible |
| Z-matrix | Gaussian, KCED, GAMESS+$ZMAT, Molpro builders | Visible |
| Fragments/symmetry | fragment construction; point-group and principal-axis operations | Visible |
| Structure comparison | superpose, RMSD, reorder for best match, merge/combine | Visible |

## Scientific results

| Area | Observable controls and behavior | Status |
|---|---|---|
| Optimizations | step tree, optimized geometry, animation, step time, smoothing | Observed for ORCA water |
| Frequencies | mode tree, auto-animation, amplitude/cycle/freeze/rebond/vector controls | Observed; vector incident unresolved |
| IR/Raman | Show spectrum control and spectrum-related menu surface | Visible; activation pending |
| Orbitals | render/analyze/input conversion/energy diagram; MO grid and isosurface controls | Partial |
| Electron density/cubes | density item, cube save/operations, mapped planes/spheres | Visible |
| IRC | compound-job IRC root and primary views | Partial; detailed tree/path playback/graph retest required |
| PES/scan | 21-point A1 scan tree and optimized geometry; graph/animation commands | Partial; tree observed, graph/playback pending |
| NEB | coordinate fixture requests supplementary files | Blocked on complete fixture set |
| Charges/bond orders/spin | atomic-properties tables and visualization tools exposed | Visible |
| TDDFT/UV-visible/CD/NMR | format-dependent data/spectrum capabilities identified in menus and installed corpus | Pending direct GUI test |
| SCF/data graphs | Data Explorer, custom graphs, graph analysis, table formatting | Visible |

## Menu map

- File: clear/open/reopen/multiple open, save variants, exit, help.
- Edit: undo/redo, atom/fragment/bond operations, selection, clipboard,
  geometry transforms, vectors/planes, coordinate operations, symmetry,
  dragging, comparison, and cleanup.
- View: projection/camera, axes, labels, structural parameters, van der Waals,
  captions/vectors/surfaces, toolbars, image copy, and image sizing.
- Display: predefined molecular drawing schemes plus customization/default.
- Tools: custom geometry, Data Explorer, Z-matrix, GED, crystallography,
  animations, summaries, input helpers, fragments, orbitals, comparison,
  mass spectra, inertia/collision/area/radii, scripts, graphs, preferences, and
  job archive.
- Help: help contents, program information, gallery/hints, and license UI.

License dialogs were not opened or recorded. Menu visibility is not evidence
that every command works for every input type.
