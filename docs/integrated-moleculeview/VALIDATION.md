# Validation record

2026-10-13, Apple Silicon macOS / installed Apple Swift toolchain.

- Synthetic parser tests: CRLF; differing compound job atom counts; orphan/new-job boundaries; exact Cartesian displacement; negative/imaginary frequencies; missing, duplicate, NaN and extreme components; truncated/malformed coordinates; XYZ dummy sites and trajectories; explicit pressure units; source-attributed energy and missing facts.
- Editing tests: rigid distance invariance, fixed pivots and untouched atoms, zero-axis behavior, disconnected molecule selection, palette connectivity, terminal leaving-site rejection, two leaving atoms removed, radius-sum C–C distance 1.52 Å, rigid internal geometry, antiparallel vector alignment and invalid bond inputs.
- State tests: deletion/attachment remaps selection and groups; history undo/redo and capacity; validated Codable project; invalid indices/coordinates; charge/multiplicity serialization and dummy export rejection.
- Native GUI integration: file-open event deliberately delivered before launch initialization, then queued and loaded; selection state; move edits; mode invalidation; undo/redo; add/duplicate/delete; project roundtrip; ORCA serialization; mode navigation; in-place scene update with immutable source; attachment and saved bond-axis checks.
- Local reference water compound file: 6 three-atom frames, modes associated only with frame 6, 9 complete columns including 6 zero modes and nonzero frequencies 1606.12, 3678.02, 3777.72 cm⁻¹; known vectors checked. This vendor sample is not included.
- Local personal output: 48 geometries of 139 atoms parsed. The file is not included.
- Mach-O executable verified arm64. `codesign --verify --strict` passed for the app.

The native self-test uses the actual AppKit window and SceneKit view, calls editing UI handlers, and snapshots the scene. Selection event injection verifies picking separately. Visual inspection covers a rendered scene; it does not establish comprehensive manual interaction, file-panel coverage, accessibility, prolonged playback or crash-free long sessions. The first GUI launch inside the restricted sandbox exited with an abort; GUI-access execution allowed by automatic approval review passed. No user apps were quit or restarted.
