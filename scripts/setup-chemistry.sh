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
"$runtime/bin/python" -m pip install 'rdkit==2026.9.1' 'ase==3.29.0' 'ChemRefine[gui] @ git+https://github.com/sterling-group/ChemRefine.git@a7add556cdcf056d42fbca1bb5be17d7da063755'
"$runtime/bin/python" -c 'from rdkit.Chem import AllChem; import chemrefine; import flask; print("ChemViewer chemistry runtime ready")'
