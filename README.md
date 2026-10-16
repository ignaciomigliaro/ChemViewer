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

Requirements: macOS 13 or later and Xcode 15 or later.

```bash
cd chemcraft-macos
bash scripts/build-macos.sh
open dist/ChemViewer.app
```

The script runs Swift tests, builds an ARM64 executable, creates a conventional
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
