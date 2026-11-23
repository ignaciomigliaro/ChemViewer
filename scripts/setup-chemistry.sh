#!/bin/bash
set -euo pipefail
runtime="$HOME/Library/Application Support/ChemViewer/chemistry-venv"
python_bin="${CHEMVIEWER_CHEMISTRY_PYTHON:-python3.12}"
if [[ ! -x "$runtime/bin/python" ]] || [[ -n "${CHEMVIEWER_CHEMISTRY_PYTHON:-}" ]]; then
    "$python_bin" -m venv "$runtime"
fi
if ! "$runtime/bin/python" -m pip --version >/dev/null 2>&1; then
    "$runtime/bin/python" -m ensurepip --upgrade
fi
chemrefine_extras=gui
if [[ "${CHEMVIEWER_CHEMREFINE_MAPPING:-0}" == 1 ]]; then
    chemrefine_extras=gui,mapping
fi
chemrefine_revision=ac09bd97a4c14722fbb5df26f19d2876a3b1a79b
chemrefine_source="ChemRefine[$chemrefine_extras] @ git+https://github.com/ignaciomigliaro/ChemRefine.git@$chemrefine_revision"
if [[ -n "${CHEMVIEWER_CHEMREFINE_CHECKOUT:-}" ]]; then
    chemrefine_source="${CHEMVIEWER_CHEMREFINE_CHECKOUT%/}[$chemrefine_extras]"
fi
"$runtime/bin/python" -m pip install --upgrade 'rdkit==2026.9.1' 'ase==3.29.0' 'tblite==0.8.0' "$chemrefine_source"
# The previous pin also reports 2.0.0.dev1. pip can keep it after resolving a
# different direct source with the same package version.
if [[ -n "${CHEMVIEWER_CHEMREFINE_CHECKOUT:-}" ]] || ! "$runtime/bin/python" -c '
import json, sys
from importlib.metadata import distribution
origin = json.loads(distribution("ChemRefine").read_text("direct_url.json") or "{}")
sys.exit(origin.get("vcs_info", {}).get("commit_id") != sys.argv[1])
' "$chemrefine_revision"; then
    "$runtime/bin/python" -m pip install --force-reinstall --no-deps "$chemrefine_source"
fi
"$runtime/bin/python" -c 'from rdkit.Chem import AllChem; from tblite.ase import TBLite; from chemrefine.config import MechanismReactant; import flask; assert "initial_core" in MechanismReactant.model_fields; print("ChemViewer chemistry runtime ready")'
