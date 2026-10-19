# Energy summaries, Matplotlib figures and geometry editing — 0.3.0

## Using the new workflows

1. Open ORCA output or multi-XYZ and choose **Abstract**. ORCA shows the last
   recorded SCF energy separately from final single-point energy, with original
   snippets and links that highlight the exact source line. Selecting a geometry
   shows its own energy/sections. XYZ shows geometry energies and the selected
   structure. Image/Abs keeps the normal viewport next to the energy list.
2. For unitless XYZ energy comments, select their input unit in Abstract.
   Explicit Eh/Ha/a.u./Hartree/eV/kJ/mol/kcal/mol units take precedence.
   Supported comments include `energy=-76.1 Eh`, `E=-10 eV`,
   `energy_hartree=-76.1`, and standalone numeric energies. Unrelated numeric
   metadata and unknown unit tokens are not silently assigned an energy unit.
3. Use any directional arrow to move through geometries; selection is clamped
   at the first/last geometry and the explorer scrolls to the selected row.
   Arrows retain normal behavior inside text editing and plot sheets. Source
   and Coord are excluded from global geometry arrow handling.
4. Left-click atoms to toggle them in selection order; there is no four-atom
   cap or modifier requirement. Clear/Escape deselects; Select all/Cmd+A selects
   all while the geometry view has focus. Two selections expose distance in Å
   and **Move second atom / Move both equally**. The latter preserves the
   geometric midpoint, not a mass-weighted center. Three selections expose
   A–B–C angle editing: B is the vertex, A/B stay fixed, C moves in the original
   plane and both adjacent distances are preserved. A deterministic plane is
   used for initially collinear atoms. These operations move individual atoms;
   bonded-fragment propagation is a separate unfinished feature.
5. Choose **Energy landscape…** in Abstract, the chart toolbar button, or Tools.
   The default is a relative-energy profile against geometry index. Choose
   minimum/first-available/absolute reference, Eh/eV/kJ/mol/kcal/mol, final/comment
   versus SCF energy, and optionally the selected distance or angle as x-axis.
   Click Update plot after changing settings. Structure thumbnails, point
   labels, connections, and single/double-column sizing are configurable.
6. Export writes PDF/SVG vectors, a 600-dpi PNG, CSV, JSON data/metadata, and the
   original plotting script into a new folder. The CSV retains absolute Hartree
   energies as well as the plotted values. Reproduce with
   `python energy_landscape.py plot-input.json new-output-folder`.

## Scientific behavior and limits

ORCA TOTAL SCF ENERGY / Total Energy and FINAL SINGLE POINT ENERGY are distinct
records with one-based original source-line provenance. Final single-point
values are preferred for each geometry's default energy; SCF is used when no
final value is available. This distinction matters for correlated methods.
Coordinate/value precision at parse boundaries is retained. XYZ comments do
not have a universal energy/unit standard; unlabelled comments require a
visible user choice. Explicit comment units are never overridden by that choice.

The figure is a profile through the supplied geometries in file order. It does
not compute new electronic energies, infer reaction states, interpolate a PES,
or fabricate missing data. Missing energies make gaps. Selected internal
coordinate axes require compatible atom identities/indices across geometries;
atom ordering correspondence remains the user's responsibility. Default final
energy profiles can contain SCF fallbacks, and the per-point energy kind is
retained in the exported CSV.

Editing clears the geometry's calculated energy and replaces its energy-bearing
XYZ comment with an edited/uncalculated marker. Export/reopen cannot resurrect
that original energy. Read-only source records remain available as original
output. Undo restores coordinates, comment and energy together, including after
navigating away and back. The camera stays fixed during edits. Connected-atom
or fragment rotation is not claimed by the angle editor.

Energy conversion uses CODATA 2022 Hartree energy `4.3597447222060e-18 J`, exact
Avogadro constant `6.02214076e23 mol^-1`, thermochemical calorie `4.184 J`, and
Hartree/eV `27.211386245981`. Sources:
https://physics.nist.gov/cuu/pdf/all.pdf and
https://physics.nist.gov/cuu/pdf/factors_2022.pdf.
SCF versus final-energy reference:
https://www.faccts.de/docs/orca/5.0/tutorials/prop/single_point.html.
Matplotlib export API:
https://matplotlib.org/stable/api/_as_gen/matplotlib.pyplot.savefig.html.

## Runtime setup and validation

The native app runs independently of Python; the Matplotlib feature uses a
separate environment configured by `bash scripts/setup-plotting.sh`. This was
installed and verified locally at `~/Library/Application Support/ChemViewer/plotting-venv`
with Matplotlib 3.9.4 and Python 3.9.6. Other Macs need that setup and a working
Python >=3.9. `CHEMVIEWER_PYTHON` can select an alternate Python with Matplotlib.
There is no network/package installation during figure generation. Figure
rendering runs outside the UI thread with a 90-second timeout.

Sixteen core regression cases passed via the documented standalone runner.
Actual XCTest remains unavailable on this Command Line Tools-only Mac; both
pre/post `swift test` attempts recorded that limitation. New independent oracles
cover energy conversions, XYZ unit/provenance/export, separate SCF/final energy,
symmetric versus fixed-atom distance edits, and analytic angle coordinates.
Three Matplotlib tests passed: reference/units/missing-data numerics, PDF/SVG/PNG
formats, 4080×3120 PNG at 600 dpi, CSV values, and rejection of insufficient data.
The macOS CI workflow now installs plotting dependencies and runs those tests;
this local session does not claim to have run CI.

Both packaged live-window checks passed locally. The new energy-workflow check
exercises six-atom selection/deselection through renderer callbacks, actual key
routing/focus protection, both distance modes, angle edits, invalidated-energy
export, per-frame Undo, exact SCF source links, the bundled Python script, all
figure exports, and a visible plot sheet. It uses synthetic labelled fixtures;
none of its illustrative energies are calculation results. Automated control
routing is not a claim of manual pointer/trackpad/save-dialog acceptance.

Local screenshots and figure artifacts were inspected under
`/Users/nacho/Downloads/chemviewer-energy-work/evidence`: `abstract-energies.png`,
`abstract-scf.png`, `angle-editor.png`, `matplotlib-sheet.png`, and
`energy-profile.{pdf,svg,png,csv}`. All depict independent synthetic input.
Test commands:

```
bash scripts/build-macos.sh
"$HOME/Library/Application Support/ChemViewer/plotting-venv/bin/python3" -m unittest python_tests.test_energy_plot -v
dist/ChemViewer.app/Contents/MacOS/ChemViewer -ApplePersistenceIgnoreState YES --smoke-test
dist/ChemViewer.app/Contents/MacOS/ChemViewer -ApplePersistenceIgnoreState YES --energy-smoke-test --capture-window --energy-evidence /Users/nacho/Downloads/chemviewer-energy-work/evidence
```

The persistence flag isolates tests from saved-window restoration. One direct
CLI launch initially idled without a window; the isolated launch proceeded and
passed. It did not crash, and the existing user app process was left intact.
Remaining broad parser, fragment-builder, orbital and full-parity limits are
unchanged by this bounded update.

The installed ORCA water compound-job reference was additionally validated natively: six geometries, nine modes, final energy −76.360968646 Eh, distinct SCF/final records, last-frame association and exact source-line snippets all passed. The proprietary input remains outside the repository.
