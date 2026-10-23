#!/usr/bin/env python3
"""Real Qt/OpenGL acceptance. Requires a desktop or Xvfb + software OpenGL.

No skip on rendering failures: a blank framebuffer is a failed test.
"""
import json
import os
import sys
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "desktop"))
from main import MainWindow, configure_graphics
from PySide6.QtCore import QPoint, Qt
from PySide6.QtGui import QImage
from PySide6.QtTest import QTest
from PySide6.QtWidgets import QApplication, QTableWidgetItem

configure_graphics()
APP = QApplication.instance() or QApplication(["ChemViewer desktop acceptance"])


def wait_until(predicate, timeout=15):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        APP.processEvents()
        if predicate(): return
        QTest.qWait(20)
    raise AssertionError("Timed out waiting for Qt/core/GPU condition")


class DesktopAcceptance(unittest.TestCase):
    def setUp(self):
        self.window = MainWindow(); self.window.dialogs_enabled = False
        self.window.show()
        self.tmp = tempfile.TemporaryDirectory(prefix="ChemViewer Qt ü ")
        wait_until(lambda: self.window.bridge.process.state().name == "Running")

    def tearDown(self):
        for i in range(self.window.tabs.count()): self.window.tabs.widget(i).dirty = False
        errors = self.window.errors[:]
        self.window.close(); self.window.deleteLater(); APP.processEvents()
        self.tmp.cleanup()
        self.assertEqual(errors, [])

    def open(self, name="water.xyz"):
        count = self.window.tabs.count()
        self.window.open_path(ROOT / "Tests/fixtures" / name)
        wait_until(lambda: self.window.tabs.count() > count)
        pane = self.window.pane()
        wait_until(lambda: pane.viewport.render_count > 0 or pane.viewport.error)
        self.assertIsNone(pane.viewport.error)
        self.assertIsNotNone(pane.viewport.program)
        return pane

    def request(self, action, **kwargs):
        replies = []
        self.window.bridge.request(action, replies.append, **kwargs)
        wait_until(lambda: len(replies) == 1)
        self.assertTrue(replies[0]["ok"], replies[0])
        return replies[0]

    def assert_molecule_pixels(self, image):
        self.assertFalse(image.isNull())
        # Independently inspect saved pixels: require substantial colored atom area.
        red = 0; non_background = 0
        for y in range(0, image.height(), 3):
            for x in range(0, image.width(), 3):
                color = image.pixelColor(x, y)
                red += color.red() > color.green() * 1.5 and color.red() > color.blue() * 1.5
                non_background += min(color.red(), color.green(), color.blue()) < 180
        self.assertGreater(red, 15)
        self.assertGreater(non_background, 30)

    def test_render_pick_measure_rotate_zoom_fit_export(self):
        pane = self.open(); viewport = pane.viewport
        self.assert_molecule_pixels(viewport.grabFramebuffer())
        for index in (0, 1):
            x, y = viewport.project(viewport.positions[index])
            self.assertEqual(viewport.pick(x, y), index)
            QTest.mouseClick(viewport, Qt.LeftButton, Qt.ControlModifier if index else Qt.NoModifier, QPoint(round(x), round(y)))
        wait_until(lambda: "0.95720" in pane.measurement.text())
        self.assertEqual(pane.selection, [0, 1])
        before = viewport.yaw
        QTest.mousePress(viewport, Qt.RightButton, Qt.NoModifier, QPoint(100, 100))
        QTest.mouseMove(viewport, QPoint(180, 130), 50)
        QTest.mouseRelease(viewport, Qt.RightButton, Qt.NoModifier, QPoint(180, 130))
        self.assertNotEqual(viewport.yaw, before)
        pane.fit.click(); self.assertEqual(viewport.yaw, -20)
        image = viewport.grabFramebuffer(); path = Path(self.tmp.name) / "native molecule.png"
        self.assertTrue(image.save(str(path), "PNG")); self.assert_molecule_pixels(QImage(str(path)))
        self.window.resize(1300, 900); QTest.qWait(100)
        self.assert_molecule_pixels(viewport.grabFramebuffer())

    def test_coordinate_edit_undo_redo_shared_core(self):
        pane = self.open(); original = pane.data["frames"][0]["atoms"][1]["position"][:]
        pane.views.setCurrentIndex(1)
        pane.coordinates.setItem(1, 1, QTableWidgetItem("1.5"))
        wait_until(lambda: pane.dirty)
        self.assertEqual(pane.data["frames"][0]["atoms"][1]["position"][0], 1.5)
        self.assertEqual(pane.source.toPlainText(), (ROOT / "Tests/fixtures/water.xyz").read_text())
        self.window.undo_action.trigger(); wait_until(lambda: not pane.dirty)
        self.assertEqual(pane.data["frames"][0]["atoms"][1]["position"], original)
        self.window.redo_action.trigger(); wait_until(lambda: pane.dirty)
        self.assertEqual(pane.data["frames"][0]["atoms"][1]["position"][0], 1.5)

    def test_documents_preserve_camera_and_stop_inactive_playback(self):
        a = self.open("energy-path.xyz")
        a.viewport.yaw = 74; a.play.click(); self.assertTrue(a.timer.isActive())
        b = self.open("methane.xyz")
        self.assertFalse(a.timer.isActive())
        self.assertFalse(a.play.isChecked())
        self.window.tabs.setCurrentIndex(0)
        self.assertEqual(a.viewport.yaw, 74)
        self.assertIs(self.window.pane(), a)
        count = self.window.tabs.count(); self.window.open_path(ROOT / "Tests/fixtures/energy-path.xyz")
        QTest.qWait(100); self.assertEqual(self.window.tabs.count(), count)

    def test_trajectory_controls_and_equilibrium_xyz(self):
        pane = self.open("energy-path.xyz")
        self.assertGreater(pane.frames.count(), 1)
        pane.play.click(); wait_until(lambda: pane.frame != 0)
        pane.play.click(); self.assertFalse(pane.timer.isActive())
        destination = Path(self.tmp.name) / "trajectory.xyz"
        self.request("export_xyz", document=pane.key, path=str(destination))
        loaded = self.request("open", path=str(destination))["data"]
        self.assertEqual(len(loaded["frames"]), len(pane.data["frames"]))
        self.assertIn("Eh", pane.frames.itemText(0))

    def test_builder_delete_undo_and_project_reload(self):
        reply = self.request("new"); self.window.opened(reply)
        pane = self.window.pane(); self.assertEqual(pane.data["frames"][0]["atoms"], [])
        wait_until(lambda: pane.fragment.count() > 0)
        pane.place_fragment(); wait_until(lambda: len(pane.data["frames"][0]["atoms"]) > 0)
        initial = pane.data["frames"][0]["atoms"][:]
        pane.selection = [0]; pane.delete_atoms()
        wait_until(lambda: len(pane.data["frames"][0]["atoms"]) == len(initial) - 1)
        self.window.undo_action.trigger()
        wait_until(lambda: len(pane.data["frames"][0]["atoms"]) == len(initial))
        destination = Path(self.tmp.name) / "builder.cvdesktop"
        saved = self.request("save_project", document=pane.key, path=str(destination))
        loaded = self.request("open", path=str(destination))
        self.assertEqual(saved["data"]["frames"], loaded["data"]["frames"])

    def test_negative_mode_animation_export_and_edit_invalidation(self):
        pane = self.open("desktop-imaginary.out")
        self.assertIn("imaginary", pane.modes.item(0).text())
        original = [p[:] for p in pane.viewport.positions]
        pane.modes.setCurrentRow(0)
        wait_until(lambda: pane.viewport.positions != original)
        self.assertTrue(pane.timer.isActive())
        destination = Path(self.tmp.name) / "equilibrium.xyz"
        self.request("export_xyz", document=pane.key, path=str(destination))
        loaded = self.request("open", path=str(destination))["data"]
        self.assertEqual(loaded["frames"][0]["atoms"], pane.data["frames"][0]["atoms"])
        pane.deactivate(); self.assertEqual(pane.viewport.positions, original)
        pane.command("position", atom=0, position=[0, 1, 0])
        wait_until(lambda: pane.dirty)
        self.assertEqual(pane.modes.count(), 0)
        self.assertFalse(pane.timer.isActive())
        self.assertNotIn("energyHartree", pane.data["frames"][0])

    def test_energy_csv_preserves_source_precision_and_gaps(self):
        pane = self.open("energy-path.xyz")
        import csv, io
        rows = list(csv.reader(io.StringIO(pane.energy_plot.csv())))
        for row, frame in zip(rows[1:], pane.data["frames"]):
            value = frame.get("energyHartree")
            self.assertEqual(row[1], "" if value is None else repr(value))
        pane.energy_plot.set_points([(1, -1.123456789012), (2, None), (3, -1.0)])
        self.assertIn("2,\r\n", pane.energy_plot.csv())
        self.assertIn("-1.123456789012", pane.energy_plot.csv())

    def test_source_only_input_no_invented_geometry(self):
        path = Path(self.tmp.name) / "source.inp"
        path.write_text("! HF\n%coords\nend\n")
        self.window.open_path(path)
        wait_until(lambda: self.window.tabs.count() == 1)
        pane = self.window.pane()
        self.assertEqual(pane.data["frames"], [])
        self.assertEqual(pane.coordinates.rowCount(), 0)
        self.assertIn("%coords", pane.source.toPlainText())
        self.assertFalse(pane.play.isEnabled())


if __name__ == "__main__":
    unittest.main(verbosity=2)
