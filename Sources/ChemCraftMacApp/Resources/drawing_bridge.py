"""Local explicit-graph/SMILES to 2D depiction and 3D conformer generation."""
import argparse
import json
import math
import sys
from pathlib import Path


def molecule_from_graph(graph):
    from rdkit import Chem
    atoms, bonds = graph['atoms'], graph['bonds']
    if not 0 < len(atoms) <= 500 or len(bonds) > 1000:
        raise ValueError('Draw 1–500 atoms first.')
    mol = Chem.RWMol()
    indices = {}
    conf = Chem.Conformer(len(atoms))
    conf.Set3D(False)
    for node in atoms:
        identity = node['id']
        if identity in indices or node['element'] in ('X', 'Du', '*'):
            raise ValueError('Use unique atom IDs and real chemical elements.')
        atom = Chem.Atom(node['element'])
        charge = node.get('charge', 0)
        tag = node.get('chiralTag', 0)
        if not isinstance(charge, int) or abs(charge) > 8 or tag not in (0, 1, 2):
            raise ValueError('Invalid formal charge or chirality.')
        atom.SetFormalCharge(charge)
        for name in ('explicitHs', 'radicalElectrons'):
            value = node.get(name)
            if value is not None and (not isinstance(value, int) or not 0 <= value <= 8):
                raise ValueError('Invalid hydrogen or radical count.')
        if node.get('explicitHs') is not None:
            atom.SetNumExplicitHs(node['explicitHs'])
        if node.get('noImplicit') is not None:
            atom.SetNoImplicit(bool(node['noImplicit']))
        if node.get('radicalElectrons') is not None:
            atom.SetNumRadicalElectrons(node['radicalElectrons'])
        atom.SetChiralTag(Chem.ChiralType.values[tag])
        index = mol.AddAtom(atom)
        indices[identity] = index
        x, y = float(node['x']), float(node['y'])
        if not all(math.isfinite(v) and abs(v) < 1e6 for v in (x, y)):
            raise ValueError('Drawing coordinates must be finite.')
        conf.SetAtomPosition(index, (x / 32, y / 32, 0))
    for edge in bonds:
        a, b = indices[edge['a']], indices[edge['b']]
        order, stereo = edge['order'], edge.get('stereo', 'none')
        if a == b or mol.GetBondBetweenAtoms(a, b) or order not in (1, 2, 3) or stereo not in ('none', 'up', 'down') or (stereo != 'none' and order != 1):
            raise ValueError('Invalid or duplicate drawing bond.')
        mol.AddBond(a, b, {1: Chem.BondType.SINGLE, 2: Chem.BondType.DOUBLE, 3: Chem.BondType.TRIPLE}[order])
        if stereo != 'none':
            mol.GetBondBetweenAtoms(a, b).SetBondDir(Chem.BondDir.BEGINWEDGE if stereo == 'up' else Chem.BondDir.BEGINDASH)
    for edge in bonds:
        bond = mol.GetBondBetweenAtoms(indices[edge['a']], indices[edge['b']])
        stereo_atoms = edge.get('stereoAtoms')
        stereo_tag = edge.get('bondStereo') or 0
        if stereo_atoms is not None:
            if len(stereo_atoms) != 2 or any(i not in indices for i in stereo_atoms):
                raise ValueError('Invalid double-bond stereo atoms.')
            bond.SetStereoAtoms(indices[stereo_atoms[0]], indices[stereo_atoms[1]])
        if stereo_tag:
            if stereo_tag not in (1, 2, 3, 4, 5):
                raise ValueError('Invalid double-bond stereochemistry.')
            bond.SetStereo(Chem.BondStereo.values[stereo_tag])
    mol = mol.GetMol()
    mol.AddConformer(conf)
    Chem.SanitizeMol(mol)
    Chem.SetDoubleBondNeighborDirections(mol)
    if any(e.get('stereo', 'none') != 'none' for e in bonds):
        Chem.AssignChiralTypesFromBondDirs(mol)
    Chem.AssignStereochemistry(mol, cleanIt=True, force=True)
    return mol


def depict(mol):
    from rdkit import Chem
    from rdkit.Chem import rdDepictor
    mol = Chem.Mol(mol)
    Chem.Kekulize(mol, clearAromaticFlags=True)
    rdDepictor.Compute2DCoords(mol)
    Chem.WedgeMolBonds(mol, mol.GetConformer())
    conf = mol.GetConformer()
    atoms = [dict(id=a.GetIdx(), element=a.GetSymbol(), x=conf.GetAtomPosition(a.GetIdx()).x * 32,
                  y=conf.GetAtomPosition(a.GetIdx()).y * 32, charge=a.GetFormalCharge(), chiralTag=int(a.GetChiralTag()),
                  explicitHs=a.GetNumExplicitHs(), noImplicit=a.GetNoImplicit(), radicalElectrons=a.GetNumRadicalElectrons()) for a in mol.GetAtoms()]
    bonds = [dict(a=b.GetBeginAtomIdx(), b=b.GetEndAtomIdx(), order=int(b.GetBondTypeAsDouble()),
                  bondStereo=int(b.GetStereo()), stereoAtoms=list(b.GetStereoAtoms()) or None,
                  stereo='up' if b.GetBondDir() == Chem.BondDir.BEGINWEDGE else 'down' if b.GetBondDir() == Chem.BondDir.BEGINDASH else 'none') for b in mol.GetBonds()]
    return dict(atoms=atoms, bonds=bonds)


def run(request):
    from rdkit import Chem
    from rdkit.Chem import AllChem, rdMolDescriptors
    if 'smiles' in request:
        smiles = request['smiles'].strip()
        if not smiles or len(smiles) > 20000:
            raise ValueError('Paste a valid SMILES string (maximum 20,000 characters).')
        mol = Chem.MolFromSmiles(smiles)
        if mol is None or not 0 < mol.GetNumAtoms() <= 500:
            raise ValueError('SMILES is invalid or exceeds 500 atoms.')
    else:
        mol = molecule_from_graph(request['graph'])
    if any(a.GetIsotope() for a in mol.GetAtoms()):
        raise ValueError('Isotope labels are not yet supported by the ChemViewer atom model; use a structure without isotope labels.')
    smiles = Chem.MolToSmiles(mol, isomericSmiles=True)
    graph = depict(mol)
    if request.get('operation') == 'depict':
        return dict(graph=graph, smiles=smiles)
    mol = Chem.AddHs(mol)
    mol.RemoveAllConformers()
    params = AllChem.ETKDGv3()
    params.randomSeed = 20261020
    params.maxIterations = 500
    params.numThreads = 1
    if AllChem.EmbedMolecule(mol, params) != 0:
        params.useRandomCoords = True
        if AllChem.EmbedMolecule(mol, params) != 0:
            raise ValueError('3D embedding failed. Check connectivity, stereochemistry and ring strain.')
    optimized = AllChem.UFFHasAllMoleculeParams(mol)
    converged = False
    if optimized:
        converged = AllChem.UFFOptimizeMolecule(mol, maxIters=1000) == 0
    # Disconnected components are laid out separately instead of overlapping.
    conf = mol.GetConformer()
    fragments = Chem.GetMolFrags(mol)
    if len(fragments) > 1:
        cursor = 0.0
        for fragment in fragments:
            points = [conf.GetAtomPosition(i) for i in fragment]
            low, high = min(p.x for p in points), max(p.x for p in points)
            for index in fragment:
                p = conf.GetAtomPosition(index)
                conf.SetAtomPosition(index, (p.x - low + cursor, p.y, p.z))
            cursor += high - low + 3.0
    atoms = []
    for atom in mol.GetAtoms():
        p = conf.GetAtomPosition(atom.GetIdx())
        if not all(math.isfinite(v) for v in (p.x, p.y, p.z)):
            raise ValueError('Embedding returned nonfinite coordinates.')
        atoms.append(dict(element=atom.GetSymbol(), x=p.x, y=p.y, z=p.z))
    return dict(graph=graph, smiles=smiles, atoms=atoms, formula=rdMolDescriptors.CalcMolFormula(mol),
                charge=sum(a.GetFormalCharge() for a in mol.GetAtoms()), optimized=optimized, converged=converged,
                radicalElectrons=sum(a.GetNumRadicalElectrons() for a in mol.GetAtoms()), molBlock=Chem.MolToMolBlock(mol))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('request')
    parser.add_argument('result')
    args = parser.parse_args()
    try:
        result = run(json.loads(Path(args.request).read_text()))
        Path(args.result).write_text(json.dumps(result, allow_nan=False))
    except Exception as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
