# Remote file access and ChemRefine / SLURM — 2026-10-20

Release: ChemViewer 0.10.7 / build 29.

## Implemented behavior

File → Remote files & SLURM and the ChemRefine header open the same native
connection sheet. Connection profiles persist only on the user's Mac. Hosts,
remote working directories, Python executable/environment folders and explicit
Bash setup commands are configurable; no researcher/cluster paths are compiled
into the app. Interactive login runs in Terminal with OpenSSH, then background
requests reuse a private multiplex connection. Normal host-key checks remain.

Folders can be browsed/double-clicked. Open in viewer automatically transfers
and verifies a cached copy retaining the filename, then uses the normal native
parser. Refresh remote file replaces the cached contents. UTF-8 text up to 2 MB
can be edited and explicitly saved with changed-file digest protection. Workflow
uploads copy supported input types to a new unique folder, never overwrite an
existing calculation. They do not rewrite absolute Mac paths or install remote
packages. Hidden files, default outputs/scratch directories and symlinks are
excluded; dependencies elsewhere must be provisioned on the cluster.

Select an input.yaml and Use workflow. Check, Run and Resume delegate to the
remote installed ChemRefine API. Remote dispatch must explicitly be slurm;
missing sbatch/squeue, inputs, templates, executables and headers block launch.
The detached controller submits per-step SLURM jobs and survives disconnection.
The viewer shows lock state, survivors, failures, cached state, the log tail and
up to 20 persisted conformer energies per step with names/Hartree units. Copies
are TSV; manual and ten-second refresh are supported. Idle does not imply
scientific success. Cluster account/partition/budgets/compute-node environments
must be configured in YAML/headers. Cancel request only cancels the client
request, and never promises cancellation of already-submitted calculations.

## Verified evidence

- 13 hermetic Python remote tests pass, including complete local-shell wire
  execution rather than just string comparison. They cover filename/shell
  quoting, environment folders, checksums/cache refresh, editor conflict/symlink
  refusal, isolated uploads, missing prerequisites/local dispatch rejection,
  Run/Resume API delegation, CSV source values and timeout cleanup. Mocked
  scheduler dispatch is not evidence of an executed calculation.
- All 42 Python chemistry/drawing/local-workflow/remote tests pass. Build runs
  33 standalone core assertion cases plus three migrated parser/edit/project
  suites, packages arm64 and verifies the strict signature. Local CLT lacks
  XCTest; standalone assertions are not represented as XCTest.
- Native REMOTE_CONNECTION_PASS checks a real macOS sheet, persisted profiles,
  packaged authentication helper, invalid-host error and source energy units.
  The final sheet's own window was captured and inspected (not the desktop or
  unrelated applications). Local evidence: Downloads/chemviewer-remote-evidence.
- The user authenticated the supplied ORCD alias in Terminal. Live remote Python
  starts, ChemRefine reports **2.0.0**, its agent module exists, and sbatch/squeue
  resolve to /usr/bin. The supplied ~/home/home/ does not exist; browsing starts
  from the verified home directory instead. Home listing returned 40 entries.
- Live ORCD_REMOTE_FILES_PASS uploaded four original synthetic H2 workflow input
  files into a new exclusive folder, browsed them, verified the exact SHA-256 and
  cached bytes, saved/read back a template edit, and checked that an intentionally
  missing ORCA executable blocks preflight. No executable substitution or
  scientific calculation was used as a fake success signal.

- Native REMOTE_LIVE_PASS used the **packaged** SSH helper to browse the live
  synthetic folder, verify its checksum, open its cached XYZ in WorkspaceStore,
  and assert two hydrogen atoms with 0.74 Å separation. This tests transfer/parser
  integration, not a calculated energy or optimized geometry.
- After acceptance, cleanup verified the exact synthetic H2 digest, the exclusive
  folder prefix/home parent and intentionally-missing-executable marker, then
  removed only that fixture folder. Existing remote files and authenticated SSH
  sessions were preserved. The working personal connection is saved locally
  with a verified home-directory start; no credentials/profile are committed.

Logs: /private/tmp/chemviewer-0107-{release-final,all-final,sheet-release,live-native,orcd-files}.log.
Final native sheet capture was inspected and its controls/readouts were visible. No actual SLURM job has been submitted by this validation. End-to-end
scheduler/ORCA/MLIP completion remains unverified until a real cluster workflow
with engine paths and allocation headers is selected. Remote files are cached,
not mounted, and companion files such as NEB sidecars are not recursively synced.

Initial environment inspection timed out using an extra login shell. Explicit
non-login Bash and a lightweight package probe returned successfully; explicit
profile setup commands remain available for required modules/environment setup.
Both SSH requests and cleanup have bounded deadlines; timeout text omits the
large encoded bootstrap command.
