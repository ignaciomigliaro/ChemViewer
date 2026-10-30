#!/usr/bin/env python3
"""Check local links in the current entry-point guides and version agreement."""
from pathlib import Path
import plistlib
import re
root=Path(__file__).resolve().parents[1]
failed=[]
for name in ['README.md','docs/user-guide.md','docs/portable-viewer.md','docs/release-process.md','docs/windows-desktop.md']:
    path=root/name
    for target in re.findall(r'\]\(([^)]+)\)',path.read_text()):
        target=target.split('#',1)[0]
        if not target or '://' in target or target.startswith('mailto:'):continue
        if not (path.parent/target).exists():failed.append(f'{name}: missing {target}')
with (root/'Packaging/Info.plist').open('rb') as stream:version=plistlib.load(stream)['CFBundleShortVersionString']
cli=(root/'Sources/ChemViewerPortable/main.swift').read_text()
if f'print("{version}")' not in cli or f'ChemViewerPortable {version}' not in cli:failed.append('CLI and app versions differ')
if failed:raise SystemExit('\n'.join(failed))
print('Current guide links, images and version declarations are consistent.')
