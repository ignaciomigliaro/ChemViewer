# Private GitHub delivery

The repository contains source, tests, clean-room fixtures, the Windows
behavioral audit, Apple Silicon CI, and the Codex continuation instructions in
`AGENTS.md`. Generated screenshots, proprietary binaries, downloaded official
DMGs/apps, local virtual environments, build output, and diagnostic output are
ignored.

## Expected private-repository flow

1. Create a private repository named `ChemViewer`.
2. Push this directory as the `main` branch.
3. Allow the `Apple Silicon build` workflow to run on `macos-15`.
4. Download the `ChemViewer-macos-arm64` workflow artifact.
5. Unzip it on the Mac and try the normal Finder/Open flow. The CI artifact is
   ad-hoc signed, not Developer-ID signed or notarized; do not disable macOS
   security protections to force it to launch.
6. If the downloaded artifact is blocked, build locally with
   `bash scripts/build-macos.sh` and preserve the exact Gatekeeper diagnostic.

The workflow runs Swift tests, builds only arm64, verifies architecture and
signature structure, packages `ChemViewer.app`, and retains the ZIP artifact
for 30 days. CI proves compilation and noninteractive tests; it does not prove
Metal appearance or GUI usability.

Do not add Apple signing certificates, private keys, GitHub tokens, or
provisioning profiles to the repository. A broadly distributable build will
require a Developer ID certificate and notarization configured through
encrypted repository secrets or a separate trusted release process.
