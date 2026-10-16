# Windows GUI audit

Audit date: 2026-10-16. Reference installation: `C:\Chemcraft`.

## Scope and evidence boundary

The licensed Windows application was treated as a behavioral reference. The
installation was read-only; fixtures were copied into timestamped run folders
under `Tests/references/windows/runs/`. Those folders are ignored because
screenshots and opened-file text may contain proprietary or personal data.
Only clean-room fixtures, hashes, observations, and numeric results are
promoted into version control.

The tested executable SHA-256 is
`79fe75015a1e48c4df29e7bac4c3c05e67057bf3a0ed03a7b77fe85528d4f05a`.
The desktop was 2560 x 1440 at 100% scaling and 96 DPI.

The bundled Windows-control helper failed during initialization with
`helper_unknown_error: setup refresh had errors`. The audit recovered with a
project-local Python environment using pywinauto 0.6.9, PyAutoGUI 0.9.54,
Pillow 11.3.0, and pytest 8.4.2. UIA and Win32 inspection were used where the
application exposed controls; calibrated screenshots and input were used for
the custom-drawn viewport and toolbars.

## Interface architecture

The main window is a Delphi-style `TMainForm`. UIA exposes the top menu and
mode tabs, while the molecule viewport and many toolbar controls are
custom-drawn. The observable top-level modes are Image, Abstract, Source,
Coord, and Image/Abs. Plain XYZ enables Image, Source, and Coord; parsed output
files can additionally enable Abstract and a hierarchical result tree.

Top menus observed directly are File, Edit, View, Display, Tools, and Help.
The complete captured menu and submenu inventory is summarized in
`gui-feature-inventory.md`. Raw evidence is in runs `20261016T002432Z`,
`20261016T004617Z`, and `20261016T010108Z`.

## Verified workflows

| Workflow | Input / evidence | Result |
|---|---|---|
| XYZ rendering | clean-room `water.xyz`; run `20261016T002914Z` | O/H/H rendered; Image, Source, and Coord available; coordinates preserved |
| Camera controls | clean-room `methane.xyz`; run `20261016T003149Z` | right-drag rotates, wheel zooms, and toolbar rotation/zoom/translation change the image deterministically |
| Selection and measurement | clean-room `water.xyz`; run `20261016T005148Z` | two selections display 0.95720 A; three display 104.520 degrees |
| Signed dihedral | clean-room `dihedral.xyz`; run `20261016T005307Z` | four selected atoms display 116.565 degrees |
| ORCA optimization/frequency | installed water compound-job output; run `20261016T003538Z` | optimization tree, playback controls, nine modes, 1606.12/3678.02/3777.72 cm^-1, and time-varying animation observed |
| Molecular-orbital entry | installed Gaussian `ch4.fch`; runs `20261016T005826Z` and `20261016T005907Z` | 23 alpha orbitals plus density, occupancy/energy list, grid dialog, and isosurface controls observed |
| Structure export | clean-room water; run `20261016T011131Z` | symbol-format XYZ written and values preserved |
| Image export | clean-room water; run `20261016T011131Z` | JPEG dialog and output verified; output was 816 x 447 pixels |
| Gaussian IRC recognition | installed `Gaussian/IRC/IRC.out`; run `20261016T011218Z` | four job roots observed, including `Job 4 : IRC`; Image/Abstract/Source/Coord available; deeper run invalidated after focus mismatch |
| Gaussian PES scan | installed `H2O_PES_MODRED.out`; runs `20261016T144043Z` and `20261016T144337Z` | `Scan` tree with 21 points labeled A1=120 through A1=80 in two-degree steps, plus optimized geometry |
| Quantum Espresso NEB coordinates | installed `110Au_dif_H_2_surf1_5im_manual.crd`; run `20261016T144626Z` | blocked by a Supplementary files dialog; coordinate file alone is not a self-contained workflow |

The promoted machine-readable values are in
`Tests/references/windows/gui-scientific-reference.json`. Independent Python
geometry calculations reproduce all displayed measurement values within the
displayed precision.

## Frequency and orbital details

Selecting the ORCA 1606.12 cm^-1 mode automatically animated the molecule.
The visible control panel contained amplitude scale, cycle time, freeze,
rebonding, displacement-vector display, vector scaling, and a 0.00120
threshold. Optimization playback exposed a 0.5 time value and smooth-animation
option.

The methane formatted-checkpoint orbital dialog listed occupied MO 1 through
MO 5 and unoccupied MO 6 through MO 23. The observed HOMO/LUMO display values
were -0.5437 and 0.2551; the GUI did not label a unit, so none is inferred.
MO 5 grid generation produced a result-tree node and controls for signed
isosurfaces, contour value, colors, mapping, transparency-related style, and
cube operations. A final unmistakable lobe rendering was not captured, so the
visible-isosurface result remains partial.

## Incidents and unverified behavior

- A click on Show displacement vectors during run `20261016T003911Z` left the
  process alive but removed the visible top-level window. The exact incident is
  recorded in `Tests/references/windows/displacement-vectors-incident.json`.
  This requires a manual reference retest; it is not a pass.
- The visible Show spectrum control was observed, but the calibrated activation
  did not open a spectrum window. IR spectrum activation remains unverified.
- No installed ORCA transition-state output with a negative frequency was
  found. A later Gaussian tree run appeared to expose imaginary values, but a
  screenshot proved that run had lost focus to Visual Studio Code; all detailed
  values from that run are excluded pending a clean retest.
- The Gaussian IRC job hierarchy was recognized, but path-frame playback and
  the IRC energy graph were not exercised. A Gaussian PES scan tree was
  verified. The available Quantum Espresso NEB coordinate file requires
  supplementary files, so NEB remains blocked on a complete fixture.
- The audit did not test every dialog, format, or destructive editor action.
- No interactive macOS behavior is claimed; that requires an actual Mac.

## Reproduction

From the project root on the authorized Windows host:

```powershell
.\Tests\gui\windows\.venv\Scripts\python.exe -m pytest .\Tests\gui\windows -q
.\Tests\gui\windows\.venv\Scripts\python.exe .\Tests\gui\windows\chemcraft_driver.py menus
.\Tests\gui\windows\.venv\Scripts\python.exe .\Tests\gui\windows\chemcraft_driver.py xyz-workflow --fixture .\Tests\fixtures\methane.xyz
.\Tests\gui\windows\.venv\Scripts\python.exe .\Tests\gui\windows\chemcraft_driver.py measurements --fixture .\Tests\fixtures\water.xyz
.\Tests\gui\windows\.venv\Scripts\python.exe .\Tests\gui\windows\chemcraft_driver.py select-all --fixture .\Tests\fixtures\dihedral.xyz
.\Tests\gui\windows\.venv\Scripts\python.exe .\Tests\gui\windows\chemcraft_driver.py result-tree --fixture <output-file>
```

Visual actions are calibrated for the recorded display geometry. On a different
resolution or scaling, rerun inventory first and treat calibrated actions as
manual until their coordinates are updated.

## Focus-integrity correction

Run `20261016T144501Z` is invalid. Its third screenshot captured Visual Studio
Code instead of Chemcraft, as the user correctly identified. No detailed tree
or numerical claim from that run is used. The incident is recorded in
`Tests/references/windows/focus-mismatch-incident.json`; the driver now refuses
to capture unless the exact target window handle is foreground. Earlier PES
and NEB screenshots were visually rechecked and show Chemcraft and its
Supplementary files dialog respectively.
