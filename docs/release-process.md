# Branches, validation and releases

## Branch policy

Use short-lived `feature/…`, `fix/…` or `release/…` branches from current `main`.
Open a pull request, keep it current with main, and squash merge after the required
`release-gate` succeeds. Preserve the scientific fixture/oracle and documentation
with each implementation change. Avoid unrelated personal files in a release.

Main protection requires a pull request, up-to-date status checks, resolved review
conversations and linear history; force pushes and branch deletion are disabled.
Administrators are subject to these checks. The required status is `release-gate`.
No approval from another person is mandatory for this single-owner repository;
CODEOWNERS identifies ownership and reviews can still be requested. This permits
the owner to merge their own PR after validation without an impossible self-approval.

The workflow runs on **every push**, all pull requests, merge-group events and
manual dispatch, with no path exclusions. A failing, cancelled or skipped required
job makes the aggregate gate fail. Separate PRs cannot substitute one another's
checks. Superseded feature-branch runs are cancelled; main validation is retained.
Dependabot opens updates for Actions and pinned test dependencies.

## Automated gates

| Job | Required checks |
|---|---|
| Portable · Windows x86_64, Ubuntu x86_64, Mac arm64 | Real Swift XCTest; three migrated parser/editing/state suites; six executable regressions; five offline Chromium tests; release ZIP and execution after relocation |
| Core coverage · Ubuntu and Mac | LLVM source line coverage for every ChemCraftCore file, uploaded JSON and per-file floors |
| Scientific Python · Ubuntu and Mac | All discoverable redistributable Python tests, installed RDKit/ASE/Matplotlib/ChemRefine dependencies, branch coverage and uploaded XML/JSON |
| Native Mac | Genuine XCTest, migrated suites, arm64 release build, strict signature verification, app ZIP and relocated-resource/missing-helper checks |
| Release gate | Every preceding platform/job must report success |

The Windows Swift installer action is pinned to a commit; Linux uses the official
Swift6.1.3 container pinned to its image digest. See the [Windows setup documentation](https://github.com/compnerd/gha-setup-swift)
and [official Swift container](https://hub.docker.com/_/swift).
Test Python dependencies are pinned in `requirements-test.txt`, including an exact
ChemRefine commit. These checks do not install ORCA, proprietary datasets or model
credentials and do not submit cluster jobs.

### Coverage interpretation

`Tests/coverage-floors.json` records per-module minimums from measured baselines.
Every core Swift/Python helper file must be registered; absent coverage fails the
check. Floors are rounded down from measurements, not a claim that all functionality
is correct. New code needs independent behavioral assertions; do not lower floors
to hide a failure. Raise floors as previously untested paths gain meaningful tests.

The core baseline ranges from61% in NEB summary paths to100% in ORCA inputs, vector
math and portable serialization. The migrated builder suites now also run inside
XCTest, raising measured integrated-builder coverage from56% to93%. ORCA output is 98%
and XYZ 94% minimum. Python helper aggregate is approximately 83% combined line/
branch coverage; the remote agent remains a weaker area at a 67% floor. Coverage
currently measures source paths, not full GUI behavior or scientific correctness.
SwiftUI/AppKit/Metal code is verified by app build and separate native acceptance;
Chromium acceptance covers the portable interface. No total-app percentage is claimed.

### Local reproduction

With full Xcode selected on Mac, or an installed Swift toolchain on Linux/Windows:

```bash
swift test --enable-code-coverage
python scripts/check-coverage.py --swift "$(swift test --show-codecov-path)"
python scripts/check-building.py
python scripts/check-portable.py --binary .build/debug/ChemViewerPortable
python -m pip install -r requirements-test.txt
python -m coverage run -m unittest discover -s python_tests -v
python -m coverage report
python -m coverage json
python scripts/check-coverage.py --python .build/python-coverage.json
```

On Windows run `swift test` without coverage and use `.exe` for the portable binary;
run the POSIX remote/engine Python suite in Linux/WSL or its required CI jobs.
For browser checks:

```bash
python -m pip install playwright==1.55.0
python -m playwright install --with-deps chromium
CHEMVIEWER_PORTABLE_BINARY=.build/debug/ChemViewerPortable python Tests/gui/portable/test_viewer.py
```

In PowerShell use `$env:CHEMVIEWER_PORTABLE_BINARY = '.build/debug/ChemViewerPortable.exe'`
and then run the Python test file. Browser tests fail if the browser dependency is
missing; they do not silently skip. CLI checks use real files and the built binary,
including malformed inputs, Unicode paths, source injection, relative companions,
negative modes, missing properties, XYZ round trips and overwrite refusal.

Licensed external-corpus tests use `CHEMVIEWER_REFERENCE_CORPUS` and remain optional;
the official-artifact diagnostic test also skips absent proprietary binaries. Three
such skips are expected on a clean Mac/Linux checkout. Their redistributable
synthetic counterparts remain mandatory. These skips are not successful reference
application acceptance tests.

Command Line Tools-only Macs cannot run XCTest here. `bash scripts/build-macos.sh`
uses an explicitly named standalone assertion adapter; it does not claim XCTest.
CI uses `--require-xctest` and cannot fall back to it.

## Physical GUI and 1.0 gate

Execute [Mac GUI acceptance](macos-gui-acceptance-tests.md) on a real Apple Silicon
desktop and record inputs, hashes, numeric values, captures and failures. CI app
packaging alone never passes a physical interactive test. The native automated
flags listed there supplement manual checks; run each flag in its own process.

On both Windows and Linux physical desktops, open generated water, trajectory and
synthetic-mode HTML; check scaling, pointer rotate/pan/zoom, distance measurement,
play/pause, negative mode indication, source display and downloaded XYZ/PNG. Repeat
with browser zoom/HiDPI, small windows, spaces/Unicode paths and offline networking.
Run the downloaded CI executable/resource bundle separately from a local build.

Before 1.0, bring the missing [portable feature families](portable-viewer.md#platform-acceptance-and-remaining-work)
to the agreed support level, provide desktop packaging/runtime delivery, and pass
physical acceptance on each claimed system. Cube/MO/density and other unimplemented
scientific features remain gaps in [the feature matrix](feature-parity.md).
No build or coverage percentage establishes complete Chemcraft parity.

## Publish a validated version

1. Update `Packaging/Info.plist`, the portable CLI version/help, documentation,
   architecture, feature status, validation and handoff together.
2. Run applicable local scientific, browser and physical Mac checks. Install the
   successfully built Mac release with `bash scripts/install-macos.sh --no-build`.
   Do not terminate a running user app; quit/reopen is required to adopt the update.
3. Commit only relevant source, tests, packaging and docs. Push the release branch
   to origin and verify required CI at that commit. The user has authorized these
   version commits and pushes; no repeated permission is needed.
4. Create an annotated `v<CFBundleShortVersionString>` tag at the validated version
   commit and push it. Never overwrite a tag or invent historical version commits.
5. Merge the passing PR through protection. Verify remote branch/tag SHAs and record
   remaining unexecuted acceptance honestly. If publishing is blocked, retain the
   local commit and report the specific blocker.

A portability preview can ship with its declared subset. It cannot be relabeled
as a verified full cross-platform 1.0 application while its acceptance gaps remain.

The native archive probe runs `--resource-smoke-test` before constructing views.
It requires every helper, fragment catalog and shader to resolve inside the
app's own Resources directory, then removes one helper in a temporary copy and
requires an explicit failure. This catches successful local builds that secretly
rely on SwiftPM's absolute development-machine resource path. It does not need
Metal or count as a physical GUI pass. Downloaded release app launch/open tests
on the physical Mac remain separate.
