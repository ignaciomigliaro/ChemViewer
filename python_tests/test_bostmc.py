"""Independent synthetic CSV catalog oracles; no BosTMC data redistributed."""
import base64,csv,hashlib,importlib.util,io,json,os,subprocess,sys,tempfile,time,unittest
from pathlib import Path
from unittest.mock import patch, Mock
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
 def test_process_liveness_never_signals_current_process(self):
  self.assertTrue(Catalog.process_alive(os.getpid()))
  for invalid in (None,True,0,-1,'123',2**32):self.assertFalse(Catalog.process_alive(invalid))
  child=subprocess.Popen([sys.executable,'-c','pass']);child.wait(timeout=10)
  self.assertFalse(Catalog.process_alive(child.pid))
 def test_windows_liveness_contract_closes_handles_without_signals(self):
  import ctypes
  for handle,error,exit_code,probe_ok,expected in [(123,0,259,1,True),(123,0,0,1,False),(None,5,0,0,True),(None,87,0,0,False),(123,0,259,0,False)]:
   kernel=Mock();kernel.OpenProcess.return_value=handle
   def probe(h,code):code._obj.value=exit_code;return probe_ok
   kernel.GetExitCodeProcess.side_effect=probe
   with patch.object(module.os,'name','nt'),patch.object(ctypes,'WinDLL',return_value=kernel,create=True),patch.object(ctypes,'get_last_error',return_value=error,create=True),patch.object(module.os,'kill') as signal:
    self.assertEqual(Catalog.process_alive(42),expected)
    signal.assert_not_called()
   kernel.OpenProcess.assert_called_once_with(0x1000,False,42)
   if handle:kernel.CloseHandle.assert_called_once_with(handle)
   else:kernel.CloseHandle.assert_not_called()
 def test_status_releases_sqlite_connection(self):
  opened=[];connect=module.sqlite3.connect
  class TrackedConnection(module.sqlite3.Connection):
   closed=False
   def close(self):self.closed=True;super().close()
  def open_connection(*args,**kwargs):
   db=connect(*args,**kwargs,factory=TrackedConnection);opened.append(db);return db
  with patch.object(module.sqlite3,'connect',side_effect=open_connection):
   self.assertEqual(Catalog.status(self.request)['phase'],'ready')
  self.assertEqual(len(opened),1);self.assertTrue(opened[0].closed)
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
  self.assertTrue(all('singlets' in Path(f['path']).parts for f in first['files']));self.assertTrue(all('triplets' in Path(f['path']).parts for f in second['files']));self.assertEqual({f['kind'] for f in first['files']},{'xyz','dat'})
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
  children=[];spawn=subprocess.Popen
  def launch(*args,**kwargs):
   child=spawn(*args,**kwargs);children.append(child);return child
  try:
   with patch.object(module.subprocess,'Popen',side_effect=launch):state=Catalog.start(request)
   for _ in range(200):
    state=Catalog.status(request)
    if state['phase'] in ('ready','error'):break
    time.sleep(.025)
   self.assertEqual(state['phase'],'ready',state);self.assertEqual(state['total'],4)
  finally:
   for child in children:
    try:child.wait(timeout=10)
    except subprocess.TimeoutExpired:child.terminate();child.wait(timeout=5);raise
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

class LocalCatalogTests(unittest.TestCase):
 setUp=BosTMCTests.setUp
 tearDown=BosTMCTests.tearDown
 write=BosTMCTests.write
 query=BosTMCTests.query
 def test_compact_index_keeps_large_cells_in_read_only_source(self):
  db,m=Catalog.connect(self.request)
  self.assertEqual(db.execute('SELECT mulliken_charges FROM candidates WHERE __id=1').fetchone()[0],'')
  self.assertEqual(Catalog.detail(dict(self.request,id=1))['values']['mulliken_charges'],'[0.2,-0.1]');db.close()
 def test_summary_categories_and_histogram_numeric_oracles(self):
  s=Catalog.status(self.request)
  self.assertEqual(s['summary']['energetic_gap_eV'],dict(min=.5,max=2.0,count=3))
  self.assertEqual({v['value'] for v in s['categories']['metal']},{'Fe','Co','Ni'})
  h=Catalog.histogram(dict(self.request,property='energetic_gap_eV'))
  self.assertEqual(sum(b['count'] for b in h['bins']),3)
  self.assertEqual(h['bins'][0]['count'],1);self.assertEqual(h['bins'][-1]['count'],1)
 def test_utf8_multiline_record_offsets_and_export_roundtrip(self):
  self.records[0][1]='2\nα molecule\nH 0 0 0\nH 0 0 .74\n';self.records[1][-1]='Unicode β, CRLF\r\nand newline\n'
  self.write();Catalog.build(self.request)
  self.assertEqual(Catalog.detail(dict(self.request,id=1))['values']['xyz'],self.records[0][1])
  exported=Catalog.export(self.request)['csv'];rows=list(csv.reader(io.StringIO(exported,newline='')))
  self.assertEqual(rows[1:],self.records)
 def test_hybrid_file_resolution_needs_no_remote_csv(self):
  folder=self.root/'dataset/quartets/REMOTE';folder.mkdir(parents=True);(folder/'calc.dat').write_text('Synthetic source')
  r=Catalog.execute(dict(action='bostmc-resolve',root=str(self.root/'dataset'),record=dict(refcode='REMOTE',spinmult='4',xyz='')))
  self.assertEqual(r['files'][0]['name'],'calc.dat')
  bridge_spec=importlib.util.spec_from_file_location('bridge_hybrid',ROOT/'remote_bridge.py');bridge=importlib.util.module_from_spec(bridge_spec);bridge_spec.loader.exec_module(bridge)
  payload=dict(action='bostmc-resolve',root=str(self.root/'dataset'),record=dict(refcode='REMOTE',spinmult='4',xyz=''))
  code="import sys;sys.argv=['-c'];exec(compile("+repr(bridge.remote_agent_source().decode())+",'<chemviewer-remote>','exec'))"
  wire=subprocess.run([sys.executable,'-c',code],input=json.dumps(payload),text=True,capture_output=True,check=True)
  response=json.loads(wire.stdout.split('CHEMVIEWER_JSON:')[-1]);self.assertTrue(response['ok'],response);self.assertEqual(response['result']['files'][0]['name'],'calc.dat')

 def test_categorical_index_and_ordering_do_not_require_full_scan_sort(self):
  db,m=Catalog.connect(self.request)
  where,args=Catalog.selection(dict(filters=[dict(property='metal',mode='exact',text='Fe')]),m)
  plan=' '.join(r[3] for r in db.execute('EXPLAIN QUERY PLAN SELECT __id FROM candidates'+where,args))
  self.assertIn('SEARCH',plan)
  plan=' '.join(r[3] for r in db.execute('EXPLAIN QUERY PLAN SELECT __id FROM candidates ORDER BY refcode COLLATE NOCASE,__id LIMIT 50'))
  self.assertNotIn('TEMP B-TREE',plan);db.close()



class CoordinatingAtomTests(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name)
  self.csv=self.root/'donor catalog.csv'
  self.headers=['refcode','xyz','spinmult','metal','coordination_number','charge','coordinating_atoms']
  donors=["['N', 'O', 'S']",'["N", "O", "Cl"]',"['N', 'N']","['Na', 'O']","['Cl']",'[]','NaN',"['N', bad]",'{"N":2}', '["N",null]', '["Br","O"]','N','[7,8]','["Og"]']
  numbers=['1','2','10','11','3','','NaN','4','5','6','7','8','9','12']
  self.records=[[chr(65+i),'g.xyz','1','Co' if i==1 else 'Fe',cn,['-2','2','10'][i%3],raw] for i,(cn,raw) in enumerate(zip(numbers,donors))]
  self.request=dict(csv=str(self.csv),root=str(self.root),cache_dir=str(self.root/'cache'))
  self.build()
 def tearDown(self):self.temp.cleanup()
 def build(self):
  with self.csv.open('w',newline='',encoding='utf-8') as f:
   writer=csv.writer(f);writer.writerow(self.headers);writer.writerows(self.records)
  Catalog.build(self.request);self.assertEqual(Catalog.status(self.request)['phase'],'ready')
 def query(self,elements,**extras):
  return Catalog.query(dict(self.request,filters=[dict(property='coordinating_atom',mode='elements_all',elements=elements)],**extras))
 def test_numeric_dropdown_categories_and_numeric_table_order(self):
  metadata=Catalog.status(self.request)
  self.assertEqual([r['value'] for r in metadata['categories']['coordination_number']],[str(i) for i in range(1,13)])
  self.assertEqual([r['value'] for r in metadata['categories']['charge']],['-2','2','10'])
  for descending in (False,True):
   rows=Catalog.query(dict(self.request,sort='coordination_number',descending=descending))['rows']
   self.assertEqual([int(r['coordination_number']) for r in rows[:-2]],list(range(12,0,-1) if descending else range(1,13)))
   self.assertEqual({r['coordination_number'] for r in rows[-2:]},{'','NaN'})
 def test_contains_every_requested_donor_and_allows_extras(self):
  before=hashlib.sha256(self.csv.read_bytes()).digest()
  self.assertEqual([r['refcode'] for r in self.query(['N','O'])['rows']],['A','B'])
  self.assertEqual([r['refcode'] for r in self.query(['N','O','Cl'])['rows']],['B'])
  self.assertEqual(self.query(['N','O','P'])['total'],0)
  self.assertEqual(hashlib.sha256(self.csv.read_bytes()).digest(),before)
 def test_element_tokens_do_not_match_substrings_or_atom_counts(self):
  self.assertEqual([r['refcode'] for r in self.query(['N'])['rows']],['A','B','C','L'])
  self.assertEqual([r['refcode'] for r in self.query(['Na'])['rows']],['D'])
  self.assertEqual([r['refcode'] for r in self.query(['Cl'])['rows']],['B','E'])
  self.assertEqual(self.query(['C'])['total'],0)
  self.assertEqual([r['refcode'] for r in self.query(['N','N'])['rows']],['A','B','C','L'])
  self.assertEqual([r['refcode'] for r in self.query(['Og'])['rows']],['N'])
 def test_declared_donors_only_and_invalid_values_fail_closed(self):
  for raw in (None,'','NaN','[]','null','true','[7,8]','["N",null]','{"N":2}',"['N',bad]",'NH3','["N","X"]'):
   self.assertEqual(Catalog.coordinating_elements(raw),set(),raw)
  self.assertEqual(Catalog.coordinating_elements("('n', 'o', 'CL')"),{'N','O','Cl'})
  self.assertEqual(Catalog.coordinating_elements('"O"'),{'O'})
  self.assertEqual(Catalog.coordinating_elements(' Cl '),{'Cl'})
  self.assertEqual(Catalog.coordinating_elements('Na'),{'Na'})
  self.assertEqual(Catalog.coordinating_elements('NA'),set())
 def test_filters_combine_with_other_properties_and_export_keeps_source(self):
  filters=[dict(property='coordinating_atom',mode='elements_all',elements=['N','O']),dict(property='metal',mode='exact',text='Fe'),dict(property='coordination_number',mode='range',lower=1,upper=2)]
  request=dict(self.request,filters=filters)
  self.assertEqual([r['refcode'] for r in Catalog.query(request)['rows']],['A'])
  rows=list(csv.DictReader(io.StringIO(Catalog.export(request)['csv'])))
  self.assertEqual(len(rows),1);self.assertEqual(list(rows[0]),self.headers)
  self.assertEqual(rows[0]['coordinating_atoms'],self.records[0][-1])
 def test_invalid_requests_are_rejected(self):
  for elements in ([],None,'N',[None],['X'],['cl'],["N'); DROP TABLE candidates; --"],['N']*119):
   with self.assertRaises(ValueError):self.query(elements)
  self.assertEqual(self.query(['N'])['total'],4)
 def test_missing_header_is_not_inferred_from_other_fields(self):
  self.headers[-1]='molecular_formula';self.build()
  with self.assertRaisesRegex(ValueError,'no declared'):self.query(['N'])
 def test_singular_source_column_is_supported(self):
  self.headers[-1]='coordinating_atom';self.build()
  self.assertEqual([r['refcode'] for r in self.query(['N','O'])['rows']],['A','B'])
 def test_old_cache_is_retained_and_new_index_uses_element_keys(self):
  info=self.csv.stat()
  old=hashlib.sha256((str(self.csv.absolute())+'\0'+str(info.st_size)+'\0'+str(info.st_mtime_ns)+'\0v2').encode()).hexdigest()
  oldfile=self.root/'cache'/old/'index.sqlite';oldfile.parent.mkdir();oldfile.write_bytes(b'preserve old cache')
  self.assertNotEqual(Catalog.location(self.request)[2],old)
  self.assertEqual(oldfile.read_bytes(),b'preserve old cache')
  db,m=Catalog.connect(self.request)
  where,args=Catalog.selection(dict(filters=[dict(property='coordinating_atom',mode='elements_all',elements=['N','O'])]),m)
  plan=' '.join(row[3] for row in db.execute('EXPLAIN QUERY PLAN SELECT __id FROM candidates'+where,args))
  self.assertIn('SEARCH coordinating_elements USING PRIMARY KEY',plan)
  self.assertNotIn('cvraw',where);db.close()
 def test_embedded_remote_dispatch_has_same_element_semantics(self):
  spec=importlib.util.spec_from_file_location('donor_bridge',ROOT/'remote_bridge.py');bridge=importlib.util.module_from_spec(spec);spec.loader.exec_module(bridge)
  payload=dict(self.request,action='bostmc-query',filters=[dict(property='coordinating_atom',mode='elements_all',elements=['N','O'])])
  code="import sys;sys.argv=['-c'];exec(compile("+repr(bridge.remote_agent_source().decode())+",'<chemviewer-remote>','exec'))"
  wire=subprocess.run([sys.executable,'-c',code],input=json.dumps(payload),text=True,capture_output=True,check=True)
  response=json.loads(wire.stdout.split('CHEMVIEWER_JSON:')[-1])
  self.assertTrue(response['ok'],response);self.assertEqual([r['refcode'] for r in response['result']['rows']],['A','B'])

if __name__=='__main__':unittest.main()
