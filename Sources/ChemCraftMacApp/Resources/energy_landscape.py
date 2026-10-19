#!/usr/bin/env python3
"""ChemViewer publication energy profiles. Input contains explicit Hartree values.

No interpolation or smoothing: lines follow supplied geometry order and break
at missing energies. SVG/PDF remain vector; PNG is 600 dpi by default.
"""
import argparse
import csv
import json
import math
import os
from pathlib import Path

os.environ.setdefault('MPLBACKEND', 'Agg')
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.patches import Circle
from matplotlib.ticker import MaxNLocator
import numpy as np

FACTORS = {'Eh': 1.0, 'eV': 27.211386245981,
           'kJ/mol': 4.3597447222060e-18 * 6.02214076e23 / 1000}
FACTORS['kcal/mol'] = FACTORS['kJ/mol'] / 4.184
LABELS = {'Eh': r'$E_\mathrm{h}$', 'eV': 'eV', 'kJ/mol': r'kJ mol$^{-1}$', 'kcal/mol': r'kcal mol$^{-1}$'}


def prepare(data):
    points = data['points']
    if len(points) < 2:
        raise ValueError('At least two geometries are needed for an energy profile.')
    unit = data.get('unit', 'kJ/mol')
    if unit not in FACTORS:
        raise ValueError('Unsupported energy unit')
    energies = [p.get('energy_hartree') for p in points]
    finite = [e for e in energies if e is not None and math.isfinite(e)]
    if len(finite) < 2:
        raise ValueError('At least two geometries need known energy units and energies.')
    reference = data.get('reference', 'minimum')
    if reference not in ('minimum', 'first', 'absolute'):
        raise ValueError('Unknown energy reference')
    zero = min(finite) if reference == 'minimum' else finite[0] if reference == 'first' else 0.0
    x = [p['x'] for p in points]
    if not all(isinstance(value, (float, int)) and math.isfinite(value) for value in x):
        raise ValueError('Reaction coordinates must be finite')
    relative = [p.get('relative_energy_kcal') for p in points]
    if any(e is not None for e in relative):
        if not all(isinstance(e, (float, int)) and math.isfinite(e) for e in relative):
            raise ValueError('NEB relative energies must be complete and finite')
    if all(e is not None for e in relative) and reference != 'absolute':
        baseline = min(relative) if reference == 'minimum' else relative[0]
        factor = FACTORS[unit] / FACTORS['kcal/mol']
        y = [(e - baseline) * factor for e in relative]
    else:
        y = [(e - zero) * FACTORS[unit] if e is not None and math.isfinite(e) else math.nan for e in energies]
    return x, y, zero, unit


def structure(ax, atoms):
    ax.set_aspect('equal'); ax.axis('off')
    if not atoms:
        return
    xyz = np.array([[a['x'], a['y'], a['z']] for a in atoms], dtype=float)
    xyz -= xyz.mean(axis=0)
    if len(atoms) > 1:
        _, _, axes = np.linalg.svd(xyz, full_matrices=True)
        xy = xyz @ axes[:2].T
    else:
        xy = np.zeros((1, 2))
    # Graphical distance connectivity; no bond order inferred.
    radii = {'H': .31, 'B': .84, 'C': .76, 'N': .71, 'O': .66, 'F': .57, 'Si': 1.11,
             'P': 1.07, 'S': 1.05, 'Cl': 1.02, 'Br': 1.20, 'I': 1.39}
    colors = {'H': '#FAFAFA', 'C': '#D9D9D9', 'N': '#7F7FBF', 'O': '#FF0D0D',
              'F': '#36A94F', 'Cl': '#36A94F', 'S': '#E6BE27', 'P': '#ED8D25'}
    for i in range(len(atoms)):
        for j in range(i + 1, len(atoms)):
            cutoff = 1.22 * (radii.get(atoms[i]['element'], .9) + radii.get(atoms[j]['element'], .9))
            if .1 < np.linalg.norm(xyz[i] - xyz[j]) <= cutoff:
                ax.plot(xy[[i, j], 0], xy[[i, j], 1], color='#333333', lw=1.6, zorder=1)
    for p, atom in zip(xy, atoms):
        radius = .13 if atom['element'] == 'H' else .19
        ax.add_patch(Circle(p, radius, facecolor=colors.get(atom['element'], '#68A4B2'), edgecolor='#333333', linewidth=.65, zorder=2))
    ax.set_xlim(xy[:, 0].min() - .45, xy[:, 0].max() + .45)
    ax.set_ylim(xy[:, 1].min() - .45, xy[:, 1].max() + .45)


def draw_curve(ax, x, y, data):
    valid = [i for i, value in enumerate(y) if math.isfinite(value)]
    diagram = data.get('plot_style') == 'diagram'
    color = '#00A982' if diagram else '#0072B2'
    if diagram:
        for i in valid:
            ax.plot([x[i] - .28, x[i] + .28], [y[i], y[i]], color=color, lw=2.1, solid_capstyle='round', zorder=3)
        if data.get('connect', True):
            for i in range(len(x) - 1):
                if math.isfinite(y[i]) and math.isfinite(y[i + 1]):
                    ax.plot([x[i] + .28, x[i + 1] - .28], [y[i], y[i + 1]], color=color, lw=1.3, linestyle=(0, (2, 2)), zorder=2)
        ax.set_xticks(x, [p.get('label') or f"Geometry {p['geometry']}" for p in data['points']], fontsize=8, rotation=25 if len(x) > 5 else 0)
        if data.get('annotate', True):
            for i in valid:
                number = f'{y[i]:+.6f}' if data.get('unit') == 'Eh' else f'{y[i]:+.2f}'
                ax.annotate(number, (x[i], y[i]), xytext=(0, 8), textcoords='offset points', ha='center', fontsize=9, weight='semibold')
    else:
        if data.get('connect', True): ax.plot(x, y, lw=1.4, color=color, zorder=2)
        if data.get('annotate', True) and len(valid) <= 30:
            for i in valid:
                text = data['points'][i].get('label') or str(data['points'][i]['geometry'])
                ax.annotate(text, (x[i], y[i]), xytext=(0, 7), textcoords='offset points', ha='center', fontsize=7, color='#444444')
    if data.get('markers', True):
        dots = ax.scatter([x[i] for i in valid], [y[i] for i in valid], s=28, color=color, edgecolors='white', linewidths=.65, zorder=4)
        dots.set_gid('energy-markers')
        if not diagram:
            minimum = min(valid, key=lambda i: y[i])
            dot = ax.scatter([x[minimum]], [y[minimum]], s=40, facecolor='#D55E00', edgecolor='white', linewidth=.7, zorder=5)
            dot.set_gid('minimum-marker')


def barrier_summary(data):
    index = data.get('ts_index')
    if index is None: return None
    if not isinstance(index, int) or not 0 <= index < len(data['points']): raise ValueError('Invalid TS index')
    p = data['points']
    factor = FACTORS[data.get('unit', 'kJ/mol')]
    if all(point.get('relative_energy_kcal') is not None for point in p):
        energies = [point['relative_energy_kcal'] for point in p]
        factor /= FACTORS['kcal/mol']
    else: energies = [point['energy_hartree'] for point in p]
    return {'forward': (energies[index] - energies[0]) * factor,
            'reverse': (energies[index] - energies[-1]) * factor,
            'reaction': (energies[-1] - energies[0]) * factor,
            'unit': data.get('unit', 'kJ/mol'), 'basis': 'electronic energy; explicit refined TS'}


def render(data, output):
    x, y, zero, unit = prepare(data)
    output = Path(output)
    output.mkdir(parents=True, exist_ok=True)
    plt.rcParams.update({'font.family': 'DejaVu Sans', 'font.size': 9, 'axes.labelsize': 10,
                         'axes.linewidth': .8, 'xtick.direction': 'out', 'ytick.direction': 'out',
                         'xtick.major.size': 3, 'ytick.major.size': 3, 'pdf.fonttype': 42,
                         'ps.fonttype': 42, 'svg.fonttype': 'none', 'savefig.facecolor': 'white'})
    valid = [i for i, value in enumerate(y) if math.isfinite(value)]
    thumbnails = data.get('structures', True)
    fig = plt.figure(figsize=(float(data.get('width_inches', 6.8)), 5.2 if thumbnails else 3.8), layout='constrained')
    diagram = data.get('plot_style') == 'diagram'
    if thumbnails and not diagram:
        grid = fig.add_gridspec(2, 3, height_ratios=[3.3, 1.1])
        ax = fig.add_subplot(grid[0, :])
    else:
        ax = fig.add_subplot()
    ax.spines[['top', 'right']].set_visible(False)
    ax.grid(axis='y', color='#E5E5E5', linewidth=.5, zorder=0)
    draw_curve(ax, x, y, data)
    barriers = barrier_summary(data)
    if barriers:
        fig.suptitle(f"Forward ΔE‡ {barriers['forward']:.2f}   |   Reverse ΔE‡ {barriers['reverse']:.2f}   |   ΔE {barriers['reaction']:+.2f} {unit}", fontsize=8, color='#234C59')
    ax.set_xlabel(data.get('x_label', 'Geometry index'))
    ax.set_ylabel(('Energy' if data.get('reference') == 'absolute' else r'$\Delta E$') + ' (' + LABELS[unit] + ')')
    if data.get('x_kind', 'index') == 'index' and data.get('plot_style') != 'diagram':
        ax.xaxis.set_major_locator(MaxNLocator(integer=True, nbins=9))
    ax.ticklabel_format(axis='y', style='plain', useOffset=False)
    ax.margins(x=.18 if diagram else .08, y=.17)
    if thumbnails and diagram:
        span = max(max(y[i] for i in valid) - min(y[i] for i in valid), 1.0)
        ax.set_ylim(min(y[i] for i in valid) - .15 * span, max(y[i] for i in valid) + .45 * span)
    ax.set_title(data.get('title', 'Energy profile'), loc='left', fontsize=11, pad=12)
    if thumbnails:
        middle = data.get('ts_index') if data.get('ts_index') is not None else max(valid, key=lambda i: y[i])
        chosen = list(dict.fromkeys([valid[0], middle, valid[-1]]))
        for column, i in enumerate(chosen):
            if diagram:
                thumb = ax.inset_axes([x[i] - .34, y[i] + .055 * span, .68, .30 * span], transform=ax.transData)
                thumb.set_facecolor('none')
            else:
                thumb = fig.add_subplot(grid[1, column])
            atoms = data['points'][i].get('atoms', [])
            structure(thumb, atoms)
            if not atoms: thumb.text(.5, .5, 'Matching structure unavailable', transform=thumb.transAxes, ha='center', va='center', fontsize=7, color='#777777')
            label = data['points'][i].get('label') or f"Geometry {data['points'][i]['geometry']}"
            if not diagram: thumb.set_title(f"{label}  |  {y[i]:.2f} {unit}", fontsize=7, pad=3)
    for extension in ('pdf', 'svg', 'png'):
        fig.savefig(output / ('energy-profile.' + extension), dpi=int(data.get('dpi', 600)))
    plt.close(fig)
    with (output / 'energy-profile.csv').open('w', newline='') as stream:
        writer = csv.writer(stream)
        writer.writerow(['geometry', 'reaction_coordinate', 'energy_hartree', 'plotted_energy', 'plotted_unit', 'energy_kind', 'comment', 'label', 'relative_energy_kcal', 'source_line', 'structure_source'])
        for i, point in enumerate(data['points']):
            writer.writerow([point['geometry'], x[i], point.get('energy_hartree', ''), y[i] if math.isfinite(y[i]) else '', unit, point.get('energy_kind', ''), point.get('comment', ''), point.get('label', ''), point.get('relative_energy_kcal', ''), point.get('source_line', ''), point.get('structure_source', '')])
    (output / 'plot-input.json').write_text(json.dumps(data, indent=2, allow_nan=False))
    (output / 'plot-metadata.json').write_text(json.dumps({'matplotlib': matplotlib.__version__, 'reference_hartree': zero,
        'geometry_count': len(x), 'energy_count': len(valid), 'unit': unit, 'factors_per_hartree': FACTORS,
        'coordinate_order': 'summary path order' if data.get('x_kind') == 'neb' else 'input file order', 'missing_energies': 'gaps', 'interpolation': 'none',
        'markers': data.get('markers', True), 'plot_style': data.get('plot_style', 'profile'), 'data_source': data.get('data_source', 'optimization'),
        'relative_energy_basis': 'printed ORCA kcal/mol column' if any(p.get('relative_energy_kcal') is not None for p in data['points']) else 'Hartree differences',
        'barriers': barriers, 'status': data.get('status')}, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('input', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    render(json.loads(args.input.read_text()), args.output)
