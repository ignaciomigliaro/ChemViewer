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

class MetalCleanupTests(unittest.TestCase):
    def setUp(self):
        self.request=json.loads((ROOT/'Tests/fixtures/cleanup/copper-hydride.json').read_text())

    def test_copper_regression_and_independent_bond_oracle(self):
        import copy
        import numpy as np
        from ase.units import Bohr, Hartree
        from scipy.optimize import minimize_scalar
        from tblite.interface import Calculator
        original=copy.deepcopy(self.request)
        result=bridge.optimize(self.request)
        # Independent scalar optimization through the raw tblite API (Bohr/Eh),
        # separate from ASE BFGS/constraints/units used by the application.
        def energy(distance):
            calc=Calculator('GFN2-xTB',np.array([29,1]),np.array([[0.,0.,0.],[distance/Bohr,0.,0.]]),charge=0,uhf=0)
            calc.set('verbosity',0)
            return calc.singlepoint().get('energy')
        oracle=minimize_scalar(energy,bounds=(1.1,2.2),method='bounded',options={'xatol':1e-6})
        self.assertTrue(oracle.success)
        self.assertTrue(result['converged'])
        self.assertEqual((result['method'],result['unit']),('GFN2-xTB','eV'))
        self.assertAlmostEqual(result['initialEnergy'],energy(2.1)*Hartree,places=5)
        self.assertAlmostEqual(result['atoms'][1]['x'],oracle.x,delta=.015)
        self.assertAlmostEqual(result['finalEnergy'],oracle.fun*Hartree,delta=.001)
        self.assertLessEqual(result['maxForce'],.05)
        self.assertEqual(result['atoms'][0],self.request['atoms'][0])
        self.assertEqual(self.request,original)

    def test_copper_coordination_complex(self):
        import numpy as np
        from ase.units import Bohr, Hartree
        from tblite.interface import Calculator
        request=json.loads((ROOT/'Tests/fixtures/cleanup/copper-diammine.json').read_text())
        result=bridge.optimize(request)
        self.assertEqual(result['method'],'GFN2-xTB')
        self.assertEqual([a['element'] for a in result['atoms']], [a['element'] for a in request['atoms']])
        self.assertEqual(result['atoms'][0],request['atoms'][0])
        numbers=np.array([29,7,1,1,1,7,1,1,1])
        positions=np.array([[a[k] for k in ['x','y','z']] for a in result['atoms']])/Bohr
        raw=Calculator('GFN2-xTB',numbers,positions,charge=1,uhf=0)
        raw.set('verbosity',0)
        single=raw.singlepoint()
        self.assertAlmostEqual(result['finalEnergy'],single.get('energy')*Hartree,places=5)
        free_forces=single.get('gradient')[1:]*Hartree/Bohr
        self.assertLessEqual(float(np.linalg.norm(free_forces,axis=1).max()),.05)
        self.assertLess(result['finalEnergy'],result['initialEnergy'])

    def test_other_metal_families_and_open_shell(self):
        for element,spin in [('Li',1),('Fe',2),('Pt',2)]:
            with self.subTest(element=element):
                self.request['atoms'][0]['element']=element
                self.request['multiplicity']=spin
                result=bridge.optimize(self.request)
                self.assertTrue(result['converged'])
                self.assertLess(result['finalEnergy'],result['initialEnergy'])
                self.assertEqual(result['atoms'][0],self.request['atoms'][0])
                self.assertLessEqual(result['maxForce'],.05)

    def test_charge_and_spin_propagated(self):
        self.request.update(charge=1,multiplicity=2)
        result=bridge.optimize(self.request)
        from ase import Atoms
        from tblite.ase import TBLite
        atoms=Atoms('CuH',positions=[[0,0,0],[2.1,0,0]])
        atoms.calc=TBLite(method='GFN2-xTB',charge=1,multiplicity=2,verbosity=0)
        self.assertAlmostEqual(result['initialEnergy'],atoms.get_potential_energy(),places=5)

    def test_uff_explicit_metal_error_is_actionable(self):
        self.request['method']='uff'
        with self.assertRaisesRegex(ValueError,'Automatic or GFN2'):bridge.optimize(self.request)

    def test_nonconvergence_does_not_return_a_geometry(self):
        self.request['steps']=1
        with self.assertRaisesRegex(ValueError,'did not converge'):bridge.optimize(self.request)

    def test_heavy_element_is_bounded(self):
        self.request['atoms'][0]['element']='U'
        self.request['multiplicity']=2
        with self.assertRaisesRegex(ValueError,'H–Rn'):bridge.optimize(self.request)

    def test_invalid_inputs(self):
        from copy import deepcopy
        cases=[({'multiplicity':2},'electron count'),({'charge':.5},'integer'),
               ({'fixed':[2]},'fixed atom'),({'fixed':[0,1]},'All atoms'),
               ({'steps':0},'steps'),({'method':'bogus'},'Unknown')]
        for changes,message in cases:
            with self.subTest(changes=changes),self.assertRaisesRegex(ValueError,message):
                bridge.optimize(dict(self.request,**changes))
        for element,x,message in [('Qq',2.1,'recognized'),('H',float('nan'),'finite'),('H',0.,'overlap')]:
            request=deepcopy(self.request);request['atoms'][1].update(element=element,x=x)
            with self.assertRaisesRegex(ValueError,message):bridge.optimize(request)

    def test_organic_fallback_and_explicit_method(self):
        from unittest.mock import patch
        water={'atoms':[dict(element='O',x=0,y=0,z=0),dict(element='H',x=1.1,y=0,z=0),dict(element='H',x=0,y=1.1,z=0)],'fixed':[0]}
        with patch.object(bridge,'uff',side_effect=ValueError('atom typing failed')):
            result=bridge.optimize(water)
        self.assertEqual(result['method'],'GFN2-xTB')
        self.assertIn('atom typing failed',result['warning'])
        self.assertEqual(bridge.optimize(dict(water,method='uff'))['method'],'UFF')
        self.assertEqual(bridge.optimize(dict(water,method='gfn2'))['method'],'GFN2-xTB')

    def test_bad_backend_results_are_rejected(self):
        from unittest.mock import patch
        good=dict(positions=[[0,0,0],[1.4,0,0]],initialEnergy=-1.,finalEnergy=-2.,converged=True,method='test',unit='eV')
        for changes,message in [({'positions':[[.1,0,0],[1.4,0,0]]},'fixed atom'),
                                ({'positions':[[0,0,0],[float('inf'),0,0]]},'coordinates'),
                                ({'finalEnergy':0.},'energy'),({'finalEnergy':float('nan')},'energy')]:
            with self.subTest(changes=changes),patch.object(bridge,'gfn2',return_value=dict(good,**changes)),self.assertRaisesRegex(ValueError,message):
                bridge.optimize(self.request)

    def test_missing_backend_message(self):
        import sys
        from unittest.mock import patch
        with patch.dict(sys.modules,{'tblite.ase':None}),self.assertRaisesRegex(ValueError,'setup-chemistry'):
            bridge.optimize(self.request)

if __name__=='__main__':unittest.main()
