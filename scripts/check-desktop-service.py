#!/usr/bin/env python3
"""Protocol regressions against the real Swift service, with independent oracles."""
import argparse
import json
import math
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BINARY = None


class DesktopServiceTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="ChemViewer desktop ü ")
        self.tmp = Path(self.directory.name)
        self.process = subprocess.Popen([str(BINARY)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.counter = 0

    def tearDown(self):
        self.process.stdin.close()
        self.process.wait(timeout=10)
        error = self.process.stderr.read().decode()
        self.process.stdout.close(); self.process.stderr.close()
        self.directory.cleanup()
        self.assertEqual(self.process.returncode, 0, error)

    def request(self, action, **kwargs):
        self.counter += 1
        payload = dict(id=self.counter, action=action, **kwargs)
        self.process.stdin.write(json.dumps(payload, allow_nan=False).encode() + b"\n"); self.process.stdin.flush()
        reply = json.loads(self.process.stdout.readline())
        self.assertEqual(reply["id"], self.counter)
        return reply

    def opened(self, name="water.xyz"):
        reply = self.request("open", path=str(ROOT / "Tests/fixtures" / name))
        self.assertTrue(reply["ok"], reply)
        return reply

    def test_hello_and_unknown_action_recovery(self):
        self.assertGreater(len(self.request("hello")["fragments"]), 3)
        self.assertFalse(self.request("undefined")["ok"])
        self.assertTrue(self.request("hello")["ok"])

    def test_open_preserves_coordinates_units_missing_energy_source(self):
        reply = self.opened(); data = reply["data"]
        self.assertEqual(data["coordinateUnit"], "angstrom")
        self.assertEqual(data["energyUnit"], "hartree")
        self.assertAlmostEqual(data["frames"][0]["atoms"][1]["position"][0], 0.9572, places=6)
        self.assertNotIn("energyHartree", data["frames"][0])
        self.assertEqual(data["source"], (ROOT / "Tests/fixtures/water.xyz").read_text())
        self.assertFalse(reply["dirty"])

    def test_independent_measurement_oracles(self):
        key = self.opened()["document"]
        distance = self.request("measure", document=key, indices=[0, 1])["measurement"]
        self.assertAlmostEqual(distance, .9572, places=5)
        angle = self.request("measure", document=key, indices=[1, 0, 2])["measurement"]
        self.assertAlmostEqual(angle, 104.52, places=2)
        key = self.opened("dihedral.xyz")["document"]
        dihedral = self.request("measure", document=key, indices=[0, 1, 2, 3])["measurement"]
        self.assertAlmostEqual(dihedral, 116.56505, places=4)

    def test_edit_undo_redo_and_failed_transaction(self):
        original = self.opened(); key = original["document"]
        moved = self.request("position", document=key, atom=1, position=[1.5, 0, 0])
        self.assertTrue(moved["dirty"]); self.assertTrue(moved["canUndo"])
        self.assertNotIn("energyHartree", moved["data"]["frames"][0])
        self.assertFalse(self.request("position", document=key, atom=999, position=[1, 2, 3])["ok"])
        self.assertEqual(self.request("snapshot", document=key)["data"], moved["data"])
        undo = self.request("undo", document=key)
        self.assertEqual(undo["data"], original["data"]); self.assertFalse(undo["dirty"])
        self.assertEqual(self.request("redo", document=key)["data"], moved["data"])
        self.request("undo", document=key)
        changed = self.request("element", document=key, atom=0, element="N")
        self.assertFalse(changed["canRedo"])
        self.assertEqual(changed["data"]["frames"][0]["atoms"][0]["element"], "N")

    def test_multiple_documents_are_isolated(self):
        a = self.opened(); b = self.opened("methane.xyz")
        self.request("delete", document=a["document"], indices=[1])
        self.assertEqual(self.request("snapshot", document=b["document"])["data"], b["data"])
        self.request("close", document=a["document"])
        self.assertFalse(self.request("snapshot", document=a["document"])["ok"])
        self.assertTrue(self.request("snapshot", document=b["document"])["ok"])

    def test_internal_coordinate_edits(self):
        key = self.opened()["document"]
        self.assertTrue(self.request("distance", document=key, indices=[0, 1], value=1.25)["ok"])
        self.assertAlmostEqual(self.request("measure", document=key, indices=[0, 1])["measurement"], 1.25, places=6)
        self.assertTrue(self.request("angle", document=key, indices=[1, 0, 2], value=90)["ok"])
        self.assertAlmostEqual(self.request("measure", document=key, indices=[1, 0, 2])["measurement"], 90, places=4)
        before = self.request("snapshot", document=key)
        self.assertFalse(self.request("distance", document=key, indices=[0, 1], value=-1)["ok"])
        self.assertEqual(self.request("snapshot", document=key)["data"], before["data"])

    def test_builder_and_invalid_elements(self):
        key = self.request("new")["document"]
        self.assertFalse(self.request("add", document=key, element="unobtainium", position=[0, 0, 0])["ok"])
        reply = self.request("add", document=key, element="8", position=[1, 2, 3])
        self.assertEqual(reply["data"]["frames"][0]["atoms"][0]["element"], "O")
        self.assertEqual(reply["data"]["frames"][0]["atoms"][0]["position"], [1, 2, 3])
        reply = self.request("fragment", document=key, fragment=0, position=[5, 0, 0])
        self.assertTrue(reply["ok"], reply)
        self.assertGreater(len(reply["data"]["frames"][0]["atoms"]), 1)

    def test_project_roundtrip_and_repeat_save(self):
        opened = self.opened(); key = opened["document"]
        self.request("position", document=key, atom=1, position=[2, 0, 0])
        path = self.tmp / "water project.cvdesktop"
        saved = self.request("save_project", document=key, path=str(path))
        self.assertTrue(saved["ok"], saved); self.assertFalse(saved["dirty"])
        restored = self.request("open", path=str(path))
        self.assertEqual(restored["data"], saved["data"])
        path2 = self.tmp / "again.cvdesktop"
        self.assertTrue(self.request("save_project", document=restored["document"], path=str(path2))["ok"])
        self.assertEqual(self.request("open", path=str(path2))["data"], saved["data"])
        self.assertFalse(self.request("save_project", document=key, path=str(path))["ok"])

    def test_new_project_roundtrip(self):
        key = self.request("new")["document"]
        original = self.request("add", document=key, element="C", position=[0, 0, 0])
        path = self.tmp / "new.cvdesktop"
        self.assertTrue(self.request("save_project", document=key, path=str(path))["ok"])
        restored = self.request("open", path=str(path))
        self.assertEqual(restored["data"]["frames"], original["data"]["frames"])
        self.assertEqual(restored["data"]["source"], "")

    def test_embedded_input_companion_survives_original_deletion(self):
        xyz = self.tmp / "companion.xyz"; xyz.write_text("1\nindependent atom\nHe 1 2 3\n")
        inp = self.tmp / "job.inp"; inp.write_text('! HF\n* xyzfile -1 2 "companion.xyz"\n')
        opened = self.request("open", path=str(inp)); self.assertTrue(opened["ok"], opened)
        project = self.tmp / "job.cvdesktop"
        self.assertTrue(self.request("save_project", document=opened["document"], path=str(project))["ok"])
        xyz.unlink(); inp.unlink()
        restored = self.request("open", path=str(project))
        self.assertTrue(restored["ok"], restored)
        self.assertEqual(restored["data"], opened["data"])
        self.assertEqual(restored["data"]["charge"], -1); self.assertEqual(restored["data"]["multiplicity"], 2)

    def test_export_never_overwrites_without_explicit_request(self):
        key = self.opened()["document"]
        target = self.tmp / "output.xyz"; target.write_text("preserve me")
        self.assertFalse(self.request("export_xyz", document=key, path=str(target))["ok"])
        self.assertEqual(target.read_text(), "preserve me")
        self.assertTrue(self.request("export_xyz", document=key, path=str(target), overwrite=True)["ok"])
        self.assertEqual(self.request("open", path=str(target))["data"]["frames"][0]["atoms"], self.request("snapshot", document=key)["data"]["frames"][0]["atoms"])

    def test_trajectory_export_all_and_current(self):
        reply = self.opened("energy-path.xyz"); key = reply["document"]
        path = self.tmp / "trajectory.xyz"
        self.assertTrue(self.request("export_xyz", document=key, path=str(path))["ok"])
        self.assertEqual(len(self.request("open", path=str(path))["data"]["frames"]), len(reply["data"]["frames"]))
        one = self.tmp / "one.xyz"
        self.assertTrue(self.request("export_xyz", document=key, path=str(one), frame=1)["ok"])
        self.assertEqual(len(self.request("open", path=str(one))["data"]["frames"]), 1)

    def test_malformed_request_recovers(self):
        self.process.stdin.write(b"{bad json\n"); self.process.stdin.flush()
        reply = json.loads(self.process.stdout.readline())
        self.assertEqual(reply["id"], -1); self.assertFalse(reply["ok"])
        self.assertTrue(self.request("hello")["ok"])

    def test_negative_mode_preserved_then_invalidated_on_edit(self):
        # Independently authored ORCA-style fixture: one mode on two H atoms.
        source = """CARTESIAN COORDINATES (ANGSTROEM)
---------------------------------
H 0 0 0
H 0 0 0.74

FINAL SINGLE POINT ENERGY -1.123456789012
VIBRATIONAL FREQUENCIES
---------------------
0: -250.0 cm**-1

NORMAL MODES
------------
                  0
0  0.1
1  0.0
2  0.0
3 -0.1
4  0.0
5  0.0

IR SPECTRUM
----------
 Mode freq T**2
0: -250.0 7.5
"""
        path = self.tmp / "imaginary.out"; path.write_text(source)
        opened = self.request("open", path=str(path)); self.assertTrue(opened["ok"], opened)
        key = opened["document"]; mode = opened["data"]["modes"][0]
        self.assertEqual(mode["frequencyCM1"], -250)
        self.assertEqual(mode["infraredIntensity"], 7.5)
        self.assertNotIn("ramanActivity", mode)
        self.assertAlmostEqual(opened["data"]["frames"][0]["energyHartree"], -1.123456789012, places=12)
        edited = self.request("position", document=key, atom=0, position=[0, 1, 0])
        self.assertEqual(edited["data"]["modes"], [])
        self.assertNotIn("energyHartree", edited["data"]["frames"][0])
        self.assertEqual(edited["data"]["source"], source)
        self.assertEqual(self.request("undo", document=key)["data"], opened["data"])


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", required=True)
    arguments = parser.parse_args()
    BINARY = Path(arguments.binary).resolve()
    unittest.main(argv=[__file__], verbosity=2)
