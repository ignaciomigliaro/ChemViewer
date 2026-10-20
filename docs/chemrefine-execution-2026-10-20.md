# Centered atom captions and ChemRefine execution

ChemViewer 0.10.1, build 23 — 2026-10-20.

## Captions

Atom numbers, element symbols and combined captions use the center of the visible
CoreText glyph bounds, not a font rectangle plus an arbitrary offset. This keeps
short and long text centered on the projected atom sphere. Captions have no
background box and use the same drawing method in the live view, PNG and GIF.

## Running a workflow

1. Open ChemRefine. Create a workflow from the current structure or use Open
   workflow to select an existing input.yaml. New workflows include seed.xyz,
   templates/cleanup.inp and the initial YAML; edit steps/methods in the real local
   ChemRefine editor.
2. Check workflow saves the current form/raw YAML, including pending form edits.
   If a template editor is open, it saves that template after the new YAML so a
   newly added step can be resolved. Blocking rows identify missing input,
   templates, executables, local output/scratch problems or invalid budgets.
3. Create missing templates uses ChemRefine's own scaffolder without overwriting
   existing files. Review the generated method/template before running.
4. Choose ORCA sets the installed executable used by new workflows and replaces
   a bare default `orca` in the live form. Explicit per-workflow paths are honored.
   Raw YAML can also name its full path under executables. The executable's folder
   is provided to the child through PATH/ORCADIR. Core companion programs are
   checked, and a parallel ORCA template requires mpirun. The actual distribution
   and MPI version must be compatible; that still needs a real installation test.
5. Install required backends provisions only missing engine extras selected by
   this workflow, in isolated managed ChemRefine environments. Existing partial
   backend imports can be repaired. CPU is required for these models on this Mac;
   CUDA selections are rejected. The app does not download every possible MLIP.
6. Run ChemRefine rechecks readiness, loads selected MLIP calculators/weights to
   catch missing dependencies/checkpoints/access, then calls ChemRefine's actual
   detached start_run API. A model produced by a preceding training step is
   deferred to the pipeline's normal runtime handling. Gated models require the
   user's own authorized model access or checkpoint.
7. Inspect the native status, expandable run log, Open full log and Open run
   folder. Open result loads computed coordinates/output into ChemViewer.

Run starts the entire pipeline from step 1, with ChemRefine's run/cache semantics.
Use the embedded editor's Resume/recovery actions when reusing completed work.
Native execution is local; SLURM-directed configurations must be changed to local
for this button. Declared engine requirements are checked; arbitrary custom
Python templates may still need additional imports/data not declared by the
engine. Runtime failures remain visible in the pipeline's logs/failure ledger.

The child owns locking, scheduling and result files and continues independently
of the editor, launcher helper or ChemViewer window. The last run's config/PID
are saved for monitoring when reopening the workflow. Log/status polling is
read-only, and a stopped driver is not automatically called successful. Native
setup cancellation is available for dependency/template/check operations; Run's
combined preparation/launch has no cancellation button, so an already detached
calculation cannot be hidden by a cancellation race. Use engine/system controls
if a running calculation must be stopped.

## ORCA setup still required

The user confirmed ORCA is not installed on this Mac. It cannot be obtained from
pip or bundled with ChemViewer. The official download requires the user's
account and licence acceptance. Use Get ORCA, download the matching macOS
package, follow the installer, and then Choose ORCA. No ORCA or MPI calculation
has been claimed as tested on this host. Official instructions:
[Installing ORCA](https://www.faccts.de/docs/orca/6.1/tutorials/first_steps/install.html).
The default GFN2-xTB template uses ORCA's bundled xTB implementation once the full
ORCA distribution is installed; it does not call an unrelated xTB executable.

## Validation

- ARM64 release build: 31 standalone core assertions plus three migrated building
  suites; strict app signature and arm64 packaging checks passed.
- Combined Python suite: 24 tests (five existing chemistry, eight drawing and
  eleven runner checks), covering missing files, no launch on failed checks,
  non-overwriting templates, selected-only backend provisioning, partial backend
  repair, absent/partial ORCA, missing weights, impossible GPU budgets and real
  status reporting. Stub executable files are used only for presence-check unit
  tests, never as evidence of a scientific ORCA calculation.
- Native caption pixel test: H/I/Cl/O12/Ru123 ink centers within one raster pixel
  of the requested center; glyph bounds match projected sphere centers. Actual
  water PNG inspected. Full transparent-GIF/style/measurement/caption regression
  passed after the renderer change.
- Genuine native execution gate: provisioned an isolated PySCF 2.14.0 backend;
  created an independent H2 fixture at 0.74 Angstrom; scaffolded the real engine
  template; changed a live unsaved basis from 6-31G to STO-3G, added an unsaved
  second step and its template, and invoked the same native Run action. Both
  conventional HF/STO-3G steps (density fitting explicitly disabled) completed
  with -1.1167593074 Eh, one survivor each and zero failures. The GUI server was
  terminated after launch while the actual detached pipeline completed; native
  logs/status and steps.csv verified the result.
- Existing builder/UFF/frozen-atom/cancellation/live-ChemRefine gate passed.

Evidence: /private/tmp/chemviewer-0101-two-step.log, corresponding animation and
builder logs, /private/tmp/chemviewer-0101-python.log, and local
Downloads/chemviewer-runner-evidence. Synthetic runs and vendor binaries are not
committed. PySCF is installed in ChemRefine's managed backend environment; the
base drawing/RDKit runtime was preserved. Human native installer/file-picker
checks and a real ORCA installation/run remain pending.
