"""Local chemistry subprocess. No network required for RDKit UFF cleanup."""
import argparse,json,sys
from pathlib import Path

def optimize(request):
    from rdkit import Chem
    from rdkit.Chem import rdDetermineBonds,AllChem
    atoms=request['atoms']
    if not atoms or any(a['element'] in ('X','Du') for a in atoms):
        raise ValueError('Replace or remove all X dummy attachment sites before optimization.')
    xyz=str(len(atoms))+'\ninitial geometry\n'+'\n'.join(f"{a['element']} {a['x']} {a['y']} {a['z']}" for a in atoms)+'\n'
    mol=Chem.MolFromXYZBlock(xyz)
    if mol is None: raise ValueError('Invalid XYZ geometry')
    rdDetermineBonds.DetermineBonds(mol,charge=request.get('charge',0),allowChargedFragments=True)
    Chem.SanitizeMol(mol)
    if not AllChem.UFFHasAllMoleculeParams(mol):
        raise ValueError('UFF has no parameters for one or more atom environments. Use a suitable MLIP or quantum-chemistry engine for this structure.')
    ff=AllChem.UFFGetMoleculeForceField(mol,ignoreInterfragInteractions=False)
    for index in request.get('fixed',[]): ff.AddFixedPoint(index)
    ff.Initialize(); initial=ff.CalcEnergy()
    status=ff.Minimize(maxIts=request.get('steps',1000),forceTol=1e-4,energyTol=1e-7)
    final=ff.CalcEnergy()
    if final > initial+1e-6: raise ValueError('UFF energy increased; the result was not applied.')
    conf=mol.GetConformer()
    result=[]
    for i,atom in enumerate(atoms):
        point=conf.GetAtomPosition(i)
        result.append(dict(element=atom['element'],x=point.x,y=point.y,z=point.z))
    return dict(atoms=result,initialEnergy=initial,finalEnergy=final,converged=status==0,unit='kcal/mol')

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('request');parser.add_argument('result');args=parser.parse_args()
    try: Path(args.result).write_text(json.dumps(optimize(json.loads(Path(args.request).read_text())),allow_nan=False))
    except Exception as error: print(str(error),file=sys.stderr);sys.exit(1)
