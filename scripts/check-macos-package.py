#!/usr/bin/env python3
"""Test a relocated .app archive and fail closed on missing bundled resources.

Resource lookup must stay inside the app even when the development tree exists.
No GUI/Metal pass is inferred from this headless packaging probe.
"""
import argparse
from pathlib import Path
import subprocess
import plistlib
import sys
import tempfile
p=argparse.ArgumentParser();p.add_argument('--archive',type=Path,required=True);a=p.parse_args()
with tempfile.TemporaryDirectory(prefix='chemviewer native relocated ') as folder:
    root=Path(folder)
    subprocess.run(['ditto','-x','-k',str(a.archive.resolve()),str(root)],check=True)
    app=root/'ChemViewer.app'
    subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
    binary=app/'Contents/MacOS/ChemViewer'
    sdk=plistlib.loads((app/'Contents/Info.plist').read_bytes()).get('DTSDKName','')
    if not sdk.startswith('macosx'):raise SystemExit('Missing build SDK provenance in packaged Info.plist')
    checker=Path(__file__).with_name('check-macos-sdk.py')
    subprocess.run([sys.executable,str(checker),'--binary',str(binary),'--sdk-version',sdk[6:]],check=True)
    # Independent negative control: the actual regression mislabeled the SDK as 13.0.
    wrong=root/'wrong-sdk-binary'
    subprocess.run(['xcrun','vtool','-set-build-version','macos','13.0','13.0','-replace','-output',str(wrong),str(binary)],check=True,capture_output=True)
    rejected=subprocess.run([sys.executable,str(checker),'--binary',str(wrong),'--sdk-version',sdk[6:]],capture_output=True,text=True)
    if rejected.returncode==0 or 'does not match build SDK' not in rejected.stderr:
        raise SystemExit('Wrong linked-SDK negative control did not fail explicitly')
    print('SDK provenance and SDK-13 appearance-regression negative control passed.')
    result=subprocess.run([str(binary),'--resource-smoke-test'],check=True,capture_output=True,text=True,timeout=30)
    if 'RESOURCE_BUNDLE_PASS' not in result.stdout:raise SystemExit('Resource probe did not confirm packaged lookup')
    print(result.stdout.strip())
    # Deliberately remove a single synthetic copy's helper. A development fallback
    # must not let an incomplete archive pass while the build tree is available.
    bundle=app/'Contents/Resources/ChemViewer_ChemViewerApp.bundle'
    (bundle/'remote_bridge.py').unlink()
    result=subprocess.run([str(binary),'--resource-smoke-test'],capture_output=True,text=True,timeout=30)
    if result.returncode==0 or 'Missing packaged resource: remote_bridge.py' not in result.stderr:
        raise SystemExit('Missing-resource negative control did not fail explicitly')
    print('Relocated app archive and missing-helper negative control passed.')
