# ChemViewer agent instructions

## User context

The user is a computational chemistry researcher working with machine
learning, molecular dynamics, quantum mechanics, and scientific software.
Prefer precise scientific terminology, reproducible tests, and direct evidence.

## Objective

Build ChemViewer, an independent, native Apple Silicon molecular visualization
and computational-chemistry analysis application. Windows Chemcraft is an
authorized behavioral and file-compatibility reference, not a source-code
base. A window opening is not completion; daily-use reliability, numerical
accuracy, and tested workflows are the release criteria.

Read these files before changing code:

1. `PROJECT-BRIEF.txt` — the complete user request and milestone definition.
2. `CONVERSATION-HANDOFF.md` — current evidence, commands, and blockers.
3. `docs/feature-parity.md` — honest implementation/test status.
4. `docs/macos-gui-acceptance-tests.md` — required physical-Mac checks.
5. `docs/windows-gui-audit.md` — observed Windows behavior.

## Clean-room and licensing boundary

- Do not commit or redistribute Chemcraft executables, official application
  bundles, proprietary assets/databases, registration material, decompiled
  source, screenshots containing license identities, or proprietary sample
  output.
- Do not bypass licensing, registration, trial restrictions, Gatekeeper, SIP,
  or other security controls.
- Implement original code from documented formats, independent scientific
  references, and observable behavior.
- Keep generated Windows captures under the ignored
  `Tests/references/windows/runs/` directory.
- Add fixtures only when independently generated or clearly redistributable.

## Scientific rules

- Preserve source values and units at parse boundaries; never invent missing
  chemistry data.
- Retain negative frequencies as imaginary modes.
- Keep energies in Hartree and coordinates/displacements in their declared
  source units until an explicit, tested conversion.
- Distinguish IR intensity, Raman activity, oscillator strength, and display
  amplitude.
- A scientific feature needs a traceable fixture and independent numeric
  oracle before it can be called tested.

## Development workflow

- Keep parsers and geometry algorithms in `ChemCraftCore`; keep SwiftUI/AppKit
  and Metal code in the ChemViewer executable target.
- Run `swift test` before and after meaningful core changes.
- Build the app with `bash scripts/build-macos.sh`; it must produce
  `dist/ChemViewer.app` with an arm64 executable.
- On Windows, run the portable oracles with
  `py -3 -m unittest discover -s python_tests -v` and the GUI harness with
  `Tests/gui/windows/.venv/Scripts/python.exe -m pytest Tests/gui/windows -q`.
- Do not mark an interactive test passed from CI alone. Execute the relevant
  steps in `docs/macos-gui-acceptance-tests.md` on a real Apple Silicon GUI.
- Update architecture, validation, feature-parity, and handoff docs in the same
  change as implementation status.

## First Mac session

1. Record `uname -m`, `sw_vers`, `swift --version`, and `xcodebuild -version`.
2. Run `swift test` and `bash scripts/build-macos.sh`; fix compile/runtime issues
   before adding features.
3. Launch `dist/ChemViewer.app` and execute CV-GUI-001 through CV-GUI-013.
4. Run the read-only official-app diagnostic procedure in
   `docs/macos-diagnostics.md`; do not weaken system protections.
5. Download the GitHub Actions artifact and repeat launch/open tests separately
   from the local build.
6. Record every failure, screenshot, input hash, numeric result, and crash log.

## Immediate priorities after the first successful build

1. Correct any Swift/compiler, Metal resource, Retina, picking, or gesture bug.
2. Implement tested XYZ save and deterministic image export.
3. Add a redistributable ORCA OptTS negative-frequency fixture.
4. Implement ORCA optimization metadata and IRC/PES/NEB data models/plots.
5. Add cube parsing and signed MO/electron-density isosurfaces.
6. Expand parsers only with a fixture-and-oracle acceptance test.

When evidence is incomplete, label the result as partial or blocked and state
the exact missing input or environment. Never report full Chemcraft parity
until every required feature has passed the documented gate.

## User-authorized version publishing

The user explicitly requested on 2026-10-19 that each completed ChemViewer version be committed and pushed. This authorization persists across sessions. After the version's required checks pass, commit the relevant source, tests, packaging assets and documentation; create an annotated `v<CFBundleShortVersionString>` tag for that exact version; and push the current branch and that tag to the existing origin. Verify the remote branch/tag afterward and report the commit/tag. Do not ask for repeated permission for this release workflow. Never force-push or overwrite existing tags. Exclude personal calculations, vendor binaries/assets, generated build outputs, credentials and local evidence. If pushing fails, preserve the local commit/tag and state the exact blocker. Earlier builds without saved source snapshots must not be reconstructed as fictitious version commits.
