# Architecture

## Decision

The long-term implementation is a native Apple Silicon application using
SwiftUI/AppKit for macOS integration and Metal for rendering. Scientific parsing
and models live in a UI-independent Swift module. A small Python implementation
acts only as an independent validation oracle.

This choice favors native file dialogs, Retina rendering, keyboard/window
behavior, ARM64 performance, and a self-contained `.app`. It carries more
up-front rendering work than Qt or Electron but avoids Wine and a bundled browser
runtime. Repairing the official Mac build remains preferable if target-machine
evidence proves it can deliver parity reliably. The official b638m artifacts
were acquired for static inspection. Their strings identify ARM as Free Pascal
3.2.2 and Intel as Free Pascal 3.2.0; both use
Lazarus LCL/Cocoa and TAChart. They have only Apple system dylib/framework load
commands. Without proprietary Pascal source, a durable repair of widget or
application logic is unlikely; target-Mac crash evidence remains necessary
before closing Strategy A.

## Modules

```text
ChemViewerApp (SwiftUI/AppKit; product name `ChemViewer`)
    ├── Data Explorer and inspectors
    ├── document/window state
    └── MolecularMTKView
            └── Metal shaders

ChemCraftCore (platform-neutral Swift)
    ├── molecule/trajectory/mode models
    ├── parser registry
    ├── XYZ parser
    ├── ORCA parser
    └── bond inference

Validation tools (Python stdlib)
    └── independent extraction and corpus assertions
```

## Data model and units

- Cartesian positions and normal-mode displacements: ångström-compatible
  floating-point values as printed by the source file.
- Energies: Hartree in the stored scientific model; UI conversions will be
  explicit rather than destructive.
- Frequencies: cm⁻¹, with negative values retained as imaginary modes.
- Intensities/activities: stored separately because ORCA/Gaussian quantities
  are not interchangeable.
- Frames are immutable values at parser boundaries. UI selection and animation
  state do not modify parsed scientific values.

## Parser contract

Every parser must:

1. Preserve source values and units.
2. Reject malformed mandatory records instead of inventing data.
3. Return warnings for partial optional sections.
4. Be callable off the main thread.
5. Have at least one independently checked fixture before being marked tested.

The registry selects parsers from extension plus bounded content signatures.
Future parsers should implement the same output model, with format-specific
metadata attached through typed extensions rather than UI conditionals.

## Geometry editing

`ChemCraftCore.GeometryEditor` implements value-semantic Cartesian operations
independently of SwiftUI: atom replacement, selected-atom translation, distance
measurement, and bond-length adjustment along the observed bond direction. The
coordinate sheet edits a draft and commits atomically, while `WorkspaceStore`
retains the previous frame for undo. Angle, dihedral, fragment-side selection,
and export remain separate acceptance-tested increments.

## Rendering

The initial renderer uses point-sprite sphere impostors and Metal line bonds.
It already supports rotation, pan, zoom, Retina drawable sizing, animated
normal coordinates, and scaled normal-mode arrows. Planned evolution:

1. Instanced tessellated spheres/cylinders with depth and MSAA.
2. Atom/bond ID picking pass.
3. Periodic cells, labels, vectors, and multiple structures.
4. Marching-cubes compute pipeline for cube/MO/density isosurfaces.
5. Off-screen supersampled image and frame-sequence export.

Large-file parsing and surface construction must use detached tasks with
cancellation and bounded memory. GPU buffers are rebuilt only when the selected
frame, representation, or animation phase requires it.

## Packaging

Swift Package Manager provides repeatable compilation and unit tests.
`scripts/build-macos.sh` builds ARM64, assembles the app bundle, copies resource
bundles, ad-hoc signs for local use, and verifies the result. Release packaging
will add hardened-runtime entitlements, Developer ID signing, notarization, and
stapling after the target Mac is available.
