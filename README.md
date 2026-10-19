# ChemViewer (clean-room macOS implementation)

This repository is an independent macOS implementation of practical ChemCraft
workflows. It does not contain ChemCraft code, assets, license material, or
decompiled source. The Windows application is treated only as a behavioral and
file-compatibility reference.

## Current working slice

- Native SwiftUI macOS interface with a calculation, geometry, and frequency tree.
- Metal renderer for element-colored atoms and inferred bonds.
- Mouse and right-drag rotation, Option-drag panning, and scroll zoom.
- Multi-frame XYZ parsing, including element symbols or atomic numbers.
- ORCA text-output parsing for Cartesian geometries, final energies,
  vibrational frequencies, normal-mode displacement vectors, and IR intensity.
- Normal-mode animation with imaginary frequencies highlighted in red.
- Optional scaled normal-mode arrows in the Metal viewport.
- Editable Cartesian coordinate table with geometry undo.
- Click/Shift-click atom selection with distance, angle, and signed-dihedral readouts.
- Multi-frame trajectory play/pause at the Windows reference default interval.
- Interactive IR stick spectra with Gaussian or Lorentzian broadening.
- Background parsing so large text files do not block the UI.
- Swift unit tests plus an independent Python regression oracle.

This is Milestone 3's first application slice, not feature parity. Molecular
orbitals, volumetric surfaces, internal-coordinate editing, Raman/UV-visible spectra, and
most file formats are still pending and are tracked in
`docs/feature-parity.md`.

## Build on Apple Silicon

Requirements: macOS 13 or later and a Swift 5.9+ toolchain (Apple Command Line Tools or full Xcode).

```bash
cd ~/Documents/software/ChemViewer
bash scripts/build-macos.sh
open dist/ChemViewer.app
```

To build and update the installed app in one command:

```bash
bash scripts/install-macos.sh
```

This updates `/Applications/ChemViewer.app` and any existing `~/Applications/ChemViewer.app` copy, so existing shortcuts open the current version. Quit and reopen ChemViewer after updating; no Finder dragging is needed. After an already validated build, use `bash scripts/install-macos.sh --no-build`. The script does not close the running app or discard unsaved work.

The script runs XCTest when full Xcode is selected. On Command Line Tools-only Macs it instead runs the checked-in core regression assertions through an explicitly standalone runner (not XCTest). CI requires genuine XCTest with `--require-xctest`. It then builds an ARM64 executable, creates a conventional
`.app` bundle, copies SwiftPM resources, applies an ad-hoc local signature, and
verifies the bundle. Distribution outside the development machine will require
an Apple Developer ID signature and notarization.

## Private GitHub build artifact

`.github/workflows/macos.yml` runs on a native Apple Silicon `macos-15`
GitHub-hosted runner. On every push to `main` (or a manual dispatch), it runs
the Swift tests, builds and verifies `ChemViewer.app`, and uploads
`ChemViewer-macos-arm64.zip` as a 30-day workflow artifact. See
`docs/github-delivery.md` for the download, signing, and Gatekeeper boundary.

CI validates compilation and noninteractive tests only. Metal appearance,
Finder opening, gestures, and other interactive behavior must still pass
`docs/macos-gui-acceptance-tests.md` on the physical Mac.

The private repository is `https://github.com/ignaciomigliaro/ChemViewer`.
Apple Silicon run `38922066239` passed all seven Swift tests plus the arm64,
bundle-signature, packaging, and artifact-upload checks. Download its
`ChemViewer-macos-arm64` artifact from the repository's **Actions** page.

## Tests on the evidence host

The portable reference test runs without third-party Python packages:

```powershell
py -3 -m unittest discover -s .\python_tests -v
```

The portable oracle tests check the installed ORCA water fixture for atom
identity, per-geometry and final energies, nine mode frequencies, IR intensity,
and normal-mode vectors; compound-job section selection; and the official
ARM/Intel Mach-O architecture, dependency, and signature shape. Swift tests run
as part of `scripts/build-macos.sh` on macOS.

## Official-macOS diagnosis

The current official b638m ARM and Intel DMGs were downloaded and statically
inspected. Both are Lazarus LCL/Cocoa applications with only Apple system
dependencies. The ARM binary is ad-hoc/linker-signed without a certificate or
hardened runtime; Intel is unsigned. No target-Mac crash report or live launch
evidence is available yet. On the target Mac, run:

```bash
bash scripts/collect-macos-diagnostics.sh /Applications/Chemcraft.app
```

The script is read-only: it records architecture, code-signing, Gatekeeper,
quarantine attributes, linked libraries, load commands, hashes, and recent
ChemCraft crash reports. It does not clear quarantine or change security
settings. See `docs/macos-diagnostics.md`.

## Documentation

- `docs/architecture.md` — modular design and implementation decisions.
- `docs/windows-feature-inventory.md` — reference functionality and evidence.
- `docs/windows-gui-audit.md` — direct Windows GUI observations and incidents.
- `docs/gui-feature-inventory.md` — observed controls and workflow status.
- `docs/macos-gui-acceptance-tests.md` — Apple Silicon release checks.
- `docs/macos-diagnostics.md` — current diagnosis and target-Mac procedure.
- `docs/reverse-engineering-findings.md` — observation/inference ledger.
- `docs/feature-parity.md` — implementation and test status.
- `docs/scientific-validation.md` — units, fixtures, tolerances, and results.

## Legal boundary

Use only legally obtained ChemCraft builds and files. Do not commit or
redistribute ChemCraft executables, proprietary databases, registration data,
or recovered source. Do not bypass licensing or access controls. Test fixtures
added to this repository must be independently generated or redistributable.

## Local Mac validation (2026-10-19)

The app now builds on the user's Command Line Tools-only ARM64 Mac. Run `bash scripts/build-macos.sh`, then `open dist/ChemViewer.app`. Full Xcode is required for `swift test`, but not for this local build-and-check path.

The packaged app has an opt-in integration check:

```bash
dist/ChemViewer.app/Contents/MacOS/ChemViewer --smoke-test
```

This opens a test window, checks the actual Metal shader pipelines and completed GPU frames, XYZ opening/export, coordinate undo, selection, negative-mode loading, animation and pause, then exits. It does not replace human checks of visual fidelity, gestures and native file dialogs. See `docs/mac-validation-2026-10-19.md` for results and limits.

### Updated molecular view (0.2.0)

Use Image / Abstract / Source / Coord / Image/Abs (Cmd+1…5) to switch between the molecule, parsed summary, original output, editable coordinates and split view. Display offers Publication, Soft spheres, Large spheres and Sticks. The camera icon exports a PNG of the current viewport. The Publication and Soft palettes are inspired by [xyzrender](https://github.com/aligfellow/xyzrender); its MIT notice is included with the app. Rendering is native Metal. This update does not establish full Chemcraft feature parity; see [validation and limits](docs/rendering-and-ui-2026-10-19.md).

### Energies, plots and molecular edits (0.3.0)

Abstract now pairs geometries with energies/structures and links ORCA SCF/final-energy sections to original output. For unitless XYZ comments, choose the input energy unit there. Arrow keys browse geometries. Left-click toggles unlimited atom selection; two atoms expose distance editing (second only or both equally), three expose angle editing. Undo restores energy together with geometry.

**Energy landscape…** uses Matplotlib for relative/absolute energy profiles, with optional selected distance/angle axes and molecular thumbnails. Export includes vector PDF/SVG, 600-dpi PNG, CSV and a reproducible script. Set up the optional plotting runtime with `bash scripts/setup-plotting.sh` (already installed on the current Mac). See [usage, scientific behavior and validation](docs/energy-and-editing-2026-10-19.md).

### Thermochemistry and dragging (0.4.0)

Right-click clears selection. The hand/Atom/Fragment/Molecule toolbar enables coordinate dragging and ±X/Y/Z rotation/translation with a selectable pivot. Select a bonded pair before Fragment to isolate its second side. Angle editing now offers C-only or symmetric A/C movement about B. Abstract has compact copyable E/H/G rows and electronic-plus-thermal sums; Coord has Copy coordinates and Copy XYZ. See [behavior and validation](docs/thermochemistry-and-manipulation-2026-10-19.md).

### Measurements and smooth interaction (0.5.0)

Select 2, 3 or 4 atoms and enable Show bond length / Show angle / Show dihedral to annotate the molecule and exported PNG. Four selections also expose a signed-dihedral readout. Mouse view rotation follows the grab direction. Local drag previews and cached instanced meshes reduce update overhead; the 500-atom local benchmark's median CPU draw time fell from 17.05 to 1.17 ms. See [validation and scope](docs/measurements-and-smooth-drag-2026-10-19.md).

### Paton appearance and GIF export (0.6.0)

The default drawing style is **xyzrender · Paton**, adapted to the native renderer. Switch appearances in the toolbar or Display menu. Rotate your molecule, then use **File → Export Animation as GIF…** for multi-XYZ/ORCA geometries or the selected normal mode. The GIF keeps your viewing angle and fits the full animation once. Choose size, frame rate and optional forward/backward trajectory playback. See [details and limits](docs/paton-and-gif-2026-10-19.md).

## One app: ChemViewer 0.7.0

MoleculeView's implemented builder, project and classic GUI features are now integrated here. Use **+** or **Cmd-B** for the right-hand builder; **File → New Molecule** starts a structure. Add/import/attach fragments, insert/replace/duplicate/delete atoms, select ranges/groups, transform about axes or a saved bond, Undo/Redo, save projects and export ORCA geometry. Existing `.mvproject` files open in ChemViewer; save new working projects as `.cvproject`. The Paton Metal renderer and every existing analysis/measurement/GIF workflow are retained. **View → Result Explorer** restores left-side trajectory/frequency browsing. See [feature reconciliation and limits](docs/moleculeview-integration-2026-10-19.md).

## 0.7.1 — left explorer restored by default

The geometry/frequency Result Explorer is visible on the left at startup again, as requested. Its geometry selection, per-frame frequency selection and arrow navigation are retained; View → Result Explorer or the sidebar toolbar button still toggles it. The optional right-hand builder remains available with +/Cmd-B. This supersedes 0.7.0’s initially hidden explorer. Verify by opening a multi-geometry ORCA output and browsing geometries and modes from the left panel.

Measurement labels can be repositioned: enable the bond/angle/dihedral overlay, then drag its white label box. Use **Reset label** to restore placement. The moved placement carries into PNG and annotated GIF exports.

The native app icon is bundled at all standard/Retina sizes. Its editable master is Packaging/ChemViewerIcon.png; rebuild it with `bash scripts/build-icon.sh` (also run by the macOS build).

ORCA NEB-TS outputs now open the energy sheet with a reaction-profile option selected: reactant–TS–product levels, forward/reverse barriers, full-band image view, optional structures, and a toggle back to optimization history. Use **Markers** to make PES plots lines only. [NEB plotting details](docs/neb-reaction-profiles-2026-10-19.md).

Versioned releases are checkpointed in Git and pushed to origin after validation, using annotated `vX.Y.Z` tags. The initial cumulative checkpoint for the locally developed 0.3–0.8 features is `v0.8.0`; earlier local builds were not independently tagged.

GIF export defaults to a transparent background (switch it off for white). Atom-number and element captions no longer have white rectangles. GIF transparency is binary; fractional edge opacity cannot be retained.

## Expanded builder and local workflows (0.9.0)

Command-B opens the searchable 258-entry fragment/metal-center library. Choose a fragment, then click a host atom; right-click finishes. Add any element, reuse/save selected fragments, remove unused X sites, and run cancellable UFF cleanup with fixed atoms and undo. **ChemRefine workflow…** opens the real local workflow editor seeded from the current geometry; configure installed engines there. The chemistry runtime is already installed on this Mac. See [usage and validation](docs/building-and-local-workflows.md).

## Popup builder and ChemRefine tab (0.9.1)

Press **Command-B** or **+** to open the fragment preview gallery. Choose a structure, then left-click blank canvas to place it (including in an empty molecule), or an atom to attach it. Right-click finishes. The gallery contains 265 choices including the original templates. **Command-Shift-B** opens editing/UFF controls. **ChemRefine** now has its own main tab (**Command-6**) with the real local workflow editor.
