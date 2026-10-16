# ChemViewer continuation handoff

Date updated: 2026-10-16

This file packages the working context needed to continue the project on an
Apple Silicon Mac. The user's original, complete project request is included
beside this file as `PROJECT-BRIEF.txt`.

## User and objective

The user is a computational chemistry researcher working with machine
learning, molecular dynamics, quantum mechanics, and scientific software. The
objective is a reliable, scientifically accurate native Apple Silicon
application with practical feature parity with Windows ChemCraft. It must not
be considered complete merely because it launches.

The work must preserve licensing and must not bypass registration, trial, or
license checks. Do not redistribute ChemCraft binaries, proprietary assets, or
recovered source. Use documented formats, authorized black-box observations,
and original implementation code.

## Work completed in the Windows session

An original Swift/Metal project named ChemViewer was created in this directory. It currently
contains:

- a SwiftUI macOS application and ChemCraft-style data explorer;
- a Metal atom/bond renderer with rotate, pan, and zoom;
- multi-frame XYZ parsing;
- ORCA Cartesian geometry, final-energy, vibrational-frequency, normal-mode
  displacement, and IR-table parsing;
- normal-mode animation and red imaginary-mode marking;
- IR sticks and Gaussian/Lorentzian broadening;
- macOS file importer and Finder/open-document URL handling;
- background parsing;
- Swift tests and an independent Python reference oracle;
- an ARM64 `.app` assembly/signing script;
- a read-only official-app diagnostic collection script;
- architecture, feature inventory, parity, diagnostics, reverse-engineering,
  and scientific-validation documents.
- recovered Windows GUI automation with direct reference observations;
- click/multi-click atom selection and distance/angle/dihedral readouts;
- trajectory play/pause and Windows-compatible right-drag rotation;
- native Apple Silicon GitHub Actions packaging.

This is a Milestone 3 implementation slice. It is not full feature parity or a
daily-use release.

## How the current GUI and vibration system work

The SwiftUI interface has a hierarchical calculation/geometry/frequency list
on the left and a Metal viewport on the right. The renderer currently draws
atom point-sprite impostors and line bonds. It infers bonds from covalent radii.

A parsed mode contains one Cartesian displacement vector per atom. The display
position is evaluated as:

```text
r_i(t) = r_i(0) + amplitude * q_i * sin(display_phase)
```

The display phase uses a fixed visible animation rate; it is not the physical
vibrational frequency. The scientific wavenumber remains attached to the mode
and is shown in the UI. Negative frequencies remain negative and are marked as
imaginary. Their animation is a visualization of the unstable normal
coordinate, not a physical periodic vibration.

The installed ORCA reference fixture labels the plotted third IR-table column
as `T**2`. The implementation retains the raw source value for relative
rendering and does not invent an undocumented unit conversion.

## Verified environment evidence

The Windows evidence host provided REA 6.5.0, Ghidra 12.1.4, Node, Python,
Git, CMake, WSL Ubuntu, and .NET. It did not provide Swift/Xcode. The bundled
Windows-control helper could not initialize, but the project-local
pywinauto/PyAutoGUI/Pillow fallback completed an evidence-backed GUI audit.
See `docs/windows-gui-audit.md` and `docs/gui-feature-inventory.md`.

REA was registered with Codex. Its setup backed up the Codex configuration to
`C:\Users\Ignac\.codex\config.toml.rea.backup`. REA native deep analysis still
requires a supported Ghidra/IDA provider and a fresh MCP connection.

### Windows reference artifact

- Path on evidence host: `C:\Chemcraft\Chemcraft.exe`
- Size: 12,841,472 bytes
- SHA-256: `79fe75015a1e48c4df29e7bac4c3c05e67057bf3a0ed03a7b77fe85528d4f05a`
- REA artifact Evidence:
  `ev_0c9f0c954791b774000004a1abebd6fd536c0ecfbc398824ba4a445307e48c84`
- REA native classification Evidence:
  `ev_dcac80936b8e7436946ddb1cb064e398bf50862b4015ab61dcf6273942cf024d`
- Observed as unsigned native PE32+ x86-64 with 15 sections and no CLR.
- Static PE evidence shows an Enigma protection/virtualization boundary,
  including `enigma_ide_x64.dll!EP_RegHardwareID`.
- Do not unpack the protector or trace registration/license operations.

### Official macOS b638m artifacts

The artifacts themselves are deliberately excluded from this transfer ZIP.
Download fresh copies from the official website on the Mac.

- ARM DMG SHA-256:
  `603e4e9c2a6b7d2e4cffdd9686490327200dde637065b9e3ed78020689387814`
- Intel DMG SHA-256:
  `967100f1d25eb877287b94e47829832aefad9ac48ccbb36f6ba48e163ec2169b`
- ARM executable SHA-256:
  `c3a83812708d942afb59e9f2f13ad5448d4be9bee20c22129f81cfdc99e86441`
- Intel executable SHA-256:
  `645bdf5291073f2e29edc101365b9803c43ecca360bc664597991169cc88a6f0`
- ARM is thin arm64, built with Free Pascal 3.2.2 and Lazarus LCL/Cocoa.
- Intel is thin x86-64, built with Free Pascal 3.2.0 and Lazarus LCL/Cocoa.
- Each declares the same 13 Apple-only linked frameworks/libraries.
- ARM has an ad-hoc/linker signature (`0x20002`), no CMS certificate, and no
  hardened-runtime flag. Intel has no `LC_CODE_SIGNATURE` command.
- Missing third-party dylibs are therefore unlikely to explain the published
  instability. The actual crash cause is unknown without target-Mac reports.

## Tests completed on Windows

The following command passed the portable scientific/artifact regressions:

```powershell
py -3 -m unittest discover -s .\python_tests -v
```

The tests validate:

1. the installed ORCA water compound-job output: final O/H/H geometry, final
   energy `-76.360968646 Eh`, nine modes, frequencies 1606.12, 3678.02, and
   3777.72 `cm^-1`, raw IR values, and a normal-mode vector component;
2. the official ARM/Intel Mach-O architectures, linked-dependency counts,
   hashes, and signature shape, when those local artifacts are available.

Both shell scripts pass `bash -n`, and `Packaging/Info.plist` parses as XML.
Swift tests have not been run because the evidence host has no Swift/macOS
toolchain.

## First commands on the Apple Silicon Mac

Install Xcode 15 or newer and its command-line tools. Then, from this directory:

```bash
xcode-select -p
swift --version
bash scripts/build-macos.sh
open dist/ChemViewer.app
```

The build script runs `swift test`, builds ARM64 release code, assembles the
application bundle, includes the SwiftPM Metal resource bundle, signs locally
with an ad-hoc signature, and verifies it.

Download the official ARM and Intel beta bundles from:

- https://chemcraftprog.com/MacVersion.html

Run the read-only diagnostic script separately against each installed bundle:

```bash
bash scripts/collect-macos-diagnostics.sh /Applications/Chemcraft.app
```

Do not clear quarantine or disable Gatekeeper/SIP as a first diagnostic step.
Capture the exact launch result and any `.ips` crash report. Test the Intel
build under Rosetta separately and record Rosetta availability.

## Immediate continuation priorities

1. Compile and run all Swift tests. Fix compiler/API issues before adding more
   uncompiled code.
2. Launch the new app with a small XYZ file and an ORCA frequency output.
3. Verify continuous normal-mode animation, Retina sizing, camera gestures,
   shader-bundle lookup, and imaginary-mode presentation.
4. Run both official builds and collect crash reports/signing/quarantine
   evidence with the provided script.
5. Compare official ARM versus Intel behavior using the reproduction matrix in
   `docs/macos-diagnostics.md`.
6. Run the acceptance matrix in `docs/macos-gui-acceptance-tests.md` and record
   interactive results separately from CI.
7. Add checked-in test fixtures only when independently generated or clearly
   redistributable.
8. Prioritize ORCA 6 optimization, OptTS/frequency, NEB, IRC, scan, orbital,
   cube, and Hessian workflows.
9. Add depth-correct instanced spheres/cylinders, trajectory graphs,
   geometry editing, and volumetric isosurfaces in bounded, tested slices.

## Important limitations

- No `.app` was produced on Windows.
- No target-Mac runtime or crash evidence exists yet.
- The current renderer is a prototype without depth testing or bond picking;
  CPU screen-space atom picking is implemented but not yet run on a Mac.
- ORCA support covers one observed layout family, not every ORCA version and
  calculation type.
- Most other chemistry formats, molecular orbitals, volumetric surfaces,
  editing, reaction pathways, export, and advanced properties remain pending.
- Windows GUI coverage is substantial but still partial: IR-spectrum activation,
  a displacement-vector incident, imaginary-mode reference behavior, PES, and
  NEB remain unresolved.
- Keep every status in `docs/feature-parity.md` honest; do not mark a feature
  complete until its scientific and interactive acceptance tests pass.

## Suggested continuation request

```text
Continue the ChemViewer project using AGENTS.md, PROJECT-BRIEF.txt, and
CONVERSATION-HANDOFF.md. First inspect the current Mac/Xcode environment, run
the Swift tests and build script, launch the generated app, fix all build or
runtime defects, and collect read-only diagnostics for the official ARM and
Intel ChemCraft builds. Preserve the clean-room and licensing boundaries and
update the evidence and parity documents with verified results.
```
