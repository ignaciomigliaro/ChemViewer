# Skeletal chains and ring palette

ChemViewer 0.10.5/build27.

Draw now provides a Chain tool. Drag blank space to create a carbon zigzag chain,
or start on an existing atom to attach one. The preview is local until mouse-up;
the completed chain is one Undo operation. Chains use equal 48-unit drawing
bonds with alternating directions and 120-degree internal angles. Drag distance
controls the bond count (up to 100 per gesture, within the existing graph limit).

Clicking a terminal atom with the bond/chain tool extends a skeletal chain with
120-degree angles rather than maximizing distance and choosing a straight line.
Normal terminal bond drags also choose the nearest 120-degree direction. Triple
bonds retain linear placement, explicit existing-atom connections remain exact,
and Option-drag permits other snapped angles. These are 2D drawing conventions,
not claims about the final optimized 3D bond angles.

The toolbar contains an original benzene glyph with alternating inner bonds and
polygon glyphs for saturated 3–8-membered rings. More rings opens a visual grid
with 14 templates: benzene, cyclopropane, cyclobutane, cyclopentane, cyclohexane,
cycloheptane, cyclooctane, cyclopentene, cyclohexene, cyclopentadiene, pyridine,
pyrrole, furan and thiophene. Templates store explicit elements/bond orders and
pass through the same RDKit sanitization/3D pipeline as other drawings. Clicking
an existing atom shares a vertex; automatic bond-fused rings are not added by
this change. Icons and template code are original, not copied ChemDraw assets.

Formal charge buttons have moved to More. Formal charge metadata and existing
charged structures remain supported and preserved during drawing/3D transfer.
Neutral-charge text is removed from the main 3D preview caption. Workflow charge
and multiplicity settings remain separate calculation controls.

Validation:

- 33 standalone core regression cases, including analytic 48-unit bonds and
  120-degree zigzags, terminal extension, all catalog elements/bond orders and
  pyrrole nitrogen connectivity. Three migrated core suites passed.
- Native mouse gestures: six-bond heptane chain preview did not publish before
  mouse-up; one Undo removed it; 3D generation produced C7H16. Repeated horizontal
  terminal bond drags bent at 120 degrees. All 14 templates were placed through
  the canvas and generated in 3D, with formulas checked against independent
  chemical expectations, including C5H5N/C4H5N/C4H4O/C4H4S heterocycles.
- Existing native Draw/measurement suite passed: pinned labels, GIF/PNG, atom
  move/erase/charge, undo/redo, ethanol and automatic amine generation, Metal
  preview, cancellation, tab preservation, undoable viewer transfer, chiral
  SMILES, periodic picker and benzene.
- Python chemistry integration suite: 29 tests passed. Signed ARM64 release
  build passed. Before/after swift test was attempted but the selected local
  Command Line Tools lacks XCTest; the standalone adapter ran the actual core
  assertions. CI uses full Xcode.

Evidence: /private/tmp/chemviewer-0105-{build,python,native}.log and
~/Downloads/chemviewer-drawing-evidence/zigzag-chain.png (visually inspected).
No personal structures/calculations were modified.
