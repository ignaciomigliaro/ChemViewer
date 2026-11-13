"""Independent scalar checks of the original branched-edit Cartesian oracle."""
import json
import math
from pathlib import Path
import unittest

FIXTURE = Path(__file__).resolve().parents[1] / 'Tests/fixtures/integrated-building/synthetic-internal-coordinates.cvproject'


def distance(a, b):
    return math.sqrt(sum((x-y)**2 for x, y in zip(a, b)))


def angle(a, b, c):
    left = [x-y for x, y in zip(a, b)]
    right = [x-y for x, y in zip(c, b)]
    return math.degrees(math.acos(sum(x*y for x, y in zip(left, right)) / distance(a, b) / distance(c, b)))


class InternalCoordinateOracle(unittest.TestCase):
    def test_tabulated_coordinates_have_exact_targets_and_rigid_fragments(self):
        data = json.loads(FIXTURE.read_text())
        original = [[a[k] for k in ('x', 'y', 'z')] for a in data['atoms']]
        for name, expected in data['oracles'].items():
            self.assertEqual(expected[7], original[7])
            if name.startswith('distance'):
                self.assertAlmostEqual(distance(expected[1], expected[2]), 3, places=12)
                left = [0, 1, 5, 6]
            else:
                self.assertAlmostEqual(angle(expected[0], expected[1], expected[2]), 60, places=12)
                self.assertEqual(expected[1], original[1])
                self.assertEqual(expected[6], original[6])
                left = [0, 5]
                self.assertAlmostEqual(distance(expected[0], expected[1]), distance(original[0], original[1]), places=12)
                self.assertAlmostEqual(distance(expected[2], expected[1]), distance(original[2], original[1]), places=12)
            for group in [left, [2, 3, 4]]:
                for i in group:
                    for j in group:
                        self.assertAlmostEqual(distance(expected[i], expected[j]), distance(original[i], original[j]), places=12)
            if 'Both' not in name:
                for i in left:
                    self.assertEqual(expected[i], original[i])


if __name__ == '__main__':
    unittest.main()
