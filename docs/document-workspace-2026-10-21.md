# Document workspace and ORCA inputs — 2026-10-21

Release: ChemViewer 0.10.9 / build 31.

## Delivered behavior

Remote Files is a persistent main-window tree, with the existing geometry and
frequency list below it. Connection/SLURM settings remain available through the
gear; opening normal structure/output/input files does not require that modal.
Expansions use the existing persistent SSH/Python channel and cache. A busy
channel queues expansions; canceled/profile-obsolete replies do not publish.

DocumentTabs retains independent WorkspaceStore models for local URLs or remote
host/path identities. Open accepts multiple files; repeat opening selects the
existing tab. Cameras/zoom, measurement placements, selections, frame/mode,
geometry edit histories and drawing graphs are independent. X/Cmd-W closes a
file tab; geometry/drawing edits require saving or explicit discard. Parsed data
and undo remain in memory in open inactive tabs for quick return. Normal inactive
playback, trajectory timers and drawing preview work are suspended. Loaded Image
tab switches share one renderer/mesh; detached views release GPU/coordinator/text
resources. Closed models explicitly clear geometry/source/undo/preview data.
Calculation/export jobs keep their separate lifetime. Tabs are not restored
across application quit; this is not full VS Code remote editing or SSHFS.

ORCAInputParser supports ordinary Cartesian star blocks, inline Angstrom/Bohr,
Fortran exponents, explicit spin/charge and explicit XYZ companion files. Remote
references use per-file cache mappings, preserving original paths/source text.
Templates without Cartesian geometry, internal coordinates and %coords forms can
be inspected as Source with a visible limitation. Annotated/expressive atom rows
and Bohr xyzfile conversion are not supported; malformed/unsupported cases give
messages rather than fabricated geometry. Multi-block charge/spin describe the
first block, with a warning; input geometries have no inferred SCF energies.
The source syntax reference is the [ORCA 6.1 coordinate manual](https://www.faccts.de/docs/orca/6.1/manual/contents/essentialelements/coordinates.html).

## Validation

- **41 core regression cases** pass using the explicit standalone assertion
  adapter, including eight new input cases. Baseline and final `swift test`
  were attempted; local CLT has no XCTest module. Standalone results are not
  claimed as XCTest runs. The three migrated parser/edit/project suites pass.
- Input oracles include independent Fe/H Cartesian coordinates with charge -1,
  multiplicity2; 2Bohr=1.058354421806Å (Float tolerance1e-6); quoted/relative/mapped
  XYZ files; template/internal Source; bad spin/nonfinite/missing terminator/
  ambiguous-unit rejection; multi-geometry/no-fabricated-energy behavior.
- **45 Python regressions** pass: builder chemistry, drawing, workflow and SSH.
- **DOCUMENT_WORKSPACE_PASS**:50loaded switches preserve one active renderer and
  mesh build while preserving angle/zoom/labels/selections; inactive trajectory
  and vibration pause; independent edit/undo/drawing state; dirty-close refusal;
  actual Cmd-W menu action; source-only templates; Abstract restoration; closed
  data cleanup and detached renderer readiness/buffer release. Active renderer
  readiness is checked after switches/source views.
- **Smooth interaction PASS**: existing direct-file loads, 2/3/4-atom label dragging,
  geometry mouse drags/one Undo, one mesh, grab rotation, stable selection camera,
  annotated PNG/GIF and retained label placement.
- **PERSISTENT_LABELS_PASS / SKELETAL_DRAWING_PASS / AUTO_DRAW_PREVIEW_PASS /
  DRAWING_LABELS_PASS**: four simultaneous labels; native zigzags and all14ring
  formula oracles; actual same-count Metal isomer changes; stale/canceled preview
  rejection; invalid-valence recovery; real RDKit/UFF, chiral import, periodic
  picker, exports and undoable viewer transfer.
- **REMOTE_TREE_PASS** on authenticated ORCD: persistent root and child expansion,
  remote XYZ and ORCA input in separate tabs, referenced XYZ retrieval, exact
  synthetic H2 distance0.74Å, no inferred energies, duplicate-file selection and
  inactive animation pause. No calculation/SLURM job was submitted. Original
  profile/explorer preferences were restored. The isolated fixture was removed
  after checking its original H2 digest, home-parent/prefix and explicit test
  config marker. Existing remote files and the shared login were preserved.
- Strict signed arm64 packaging passes. Native window-only captures of tabs and
  the remote tree were visually inspected; personal/local evidence is excluded
  from Git. The previous0.10.8 GitHub build passed; new CI starts on publication.

Logs are in /private/tmp/chemviewer-0109-{final-build,python-final,
document-release,smooth-final,drawing,remote-release}.log. Captures/independent
local fixture inputs are under Downloads/chemviewer-document-evidence and
Downloads/chemviewer-remote-evidence. No personal calculation was modified.

Development checks caught retained closed-document references and a stale camera
snapshot from a different directly loaded file. Dynamic menu bindings, explicit
close/detach cleanup and viewport generations fix those cases. Loaded-tab
restoration remains separate from new-file initialization. The final tests above
were rerun against the corrected bundle.

## Repeating native checks

Build with scripts/build-macos.sh, then launch a separate app instance with
Tests/fixtures/water.xyz and --document-workspace-smoke-test. Existing flags
--smooth-smoke-test and --drawing-labels-smoke-test exercise old interactions.

--remote-tree-smoke-test is opt-in and needs an authenticated saved connection
and an isolated fixture folder: seed.xyz (two H at0 and0.74Å), molecule.inp with
`* xyzfile 0 1 seed.xyz`, plus templates/step1.inp. Its metadata file is
Downloads/chemviewer-remote-evidence/live-fixture.json, containing `profile`
(the complete saved RemoteProfile JSON including UUID/name/host/directory/Python/
setup/config) and `path` (absolute remote fixture folder). Launch with the local
water fixture as above. Do not point this acceptance test at a personal workflow;
it is an explicitly staged synthetic test. Remove only that fixture after use.
