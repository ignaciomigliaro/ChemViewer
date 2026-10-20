# ChemRefine dashboard actions and step energies

ChemViewer 0.10.3/build25, 2026-10-20.

The embedded editor uses JavaScript confirmation dialogs before its Run,
Resume and recovery actions. WKWebView previously had no UI delegate for those
dialogs, so the buttons could silently cancel. It also launched through the
editor server rather than the native save/check/model/environment path.

ChemRefineWebDelegate now displays native confirmation, alert and text-entry
sheets. A document-start integration intercepts only local POST /api/run calls
and forwards the requested action/optional step target to WorkflowRunner.
Run, Resume, Rebuild cache, Rebuild NMS, Rerun and Rerun errors retain their real
ChemRefine semantics. Run and Resume do not accept a step target. The embedded
editor still controls its confirmation wording and target selector. The top
panel also has a Resume button.

Both entry points flush current YAML/form edits and the open template, run the
same readiness/model checks, supply the configured ORCA environment, launch the
actual detached ChemRefine driver and monitor real logs/status. Concurrent
native launches are refused visibly. The editor API receives launch errors
rather than a silent cancellation. The local request handler checks the main
frame, loopback host and the current editor's port. Upstream ChemRefine files
and dependencies are not patched.

The bottom-right Run panel now includes a Step energy summary, initially
expanded, with one row for every saved workflow step. Rows show the step number,
name (or Step N), engine, status, lowest reported energy, units, energy type,
conformer identifier and number of finite reported conformers. Multiple
conformers are summarized by their minimum; the existing paginated per-conformer
results remain available below. Units are Eh, kcal/mol, kJ/mol and eV, using the
same CODATA 2022 factors as ChemCraftCore. Copy table copies tab-separated text
with the displayed units.

Energies come from ChemRefine's steps.csv and stay in Hartree at the bridge
boundary. Blank/unavailable/nonfinite values are never replaced with zero. CSV
rows retained for steps without a successful cache are marked previous results.
These are saved workflow results, not a live SCF-iteration trace. Refresh and
five-second polling update them; changing units does not modify source data.
Different engines/methods have different energy references; no cross-step
relative energy is inferred.

Local checks and evidence are recorded in CONVERSATION-HANDOFF.md and
scientific-validation.md. Personal calculations and vendor binaries are not
included in the repository or used by the synthetic acceptance run.

## ChemRefine dashboard acceptance — 0.10.3 (2026-10-20)

The embedded Run action was invoked through the actual editor launch function,
with its real native confirmation sheet accepted by the native test. Unsaved
6-31G -> STO-3G changes and a newly added second step/template were flushed
before launch. Both independent H2 conventional HF/STO-3G steps completed with
-1.1167593074 Eh, one survivor and zero failures. Actual bottom Resume, targeted
Rebuild cache and Rerun errors also passed through confirmations/native routing
and completed. The final recovery driver survived termination of its editor
server. Per-action target dispatch for all six actions is covered by Python
tests; Rebuild NMS requires a real NMS-configured workflow and is not claimed
scientifically exercised here.

The actual WK-rendered step table showed Step 1 and refine with their real
energies/status and units. Its kcal/mol display matched the independent core
CODATA conversion oracle; the original upstream progress table was also checked
for fresh successful-cache/survivor state after a fast run. A direct WK snapshot
was visually inspected at ~/Downloads/chemviewer-runner-evidence/workflow-dashboard.png.
A prior desktop capture showed the user's editor instead and is not visual
evidence of this feature.

Final local gates: 28 Python chemistry integration tests; 31 standalone core
cases plus three migrated suites; signed ARM64 release build; native action/
confirmation/editor-save/energy-table and unit-conversion acceptance. Genuine
XCTest is unavailable in the selected local Command Line Tools. Evidence:
/private/tmp/chemviewer-0103-python.log, chemviewer-0103-build.log,
chemviewer-0103-native-verified.log; synthetic real-pyscf-D85B504E under
~/Downloads/chemviewer-runner-evidence. No personal calculation was rerun.
