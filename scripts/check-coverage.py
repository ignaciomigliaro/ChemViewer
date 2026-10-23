#!/usr/bin/env python3
"""Fail closed on missing modules or coverage below the checked-in floor."""
import argparse
import json
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--swift',type=Path);p.add_argument('--python',type=Path);args=p.parse_args()
root=Path(__file__).resolve().parents[1]
floors=json.loads((root/'Tests/coverage-floors.json').read_text())
failed=[]
inventories = {
    'swift': {p.name for p in (root/'Sources/ChemCraftCore').glob('*.swift')},
    'python': {p.name for p in (root/'Sources/ChemCraftMacApp/Resources').glob('*.py')}
}
for kind, names in inventories.items():
    if names != set(floors[kind]):
        failed.append(kind + ' coverage inventory differs; register every module in Tests/coverage-floors.json')
if args.swift:
    data=json.loads(args.swift.read_text())
    files={Path(f['filename']).name:f['summary']['lines'] for d in data['data'] for f in d['files'] if '/Sources/ChemCraftCore/' in f['filename'].replace('\\','/')}
    for name,minimum in floors['swift'].items():
        value=files.get(name);percent=value['covered']/max(value['count'],1)*100 if value else -1
        print(f'Swift {name}: {percent:.2f}% (floor {minimum}%)')
        if percent<minimum:failed.append(name)
    if not files:failed.append('missing core coverage')
if args.python:
    files=json.loads(args.python.read_text())['files']
    for name,minimum in floors['python'].items():
        values=[v['summary']['percent_covered'] for k,v in files.items() if Path(k).name==name]
        percent=values[0] if len(values)==1 else -1
        print(f'Python {name}: {percent:.2f}% (line + branch floor {minimum}%)')
        if percent<minimum:failed.append(name)
if not (args.swift or args.python):p.error('provide --swift or --python')
if failed:raise SystemExit('Coverage gate failed: '+', '.join(failed))
