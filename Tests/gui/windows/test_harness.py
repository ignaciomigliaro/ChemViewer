import math
from pathlib import Path

import pytest

from chemcraft_driver import DEFAULT_EXE, PROJECT, sha256


FIXTURES = PROJECT / "Tests" / "fixtures"


def read_xyz(path: Path) -> list[tuple[float, float, float]]:
    lines = path.read_text(encoding="utf-8").splitlines()
    count = int(lines[0])
    coordinates = []
    for line in lines[2 : 2 + count]:
        fields = line.split()
        coordinates.append(tuple(float(value) for value in fields[1:4]))
    return coordinates


def vector(first: tuple[float, ...], second: tuple[float, ...]) -> tuple[float, ...]:
    return tuple(a - b for a, b in zip(first, second))


def dot(first: tuple[float, ...], second: tuple[float, ...]) -> float:
    return sum(a * b for a, b in zip(first, second))


def cross(first: tuple[float, ...], second: tuple[float, ...]) -> tuple[float, float, float]:
    return (
        first[1] * second[2] - first[2] * second[1],
        first[2] * second[0] - first[0] * second[2],
        first[0] * second[1] - first[1] * second[0],
    )


def norm(value: tuple[float, ...]) -> float:
    return math.sqrt(dot(value, value))


def test_paths_are_isolated() -> None:
    writable_samples = Path(r"C:\Chemcraft\samples").resolve()
    installation_executable = Path(r"C:\Chemcraft\Chemcraft.exe").resolve()
    assert PROJECT.resolve().is_relative_to(writable_samples)
    assert not installation_executable.is_relative_to(PROJECT.resolve())


def test_reference_executable_identity() -> None:
    assert DEFAULT_EXE.is_file()
    assert sha256(DEFAULT_EXE) == "79fe75015a1e48c4df29e7bac4c3c05e67057bf3a0ed03a7b77fe85528d4f05a"


def test_clean_room_fixture_hashes() -> None:
    assert sha256(FIXTURES / "water.xyz") == "ad9798ab5b0e47faa79fd95b835b23295353c3801a0e9cba36109cd83c8aa1f6"
    assert sha256(FIXTURES / "methane.xyz") == "5bb58ad835f2af3b796eba40097193b33fe3ee42616c7058fd4d529dd68f2955"
    assert sha256(FIXTURES / "dihedral.xyz") == "2c8cf8aaac94de44aff27431ec554814804ef06756acc291cfadf4c99b5e4e14"


def test_measurement_oracle_matches_windows_reference() -> None:
    water = read_xyz(FIXTURES / "water.xyz")
    oh = norm(vector(water[2], water[0]))
    left = vector(water[2], water[0])
    right = vector(water[1], water[0])
    angle = math.degrees(math.acos(dot(left, right) / (norm(left) * norm(right))))
    assert oh == pytest.approx(0.95720, abs=1e-5)
    assert angle == pytest.approx(104.520, abs=1e-3)

    chain = read_xyz(FIXTURES / "dihedral.xyz")
    b0 = vector(chain[0], chain[1])
    b1 = vector(chain[2], chain[1])
    b2 = vector(chain[3], chain[2])
    axis = tuple(value / norm(b1) for value in b1)
    v = vector(b0, tuple(value * dot(b0, axis) for value in axis))
    w = vector(b2, tuple(value * dot(b2, axis) for value in axis))
    dihedral = math.degrees(math.atan2(dot(cross(axis, v), w), dot(v, w)))
    assert dihedral == pytest.approx(116.565, abs=1e-3)
