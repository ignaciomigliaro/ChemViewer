# Thermochemistry, clipboard and geometry manipulation — 0.4.0

## Controls

- Right-click clears all selected atoms and fragment-boundary state. Right-drag
  no longer rotates the camera. Left-drag with dragging disabled rotates the
  camera; Option-drag pans; wheel zooms.
- The four-button geometry toolbar contains a hand toggle and Atom, Fragment,
  Molecule scopes, independently drawn from the supplied visual reference.
  Choosing a scope also enables dragging. No proprietary icons are bundled.
- Atom moves the clicked atom. Fragment identifies its connected group using
  inferred bonds. To isolate a subgroup, select bonded atoms A then B with
  dragging off and choose Fragment: B's side is selected while A's side stays
  outside. The boundary is a manipulation boundary, not a deleted chemical bond.
  Ring bonds that do not split the graph are rejected. Right-click resets it.
  Molecule moves the entire loaded geometry, including disconnected components.
- Dragging uses a screen-parallel plane, with Option-drag for camera depth, or
  constrain it to molecular/world X, Y, Z. Background dragging retains camera
  control. Target atom membership is frozen for each gesture.
- Six X−/X+/Y−/Y+/Z−/Z+ buttons rotate by the selected positive degree step.
  Choose group center, attachment/first atom, or world origin as pivot. A
  second set of axis buttons translates by the selected Å step. These transform
  coordinates; they do not optimize geometry or calculate new energies.
- A mouse drag with many preview events creates exactly one Undo operation.
  Undo restores the original energy/comment as well as positions. Existing
  energy invalidation and per-geometry undo behavior remain in place.
- For A → B → C angle selection, B is always the vertex. The new picker chooses
  C-only or equal-and-opposite rotations of A and C. Adjacent distances and B
  remain fixed. This matches the user's explicit clarification.
- Coord has Copy coordinates (element/X/Y/Z TSV) and Copy XYZ. Both copy the
  current editor contents, including pending coordinate edits, in Å. Copy XYZ
  includes the atom count/comment and does not attach an old calculated energy.

## Cleaner Abstract and sums

Abstract now has compact numeric rows, numeric-only copy icons, a selected
structure, collapsed output details, and Copy table / Copy values at the end.
Single-geometry files avoid a redundant geometry list. SCF, electronic energy,
ZPE, reported enthalpy H and reported Gibbs energy G are shown when available.
Reported values keep source-line provenance. Multiple thermochemistry sections
for one geometry can be selected by temperature/source section; missing
quantities/temperatures are not replaced with zero.

The sums section sits at the end. It uses the selected electronic base (final
energy, SCF or the printed thermochemistry electronic energy) and the complete
H−E/G−E corrections to compute Ebase + δH and Ebase + δG. It never adds electronic
energy to an already-total H or G. ORCA's line named Thermal Enthalpy correction
is only the kBT increment to U, so it is not mistaken for the complete H−E
correction. H−E is derived from printed H and electronic E; G−E uses the explicit
printed correction when present, otherwise the difference of G and electronic E.
No correction is invented when its necessary source values are absent.

Reported thermochemistry may use a rounded/different electronic energy from the
final single-point line. Choosing Final energy preserves that line's precision;
the calculated sum may therefore differ slightly from reported H/G. Selecting
Thermochemistry E reproduces totals using the source thermochemistry base.
Data stay associated with their geometry and thermochemistry section; edited
geometries hide applicable calculated values/sums until Undo or recalculation.

Primary format/scientific reference:
https://www.faccts.de/docs/orca/6.1/manual/contents/structurereactivity/thermochemistry.html
and https://www.faccts.de/docs/orca/5.0/tutorials/prop/thermo.html.

## Validation

Nineteen standalone Swift core cases pass. New numeric oracles check two
independent thermochemistry sections, H−E versus the smaller kBT contribution,
missing-data behavior, base-energy sums, symmetric A/C angle coordinates,
boundary-identified fragments, isolated-atom preservation, rotation distance
invariance and rejection of nonseparating ring bonds. Actual XCTest remains
unavailable with Command Line Tools; pre/post attempts are recorded separately.

The installed ORCA water compound-job sample additionally passed native checks
for frame 6, 298.15 K, H = −76.33654419 Eh, G = −76.35763657 Eh, δH = 0.02442433 Eh
and δG = 0.00333195 Eh. With its final electronic energy −76.360968646 Eh the
computed totals are −76.336544316 and −76.357636696 Eh. Proprietary input stays
outside the repository.

All three packaged live-window checks passed: existing GPU/render/parser flows,
energy/Matplotlib flows, and the new manipulation flow. The latter exercises
actual mouse-handler paths with NSEvent coordinates for right-click clear and
atom/fragment/whole-geometry dragging; verifies rigid membership, attachment-axis
rotation, one Undo per gesture, symmetric angle edits, isolated clipboard
roundtrips, and displayed Abstract/Coord views. It does not claim exhaustive
manual trackpad or clipboard-button clicking acceptance.

Opt-in test:

```
bash scripts/build-macos.sh
dist/ChemViewer.app/Contents/MacOS/ChemViewer -ApplePersistenceIgnoreState YES \
  --manipulation-smoke-test --capture-window \
  --manipulation-evidence /Users/nacho/Downloads/chemviewer-manipulation-work/evidence
```

Screenshots `fragment-toolbar.png`, `clean-abstract.png`, and
`copy-coordinates.png` were inspected at the controlled 1100×760 point window
size. They use synthetic fixtures and are local under that evidence directory.

## Clipboard-test incident and correction

The first validation test used the general pasteboard, then exited before its
deferred restoration executed. It replaced the existing clipboard with the
synthetic numeric test value. The user was informed; previous contents could
not be recovered. The test now uses NSPasteboard.withUniqueName, never reads or
writes the general clipboard, and returns normally before process exit so
cleanup executes. The corrected isolated test passed. Ordinary app copy
buttons still write to the system clipboard when explicitly clicked.

## Remaining limits

Fragment membership uses distance-inferred connectivity; this is not a full
fragment-construction or persistent manual-bond editor. Rings require a
separating boundary; arbitrary ring subgroups are not automatically guessed.
Mouse translation is planar/depth or axis-constrained; geometry rotations use
explicit step buttons. Thermochemistry support here is ORCA text, not a promise
of Gaussian or other output-format coverage. Full Chemcraft parity remains open.
