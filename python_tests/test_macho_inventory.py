from pathlib import Path
import sys
import unittest

PROJECT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT / "tools"))

from macho_inventory import parse  # noqa: E402


class OfficialMacArtifactTests(unittest.TestCase):
    def setUp(self) -> None:
        root = PROJECT / "evidence" / "official-macos-b638m"
        self.arm = root / "extracted-arm" / "Chemcraft_ARM.app" / "Contents" / "MacOS" / "Chemcraft_ARM"
        self.intel = root / "extracted-intel" / "Chemcraft_Intel.app" / "Contents" / "MacOS" / "Chemcraft_Intel"
        if not self.arm.exists() or not self.intel.exists():
            self.skipTest("official proprietary artifacts are intentionally not committed")

    def test_architecture_dependencies_and_signature_shape(self) -> None:
        arm = parse(self.arm)
        intel = parse(self.intel)
        self.assertEqual(arm["architecture"], "arm64")
        self.assertEqual(intel["architecture"], "x86_64")
        self.assertEqual(len(arm["dependencies"]), 13)
        self.assertEqual(len(intel["dependencies"]), 13)
        self.assertEqual(arm["sha256"], "c3a83812708d942afb59e9f2f13ad5448d4be9bee20c22129f81cfdc99e86441")
        self.assertEqual(intel["sha256"], "645bdf5291073f2e29edc101365b9803c43ecca360bc664597991169cc88a6f0")
        self.assertIsNone(intel["code_signature"])
        self.assertFalse(arm["code_signature"]["has_cms_signature"])
        self.assertIn("adhoc", arm["code_signature"]["slots"][0]["flag_names"])
        self.assertIn("linker-signed", arm["code_signature"]["slots"][0]["flag_names"])


if __name__ == "__main__":
    unittest.main()
