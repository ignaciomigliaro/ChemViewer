import importlib.util
import math
import unittest
import sys
sys.dont_write_bytecode = True
from pathlib import Path
from rdkit import Chem

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('drawing_bridge', ROOT / 'Sources/ChemCraftMacApp/Resources/drawing_bridge.py')
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)


def node(i, symbol, x, y, charge=0):
    return dict(id=i, element=symbol, x=x, y=y, charge=charge, chiralTag=0)


def edge(a, b, order=1, stereo='none'):
    return dict(a=a, b=b, order=order, stereo=stereo)


class DrawingTests(unittest.TestCase):
    def test_explicit_ethanol_formula_and_geometry(self):
        graph = dict(atoms=[node(0, 'C', 0, 0), node(5, 'C', 48, 0), node(9, 'O', 72, 42)], bonds=[edge(0, 5), edge(5, 9)])
        result = bridge.run(dict(graph=graph))
        self.assertEqual(result['formula'], 'C2H6O')
        self.assertEqual(result['smiles'], 'CCO')
        self.assertEqual(len(result['atoms']), 9)
        self.assertTrue(result['optimized'] and result['converged'])
        points = result['atoms']
        for a, b, low, high in [(0, 1, 1.45, 1.60), (1, 2, 1.35, 1.50)]:
            distance = math.sqrt(sum((points[a][k] - points[b][k]) ** 2 for k in ('x', 'y', 'z')))
            self.assertTrue(low < distance < high)
        # Distinguish a genuine 3D conformer from merely lifting a flat sketch.
        center = points[0]
        vectors = [[points[i][k] - center[k] for k in ('x', 'y', 'z')] for i in (1, 3, 4)]
        a, b, c = vectors
        volume = sum(a[i] * (b[(i+1)%3]*c[(i+2)%3] - b[(i+2)%3]*c[(i+1)%3]) for i in range(3))
        self.assertGreater(abs(volume), 0.5)

    def test_double_triple_and_benzene(self):
        for smiles, formula in [('C=O', 'CH2O'), ('C#N', 'CHN'), ('c1ccccc1', 'C6H6')]:
            result = bridge.run(dict(smiles=smiles))
            self.assertEqual(result['formula'], formula)
            restored = bridge.run(dict(graph=result['graph'], operation='depict'))
            self.assertEqual(restored['smiles'], Chem.MolToSmiles(Chem.MolFromSmiles(smiles)))

    def test_chirality_and_ez_survive_depiction_graph_and_embedding(self):
        for smiles in ['N[C@@H](C)C(=O)O', 'N[C@H](C)C(=O)O', 'F/C=C/F', 'F/C=C\\F']:
            expected = Chem.MolToSmiles(Chem.MolFromSmiles(smiles), isomericSmiles=True)
            depicted = bridge.run(dict(smiles=smiles, operation='depict'))
            result = bridge.run(dict(graph=depicted['graph']))
            self.assertEqual(result['smiles'], expected)
            mol = Chem.MolFromMolBlock(result['molBlock'], removeHs=True)
            self.assertEqual(Chem.MolToSmiles(mol, isomericSmiles=True), expected)

    def test_wedge_direction_changes_enantiomer(self):
        graph = dict(atoms=[node(0, 'C', 0, 0), node(1, 'F', 48, 0), node(2, 'Cl', -24, 42), node(3, 'Br', -24, -42)],
                     bonds=[edge(0, 1, stereo='up'), edge(0, 2), edge(0, 3)])
        up = bridge.run(dict(graph=graph))['smiles']
        graph['bonds'][0]['stereo'] = 'down'
        down = bridge.run(dict(graph=graph))['smiles']
        self.assertIn('@', up)
        self.assertNotEqual(up, down)

    def test_charge_and_disconnected_fragments(self):
        result = bridge.run(dict(smiles='C[NH3+].[Cl-]'))
        self.assertEqual(result['charge'], 0)
        self.assertEqual(result['formula'], 'CH6ClN')
        mol = Chem.MolFromMolBlock(result['molBlock'], removeHs=False)
        fragments = Chem.GetMolFrags(mol)
        conf = mol.GetConformer()
        xs = [[conf.GetAtomPosition(i).x for i in group] for group in fragments]
        self.assertGreaterEqual(min(xs[1]) - max(xs[0]), 2.99)

    def test_invalid_graphs_and_valence_are_rejected(self):
        with self.assertRaises(ValueError):
            bridge.run(dict(smiles='not a molecule'))
        with self.assertRaises(ValueError):
            bridge.run(dict(graph=dict(atoms=[node(0, 'X', 0, 0)], bonds=[])))
        graph = dict(atoms=[node(0, 'C', 0, 0)] + [node(i, 'F', i*48, 0) for i in range(1, 6)], bonds=[edge(0, i) for i in range(1, 6)])
        with self.assertRaises(ValueError):
            bridge.run(dict(graph=graph))
        with self.assertRaises(ValueError):
            bridge.run(dict(graph=dict(atoms=[node(0, 'O', float('nan'), 0)], bonds=[])))

    def test_explicit_hydrogens_radicals_and_isotope_rejection(self):
        for smiles, formula in [('[CH3]', 'CH3'), ('[O-]', 'O-'), ('c1cc[nH]c1', 'C4H5N')]:
            depicted = bridge.run(dict(smiles=smiles, operation='depict'))
            result = bridge.run(dict(graph=depicted['graph']))
            self.assertEqual(result['formula'], formula)
            self.assertEqual(result['smiles'], Chem.MolToSmiles(Chem.MolFromSmiles(smiles)))
        with self.assertRaisesRegex(ValueError, 'Isotope'):
            bridge.run(dict(smiles='[2H]O[2H]'))

    def test_deterministic_embedding(self):
        a, b = bridge.run(dict(smiles='CCO')), bridge.run(dict(smiles='CCO'))
        self.assertEqual(a['atoms'], b['atoms'])


if __name__ == '__main__':
    unittest.main()
