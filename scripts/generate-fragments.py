import json,math
from pathlib import Path
from rdkit import Chem
from rdkit.Chem import AllChem
# Original curated connection-site SMILES; conformers are generated locally by RDKit.
items={
'Alkyl': {'Methyl':'*C','Ethyl':'*CC','Propyl':'*CCC','Isopropyl':'*C(C)C','Butyl':'*CCCC','tert-Butyl':'*C(C)(C)C','Trifluoromethyl':'*C(F)(F)F','Vinyl':'*C=C','Ethynyl':'*C#C','Cyclopropyl':'*C1CC1','Cyclobutyl':'*C1CCC1','Cyclopentyl':'*C1CCCC1','Cyclohexyl':'*C1CCCCC1','Adamantyl':'*C12CC3CC(CC(C3)C1)C2'},
'Aromatic':{'Phenyl':'*c1ccccc1','Benzyl':'*Cc1ccccc1','Naphthyl':'*c1cccc2ccccc12','2-Pyridyl':'*c1ccccn1','3-Pyridyl':'*c1cccnc1','4-Pyridyl':'*c1ccncc1','Furyl':'*c1ccco1','Thienyl':'*c1cccs1','Pyrrolyl':'*c1ccc[nH]1','Imidazolyl':'*c1ncc[nH]1','Indolyl':'*c1c[nH]c2ccccc12'},
'Oxygen':{'Hydroxyl':'*O','Methoxy':'*OC','Ethoxy':'*OCC','Phenoxy':'*Oc1ccccc1','Acetyl':'*C(=O)C','Formyl':'*C=O','Carboxyl':'*C(=O)O','Methyl ester':'*C(=O)OC','Acetoxy':'*OC(=O)C','Hydroperoxy':'*OO','Carbonate':'*OC(=O)OC'},
'Nitrogen':{'Amino':'*N','Methylamino':'*NC','Dimethylamino':'*N(C)C','Acetamido':'*NC(=O)C','Amide':'*C(=O)N','Nitrile':'*C#N','Nitro':'*[N+](=O)[O-]','Isocyanate':'*N=C=O','Guanidino':'*NC(=N)N','Azido':'*N=[N+]=[N-]'},
'Sulfur and phosphorus':{'Thiol':'*S','Methylthio':'*SC','Sulfonyl methyl':'*S(=O)(=O)C','Sulfonic acid':'*S(=O)(=O)O','Phosphino':'*P','Dimethylphosphino':'*P(C)C','Diphenylphosphino':'*P(c1ccccc1)c1ccccc1','Phosphate':'*OP(=O)(O)O','Boronic acid':'*B(O)O','Trimethylsilyl':'*[Si](C)(C)C'},
'Linkers':{'Methylene linker':'*C*','Ethylene linker':'*CC*','Ether linker':'*COC*','Amine linker':'*CNC*','Para-phenylene linker':'*c1ccc(*)cc1','Meta-phenylene linker':'*c1cccc(*)c1','Acetylene linker':'*C#C*','Carbonyl linker':'*C(=O)*','Disulfide linker':'*SS*'},
'Ligands':{'Ammonia donor':'*N','Aqua donor':'*O','Pyridine N donor':'*[n+]1ccccc1','Acetonitrile donor':'*[N+]#CC','Ethylenediamine donor':'*NCCN','Triphenylphosphine donor':'*P(c1ccccc1)(c1ccccc1)c1ccccc1'}
}
out=[]
for category,entries in items.items():
 for name,smiles in entries.items():
  if category == "Ligands": continue
  base=Chem.MolFromSmiles(smiles)
  dummy_indices={a.GetIdx() for a in base.GetAtoms() if not a.GetAtomicNum()}
  for index in dummy_indices: base.GetAtomWithIdx(index).SetAtomicNum(1)
  mol=Chem.AddHs(base); params=AllChem.ETKDGv3();params.randomSeed=517
  if AllChem.EmbedMolecule(mol,params)!=0: raise RuntimeError(name)
  # Dummies define initial attachment vectors; no force-field energy is implied.
  conf=mol.GetConformer()
  atoms=[{'element':'X' if a.GetIdx() in dummy_indices else a.GetSymbol(),'x':conf.GetAtomPosition(a.GetIdx()).x,'y':conf.GetAtomPosition(a.GetIdx()).y,'z':conf.GetAtomPosition(a.GetIdx()).z} for a in mol.GetAtoms()]
  out.append(dict(name=name,category=category,atoms=atoms))
# Coordination donors retain their actual ligand hydrogens. X is a separate
# coordination site, not a covalent substituent removed from NH3/H2O/PR3.
for name,smiles,donor in [('Ammonia donor','N','N'),('Aqua donor','O','O'),('Carbon monoxide donor','[C-]#[O+]','C'),('Pyridine N donor','c1ccncc1','N'),('Acetonitrile donor','CC#N','N'),('Ethylenediamine donor','NCCN','N'),('Triphenylphosphine donor','P(c1ccccc1)(c1ccccc1)c1ccccc1','P')]:
 mol=Chem.AddHs(Chem.MolFromSmiles(smiles));params=AllChem.ETKDGv3();params.randomSeed=517
 if AllChem.EmbedMolecule(mol,params)!=0: raise RuntimeError(name)
 conf=mol.GetConformer();anchor=next(a.GetIdx() for a in mol.GetAtoms() if a.GetSymbol()==donor);origin=conf.GetAtomPosition(anchor)
 atoms=[dict(element=a.GetSymbol(),x=conf.GetAtomPosition(a.GetIdx()).x,y=conf.GetAtomPosition(a.GetIdx()).y,z=conf.GetAtomPosition(a.GetIdx()).z) for a in mol.GetAtoms()]
 best=None;score=-1
 for k in range(96):
  z=1-2*(k+.5)/96;phi=k*2.39996323;r=math.sqrt(1-z*z)
  point=[origin.x+1.8*r*math.cos(phi),origin.y+1.8*r*math.sin(phi),origin.z+1.8*z]
  clearance=min(math.dist(point,[a[t] for t in ['x','y','z']]) for i,a in enumerate(atoms) if i!=anchor)
  if clearance>score:score=clearance;best=point
 atoms.append(dict(element='X',x=best[0],y=best[1],z=best[2]))
 out.append(dict(name=name,category='Ligands',atoms=atoms))
geometries={'Linear':[(1,0,0),(-1,0,0)],'Trigonal planar':[(math.cos(i*2*math.pi/3),math.sin(i*2*math.pi/3),0) for i in range(3)],'Tetrahedral':[(a/math.sqrt(3),b/math.sqrt(3),c/math.sqrt(3)) for a,b,c in [(1,1,1),(1,-1,-1),(-1,1,-1),(-1,-1,1)]],'Square planar':[(1,0,0),(-1,0,0),(0,1,0),(0,-1,0)],'Trigonal bipyramidal':[(0,0,1),(0,0,-1)]+[(math.cos(i*2*math.pi/3),math.sin(i*2*math.pi/3),0) for i in range(3)],'Octahedral':[(1,0,0),(-1,0,0),(0,1,0),(0,-1,0),(0,0,1),(0,0,-1)]}
for metal in ['Li','Mg','Al','Ca','Sc','Ti','V','Cr','Mn','Fe','Co','Ni','Cu','Zn','Zr','Mo','Ru','Rh','Pd','Ag','Cd','W','Re','Os','Ir','Pt','Au','Hg','La','Ce','U']:
 for geometry,vectors in geometries.items():
  atoms=[dict(element=metal,x=0,y=0,z=0)]+[dict(element='X',x=x*2,y=y*2,z=z*2) for x,y,z in vectors]
  out.append(dict(name=metal+' · '+geometry,category='Metal centers',atoms=atoms))
path=Path(__file__).resolve().parents[1] / 'Sources/ChemCraftMacApp/Resources/Fragments.json';path.write_text(json.dumps(out,indent=2)+'\n');print(len(out),'fragments')
