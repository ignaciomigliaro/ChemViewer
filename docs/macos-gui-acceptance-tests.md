# ChemViewer macOS GUI acceptance tests

These tests translate observed Windows reference behavior into release gates
for the independent macOS app. Automated core tests may establish scientific
values, but interactive rows require an actual Apple Silicon GUI run.

## Required Apple Silicon matrix

Record Mac model, macOS version, Xcode/Swift version, display scale, build SHA,
and whether the app came from a local build or GitHub artifact. Test at Retina
scale and, when available, an external display.

| ID | Expected ChemViewer behavior | Fixture | Acceptance criterion | Current state |
|---|---|---|---|---|
| CV-GUI-001 | Launch native app and show empty workspace | none | arm64 executable; no crash; responsive window | Pending Mac |
| CV-GUI-002 | Open from toolbar, Cmd+O, Finder, and drag/drop | `water.xyz` | all routes produce the same 3 atoms; cancel is harmless | Partial source; drag/drop pending |
| CV-GUI-003 | Render atoms/bonds at Retina resolution | `methane.xyz` | correct 5 atoms/4 bonds; no clipping or blurry scaling | Pending Mac |
| CV-GUI-004 | Rotate with drag and right-drag; pan with Option-drag; wheel zoom | `methane.xyz` | each gesture changes only intended camera state; right-drag matches Windows rotation | Implemented; pending Mac |
| CV-GUI-005 | Select one to four atoms with click plus Shift/Cmd-click | `water.xyz`, `dihedral.xyz` | selection highlight and ordered identities are stable | Implemented; pending Mac |
| CV-GUI-006 | Display distance, angle, and signed dihedral | same | 0.95720 A, 104.520 degrees, 116.565 degrees within 1e-5/1e-3/1e-3 | Core implemented; Swift/GUI pending |
| CV-GUI-007 | Edit Cartesian coordinates and undo | `water.xyz` | committed coordinate changes geometry; undo restores exact values | Partial source; pending Mac |
| CV-GUI-008 | Browse a multi-frame trajectory and play/pause | deterministic multi-XYZ plus ORCA optimization | frame count/order exact; 0.5 s playback cycles without UI blocking | Implemented; pending Mac |
| CV-GUI-009 | Parse ORCA compound optimization/frequency | authorized hashed reference file | final energy -76.360968646 Eh; 9 modes; key frequencies exact within 0.01 cm^-1 | Oracle pass; Swift/Mac pending |
| CV-GUI-010 | Animate the 1606.12 cm^-1 normal mode | ORCA reference | continuous symmetric motion; pause freezes; amplitude changes display only | Source implemented; pending Mac |
| CV-GUI-011 | Mark and animate imaginary mode | clean-room negative-mode fixture | negative value remains negative/red; no real-frequency reinterpretation | Unit source exists; real OptTS fixture needed |
| CV-GUI-012 | Toggle displacement arrows | mode fixture | arrow origin/direction follows source vectors; toggle never crashes | Source implemented; pending Mac |
| CV-GUI-013 | Show IR sticks and broadened curves | ORCA reference | source positions/intensities preserved; Gaussian/Lorentzian HWHM semantics pass | Core implemented; pending Mac |
| CV-GUI-014 | Open/save structure | `water.xyz` | exported XYZ reparses with identical symbols/coordinates | Save not implemented |
| CV-GUI-015 | Export image | `water.xyz` | requested pixel size, background, and antialiasing are deterministic | Not implemented |
| CV-GUI-016 | Load MO/density grid and render signed isosurfaces | clean-room cube/fchk fixture | grid dimensions/units exact; +/- lobes and isovalue controls visible | Not implemented |
| CV-GUI-017 | IRC/PES/NEB navigation and energy plot | licensed-to-use redistributable fixtures | frame order, reaction coordinate, absolute/relative energy and barriers match oracle | Not implemented |
| CV-GUI-018 | Large-system responsiveness | generated 10k and 100k atom cases | no main-thread parsing stall; documented memory/frame-time limits | Pending |

## Procedure and evidence

For every interactive case:

1. Record input path and SHA-256.
2. Start from a new app launch and document all clicks/shortcuts.
3. Capture before/after screenshots and app/system logs.
4. Record displayed and parsed numeric values separately.
5. Repeat once after relaunch and once from the packaged `.app`.
6. Mark pass only when both scientific and interaction criteria pass.

GitHub Actions on `macos-15` can compile and execute Swift unit tests natively
on Apple Silicon and produce an ad-hoc-signed artifact. It cannot validate
human-visible Metal output or normal macOS interaction; those rows remain
pending until observed on the physical Mac.
