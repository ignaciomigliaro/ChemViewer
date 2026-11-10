#!/usr/bin/env python3
"""Real Launch Services acceptance in a uniquely identified, signed test app.

Only the owned temporary process/window may close. Never targets the installed app.
"""
import argparse
from pathlib import Path
import plistlib
import subprocess
import tempfile
import time
import uuid

parser = argparse.ArgumentParser()
parser.add_argument('--app', type=Path, required=True)
args = parser.parse_args()
with tempfile.TemporaryDirectory(prefix='chemviewer file open ') as folder:
    app = Path(folder) / 'ChemViewer-file-open.app'
    subprocess.run(['ditto', str(args.app.resolve()), str(app)], check=True)
    identity = 'org.cleanroom.ChemViewer.FileOpenTest.' + str(uuid.uuid4())
    info = app / 'Contents/Info.plist'
    metadata = plistlib.loads(info.read_bytes())
    metadata['CFBundleIdentifier'] = identity
    info.write_bytes(plistlib.dumps(metadata))
    subprocess.run(['codesign', '--force', '--deep', '--sign', '-', str(app)], check=True)
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    log = Path(folder) / 'native.log'
    with log.open('w') as output:
        process = subprocess.Popen([str(app / 'Contents/MacOS/ChemViewer'),
            '--file-open-smoke-test', '-ApplePersistenceIgnoreState', 'YES'],
            stdout=output, stderr=subprocess.STDOUT)
        try:
            time.sleep(1)
            subprocess.run(['open', '-a', str(app)], check=True)
            code = process.wait(timeout=180)
        finally:
            if process.poll() is None:
                process.terminate()  # Only the exact subprocess created above.
                process.wait(timeout=10)
    text = log.read_text()
    print(text)
    if code or 'FILE_OPEN_PASS:' not in text:
        raise SystemExit('Isolated native file-open acceptance failed')
