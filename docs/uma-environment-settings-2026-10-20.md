# Choosing a UMA Python environment

ChemViewer 0.10.4/build26.

In the ChemRefine tab, use the UMA Python row above the readiness report:

1. Choose environment selects either an environment folder or its bin/python.
   You can also type an interpreter path. Environment folders resolve to
   bin/python; tilde expansion is supported. The symlink path is preserved so
   a virtual environment is not accidentally replaced by its base interpreter.
2. Check Python runs that interpreter and checks fairchem.core and ChemRefine
   imports, reports the actual prefix/version and identifies missing Flask or
   Waitress required by mlip-extopt. It does not install packages or load weights.
   Normal Check/Run readiness still checks the selected workflow/model.
3. Use for UMA steps explicitly saves the chosen path into this workflow's
   FAIRChem MLIP steps, including existing overrides. This is how to deliberately
   move an existing workflow to another environment.

The default is stored locally in ChemViewerUMAPython preferences. It is empty on
an unconfigured installation; there is no developer-specific UMA path in app
code. Saving/checking/running fills only missing backend_python values for
FAIRChem task heads on mlip, mlip-extopt and mlip-train steps. Existing overrides,
other MLIP families and other engines are preserved. The selected interpreter
is written as options.backend_python in input.yaml, so command-line ChemRefine
uses the same environment without depending on ChemViewer preferences.

The bottom-right Run panel also shows MLIP Python environments, with an editable
path for each MLIP step. These fields override the default. Clearing a field
uses the selected default when saved, or ChemRefine's normal managed-backend
resolution when the default is blank. Actively typed fields are flushed before
Check/Run/Apply. Raw YAML mode uses backend_python in the YAML itself; the
per-step fields are disabled in that mode. Applying a missing default in raw
mode parses and re-emits the YAML, which can reformat comments/spacing.

This is interpreter selection, not shell activation: select bin/python rather
than typing conda activate or the name of an environment. A selected environment
needs both fairchem-core and the same compatible ChemRefine, plus server packages
for ExtOpt. Model access/checkpoints remain separate workflow readiness checks.
No package trees are merged or automatically replaced by selecting a path.

## UMA Python settings validation — 0.10.4 (2026-10-20)

29 Python chemistry integration tests pass, including selected interpreter/folder
resolution, import-check dispatch and invalid paths. The actual installed UMA
environment passed the new checker: Python environment prefix was correct,
fairchem-core 2.23.0 and compatible ChemRefine imported, and ExtOpt server
packages were available. This import check does not claim a new UMA calculation.

Native acceptance passed persistent-setting/directory resolution, default-only
filling, preserved explicit overrides, non-FAIRChem/other-engine exclusion,
explicit replacement, actual visible per-step editing, pending-input flushing
and raw YAML insertion. The original live editor config and user preferences
were restored after synthetic checks. The same test then passed actual bottom
Run/Resume/targeted recovery, unsaved editor/template saving, a real two-step
PySCF H2 HF/STO-3G oracle (-1.1167593074 Eh), energy table/unit conversion and
detached recovery/editor-server survival. Core31 and three migrated suites,
strict signature and ARM64 release build pass. No personal calculation was run.
Evidence: /private/tmp/chemviewer-0104-python.log, chemviewer-0104-build.log,
chemviewer-0104-native-final.log; real-pyscf-CECAC37C under
~/Downloads/chemviewer-runner-evidence. No vendor binaries or model credentials
are part of the source release.
