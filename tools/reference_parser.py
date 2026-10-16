"""Independent, standard-library-only oracle for parser regression checks.

This is deliberately separate from the Swift implementation. It validates facts
extracted from representative output files without serving as application code.
"""

from __future__ import annotations

from dataclasses import dataclass, field
import re
from pathlib import Path


@dataclass(frozen=True)
class Atom:
    element: str
    x: float
    y: float
    z: float


@dataclass
class Mode:
    index: int
    frequency_cm1: float
    ir_intensity: float | None = None
    displacements: list[tuple[float, float, float]] = field(default_factory=list)


@dataclass
class OrcaResult:
    geometries: list[list[Atom]]
    energies_hartree: list[float]
    geometry_energies_hartree: list[float | None]
    modes: list[Mode]


_FREQUENCY = re.compile(r"^\s*(\d+):\s*([-+]?\d+(?:\.\d+)?)\s+cm\*\*-1")
_IR = re.compile(r"^\s*(\d+):\s*([-+]?\d+(?:\.\d+)?)\s+([-+]?\d+(?:\.\d+)?(?:[Ee][-+]?\d+)?)")
_ENERGY = re.compile(r"FINAL SINGLE POINT ENERGY\s+([-+]?\d+(?:\.\d+)?(?:[Ee][-+]?\d+)?)")


def parse_orca(text: str) -> OrcaResult:
    lines = text.splitlines()
    geometries: list[list[Atom]] = []
    geometry_line_indices: list[int] = []
    cursor = 0
    while cursor < len(lines):
        if "CARTESIAN COORDINATES (ANGSTROEM)" not in lines[cursor]:
            cursor += 1
            continue
        header_line_index = cursor
        cursor += 1
        while cursor < len(lines) and (
            not lines[cursor].strip() or set(lines[cursor].strip()) == {"-"}
        ):
            cursor += 1
        atoms: list[Atom] = []
        while cursor < len(lines):
            fields = lines[cursor].split()
            if len(fields) < 4:
                break
            try:
                atoms.append(Atom(fields[0], float(fields[1]), float(fields[2]), float(fields[3])))
            except ValueError:
                break
            cursor += 1
        if atoms:
            geometries.append(atoms)
            geometry_line_indices.append(header_line_index)

    energy_records = [
        (line_index, float(match.group(1)))
        for line_index, line in enumerate(lines)
        if (match := _ENERGY.search(line))
    ]
    energies = [value for _, value in energy_records]
    geometry_energies: list[float | None] = [None] * len(geometries)
    for energy_line_index, energy in energy_records:
        preceding = [
            index
            for index, geometry_line_index in enumerate(geometry_line_indices)
            if geometry_line_index < energy_line_index
        ]
        if preceding:
            geometry_energies[preceding[-1]] = energy

    frequency_by_index: dict[int, Mode] = {}
    in_frequencies = False
    frequency_starts = [
        index for index, line in enumerate(lines) if "VIBRATIONAL FREQUENCIES" in line
    ]
    frequency_start = frequency_starts[-1] if frequency_starts else len(lines)
    for line in lines[frequency_start + 1 :]:
        if "VIBRATIONAL FREQUENCIES" in line:
            in_frequencies = True
            continue
        if not in_frequencies:
            in_frequencies = True
        if in_frequencies and "NORMAL MODES" in line:
            break
        if in_frequencies and (match := _FREQUENCY.match(line)):
            index = int(match.group(1))
            frequency_by_index[index] = Mode(index, float(match.group(2)))

    coordinate_count = 3 * len(geometries[-1]) if geometries else 0
    vectors: dict[int, list[float]] = {}
    try:
        start = max(i for i, line in enumerate(lines) if line.strip() == "NORMAL MODES") + 1
    except ValueError:
        start = len(lines)
    headers: list[int] = []
    for line in lines[start:]:
        if line.strip() in {"IR SPECTRUM", "RAMAN SPECTRUM"}:
            break
        tokens = line.split()
        if tokens and all(token.isdigit() for token in tokens):
            headers = [int(token) for token in tokens]
            for mode in headers:
                vectors.setdefault(mode, [0.0] * coordinate_count)
            continue
        if not headers or len(tokens) != len(headers) + 1 or not tokens[0].isdigit():
            continue
        coordinate = int(tokens[0])
        if coordinate >= coordinate_count:
            continue
        try:
            for offset, mode in enumerate(headers):
                vectors[mode][coordinate] = float(tokens[offset + 1])
        except ValueError:
            continue

    ir_starts = [index for index, line in enumerate(lines) if line.strip() == "IR SPECTRUM"]
    in_ir = bool(ir_starts)
    for line in lines[(ir_starts[-1] + 1) if ir_starts else len(lines) :]:
        if in_ir and ("THERMOCHEMISTRY" in line or line.strip() == "RAMAN SPECTRUM"):
            break
        if in_ir and (match := _IR.match(line)):
            mode_index = int(match.group(1))
            if mode_index in frequency_by_index:
                frequency_by_index[mode_index].ir_intensity = float(match.group(3))

    for index, values in vectors.items():
        if index not in frequency_by_index or not any(values):
            continue
        frequency_by_index[index].displacements = [
            tuple(values[offset : offset + 3])
            for offset in range(0, coordinate_count, 3)
        ]

    return OrcaResult(geometries, energies, geometry_energies, list(frequency_by_index.values()))


def parse_orca_file(path: Path) -> OrcaResult:
    return parse_orca(path.read_text(encoding="utf-8", errors="replace"))
