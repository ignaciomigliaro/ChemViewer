#!/usr/bin/env python3
"""Exercise the built executable through real files; no Swift logic duplicated."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BINARY = None

class PortableTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name)

    def run_cli(self, *args, ok=True):
        result = subprocess.run([str(BINARY), *map(str, args)], capture_output=True, text=True, encoding='utf-8')
        self.assertEqual(result.returncode == 0, ok, result.stderr)
        return result

    def test_water_json_coordinates_bonds_missing_energy_and_unicode_path(self):
        path = self.folder / 'water μ with spaces.json'
        self.run_cli(ROOT/'Tests/fixtures/water.xyz', '--json', '--output', path)
        value = json.loads(path.read_text(encoding='utf-8'))
        self.assertEqual(value['schemaVersion'], 1)
        self.assertEqual(value['coordinateUnit'], 'angstrom')
        self.assertEqual(value['energyUnit'], 'hartree')
        self.assertEqual([a['element'] for a in value['frames'][0]['atoms']], ['O', 'H', 'H'])
        self.assertAlmostEqual(value['frames'][0]['atoms'][1]['position'][0], .9572, places=6)
        self.assertEqual(value['frames'][0]['bonds'], [[0, 1], [0, 2]])
        self.assertNotIn('energyHartree', value['frames'][0])

    def test_trajectory_export_roundtrip_and_no_overwrite(self):
        path = self.folder/'path.xyz'
        original = ROOT/'Tests/fixtures/energy-path.xyz'
        self.run_cli(original, '--xyz', '--output', path)
        jsons = []
        for i, source in enumerate([original, path]):
            destination = self.folder/f'{i}.json'
            self.run_cli(source, '--json', '--output', destination)
            jsons.append(json.loads(destination.read_text(encoding='utf-8')))
        self.assertEqual(len(jsons[0]['frames']), len(jsons[1]['frames']))
        for a, b in zip(jsons[0]['frames'], jsons[1]['frames']):
            self.assertEqual(a['atoms'], b['atoms'])
            self.assertEqual(a.get('energyHartree'), b.get('energyHartree'))
        before = path.read_bytes()
        self.run_cli(original, '--xyz', '--output', path, ok=False)
        self.assertEqual(path.read_bytes(), before)
        self.run_cli(original, '--xyz', '--output', original, ok=False)

    def test_imaginary_mode_and_source_geometry(self):
        path = self.folder/'modes.json'
        self.run_cli(ROOT/'Tests/fixtures/integrated-building/synthetic-modes.out', '--json', '--output', path)
        value = json.loads(path.read_text(encoding='utf-8'))
        self.assertEqual([m['frequencyCM1'] for m in value['modes']], [1600, 3600, -250])
        self.assertEqual(value['vibrationalFrameIndex'], 0)
        self.assertEqual(value['modes'][2]['displacements'], [[.2, 0, 0], [-.1, 0, 0], [-.1, 0, 0]])
        self.assertEqual(value['frames'][0]['energyHartree'], -75)

    def test_rejects_invalid_and_unknown_arguments_without_output(self):
        invalid = self.folder/'invalid.xyz'
        invalid.write_text('2\ntruncated\nH 0 0 0\n', encoding='utf-8')
        path = self.folder/'must-not-exist.html'
        self.run_cli(invalid, '--output', path, ok=False)
        self.assertFalse(path.exists())
        for args in [('--nonsense',), ('--json', '--xyz'), ('--output',)]:
            self.run_cli(invalid, *args, ok=False)
        self.run_cli(self.folder/'missing.xyz', ok=False)
        self.run_cli('--help'); self.run_cli('--version')

    def test_orca_input_companion_is_resolved_from_input_directory(self):
        (self.folder/'seed.xyz').write_text('2\nH2\nH 0 0 0\nH 0 0 .74\n', encoding='utf-8')
        source = self.folder/'input.inp'
        source.write_text('! HF STO-3G\n* xyzfile -1 2 seed.xyz\n', encoding='utf-8')
        path = self.folder/'input.json'
        self.run_cli(source, '--json', '--output', path)
        value = json.loads(path.read_text(encoding='utf-8'))
        self.assertEqual((value['charge'], value['multiplicity']), (-1, 2))
        self.assertEqual(len(value['frames'][0]['atoms']), 2)

    def test_html_injection_is_inert_and_viewer_has_no_network_dependency(self):
        import base64
        import re
        source = self.folder/'injection.xyz'
        # Write exact bytes: Windows text-mode writes otherwise translate LF to
        # CRLF. Source preservation must be checked against the bytes we supply.
        text = '1\r\n</script><img src=x onerror=alert(1)> μ\r\nHe 0 0 0\r\n'
        source.write_bytes(text.encode('utf-8'))
        output = self.folder/'view.html'
        self.run_cli(source, '--output', output)
        html = output.read_text(encoding='utf-8')
        self.assertNotIn('onerror=alert(1)', html)
        encoded = re.search(r'<script id="payload"[^>]*>([^<]+)</script>', html).group(1)
        self.assertEqual(json.loads(base64.b64decode(encoded))['source'], text)
        self.assertNotRegex(html, r'(?:src|href)="https?://')

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--binary', type=Path, required=True)
    args = parser.parse_args()
    BINARY = args.binary.resolve()
    unittest.main(argv=[__file__], verbosity=2)
