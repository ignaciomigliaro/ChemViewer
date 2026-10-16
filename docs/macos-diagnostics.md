# Official macOS build diagnostics

## Current result

The official b638m ARM and Intel DMGs were acquired from ChemCraft's website and
inspected without execution. Runtime diagnosis remains **blocked by the absence
of a target Mac and crash reports**.

Observed static facts:

- Both DMGs are APFS images containing 287 files and 85 directories.
- ARM is a thin arm64 Mach-O (13,091,048 bytes); Intel is thin x86-64
  (12,387,064 bytes).
- Both identify as bundle `com.company.Chemcraft`, version `0.1`/build `1`, use
  wildcard document handling, and declare no `LSMinimumSystemVersion` in the
  plist.
- Both load the same 13 Apple frameworks/libraries: Cocoa, AppKit, Foundation,
  CoreFoundation, CoreGraphics, CoreText, CoreData, CoreServices,
  ApplicationServices, QuartzCore, libSystem, libobjc, and libiconv. No
  third-party dylib dependency is present in the Mach-O load commands.
- ARM contains an ad-hoc, linker-generated signature with SHA-1 and SHA-256 Code
  Directories, no CMS certificate, and no hardened-runtime flag. Intel has no
  `LC_CODE_SIGNATURE`.
- ARM embeds `FPC 3.2.2 ... aarch64-Darwin`; Intel embeds `FPC 3.2.0 ...
  x86_64-Darwin`. Both contain Lazarus LCL form/application and TAChart strings.
- ARM declares a 10.9 minimum/SDK load command even though arm64 macOS began much
  later; Intel declares minimum 10.8 and an unusual SDK value decoded as 10.18.
  These are observed metadata inconsistencies, not established crash causes.

Current assessment:

- Missing bundled third-party dylibs are unlikely to explain instability.
- Gatekeeper friction is expected from the absent Developer ID signature and is
  separate from crashes after successful launch.
- The different FPC generations and Lazarus Cocoa widgetset builds are credible
  sources of ARM-versus-Intel behavioral divergence, but this remains an
  inference until crash stacks identify failing modules/functions.
- Direct OpenGL or Metal linkage was not observed. The dependency/import set is
  consistent with an AppKit/CoreGraphics software-rendered application, though
  dynamic loading via `dlopen` remains possible.

## Required evidence from the target Mac

Run the following separately for both the official ARM and Intel bundles on the
target Mac:

```bash
bash scripts/collect-macos-diagnostics.sh /Applications/Chemcraft.app
```

The script records, without modifying the app or macOS security state:

- `sw_vers`, kernel, and CPU identity;
- Mach-O architecture slices (`file`, `lipo`);
- signature, entitlements, strict verification, and Gatekeeper assessment;
- extended attributes, including quarantine, without clearing them;
- linked dylibs and Mach-O load commands;
- SHA-256 for every bundle file;
- ChemCraft `.crash`/`.ips` reports from the preceding 30 days.

## Reproduction matrix

For each build, record cold launch, open dialog, drag-and-drop, sample parsing,
rotation/picking, frequencies, orbitals/cubes, image export, and quit/relaunch.
Each failure needs exact input SHA-256, action sequence, observed result, crash
report, and whether it reproduces in a fresh user account. Intel testing should
record Rosetta availability and must not silently alter system security.

## Diagnosis order

1. Architecture and minimum macOS version.
2. Bundle completeness and executable permission.
3. Signature/Gatekeeper/quarantine evidence.
4. Missing or incorrectly resolved dylibs/rpaths.
5. Crash exception, terminating thread, and backtrace.
6. Graphics/device dependence and Retina scaling.
7. Threading/race behavior across repeated runs.
8. Feature-level failures that do not crash.

Repairs must preserve licensing and system protections. Removing quarantine,
disabling Gatekeeper/SIP, or patching license checks is out of scope.
