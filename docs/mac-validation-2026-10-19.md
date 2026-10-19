# Local Apple Silicon validation — 2026-10-19

Environment: arm64, macOS 26.5.1 (25F80), Apple Swift 6.3.3, developer directory `/Library/Developer/CommandLineTools`. Full Xcode is not installed.

## Confirmed defect and fix

`swift test` fails at `import XCTest` with this toolchain. The default packaging script now detects whether `xctest` is available: full Xcode runs genuine XCTest, while Command Line Tools runs the same checked-in core assertion cases using `scripts/check-core.py`. This script creates a temporary standalone Swift entry point, explicitly adapts the supported assertion calls, and fails on unsupported XCTest constructs or assertion failures. It neither installs nor emulates an XCTest module. `--require-xctest` remains strict and is used by CI.

A real CRLF ORCA reference initially parsed six one-atom geometries and truncated vectors. Both text parsers now normalize LF, CRLF and CR. Frequency vectors are bound to the geometry before their frequency block, not a later compound job. Incomplete/duplicate/nonfinite vector data is not completed with invented zeros. Missing final matrices/intensities are not borrowed from earlier jobs. Nonfinite coordinates are rejected. File-load generation guards prevent stale background results; normal modes are disabled after geometry edits; frame changes clear incompatible undo history.

## Observed checks

- Default `bash scripts/build-macos.sh`: passed; 11 standalone core regression methods, release compilation, ARM64 verification, packaged resource copy and strict local signature verification.
- `--smoke-test` on the packaged executable: passed, with a real SwiftUI window, live Metal pipelines and completed GPU command buffers. Exercised XYZ opening/export, coordinate undo, selection propagation, synthetic negative ORCA mode selection, continuous frame production and pause.
- Native Swift parser checked against the authorized installed water ORCA reference: six three-atom geometries, frequency frame 5 (zero-based), final energy -76.360968646 Eh, nine modes, mode 6 at 1606.12 cm^-1, oxygen-z displacement -0.070076. Passed the documented tolerances.
- Independent Python reference suite: three scientific regression methods passed on the same locally installed reference. No proprietary input was copied into the repository.
- Shell syntax and `git diff --check`: passed.

Logs and temporary native reference harness are under `/Users/nacho/Downloads/chemviewer-validation`.

## Limits

This is not a claim of full Chemcraft parity or proven long-term stability. Manual file-panel/Finder/drag-drop interaction, visual depth/Retina fidelity, trackpad gestures, coordinate-sheet interaction, IR window appearance, large systems and the remaining acceptance matrix still require their own observed checks. Genuine XCTest remains unavailable on this host until full Xcode is selected. The existing full-Xcode CI route is retained. No Gatekeeper, quarantine, SIP, registration or license controls were weakened.
