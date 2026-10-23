"""The merge gate must fail closed for missing modules and coverage regressions."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
ROOT=Path(__file__).resolve().parents[1]
FLOORS=json.loads((ROOT/'Tests/coverage-floors.json').read_text())
class CoverageGateTests(unittest.TestCase):
    def run_gate(self, swift, python):
        with tempfile.TemporaryDirectory() as folder:
            a=Path(folder)/'swift.json'; b=Path(folder)/'python.json'
            a.write_text(json.dumps(swift));b.write_text(json.dumps(python))
            return subprocess.run([sys.executable,str(ROOT/'scripts/check-coverage.py'),'--swift',str(a),'--python',str(b)],capture_output=True,text=True)
    def reports(self):
        swift={'data':[{'files':[{'filename':'/workspace/Sources/ChemCraftCore/'+name,'summary':{'lines':{'count':100,'covered':100}}} for name in FLOORS['swift']]}]}
        python={'files':{name:{'summary':{'percent_covered':100}} for name in FLOORS['python']}}
        return swift,python
    def test_complete_reports_pass(self):
        self.assertEqual(self.run_gate(*self.reports()).returncode,0)
    def test_missing_core_or_python_module_fails(self):
        for kind in ['swift','python']:
            a,b=self.reports()
            if kind=='swift':a['data'][0]['files'].pop()
            else:b['files'].pop(next(iter(b['files'])))
            self.assertNotEqual(self.run_gate(a,b).returncode,0)
    def test_coverage_regression_fails(self):
        for kind in ['swift','python']:
            a,b=self.reports()
            if kind=='swift':a['data'][0]['files'][0]['summary']['lines']['covered']=0
            else:b['files'][next(iter(b['files']))]['summary']['percent_covered']=0
            self.assertNotEqual(self.run_gate(a,b).returncode,0)
