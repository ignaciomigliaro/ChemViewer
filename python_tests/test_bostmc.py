"""Independent synthetic CSV catalog oracles; no BosTMC data redistributed."""
import base64,csv,hashlib,importlib.util,io,json,os,subprocess,sys,tempfile,time,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]/'Sources/ChemCraftMacApp/Resources'
spec=importlib.util.spec_from_file_location('bostmc_catalog',ROOT/'bostmc_catalog.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);Catalog=module.BosTMCCatalog

class BosTMCTests(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name)
  self.csv=self.root/'properties with spaces.csv'
  self.headers=['refcode','xyz','spinmult','metal','charge','electronic_energy_Eh','energetic_gap_eV','geometry','coordination_number','metal_ligand_bond_lengths','mulliken_charges','note']
  self.records=[['HUNJAE_comp_0','geometry.xyz','1','Fe','2','-1543.123456789012','1.20','octahedral','6','{"N":[1.9,2.1]}','[0.2,-0.1]','quoted, text\nsecond line'],['HUNJAE_comp_0','geometry.xyz','3','Fe','2','-1543.100000000001','0.50','tetrahedral','4','[2.2,2.3]','[]','triplet'],['CO_TEST','geometry.xyz','2','Co','-1','NaN','2.0','octahedral','6','[1.8,2.0]','[0.3,-0.3]','doublet'],['NI_TEST','geometry.xyz','5','Ni','0','-100.0','','square planar','4','[]','[-0.4,0.4]','missing gap']]
  self.write();self.request=dict(csv=str(self.csv),root=str(self.root/'dataset'),cache_dir=str(self.root/'cache'))
  Catalog.build(self.request);self.assertEqual(Catalog.status(self.request)['phase'],'ready')
 def tearDown(self): self.temp.cleanup()
 def write(self):
  with self.csv.open('w',newline='',encoding='utf-8-sig') as stream:
   writer=csv.writer(stream);writer.writerow(self.headers);writer.writerows(self.records)
 def query(self,**kwargs): return Catalog.query(dict(self.request,**kwargs))
 def test_quoted_csv_and_source_precision(self):
  before=self.csv.read_bytes();d=Catalog.detail(dict(self.request,id=1))['values']
  self.assertEqual(d['note'],'quoted, text\nsecond line');self.assertEqual(d['electronic_energy_Eh'],'-1543.123456789012');self.assertEqual(before,self.csv.read_bytes())
 def test_duplicate_refcodes_keep_spin_records(self):
  rows=self.query(search='HUNJAE')['rows'];self.assertEqual(len(rows),2);self.assertEqual({r['spinmult'] for r in rows},{'1','3'});self.assertEqual(len({r['__id'] for r in rows}),2)
 def test_combined_geometry_electronic_and_spin_filters(self):
  f=[dict(property='metal',mode='exact',text='fe'),dict(property='geometry',mode='exact',text='octahedral'),dict(property='energetic_gap_eV',mode='range',lower=1,upper=1.5)]
  result=self.query(filters=f);self.assertEqual(result['total'],1);self.assertEqual(result['rows'][0]['__id'],1)
 def test_numeric_missing_never_becomes_zero_and_bounds_inclusive(self):
  self.assertEqual(self.query(filters=[dict(property='energetic_gap_eV',mode='range',lower=0,upper=.5)])['total'],1)
  self.assertEqual(self.query(filters=[dict(property='electronic_energy_Eh',mode='range',lower=-2000,upper=0)])['total'],3)
  self.assertEqual(self.query(filters=[dict(property='energetic_gap_eV',mode='missing')])['total'],1)
 def test_array_geometry_any_all_and_mean(self):
  self.assertEqual(self.query(filters=[dict(property='metal_ligand_bond_lengths',mode='any',lower=2.05,upper=2.15)])['rows'][0]['__id'],1)
  self.assertEqual(self.query(filters=[dict(property='metal_ligand_bond_lengths',mode='all',lower=2,upper=2.4)])['rows'][0]['__id'],2)
  self.assertEqual(self.query(filters=[dict(property='metal_ligand_bond_lengths',mode='mean',lower=1.99,upper=2.01)])['rows'][0]['__id'],1)
  self.assertEqual(Catalog.numbers("{'N': [1.9, 2.1], 'atom': 'N2'}"),[1.9,2.1])
 def test_array_limits_apply_to_same_entry_and_empty_all_is_false(self):
  self.assertEqual(self.query(filters=[dict(property='mulliken_charges',mode='any',lower=-.05,upper=.05)])['total'],0)
  self.assertEqual(self.query(filters=[dict(property='mulliken_charges',mode='all',lower=-1,upper=1)])['total'],3)
 def test_bad_filters_and_sql_injection_are_rejected_or_literal(self):
  for f in [dict(property='electronic_energy_Eh',mode='range',lower=2,upper=1),dict(property='charge',mode='range',lower='NaN'),dict(property='evil";DROP TABLE candidates;',mode='present')]:
   with self.assertRaises(ValueError):self.query(filters=[f])
  self.assertEqual(self.query(search="' OR 1=1 --")['total'],0);self.assertEqual(self.query()['total'],4)
 def test_numeric_sort_and_page_boundaries(self):
  a=self.query(sort='electronic_energy_Eh',descending=True,limit=2);b=self.query(sort='electronic_energy_Eh',descending=True,limit=2,offset=2)
  self.assertEqual([r['__id'] for r in a['rows']+b['rows']],[4,2,1,3])
 def test_export_preserves_all_columns_and_quoted_array_values(self):
  result=Catalog.export(dict(self.request,filters=[dict(property='metal',mode='exact',text='Fe')]))
  rows=list(csv.DictReader(io.StringIO(result['csv'])));self.assertEqual(len(rows),2);self.assertEqual(list(rows[0]),self.headers);self.assertEqual(rows[0]['note'],self.records[0][-1]);self.assertEqual(rows[0]['mulliken_charges'],'[0.2,-0.1]')
 def test_spin_folder_resolution_and_dat_association(self):
  for name in ['singlets','triplets']:
   folder=self.root/'dataset'/name/'HUNJAE_comp_0';folder.mkdir(parents=True)
   (folder/'geometry.xyz').write_text('2\nH2\nH 0 0 0\nH 0 0 .74\n');(folder/'psi4.dat').write_text('Synthetic source text')
  first=Catalog.files(dict(self.request,id=1));second=Catalog.files(dict(self.request,id=2))
  self.assertTrue(all('/singlets/' in f['path'] for f in first['files']));self.assertTrue(all('/triplets/' in f['path'] for f in second['files']));self.assertEqual({f['kind'] for f in first['files']},{'xyz','dat'})
 def test_structured_bond_records_exclude_atom_indices(self):
  self.assertEqual(Catalog.numbers('[{"atom1":0,"atom2":1,"length":2.0},{"atom1":0,"atom2":2,"length":1.9}]'),[2.0,1.9])
  self.assertEqual(Catalog.numbers('[{"index":0,"charge":-0.4},{"index":1,"charge":0.4}]'),[-0.4,0.4])
 def test_source_changes_invalidate_fingerprint(self):
  old=Catalog.status(self.request)['fingerprint'];self.records.append(['NEW','g.xyz','1','Cu','','-1','','','','[]','[]','']);self.write()
  current=Catalog.status(self.request);self.assertEqual(current['phase'],'not_indexed');self.assertNotEqual(old,current['fingerprint'])
 def test_malformed_csv_reports_error_without_partial_index(self):
  self.csv.write_text('refcode,xyz,spinmult\na,b,1,extra\n');Catalog.build(self.request)
  state=Catalog.status(self.request);self.assertEqual(state['phase'],'error');self.assertIn('cells',state['error'])
 def test_background_index_protocol_and_csv_path_with_spaces(self):
  other=self.root/'another.csv';other.write_bytes(self.csv.read_bytes());request=dict(self.request,csv=str(other))
  state=Catalog.start(request)
  for _ in range(200):
   state=Catalog.status(request)
   if state['phase'] in ('ready','error'):break
   time.sleep(.025)
  self.assertEqual(state['phase'],'ready',state);self.assertEqual(state['total'],4)
 def test_inline_xyz_still_locates_associated_output(self):
  self.records[0][1]='2\ninline XYZ\nH 0 0 0\nH 0 0 .74\n';self.write();Catalog.build(self.request)
  folder=self.root/'dataset/singlets/HUNJAE_comp_0';folder.mkdir(parents=True);(folder/'psi4.dat').write_text('source')
  found=Catalog.files(dict(self.request,id=1));self.assertEqual(found['inline_xyz'],self.records[0][1]);self.assertEqual(found['files'][0]['kind'],'dat')
 def test_full_user_schema_retains_hyphens_and_all_source_columns(self):
  headers='refcode,xyz,charge,spinmult,electronic_energy_Eh,dipole_moment_debye,alpha_HOMO_Eh,beta_HOMO_Eh,alpha_LUMO_Eh,beta_LUMO_Eh,alpha_gap_Eh,beta_gap_Eh,spin_contamination,mulliken_charges,lowdin_charges,mw,natoms,metal,ox_state,metal_lowdin_charge,metal_lowdin_spin,lowdin_spins,metal_mulliken_charge,metal_mulliken_spin,mulliken_spins,energetic_gap_eV,dipole_magnitude_debye,IS-LS_VSSE_kcal_mol,HS-LS_VSSE_kcal_mol,HS-IS_VSSE_kcal_mol,atomization_energy_Eh,relative_AE_kcal_g,molecular_formula,coordination_formula,csd_r_factor,geometry,geometry_details,coordinating_atoms,bond_lengths,metal_ligand_bond_lengths,metal_index,coordination_number,mol2'.split(',')
  row={h:'' for h in headers};row.update(refcode='SCHEMA',xyz='g.xyz',spinmult='1');row['IS-LS_VSSE_kcal_mol']='-2.123456789'
  with self.csv.open('w',newline='') as f:writer=csv.DictWriter(f,fieldnames=headers);writer.writeheader();writer.writerow(row)
  Catalog.build(self.request);self.assertEqual(Catalog.status(self.request)['headers'],headers)
  found=self.query(filters=[dict(property='IS-LS_VSSE_kcal_mol',mode='range',lower=-3,upper=-2)])
  self.assertEqual(found['total'],1);self.assertEqual(Catalog.detail(dict(self.request,id=1))['values']['IS-LS_VSSE_kcal_mol'],'-2.123456789')
 def test_export_is_streamed_across_batches_and_query_limit_is_bounded(self):
  self.records=[['REC'+str(i),'g.xyz','1','Fe','0','-1','1','octahedral','6','[]','[]',''] for i in range(1050)];self.write();Catalog.build(self.request)
  after=0;parts=[]
  while True:
   batch=Catalog.export(dict(self.request,after=after));parts.append(batch['csv'])
   if batch['done']:break
   self.assertGreater(batch['after'],after);after=batch['after']
  self.assertEqual(len(list(csv.DictReader(io.StringIO(''.join(parts))))),1050)
  self.assertEqual(len(self.query(limit=9999)['rows']),200)

 def test_embedded_remote_agent_catalog_dispatch(self):
  bridge_spec=importlib.util.spec_from_file_location('bridge',ROOT/'remote_bridge.py');bridge=importlib.util.module_from_spec(bridge_spec);bridge_spec.loader.exec_module(bridge)
  source=bridge.remote_agent_source().decode()
  payload=dict(self.request,action='bostmc-query',filters=[dict(property='metal',mode='exact',text='Co')])
  code="import sys;sys.argv=['-c'];exec(compile("+repr(source)+",'<chemviewer-remote>','exec'))"
  result=subprocess.run([sys.executable,'-c',code],input=json.dumps(payload),text=True,capture_output=True,check=True)
  response=json.loads(result.stdout.split('CHEMVIEWER_JSON:')[-1]);self.assertTrue(response['ok'],response);self.assertEqual(response['result']['rows'][0]['refcode'],'CO_TEST')

if __name__=='__main__':unittest.main()
