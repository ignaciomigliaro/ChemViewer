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
from unittest.mock import patch
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "desktop"))
from main import MainWindow, apply_theme, configure_graphics
from PySide6.QtCore import QPoint, Qt
from PySide6.QtGui import QImage
from PySide6.QtTest import QTest
from PySide6.QtWidgets import QApplication, QTableWidgetItem, QMessageBox

configure_graphics()
APP = QApplication.instance() or QApplication(["ChemViewer desktop acceptance"])
apply_theme(APP)


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
        if os.environ.get("MESA_GL_VERSION_OVERRIDE") == "3.0":
            self.assertEqual(pane.viewport.shader_version, "130")
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
        if red <= 15: image.save(str(ROOT / ".build" / ("desktop-pixels-failure-" + sys.platform + ".png")), "PNG")
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
        # Exercise every native-Mac-style camera-rail action explicitly. Besides
        # checking the controls, this keeps branch coverage deterministic across
        # Windows, Linux/Xvfb, and macOS event-delivery implementations.
        camera_before = (viewport.yaw, viewport.pitch, viewport.roll, tuple(viewport.pan), viewport.distance)
        for action in ("left", "right", "up", "down", "roll_left", "roll_right",
                       "pan_up", "pan_down", "zoom_in", "zoom_out"):
            viewport.nudge(action)
        self.assertAlmostEqual(viewport.yaw, camera_before[0])
        self.assertAlmostEqual(viewport.pitch, camera_before[1])
        self.assertAlmostEqual(viewport.roll, camera_before[2])
        self.assertAlmostEqual(viewport.pan[0], camera_before[3][0])
        self.assertAlmostEqual(viewport.pan[1], camera_before[3][1])
        self.assertAlmostEqual(viewport.distance, camera_before[4])
        viewport.nudge("fit")
        pane.fit.click(); self.assertEqual(viewport.yaw, -20)
        image = viewport.grabFramebuffer(); path = Path(self.tmp.name) / "native molecule.png"
        self.assertTrue(image.save(str(path), "PNG")); self.assert_molecule_pixels(QImage(str(path)))
        self.window.resize(1300, 900); QTest.qWait(100)
        self.assert_molecule_pixels(viewport.grabFramebuffer())

    def test_coordinate_edit_undo_redo_shared_core(self):
        pane = self.open(); original = pane.data["frames"][0]["atoms"][1]["position"][:]
        pane.mode_tabs.setCurrentIndex(3)
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
        pane.show_energy(); QTest.qWait(50)
        self.assertIn("2,\r\n", pane.energy_plot.csv())
        self.assertIn("-1.123456789012", pane.energy_plot.csv())

    def test_save_export_dialog_workflows_and_dirty_close_cancel(self):
        pane = self.open()
        pane.command("position", atom=1, position=[1.5, 0, 0])
        wait_until(lambda: pane.dirty)
        with patch("main.QMessageBox.question", return_value=QMessageBox.Cancel):
            self.window.close_document(0)
            self.window.close()
        self.assertEqual(self.window.tabs.count(), 1)
        self.assertTrue(self.window.isVisible())
        directory = Path(self.tmp.name)
        project = directory / "saved.cvdesktop"
        with patch("main.QFileDialog.getSaveFileName", return_value=(str(project), "")):
            self.window.save_project()
        wait_until(lambda: project.exists() and not pane.dirty)
        xyz = directory / "saved.xyz"
        with patch("main.QFileDialog.getSaveFileName", return_value=(str(xyz), "")):
            self.window.export_xyz()
        wait_until(xyz.exists)
        self.assertEqual(self.request("open", path=str(xyz))["data"]["frames"][0]["atoms"], pane.data["frames"][0]["atoms"])
        png = directory / "saved.png"
        pane.views.setCurrentIndex(0); QTest.qWait(50)
        with patch("main.QFileDialog.getSaveFileName", return_value=(str(png), "")):
            self.window.export_png()
        self.assert_molecule_pixels(QImage(str(png)))
        csv_path = directory / "energy.csv"
        pane.show_energy(); QTest.qWait(50)
        with patch("main.QFileDialog.getSaveFileName", return_value=(str(csv_path), "")):
            self.window.export_energy()
        self.assertIn("Energy / Hartree", csv_path.read_text())
        import csv, io
        exported_rows = list(csv.reader(io.StringIO(csv_path.read_text())))
        self.assertEqual(len(exported_rows), len(pane.data["frames"]) + 1)
        self.assertNotIn(b"\r\r\n", csv_path.read_bytes())
        self.window.copy_xyz(); self.assertIn("1.5", QApplication.clipboard().text())
        self.window.close_document(0); wait_until(lambda: self.window.tabs.count() == 0)
        with patch("main.QFileDialog.getOpenFileNames", return_value=([str(project)], "")):
            self.window.open_dialog()
        wait_until(lambda: self.window.tabs.count() == 1)
        self.assertEqual(self.window.pane().data["frames"][0]["atoms"][1]["position"][0], 1.5)

    def test_invalid_coordinate_edits_restore_authoritative_state(self):
        pane = self.open(); original = pane.data["frames"][0]["atoms"][:]
        pane.mode_tabs.setCurrentIndex(3)
        pane.coordinates.setItem(1, 1, QTableWidgetItem("nan"))
        self.assertIn("finite", self.window.errors.pop())
        self.assertEqual(float(pane.coordinates.item(1, 1).text()), original[1]["position"][0])
        pane.coordinates.setItem(0, 0, QTableWidgetItem("unobtainium"))
        wait_until(lambda: len(self.window.errors) == 1)
        self.window.errors.clear()
        wait_until(lambda: pane.coordinates.item(0, 0).text() == "O")
        self.assertEqual(pane.data["frames"][0]["atoms"], original)
        self.assertFalse(pane.dirty)

    def test_numeric_edit_actions_builder_add_and_display_controls(self):
        pane = self.open(); pane.selection = [0, 1]
        with patch("main.QInputDialog.getDouble", return_value=(1.25, True)):
            pane.set_internal("distance")
        wait_until(lambda: abs(pane.data["frames"][0]["atoms"][1]["position"][0] - 1.25) < 1e-6)
        pane.selection = [1, 0, 2]
        with patch("main.QInputDialog.getDouble", return_value=(90, True)):
            pane.set_internal("angle")
        wait_until(lambda: not self.window.bridge.pending)
        measure = self.request("measure", document=pane.key, indices=[1, 0, 2])
        self.assertAlmostEqual(measure["measurement"], 90, places=4)
        pane.placement[0].setValue(3.0)
        with patch("main.QInputDialog.getText", return_value=("He", True)):
            pane.add_atom()
        wait_until(lambda: len(pane.data["frames"][0]["atoms"]) == 4)
        pane.change_style("Space filling"); pane.change_labels(True)
        pane.views.setCurrentIndex(0); QTest.qWait(50)
        raw = pane.viewport.grabFramebuffer()
        exported = pane.viewport.export_image()
        self.assert_molecule_pixels(exported)
        self.assertNotEqual(bytes(raw.constBits()), bytes(exported.constBits()))
        self.assertEqual(pane.viewport.style, "Space filling")
        self.assertTrue(pane.viewport.labels)

    def test_mac_workspace_shell_layout_and_modes(self):
        pane = self.open()
        self.assertEqual(
            [pane.mode_tabs.tabText(i) for i in range(pane.mode_tabs.count())],
            ["Image", "Abstract", "Source", "Coord", "Image/Abs", "ChemRefine", "Draw", "BOS-TMC"],
        )
        self.assertTrue(pane.explorer.isVisible())
        self.assertFalse(pane.builder.isVisible())
        self.assertEqual(pane.geometry_list.count(), pane.frames.count())
        self.assertEqual(pane.geometry_list.currentRow(), pane.frame)
        self.assertEqual(pane.explorer_title.text(), pane.data["title"])
        self.assertEqual(pane.selection_title.text(), "Selection (0)")
        inspector = pane.findChild(type(pane.image_content), "selectionInspector")
        self.assertIsNotNone(inspector)
        self.assertEqual(inspector.height(), 140)
        pane.toggle_builder(True)
        self.assertTrue(pane.builder.isVisible())
        pane.mode_tabs.setCurrentIndex(4)
        self.assertIs(pane.views.currentWidget(), pane.combined_page)
        pane.mode_tabs.setCurrentIndex(0)
        self.assertIs(pane.views.currentWidget(), pane.image_page)
        pane.set_label_mode("Element + number")
        self.assertEqual(pane.viewport.label_mode, "Element + number")
        self.assertTrue(pane.viewport.labels)

    def test_packaged_acceptance_path_checks_actual_gui(self):
        from acceptance import run
        report = Path(self.tmp.name) / "report.json"
        run(self.window, ROOT / "Tests/fixtures/water.xyz", report)
        wait_until(report.exists)
        result = json.loads(report.read_text())
        self.assertTrue(result["ok"], result)
        self.assertTrue(report.with_suffix(".png").exists())

    def test_packaged_acceptance_rejects_wrong_fixture(self):
        from acceptance import run
        report = Path(self.tmp.name) / "report.json"
        run(self.window, ROOT / "Tests/fixtures/methane.xyz", report)
        wait_until(report.exists)
        self.assertFalse(json.loads(report.read_text())["ok"])

    def test_service_locator_resolves_bundled_and_explicit_paths(self):
        from bridge import service_path
        directory = Path(self.tmp.name)
        binary = directory / ("ChemViewerService.exe" if sys.platform == "win32" else "ChemViewerService")
        with patch.dict(os.environ, {"CHEMVIEWER_SERVICE": str(binary)}):
            self.assertEqual(service_path(), str(binary.resolve()))
        with patch.dict(os.environ, {"CHEMVIEWER_SERVICE": ""}), patch.object(sys, "_MEIPASS", str(directory), create=True):
            with self.assertRaises(FileNotFoundError): service_path()
            binary.write_bytes(b"packaged locator fixture")
            self.assertEqual(service_path(), str(binary.resolve()))

    def test_core_process_failure_preserves_visible_document(self):
        pane = self.open(); original = pane.data.copy()
        self.window.bridge.process.kill()
        wait_until(lambda: self.window.bridge.process.state().name == "NotRunning")
        wait_until(lambda: any("stopped" in message for message in self.window.errors))
        self.assertEqual(pane.data, original)
        replies = []
        self.window.bridge.request("snapshot", replies.append, document=pane.key)
        self.assertFalse(replies[0]["ok"])
        self.assertFalse(self.window.bridge.pending)
        self.window.errors.clear()

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
