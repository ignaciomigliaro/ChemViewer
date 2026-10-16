from pathlib import Path
import sys
import unittest

PROJECT = Path(__file__).resolve().parents[1]
SAMPLES = PROJECT.parent
sys.path.insert(0, str(PROJECT / "tools"))

from reference_parser import parse_orca, parse_orca_file  # noqa: E402


class InstalledCorpusTests(unittest.TestCase):
    def test_orca_water_frequency_job(self) -> None:
        path = SAMPLES / "ORCA" / "H2O_xyz_opt_freq_compound_jobs.out"
        self.assertTrue(path.exists(), f"missing authorized fixture: {path}")
        result = parse_orca_file(path)

        self.assertGreaterEqual(len(result.geometries), 3)
        self.assertEqual(len(result.geometries[-1]), 3)
        self.assertEqual([atom.element for atom in result.geometries[-1]], ["O", "H", "H"])
        self.assertAlmostEqual(result.energies_hartree[-1], -76.360968646, places=9)

        modes = {mode.index: mode for mode in result.modes}
        self.assertEqual(len(modes), 9)
        self.assertAlmostEqual(modes[6].frequency_cm1, 1606.12, places=2)
        self.assertAlmostEqual(modes[7].frequency_cm1, 3678.02, places=2)
        self.assertAlmostEqual(modes[8].frequency_cm1, 3777.72, places=2)
        self.assertAlmostEqual(modes[6].ir_intensity or 0, 45.965085, places=6)
        self.assertEqual(len(modes[6].displacements), 3)
        self.assertAlmostEqual(modes[6].displacements[0][2], -0.070076, places=6)

    def test_orca_water_geometry_energy_association(self) -> None:
        path = SAMPLES / "ORCA" / "H2O_xyz_opt_freq_compound_jobs.out"
        result = parse_orca_file(path)
        self.assertEqual(
            result.geometry_energies_hartree,
            [
                -76.360768437,
                -76.360937665,
                -76.360964066,
                -76.360970959,
                -76.360980198,
                -76.360968646,
            ],
        )

    def test_compound_job_uses_last_frequency_section(self) -> None:
        text = """
CARTESIAN COORDINATES (ANGSTROEM)
---------------------------------
H 0 0 0

FINAL SINGLE POINT ENERGY -1.0
VIBRATIONAL FREQUENCIES
0: 100.0 cm**-1
NORMAL MODES
     0
0 0.1
1 0.0
2 0.0
IR SPECTRUM
0: 100.0 1.0
THERMOCHEMISTRY
CARTESIAN COORDINATES (ANGSTROEM)
---------------------------------
H 0 0 1

FINAL SINGLE POINT ENERGY -2.0
VIBRATIONAL FREQUENCIES
0: -25.0 cm**-1
NORMAL MODES
     0
0 0.0
1 0.0
2 0.2
IR SPECTRUM
0: -25.0 3.0
THERMOCHEMISTRY
"""
        result = parse_orca(text)
        self.assertEqual(result.geometry_energies_hartree, [-1.0, -2.0])
        self.assertEqual(len(result.modes), 1)
        self.assertEqual(result.modes[0].frequency_cm1, -25.0)
        self.assertEqual(result.modes[0].ir_intensity, 3.0)
        self.assertEqual(result.modes[0].displacements[0][2], 0.2)


if __name__ == "__main__":
    unittest.main()
