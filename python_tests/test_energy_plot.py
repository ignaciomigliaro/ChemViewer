import csv
import importlib.util
import json
import math
from pathlib import Path
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'Sources/ChemCraftMacApp/Resources/energy_landscape.py'
spec = importlib.util.spec_from_file_location('energy_landscape', SCRIPT)
plot = importlib.util.module_from_spec(spec)
try:
    spec.loader.exec_module(plot)
except ModuleNotFoundError as error:
    if error.name in ('matplotlib', 'numpy'):
        raise unittest.SkipTest('Matplotlib plotting tests require scripts/setup-plotting.sh')
    raise


class EnergyPlotTests(unittest.TestCase):
    def data(self):
        return {'unit': 'kJ/mol', 'reference': 'minimum', 'structures': True,
                'points': [{'geometry': i + 1, 'x': i + 1, 'energy_hartree': e,
                            'atoms': [{'element': 'H', 'x': 0, 'y': 0, 'z': 0}, {'element': 'H', 'x': .74, 'y': 0, 'z': 0}]}
                           for i, e in enumerate([-1.0, -1.005, None, -.995])]}

    def test_units_reference_and_missing_energy_gap(self):
        data = self.data()
        x, y, zero, unit = plot.prepare(data)
        self.assertEqual(x, [1, 2, 3, 4])
        self.assertEqual(zero, -1.005)
        self.assertAlmostEqual(y[0], 13.1274981974, places=8)
        self.assertEqual(y[1], 0)
        self.assertTrue(math.isnan(y[2]))
        self.assertAlmostEqual(y[3], 26.2549963948, places=8)
        data['reference'] = 'first'; data['unit'] = 'kcal/mol'
        self.assertAlmostEqual(plot.prepare(data)[1][1], -3.1375473703, places=8)
        data['reference'] = 'absolute'; data['unit'] = 'Eh'
        self.assertEqual(plot.prepare(data)[1][0], -1)

    def test_publication_exports_and_data(self):
        from PIL import Image
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            plot.render(self.data(), root)
            self.assertTrue((root / 'energy-profile.pdf').read_bytes().startswith(b'%PDF'))
            self.assertIn('<svg', (root / 'energy-profile.svg').read_text())
            image = Image.open(root / 'energy-profile.png')
            self.assertEqual(image.size, (4080, 3120))
            self.assertAlmostEqual(image.info['dpi'][0], 600, places=1)
            with (root / 'energy-profile.csv').open() as stream:
                rows = list(csv.DictReader(stream))
            self.assertEqual(rows[2]['plotted_energy'], '')
            self.assertEqual(rows[2]['energy_hartree'], '')
            self.assertAlmostEqual(float(rows[0]['plotted_energy']), 13.1274981974, places=8)
            metadata = json.loads((root / 'plot-metadata.json').read_text())
            self.assertEqual(metadata['reference_hartree'], -1.005)
            self.assertEqual(metadata['energy_count'], 3)
            self.assertEqual(metadata['interpolation'], 'none')

    def test_reject_unknown_units_and_insufficient_data(self):
        data = self.data(); data['unit'] = 'unknown'
        with self.assertRaises(ValueError): plot.prepare(data)
        data['unit'] = 'Eh'; data['points'] = data['points'][:1]
        with self.assertRaises(ValueError): plot.prepare(data)


if __name__ == '__main__':
    unittest.main()

class NEBPlotTests(unittest.TestCase):
    def data(self):
        return {'unit': 'kcal/mol', 'reference': 'first', 'structures': False, 'markers': False,
                'plot_style': 'diagram', 'data_source': 'ORCA NEB path summary', 'ts_index': 1,
                'points': [{'geometry': i + 1, 'x': i, 'label': label, 'energy_hartree': e,
                            'relative_energy_kcal': relative, 'atoms': []}
                           for i, (label, e, relative) in enumerate([('Reactants', -10, 0), ('Transition state', -9.85, 94.13), ('Products', -9.95, 31.38)])]}

    def test_printed_relative_precision_and_refined_barriers(self):
        data = self.data()
        self.assertEqual(plot.prepare(data)[1], [0, 94.13, 31.38])
        summary = plot.barrier_summary(data)
        self.assertAlmostEqual(summary['forward'], 94.13)
        self.assertAlmostEqual(summary['reverse'], 62.75)
        data['unit'] = 'kJ/mol'
        self.assertAlmostEqual(plot.prepare(data)[1][1], 94.13 * 4.184)
        data['reference'] = 'absolute'; data['unit'] = 'Eh'
        self.assertEqual(plot.prepare(data)[1], [-10, -9.85, -9.95])

    def test_no_markers_on_lines_or_levels(self):
        for style in ['profile', 'diagram']:
            fig, ax = plot.plt.subplots()
            data = self.data(); data['plot_style'] = style
            x, y, _, _ = plot.prepare(data)
            plot.draw_curve(ax, x, y, data)
            self.assertEqual(len(ax.collections), 0)
            self.assertGreater(len(ax.lines), 0)
            plot.plt.close(fig)
        data['markers'] = True
        fig, ax = plot.plt.subplots()
        plot.draw_curve(ax, x, y, data)
        self.assertGreater(len(ax.collections), 0)
        plot.plt.close(fig)

    def test_reaction_diagram_metadata_and_exports(self):
        with tempfile.TemporaryDirectory() as folder:
            data = self.data(); plot.render(data, folder)
            folder = Path(folder)
            metadata = json.loads((folder / 'plot-metadata.json').read_text())
            self.assertAlmostEqual(metadata['barriers']['reverse'], 62.75)
            self.assertFalse(metadata['markers'])
            self.assertEqual(metadata['relative_energy_basis'], 'printed ORCA kcal/mol column')
            svg = (folder / 'energy-profile.svg').read_text()
            self.assertNotIn('energy-markers', svg)
            self.assertIn('Transition state', svg)
