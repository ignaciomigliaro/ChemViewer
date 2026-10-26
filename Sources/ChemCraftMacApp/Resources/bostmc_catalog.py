"""Original BOS-TMC CSV/SQLite screening engine. Standard library only; source data is read-only."""
import ast
import base64
import csv
from contextlib import closing
import hashlib
import io
import json
import math
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import time


class BosTMCCatalog:
    numeric = set('charge spinmult electronic_energy_Eh dipole_magnitude_debye alpha_HOMO_Eh beta_HOMO_Eh alpha_LUMO_Eh beta_LUMO_Eh alpha_gap_Eh beta_gap_Eh spin_contamination mw natoms ox_state metal_lowdin_charge metal_lowdin_spin metal_mulliken_charge metal_mulliken_spin energetic_gap_eV IS-LS_VSSE_kcal_mol HS-LS_VSSE_kcal_mol HS-IS_VSSE_kcal_mol atomization_energy_Eh relative_AE_kcal_g csd_r_factor metal_index coordination_number'.split())
    bulky = set('xyz mol2 mulliken_charges lowdin_charges mulliken_spins lowdin_spins geometry_details bond_lengths metal_ligand_bond_lengths dipole_moment_debye coordinating_atoms'.split())
    categorical = set('metal geometry charge spinmult ox_state coordination_number'.split())
    missing = {'', 'none', 'null', 'nan', 'na', 'n/a', '--'}
    elements = frozenset("H He Li Be B C N O F Ne Na Mg Al Si P S Cl Ar K Ca Sc Ti V Cr Mn Fe Co Ni Cu Zn Ga Ge As Se Br Kr Rb Sr Y Zr Nb Mo Tc Ru Rh Pd Ag Cd In Sn Sb Te I Xe Cs Ba La Ce Pr Nd Pm Sm Eu Gd Tb Dy Ho Er Tm Yb Lu Hf Ta W Re Os Ir Pt Au Hg Tl Pb Bi Po At Rn Fr Ra Ac Th Pa U Np Pu Am Cm Bk Cf Es Fm Md No Lr Rf Db Sg Bh Hs Mt Ds Rg Cn Nh Fl Mc Lv Ts Og".split())

    @classmethod
    def coordinating_elements(cls, raw):
        """Exact symbols from the declared donor list; never infer from formula/XYZ."""
        if not isinstance(raw, str): return set()
        if raw.strip() in cls.elements: return {raw.strip()}
        if raw.strip().lower() in cls.missing: return set()
        try:
            parsed = json.loads(raw)
        except (ValueError, TypeError):
            try: parsed = ast.literal_eval(raw)
            except (ValueError, SyntaxError, TypeError, RecursionError): parsed = raw.strip()
        if isinstance(parsed, str): parsed = [parsed]
        if not isinstance(parsed, (list, tuple)): return set()
        symbols = set()
        for value in parsed:
            if not isinstance(value, str): return set()
            symbol = value.strip().capitalize()
            if symbol not in cls.elements: return set()
            symbols.add(symbol)
        return symbols

    @staticmethod
    def number(value):
        try:
            result = float(str(value).strip().replace('D', 'E').replace('d', 'e'))
            return result if math.isfinite(result) else None
        except (ValueError, TypeError):
            return None
    @staticmethod
    def numbers(value):
        try:
            parsed = json.loads(value)
        except (ValueError, TypeError):
            try: parsed = ast.literal_eval(value)
            except (ValueError, SyntaxError, TypeError, RecursionError): return []
        result = []
        def visit(v, depth=0):
            if depth > 12: return
            if isinstance(v, dict):
                # Structured per-bond/per-atom records: do not aggregate identifier indices.
                value_keys=[k for k in ('length','bond_length','distance','charge','spin','value') if k in v]
                if len(value_keys)==1: visit(v[value_keys[0]],depth+1)
                elif not value_keys:
                    for key,child in v.items():
                        if str(key).lower() not in ('index','atom','atom1','atom2','i','j','metal_index'): visit(child,depth+1)
            elif isinstance(v, (list, tuple)):
                for child in v: visit(child, depth+1)
            elif isinstance(v, (int,float)) and not isinstance(v,bool) and math.isfinite(v): result.append(float(v))
        visit(parsed)
        return result
    @staticmethod
    def location(request):
        source = Path(request['csv']).expanduser().absolute()
        info = source.stat()
        fingerprint = hashlib.sha256((str(source)+'\0'+str(info.st_size)+'\0'+str(info.st_mtime_ns)+'\0v3').encode()).hexdigest()
        cache = Path(request.get('cache_dir') or Path.home()/'.cache/ChemViewer/BossTMC').expanduser().absolute()/fingerprint
        cache.mkdir(parents=True, exist_ok=True, mode=0o700)
        return source, cache, fingerprint
    @staticmethod
    def atomic(path, value):
        temporary = path.with_name(path.name+'.'+str(os.getpid())+'.tmp')
        temporary.write_text(json.dumps(value, allow_nan=False)); temporary.replace(path)
    @classmethod
    def build(cls, request):
        source, cache, fingerprint = cls.location(request)
        with (cache/'build.lock').open('a') as lock:
            try:
                if os.name == 'nt':
                    import msvcrt
                    lock.write(' ');lock.flush();lock.seek(0);msvcrt.locking(lock.fileno(),msvcrt.LK_NBLCK,1)
                else:
                    import fcntl
                    fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
            except OSError: return
            temporary = cache/('index.'+str(os.getpid())+'.tmp')
            status = dict(phase='indexing', rows=0, pid=os.getpid(), fingerprint=fingerprint)
            cls.atomic(cache/'status.json', status)
            db = None
            try:
                csv.field_size_limit(50_000_000)
                with source.open('rb') as stream:
                    class Lines:
                        def __iter__(self): return self
                        def __next__(self):
                            at=stream.tell();line=stream.readline()
                            if not line: raise StopIteration
                            return line.decode('utf-8-sig' if at==0 else 'utf-8')
                    reader = csv.reader(Lines(), strict=True)
                    headers = next(reader)
                    if len(headers) != len(set(headers)) or not 1 <= len(headers) <= 200: raise ValueError('CSV headers must be unique (maximum 200).')
                    if not {'refcode','xyz','spinmult'}.issubset(headers): raise ValueError('CSV needs refcode, xyz and spinmult columns.')
                    if any(not h or len(h)>120 or h.startswith('__') for h in headers): raise ValueError('Invalid CSV column name.')
                    quote = lambda h: '"'+h.replace('"','""')+'"'
                    numeric = [h for h in headers if h in cls.numeric]
                    db = sqlite3.connect(temporary)
                    db.execute('PRAGMA journal_mode=OFF'); db.execute('PRAGMA synchronous=OFF')
                    definitions = ['__id INTEGER PRIMARY KEY']+[quote(h)+' TEXT' for h in headers]+['"__n'+str(i)+'" REAL' for i in range(len(numeric))]
                    db.execute('CREATE TABLE candidates ('+','.join(definitions)+')')
                    db.execute('CREATE TABLE payloads (id INTEGER PRIMARY KEY, offset INTEGER, length INTEGER)')
                    db.execute('CREATE TABLE coordinating_elements (element TEXT, candidate_id INTEGER, PRIMARY KEY(element,candidate_id)) WITHOUT ROWID')
                    insert = 'INSERT INTO candidates VALUES ('+','.join('?' for _ in definitions)+')'
                    count=0
                    while True:
                        begin=stream.tell()
                        try: values=next(reader)
                        except StopIteration: break
                        end=stream.tell()
                        if not values: continue
                        if len(values)!=len(headers): raise ValueError('CSV record '+str(reader.line_num)+' has '+str(len(values))+' cells; expected '+str(len(headers))+'.')
                        count+=1; row=dict(zip(headers,values))
                        db.execute(insert,[count]+['' if h in cls.bulky else row[h] for h in headers]+[cls.number(row[h]) for h in numeric])
                        db.execute('INSERT INTO payloads VALUES (?,?,?)',[count,begin,end-begin])
                        donors = cls.coordinating_elements(row.get('coordinating_atoms', row.get('coordinating_atom', '')))
                        db.executemany('INSERT INTO coordinating_elements VALUES (?,?)', [(symbol,count) for symbol in donors])
                        if count%2000==0:
                            db.commit();status['rows']=count;cls.atomic(cache/'status.json',status)
                    for h in ['refcode','metal','spinmult','geometry','charge','ox_state','coordination_number']:
                        if h in headers: db.execute('CREATE INDEX '+quote('__i'+str(headers.index(h)))+' ON candidates('+quote(h)+' COLLATE NOCASE)' )
                    for i in range(len(numeric)): db.execute('CREATE INDEX "__ni'+str(i)+'" ON candidates("__n'+str(i)+'")')
                    summary={}
                    for h in numeric:
                        col='__n'+str(numeric.index(h));lo,hi,n=db.execute('SELECT MIN('+col+'), MAX('+col+'), COUNT('+col+') FROM candidates').fetchone()
                        summary[h]=dict(min=lo,max=hi,count=n)
                    categories={}
                    for h in cls.categorical & set(headers):
                        order = ('"__n'+str(numeric.index(h))+'" ASC NULLS LAST,') if h in numeric else ''
                        categories[h] = [dict(value=v,count=n) for v,n in db.execute('SELECT '+quote(h)+', COUNT(*) FROM candidates GROUP BY '+quote(h)+' ORDER BY '+order+quote(h)+' COLLATE NOCASE') if v.strip() and v.strip().lower() not in cls.missing]
                    metadata = dict(summary=summary,categories=categories,headers=headers,numeric=numeric,total=count,fingerprint=fingerprint,csv=str(source),phase='ready')
                    db.execute('CREATE TABLE metadata (data TEXT)');db.execute('INSERT INTO metadata VALUES (?)',[json.dumps(metadata)])
                    db.commit();db.close();db=None
                    if cls.location(request)[2]!=fingerprint: raise ValueError('CSV changed while indexing. Index the current version again.')
                    temporary.replace(cache/'index.sqlite')
                    cls.atomic(cache/'status.json',dict(metadata,rows=count))
            except Exception as error:
                if db is not None: db.close()
                temporary.unlink(missing_ok=True)
                cls.atomic(cache/'status.json',dict(phase='error',error=str(error),rows=status['rows']))
    @classmethod
    def start(cls, request):
        source, cache, fingerprint = cls.location(request)
        if (cache/'index.sqlite').exists(): return cls.status(request)
        status=cls.status(request)
        if status['phase']=='indexing': return status
        code = globals().get('_BOSTMC_SOURCE') or Path(__file__).read_text()
        bootstrap='import base64,json;exec(compile(base64.b64decode('+repr(base64.b64encode(code.encode()).decode())+'),"<bostmc-index>","exec"));getattr(os,"nice",lambda _:None)(10);BosTMCCatalog.build(json.loads(base64.b64decode('+repr(base64.b64encode(json.dumps(request).encode()).decode())+')))'
        log=(cache/'index.log').open('ab')
        child=subprocess.Popen([sys.executable,'-c',bootstrap],stdin=subprocess.DEVNULL,stdout=log,stderr=log,start_new_session=True);log.close()
        return dict(phase='indexing',rows=0,pid=child.pid,fingerprint=fingerprint)
    @classmethod
    def status(cls,request):
        source,cache,fingerprint=cls.location(request)
        if (cache/'index.sqlite').exists():
            with closing(sqlite3.connect(cache/'index.sqlite')) as db: result=json.loads(db.execute('SELECT data FROM metadata').fetchone()[0])
            return result
        try: result=json.loads((cache/'status.json').read_text())
        except (OSError,ValueError): return dict(phase='not_indexed',rows=0,fingerprint=fingerprint)
        if result.get('phase')=='indexing':
            try: os.kill(result['pid'],0)
            except (OSError,KeyError): return dict(phase='error',error='Indexing stopped. Click Index CSV to retry.',rows=result.get('rows',0))
        return result
    @classmethod
    def raw(cls,db,metadata,row_id):
        record=db.execute('SELECT offset,length FROM payloads WHERE id=?',[row_id]).fetchone()
        if record is None: raise ValueError('Record not found.')
        with Path(metadata['csv']).open('rb') as stream:
            stream.seek(record[0]);data=stream.read(record[1]).decode('utf-8')
        values=next(csv.reader(io.StringIO(data,newline='')))
        return dict(zip(metadata['headers'],values))
    @classmethod
    def connect(cls,request):
        _,cache,_=cls.location(request)
        if not (cache/'index.sqlite').exists(): raise ValueError('Index this CSV before querying it.')
        db=sqlite3.connect((cache/'index.sqlite').as_uri()+'?mode=ro',uri=True)
        db.row_factory=sqlite3.Row
        metadata=json.loads(db.execute('SELECT data FROM metadata').fetchone()[0])
        csv.field_size_limit(50_000_000)
        db.create_function('cvraw',2,lambda row_id,index:cls.raw(db,metadata,row_id)[metadata['headers'][index]])
        db.create_function('cvnumber',1,cls.number)
        db.create_function('cvpresent',1,lambda x: int(str(x or '').strip().lower() not in cls.missing))
        def array_test(raw, mode, lower, upper):
            values=cls.numbers(raw)
            if not values: return 0
            if mode=='any': return int(any((lower is None or v>=lower) and (upper is None or v<=upper) for v in values))
            if mode=='all': return int(all((lower is None or v>=lower) and (upper is None or v<=upper) for v in values))
            v={'mean':lambda:sum(values)/len(values),'min':lambda:min(values),'max':lambda:max(values)}[mode]()
            return int((lower is None or v>=lower) and (upper is None or v<=upper))
        db.create_function('cvarray',4,array_test)
        return db,metadata
    @classmethod
    def selection(cls,request,metadata):
        quote=lambda h:'"'+h.replace('"','""')+'"'
        clauses=[];values=[];headers=metadata['headers']
        search=str(request.get('search','')).strip()
        if search:
            fields=[h for h in ['refcode','molecular_formula','coordination_formula','metal','geometry'] if h in headers]
            clauses.append('('+' OR '.join('instr(lower('+quote(h)+'),lower(?))>0' for h in fields)+')');values.extend([search]*len(fields))
        filters=request.get('filters',[])
        if len(filters)>32: raise ValueError('Maximum 32 filters.')
        for f in filters:
            h=f['property'];mode=f.get('mode','range')
            if h == 'coordinating_atom' and mode == 'elements_all':
                if not {'coordinating_atoms','coordinating_atom'} & set(headers):
                    raise ValueError('CSV has no declared coordinating-atom field.')
                requested = f.get('elements')
                if not isinstance(requested, list) or not 1 <= len(requested) <= 118:
                    raise ValueError('Choose at least one coordinating element (maximum 118).')
                selected = set()
                for element in requested:
                    if not isinstance(element, str) or element not in cls.elements:
                        raise ValueError('Choose valid periodic-table element symbols.')
                    selected.add(element)
                for element in sorted(selected):
                    clauses.append('__id IN (SELECT candidate_id FROM coordinating_elements WHERE element=?)')
                    values.append(element)
                continue
            if h not in headers: raise ValueError('Unknown property: '+h)
            col=quote(h)
            if h in cls.bulky: col='cvraw(__id,'+str(headers.index(h))+')'
            if mode in ('present','missing'): clauses.append('cvpresent('+col+')='+('1' if mode=='present' else '0'));continue
            if mode in ('contains','exact'):
                text=str(f.get('text',''))
                clauses.append('instr(lower('+col+'),lower(?))>0' if mode=='contains' else col+'=? COLLATE NOCASE');values.append(text);continue
            lower,upper=f.get('lower'),f.get('upper')
            for bound in (lower,upper):
                if bound is not None and cls.number(bound) is None: raise ValueError('Range limits must be finite numbers.')
            lower=cls.number(lower);upper=cls.number(upper)
            if lower is not None and upper is not None and lower>upper: raise ValueError('Lower limit exceeds upper limit for '+h)
            if lower is None and upper is None: raise ValueError('Enter at least one range limit.')
            if mode in ('any','all','mean','min','max'):
                clauses.append('cvarray('+col+',?,?,?)=1');values.extend([mode,lower,upper]);continue
            if mode!='range': raise ValueError('Unknown filter mode.')
            number='"__n'+str(metadata['numeric'].index(h))+'"' if h in metadata['numeric'] else 'cvnumber('+col+')'
            clauses.append(number+' IS NOT NULL')
            if lower is not None: clauses.append(number+'>=?');values.append(lower)
            if upper is not None: clauses.append(number+'<=?');values.append(upper)
        return (' WHERE '+' AND '.join(clauses) if clauses else ''),values
    @classmethod
    def query(cls,request):
        db,m=cls.connect(request)
        try:
            where,args=cls.selection(request,m)
            column=request.get('sort','refcode')
            if column not in m['headers']: raise ValueError('Unknown sort property.')
            sort='"__n'+str(m['numeric'].index(column))+'"' if column in m['numeric'] else '"'+column.replace('"','""')+'" COLLATE NOCASE'
            descending=' DESC' if request.get('descending') else ' ASC'
            limit=min(200,max(1,int(request.get('limit',50))));offset=max(0,int(request.get('offset',0)))
            fields=request.get('columns') or [h for h in ['refcode','metal','ox_state','spinmult','geometry','coordination_number','energetic_gap_eV','dipole_magnitude_debye'] if h in m['headers']]
            if any(h not in m['headers'] for h in fields): raise ValueError('Unknown display column.')
            quoted=','.join('"'+h.replace('"','""')+'"' for h in dict.fromkeys(fields))
            rows=[dict(row) for row in db.execute('SELECT __id'+(','+quoted if quoted else '')+' FROM candidates'+where+' ORDER BY '+sort+descending+(' NULLS LAST' if column in m['numeric'] else '')+',__id LIMIT ? OFFSET ?',args+[limit,offset])]
            total=db.execute('SELECT COUNT(*) FROM candidates'+where,args).fetchone()[0]
            return dict(rows=rows,total=total,offset=offset,limit=limit)
        finally: db.close()
    @classmethod
    def detail(cls,request):
        db,m=cls.connect(request)
        try:
            row=db.execute('SELECT * FROM candidates WHERE __id=?',[int(request['id'])]).fetchone()
            if row is None: raise ValueError('This record is not in the catalog.')
            return dict(id=row['__id'],values=cls.raw(db,m,row['__id']))
        finally: db.close()
    @classmethod
    def files(cls,request):
        row=request.get('record') or cls.detail(request)['values'];root=Path(request['root']).expanduser().absolute()
        spin={1:'singlets',2:'doublets',3:'triplets',4:'quartets',5:'quintets',6:'sextets'}.get(cls.number(row.get('spinmult')))
        ref=row['refcode'];raw_xyz=row.get('xyz','');xyz=raw_xyz.strip();files=[];seen=set()
        def add(path):
            if path.is_file() and str(path) not in seen:
                seen.add(str(path));files.append(dict(name=path.name,path=str(path),kind=path.suffix.lower().lstrip('.')))
        inline = raw_xyz if '\n' in xyz and xyz.splitlines()[0].strip().isdigit() else None
        directories=([root/spin/ref] if spin else [])+[root/ref]
        if xyz and inline is None:
            p=Path(xyz).expanduser()
            for candidate in ([p]+[d/p.name for d in directories] if p.is_absolute() else [root/p,Path(request.get('csv') or root).expanduser().parent/p]+[d/p for d in directories]):
                if candidate.is_file(): add(candidate);directories.insert(0,candidate.parent);break
        for directory in dict.fromkeys(directories):
            if directory.is_dir():
                for p in sorted(directory.iterdir(),key=lambda p:p.name.casefold()):
                    if len(files)>=200: break
                    if p.suffix.lower() in ('.xyz','.dat','.out','.log','.mol2'): add(p)
                if files: break
        return dict(files=files, searched=[str(p) for p in directories], **({'inline_xyz':inline} if inline is not None else {}))
    @classmethod
    def export(cls,request):
        db,m=cls.connect(request)
        try:
            where,args=cls.selection(request,m);after=max(0,int(request.get('after',0)))
            where += (' AND ' if where else ' WHERE ')+'__id>?'
            rows=list(db.execute('SELECT * FROM candidates'+where+' ORDER BY __id LIMIT 500',args+[after]))
            out=io.StringIO(newline='');writer=csv.writer(out)
            if after==0: writer.writerow(m['headers'])
            for row in rows:
                raw=cls.raw(db,m,row['__id']);writer.writerow([raw[h] for h in m['headers']])
            return dict(csv=out.getvalue(),after=rows[-1]['__id'] if rows else after,done=len(rows)<500,count=len(rows))
        finally: db.close()
    @classmethod
    def histogram(cls,request):
        db,m=cls.connect(request)
        try:
            h=request['property']
            if h not in m['numeric']: raise ValueError('Histogram needs a scalar property.')
            stat=m['summary'][h];lo,hi=stat['min'],stat['max']
            if lo is None: return dict(bins=[],**stat)
            width=(hi-lo)/24 if hi>lo else 1.0
            col='"__n'+str(m['numeric'].index(h))+'"'
            counts=dict(db.execute('SELECT MIN(23,CAST(('+col+'-?)/? AS INTEGER)),COUNT(*) FROM candidates WHERE '+col+' IS NOT NULL GROUP BY 1',[lo,width]))
            return dict(bins=[dict(lower=lo+i*width,upper=lo+(i+1)*width,count=counts.get(i,0)) for i in range(24 if hi>lo else 1)],**stat)
        finally: db.close()
    @classmethod
    def execute(cls,request):
        methods={'bostmc-start':cls.start,'bostmc-status':cls.status,'bostmc-query':cls.query,'bostmc-detail':cls.detail,'bostmc-files':cls.files,'bostmc-resolve':cls.files,'bostmc-export':cls.export,'bostmc-histogram':cls.histogram}
        return methods[request['action']](request)

if __name__=='__main__' and len(sys.argv)==3:
    try: response=dict(ok=True,result=BosTMCCatalog.execute(json.loads(Path(sys.argv[1]).read_text())))
    except Exception as error: response=dict(ok=False,error=str(error))
    Path(sys.argv[2]).write_text(json.dumps(response,allow_nan=False))
