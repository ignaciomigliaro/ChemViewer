import importlib.util,json,math,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('chemistry_bridge',ROOT/'Sources/ChemCraftMacApp/Resources/chemistry_bridge.py')
bridge=importlib.util.module_from_spec(spec);spec.loader.exec_module(bridge)
class ChemistryTests(unittest.TestCase):
    def test_uff_water_geometry_and_fixed_atom(self):
        request={'atoms':[dict(element='O',x=0,y=0,z=0),dict(element='H',x=1.1,y=0,z=0),dict(element='H',x=0,y=1.1,z=0)],'fixed':[0]}
        result=bridge.optimize(request)
        self.assertTrue(result['converged']);self.assertLess(result['finalEnergy'],result['initialEnergy'])
        self.assertEqual(result['atoms'][0],request['atoms'][0])
        a=result['atoms'];v=[a[1][k]-a[0][k] for k in ['x','y','z']];w=[a[2][k]-a[0][k] for k in ['x','y','z']]
        angle=math.degrees(math.acos(sum(x*y for x,y in zip(v,w))/math.sqrt(sum(x*x for x in v)*sum(y*y for y in w))))
        self.assertAlmostEqual(angle,104.51,delta=.02)
        self.assertAlmostEqual(math.sqrt(sum(x*x for x in v)),.99,delta=.03)
    def test_donor_stoichiometry(self):
        library=json.loads((ROOT/'Sources/ChemCraftMacApp/Resources/Fragments.json').read_text())
        by_name={f['name']:f['atoms'] for f in library if f['category']=='Ligands'}
        self.assertEqual(sum(a['element']=='H' for a in by_name['Ammonia donor']),3)
        self.assertEqual(sum(a['element']=='H' for a in by_name['Aqua donor']),2)
        self.assertEqual(sum(a['element']=='C' for a in by_name['Triphenylphosphine donor']),18)
        self.assertEqual(sum(a['element']=='H' for a in by_name['Triphenylphosphine donor']),15)
    def test_local_chemrefine_gui_schema(self):
        from chemrefine.gui.app import create_app
        client=create_app(token='synthetic-test-token').test_client()
        self.assertEqual(client.get('/api/bootstrap').status_code,401)
        response=client.get('/api/bootstrap',headers={'X-ChemRefine-Token':'synthetic-test-token'})
        self.assertEqual(response.status_code,200)
        self.assertIn('schema',response.get_json())
    def test_dummy_rejected(self):
        with self.assertRaisesRegex(ValueError,'dummy'): bridge.optimize({'atoms':[dict(element='X',x=0,y=0,z=0)]})
    def test_library_attachment_sites(self):
        library=json.loads((ROOT/'Sources/ChemCraftMacApp/Resources/Fragments.json').read_text())
        self.assertGreaterEqual(len(library),250)
        self.assertEqual(len({(x['category'],x['name']) for x in library}),len(library))
        for fragment in library:
            atoms=fragment['atoms'];sites=[a for a in atoms if a['element']=='X'];self.assertTrue(sites,fragment['name'])
            for site in sites:
                distances=[math.dist([site[k] for k in ['x','y','z']],[a[k] for k in ['x','y','z']]) for a in atoms if a['element'] not in ('X','H')]
                self.assertGreater(min(distances),.1,fragment['name']);self.assertLess(min(distances),2.6,fragment['name'])
            self.assertTrue(all(math.isfinite(a[k]) for a in atoms for k in ['x','y','z']))
if __name__=='__main__':unittest.main()
