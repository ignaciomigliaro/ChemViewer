#!/usr/bin/env bash
set -euo pipefail
plotting_root="$HOME/Library/Application Support/ChemViewer/plotting-venv"
plotting_python="${CHEMVIEWER_SETUP_PYTHON:-$(command -v python3)}"
"$plotting_python" -m venv "$plotting_root"
"$plotting_root/bin/python3" -m pip install 'matplotlib==3.9.4'
"$plotting_root/bin/python3" -c 'import matplotlib; print("ChemViewer plotting ready: Matplotlib", matplotlib.__version__)'
