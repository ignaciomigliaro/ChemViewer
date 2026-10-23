#!/usr/bin/env python3
"""Validate resource delivery and execute the relocated release ZIP on its host."""
import argparse
from pathlib import Path
import subprocess
import sys
import tempfile
import zipfile
p=argparse.ArgumentParser();p.add_argument('--archive',type=Path,required=True);a=p.parse_args()
with tempfile.TemporaryDirectory(prefix='chemviewer relocated ') as folder:
    root=Path(folder)
    with zipfile.ZipFile(a.archive) as archive:
        for name in archive.namelist():
            path=Path(name)
            if path.is_absolute() or '..' in path.parts:raise SystemExit('Invalid archive member')
        archive.extractall(root)
    resources=[p for p in root.iterdir() if p.is_dir() and p.suffix in ('.resources','.bundle')]
    if len(resources)!=1 or not (resources[0]/'viewer.html').is_file():raise SystemExit('Missing packaged viewer resource')
    executable=root/('ChemViewerPortable.exe' if sys.platform=='win32' else 'ChemViewerPortable')
    if sys.platform!='win32':executable.chmod(0o755)
    output=root/'relocated water.html'
    subprocess.run([str(executable),str(root/'examples/water.xyz'),'--output',str(output)],cwd=root,check=True,capture_output=True)
    html=output.read_text(encoding='utf-8')
    if '__CHEMVIEWER_DATA__' in html or '<canvas id="viewport"' not in html:raise SystemExit('Incomplete generated viewer')
    print('Release ZIP resource and relocated executable acceptance passed.')
