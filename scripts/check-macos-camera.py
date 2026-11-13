#!/usr/bin/env python3
"""Exercise camera or related native regressions in an owned UUID test bundle."""
import argparse
from pathlib import Path
import plistlib
import subprocess
import tempfile
import os
import signal
import uuid

parser = argparse.ArgumentParser()
parser.add_argument('--app', type=Path, required=True)
parser.add_argument('--test', choices=['camera', 'ligand-selection', 'smooth', 'animation', 'fragment-placement', 'manipulation', 'fragment-rotation', 'document-workspace', 'vibration', 'smoke'], default='camera')
parser.add_argument('--capture-window', action='store_true')
parser.add_argument('--evidence', type=Path, required=True)
args = parser.parse_args()
args.evidence.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix='chemviewer camera isolated ') as folder:
    app = Path(folder) / 'ChemViewer-camera.app'
    subprocess.run(['ditto', str(args.app.resolve()), str(app)], check=True)
    info = app / 'Contents/Info.plist'
    metadata = plistlib.loads(info.read_bytes())
    metadata['CFBundleIdentifier'] = 'org.cleanroom.ChemViewer.CameraTest.' + str(uuid.uuid4())
    info.write_bytes(plistlib.dumps(metadata))
    subprocess.run(['codesign', '--force', '--deep', '--sign', '-', str(app)], check=True)
    log = args.evidence / (args.test + '.log')
    flag = '--smoke-test' if args.test == 'smoke' else '--' + args.test + '-smoke-test'
    error_log = args.evidence / (args.test + '.stderr.log')
    log.write_text('')
    error_log.write_text('')
    process = subprocess.Popen(['open', '-W', '-n', '-a', str(app),
        '--stdout', str(log.resolve()), '--stderr', str(error_log.resolve()), '--args', flag,
        '--camera-evidence', str((args.evidence / 'camera.png').resolve()),
        '--animation-evidence', str((args.evidence / 'animation').resolve()),
        '--render-evidence', str(args.evidence.resolve()), *(['--capture-window'] if args.capture_window else []),
        '-ApplePersistenceIgnoreState', 'YES'])
    try:
        code = process.wait(timeout=240)
    finally:
        if process.poll() is None:
            # Launch Services owns the app PID. Match only this unique temporary
            # executable, using both /var and /private/var spellings.
            binaries = [str(app / 'Contents/MacOS/ChemViewer'),
                        str(app.resolve() / 'Contents/MacOS/ChemViewer')]
            listing = subprocess.check_output(['ps', '-axo', 'pid=,command='], text=True)
            for line in listing.splitlines():
                parts = line.strip().split(None, 1)
                if len(parts) == 2 and any(parts[1] == b or parts[1].startswith(b + ' ') for b in binaries):
                    try: os.kill(int(parts[0]), signal.SIGTERM)
                    except ProcessLookupError: pass
            process.terminate()
            process.wait(timeout=10)
    text = log.read_text() + error_log.read_text()
    print(text)
    if code or ('PASS' not in text and 'passed' not in text):
        raise SystemExit('Isolated native acceptance failed: ' + args.test)
