"""Local, nonperiodic cleanup: UFF or GFN2-xTB; never invent metal valences."""
import argparse
import json
import math
import sys
from pathlib import Path


def is_metal(z):
    return any(lo <= z <= hi for lo, hi in ((3, 4), (11, 13), (19, 31),
               (37, 50), (55, 84), (87, 116)))


def validate(request):
    from ase.data import atomic_numbers
    atoms = request['atoms']
    if not atoms or any(a['element'] in ('X', 'Du') for a in atoms):
        raise ValueError('Replace or remove all X dummy attachment sites before cleanup.')
    if any(a['element'] not in atomic_numbers or atomic_numbers[a['element']] < 1 for a in atoms):
        raise ValueError('Cleanup requires recognized chemical elements.')
    positions = [[a[k] for k in ('x', 'y', 'z')] for a in atoms]
    if any(not isinstance(x, (int, float)) or not math.isfinite(x) for p in positions for x in p):
        raise ValueError('Cleanup requires finite coordinates in angstrom.')
    if any(math.dist(a, b) < 0.1 for i, a in enumerate(positions) for b in positions[i + 1:]):
        raise ValueError('Atoms overlap (less than 0.1 angstrom apart); move them apart before cleanup.')
    numbers = [atomic_numbers[a['element']] for a in atoms]
    charge, multiplicity = request.get('charge', 0), request.get('multiplicity', 1)
    if type(charge) is not int or type(multiplicity) is not int or multiplicity < 1:
        raise ValueError('Charge must be an integer and multiplicity a positive integer.')
    electrons = sum(numbers) - charge
    if electrons < 1 or multiplicity - 1 > electrons or (electrons - multiplicity + 1) % 2:
        raise ValueError('Charge and multiplicity are inconsistent with the electron count. Review both before cleanup.')
    fixed = request.get('fixed', [])
    if any(type(i) is not int or not 0 <= i < len(atoms) for i in fixed):
        raise ValueError('Invalid fixed atom index.')
    if len(set(fixed)) == len(atoms):
        raise ValueError('All atoms are fixed; unselect an atom or disable Keep selected atoms fixed.')
    steps = request.get('steps', 1000)
    if type(steps) is not int or not 1 <= steps <= 1000:
        raise ValueError('Cleanup steps must be between 1 and 1000.')
    return numbers, positions


def uff(request):
    from rdkit import Chem
    from rdkit.Chem import rdDetermineBonds, AllChem
    atoms = request['atoms']
    xyz = str(len(atoms)) + '\ninitial geometry\n' + '\n'.join(
        f"{a['element']} {a['x']} {a['y']} {a['z']}" for a in atoms) + '\n'
    mol = Chem.MolFromXYZBlock(xyz)
    if mol is None:
        raise ValueError('Invalid XYZ geometry')
    rdDetermineBonds.DetermineBonds(mol, charge=request.get('charge', 0), allowChargedFragments=True)
    Chem.SanitizeMol(mol)
    if not AllChem.UFFHasAllMoleculeParams(mol):
        raise ValueError('UFF parameters unavailable for this atom environment.')
    ff = AllChem.UFFGetMoleculeForceField(mol, ignoreInterfragInteractions=False)
    for index in request.get('fixed', []):
        ff.AddFixedPoint(index)
    ff.Initialize()
    initial = ff.CalcEnergy()
    status = ff.Minimize(maxIts=request.get('steps', 1000), forceTol=1e-4, energyTol=1e-7)
    conf = mol.GetConformer()
    positions = [list(conf.GetAtomPosition(i)) for i in range(len(atoms))]
    return dict(positions=positions, initialEnergy=initial, finalEnergy=ff.CalcEnergy(),
                converged=status == 0, method='UFF', unit='kcal/mol')


def gfn2(request, numbers, positions):
    if max(numbers) > 86:
        raise ValueError('GFN2-xTB supports elements H–Rn (Z ≤ 86). Use a configured QM workflow for heavier elements.')
    try:
        from tblite.ase import TBLite
    except ImportError as error:
        raise ValueError('GFN2-xTB cleanup is not installed. Run bash scripts/setup-chemistry.sh, then retry.') from error
    from ase import Atoms
    from ase.constraints import FixAtoms
    from ase.optimize import BFGS
    atoms = Atoms(numbers=numbers, positions=positions)
    atoms.set_constraint(FixAtoms(indices=request.get('fixed', [])))
    atoms.calc = TBLite(method='GFN2-xTB', charge=request.get('charge', 0),
                       multiplicity=request.get('multiplicity', 1), verbosity=0)
    initial = atoms.get_potential_energy()
    optimizer = BFGS(atoms, logfile=None, maxstep=0.1)
    converged = optimizer.run(fmax=0.05, steps=request.get('steps', 1000))
    return dict(positions=atoms.positions.tolist(), initialEnergy=initial,
                finalEnergy=atoms.get_potential_energy(), converged=bool(converged),
                maxForce=float(max(sum(f*f) ** 0.5 for f in atoms.get_forces())),
                method='GFN2-xTB', unit='eV')


def optimize(request):
    numbers, positions = validate(request)
    method = request.get('method', 'auto')
    if method not in ('auto', 'uff', 'gfn2'):
        raise ValueError('Unknown cleanup method.')
    if method == 'uff' and any(is_metal(z) for z in numbers):
        raise ValueError('Use Automatic or GFN2-xTB for metal-containing structures; UFF metal valences are unreliable.')
    warning = ''
    if method == 'gfn2' or (method == 'auto' and any(is_metal(z) for z in numbers)):
        result = gfn2(request, numbers, positions)
    elif method == 'auto':
        try:
            result = uff(request)
        except (ValueError, RuntimeError) as error:
            warning = 'UFF unavailable; used GFN2-xTB. ' + str(error)
            result = gfn2(request, numbers, positions)
    else:
        result = uff(request)
    coords = result.pop('positions')
    if not result['converged']:
        raise ValueError(result['method'] + ' did not converge within the iteration limit; geometry unchanged. Review the starting geometry, charge and multiplicity or use a QM workflow.')
    if len(coords) != len(positions) or any(not math.isfinite(x) for p in coords for x in p):
        raise ValueError('Optimizer returned invalid coordinates; geometry unchanged.')
    if not all(math.isfinite(result[k]) for k in ('initialEnergy', 'finalEnergy')) or result['finalEnergy'] > result['initialEnergy'] + 1e-6:
        raise ValueError('Optimizer energy is invalid or increased; geometry unchanged.')
    for i in request.get('fixed', []):
        if math.dist(coords[i], positions[i]) > 1e-8:
            raise ValueError('Optimizer moved a fixed atom; geometry unchanged.')
        coords[i] = positions[i]
    result['atoms'] = [dict(element=a['element'], **dict(zip(('x', 'y', 'z'), p)))
                       for a, p in zip(request['atoms'], coords)]
    result['warning'] = warning
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('request')
    parser.add_argument('result')
    args = parser.parse_args()
    try:
        Path(args.result).write_text(json.dumps(optimize(json.loads(Path(args.request).read_text())), allow_nan=False))
    except Exception as error:
        print('Cleanup failed; geometry unchanged. ' + str(error), file=sys.stderr)
        sys.exit(1)
