#!/usr/bin/env python3
"""Package an already built portable executable and its SwiftPM resource bundle.

Swift runtime/toolchain is required on the destination; this is a preview SDK
artifact, not a standalone Windows installer. Never include local calculations.
"""
import argparse
from pathlib import Path
import shutil
import subprocess
import sys
import zipfile
p=argparse.ArgumentParser();p.add_argument('--output', type=Path, required=True);a=p.parse_args()
root=Path(__file__).resolve().parents[1]
bin_dir=Path(subprocess.check_output(['swift','build','-c','release','--show-bin-path'],cwd=root,text=True).strip())
exe='ChemViewerPortable'+('.exe' if sys.platform=='win32' else '')
resources=[x for x in bin_dir.iterdir() if x.is_dir() and 'ChemViewerPortable' in x.name and x.suffix in ('.resources','.bundle')]
if len(resources)!=1:raise SystemExit('Expected one portable SwiftPM resource bundle')
a.output.parent.mkdir(parents=True,exist_ok=True)
with zipfile.ZipFile(a.output,'w',zipfile.ZIP_DEFLATED) as archive:
    archive.write(bin_dir/exe,exe)
    for file in resources[0].rglob('*'):
        if file.is_file():archive.write(file,file.relative_to(bin_dir))
    archive.write(root/'docs/portable-viewer.md','README.md')
    for file in (root/'Tests/fixtures').glob('*.xyz'):archive.write(file,'examples/'+file.name)
print(a.output)
