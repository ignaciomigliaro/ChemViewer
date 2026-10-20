# Draw and persistent measurement labels

ChemViewer 0.10.0, build 22 — 2026-10-20.

## Measurements

Select 2/3/4 atoms and enable Show bond length/angle/dihedral. That selection is
pinned independently of active atom selection. Right-click clears selection,
allowing a new selection and another label. Visible labels lists each annotation:
click its atom numbers to select it, its × to remove it, or Hide all to remove
all. Re-selecting the same atoms in reverse order identifies the existing label.
Drag labels to reposition them; initial overlapping boxes receive separate
positions. PNG includes all visible labels. GIF's Include measurement labels
option exports all pins, recomputing values for every trajectory/mode frame.

Pins are associated with the current geometry/frame and survive tab switches,
coordinate edits and additions of unrelated atoms. Surviving atom identities
are remapped after topology edits; deletion of an annotated atom removes that
label. Geometry Undo restores annotations. Pins are not yet serialized into
.cvproject files or restored across application restarts.

## Drawing

Open Draw next to ChemRefine, or Cmd-7. The left canvas is a skeletal 2D editor;
carbon vertices and their implicit hydrogens are omitted in the usual skeletal
style. Heteroatom labels show simple implicit/explicit hydrogen counts. RDKit
sanitization, not the canvas text heuristic, determines the generated chemistry.

- Single/Double/Triple: click empty space to start, click an atom to extend,
  or drag from one atom to another/new space to add a bond. Click an existing
  bond to set its order/direction. Wedge/Dash set a directed stereobond from
  the gesture's start atom.
- Atom: click blank space to place, or an existing atom to change its element.
  Quick elements and the full periodic table are available.
- Rings: benzene or 3–8-membered carbon rings; click empty space or an atom
  to share that vertex. Fused-bond ring stamping is not a separate tool; build
  explicit connectivity or import SMILES for complex fused scaffolds.
- Move drags an atom; dragging blank space pans. Scroll zooms; Fit recenters.
  Erase removes atoms/bonds, with connected bonds removed when an atom is erased.
  +/− charge edits formal charge. Drawing Undo/Redo is independent of 3D history.
- Load SMILES imports chemistry with a fresh 2D depiction. Clean 2D redisplays
  the current connectivity. Open/Save store the original graph as JSON.

Auto 3D preview debounces edits by 750 ms; Generate 3D also runs manually.
The existing chemistry runtime (`bash scripts/setup-chemistry.sh`) supplies
RDKit. The bridge adds hydrogens, generates a deterministic ETKDGv3 conformer,
and applies UFF where parameterized. It separates disconnected fragments and
retains chiral/E/Z, explicit-H and radical metadata. Unsupported isotope labels
are rejected because the viewer cannot preserve isotope information. A generated
conformer is a starting structure; this is not a conformer search. Where UFF is
unavailable or reaches its limit, status says so. Choose the intended multiplicity
before transferring a radical/open-shell structure.

3D preview uses the existing native Paton renderer and can be rotated. It never
modifies the viewer document. Use 3D in Viewer transfers the current preview to
the current frame as an undoable geometry edit, preserving the draft. Stale
previews cannot be transferred. Child jobs are cancellable, revision checked and
limited to 45 seconds. The drawing and bridge require no web service or MolDraw
account/code/assets.

## Evidence and limits

Local build: 31 core assertions and three migrated building suites. New core
oracles check ring bond lengths (48 drawing units), connectivity, unique IDs,
deletion, JSON round trips, and rejection of malformed/duplicate connectivity.
Eight Python drawing tests independently check ethanol formula/explicit-H count,
C–C/C–O distances and nonzero tetrahedral volume, double/triple bonds and benzene,
chiral/E/Z preservation through both graph and 3D MOL blocks, wedge direction,
charges/separated fragments, radicals/explicit H, isotope rejection, deterministic
embedding and invalid valence/coordinates.

The native gate uses actual drawing-canvas events and GPU completion, four
simultaneous measurement labels, independent dragging/removal, reverse selection,
geometry edits/undo/additions, PNG/GIF, tab state, ethanol and benzene generation,
auto preview, cancellation, undoable viewer transfer, SMILES chirality and the
Draw periodic picker. Local evidence is under Downloads/chemviewer-drawing-evidence
and /private/tmp/chemviewer-0100-*.log, excluded from source control. Broader
MolDraw/Chemcraft parity is not claimed; saved-drawing panel behavior and general
human visual-fidelity assessment remain manual checks.

Implementation references: [RDKit Python guide](https://www.rdkit.org/docs/GettingStartedInPython.html)
and [ETKDG documentation](https://www.rdkit.org/docs/RDKit_Book.html).

Measurement tracking also spans trajectory frames with the same atom count and
element ordering: enabling/removing a pin updates every compatible frame, and
values are recomputed for the current coordinates. Frames with different atom
ordering/composition keep separate pin sets. The native gate checks two frames
with independently known 2.0/2.3 Å distances and propagates removal to both.

Final local release gate passed all of the above, plus the existing native
smooth drag/selection/label-placement suite, transparent trajectory/frequency
GIF suite, coordinate-element/periodic-picker suite, fragment/camera/ChemRefine
persistence suite and native UFF/frozen-atom/cancellation workflow. The combined
Python command ran 13 tests successfully. Local XCTest itself remains unavailable
on the Command Line Tools host; the checked-in 31 core assertions run through
the standalone adapter, with GitHub's full Xcode job responsible for XCTest.
