"""ChemViewer Windows-first Qt desktop frontend, also buildable on Linux/macOS."""
import argparse
import math
import sys
from pathlib import Path

from PySide6.QtCore import Qt, QTimer, Signal, QSignalBlocker
from PySide6.QtGui import QAction, QKeySequence, QSurfaceFormat
from PySide6.QtWidgets import (
    QApplication, QCheckBox, QComboBox, QDoubleSpinBox, QFileDialog, QFormLayout,
    QHBoxLayout, QInputDialog, QLabel, QListWidget, QMainWindow, QMessageBox,
    QPushButton, QSplitter, QTabWidget, QTableWidget, QTableWidgetItem,
    QTextEdit, QToolBar, QVBoxLayout, QWidget, QAbstractItemView, QSizePolicy,
)
from bridge import CoreBridge
from viewport import MoleculeViewport
from plots import ScientificPlot


def configure_graphics():
    fmt = QSurfaceFormat()
    fmt.setRenderableType(QSurfaceFormat.OpenGL)
    fmt.setProfile(QSurfaceFormat.CoreProfile)
    fmt.setVersion(3, 3)
    fmt.setDepthBufferSize(24); fmt.setSamples(4)
    QSurfaceFormat.setDefaultFormat(fmt)


class DocumentPane(QWidget):
    changed = Signal()

    def __init__(self, bridge, reply, path=None, parent=None):
        super().__init__(parent)
        self.bridge = bridge; self.key = reply["document"]; self.path = path
        self.project_path = path if path and path.lower().endswith(".cvdesktop") else None
        self.frame = 0; self.mode = -1; self.phase = 0.0; self.selection = []
        self.closed = False
        self.data = {}; self.dirty = False; self.can_undo = False; self.can_redo = False
        self.timer = QTimer(self); self.timer.setInterval(33); self.timer.timeout.connect(self.tick)
        self.trajectory_ticks = 0
        self.viewport = MoleculeViewport(self)
        self.viewport.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)
        self.viewport.atomPicked.connect(self.pick)
        self.viewport.renderFailed.connect(lambda message: self.window().show_error(message))
        self.frames = QComboBox(); self.frames.setObjectName("frameSelector")
        self.frames.currentIndexChanged.connect(self.choose_frame)
        self.play = QPushButton("Play trajectory"); self.play.setCheckable(True)
        self.play.toggled.connect(self.play_trajectory)
        self.fit = QPushButton("Fit"); self.fit.clicked.connect(self.viewport.fit)
        style = QComboBox(); style.addItems(["Ball and stick", "Space filling"])
        style.currentTextChanged.connect(self.change_style)
        labels = QCheckBox("Labels"); labels.toggled.connect(self.change_labels)
        controls = QHBoxLayout()
        for item in [self.frames, self.play, self.fit, style, labels]: controls.addWidget(item)
        image = QWidget(); image_layout = QVBoxLayout(image)
        image_layout.addLayout(controls); image_layout.addWidget(self.viewport, 1)
        self.measurement = QLabel("Click atoms to measure; Ctrl-click adds to the selection.")
        self.measurement.setSizePolicy(QSizePolicy.Preferred, QSizePolicy.Fixed)
        image_layout.addWidget(self.measurement)
        self.views = QTabWidget(); self.views.addTab(image, "Image")
        self.coordinates = QTableWidget(0, 4); self.coordinates.setObjectName("coordinates")
        self.coordinates.setHorizontalHeaderLabels(["Element", "X / Å", "Y / Å", "Z / Å"])
        self.coordinates.setSelectionBehavior(QAbstractItemView.SelectRows)
        self.coordinates.cellChanged.connect(self.edit_coordinate)
        self.views.addTab(self.coordinates, "Coordinates")
        self.energy_plot = ScientificPlot("Geometry index (1-based)", "Energy / Hartree")
        self.views.addTab(self.energy_plot, "Energy")
        self.abstract = QTextEdit(); self.abstract.setReadOnly(True); self.views.addTab(self.abstract, "Properties")
        self.source = QTextEdit(); self.source.setReadOnly(True); self.views.addTab(self.source, "Source")
        self.modes = QListWidget(); self.modes.setObjectName("normalModes"); self.modes.currentRowChanged.connect(self.choose_mode)
        self.amplitude = QDoubleSpinBox(); self.amplitude.setRange(0, 3); self.amplitude.setSingleStep(0.1); self.amplitude.setValue(0.5)
        self.animate_mode = QCheckBox("Animate mode (illustrative)"); self.animate_mode.toggled.connect(self.toggle_mode)
        self.fragment = QComboBox(); self.bridge.request("hello", self.fragments_received)
        self.placement = [QDoubleSpinBox() for _ in range(3)]
        form = QFormLayout()
        form.addRow("Normal modes / cm⁻¹", self.modes)
        form.addRow("Display amplitude", self.amplitude); form.addRow(self.animate_mode)
        form.addRow("Builder fragment", self.fragment)
        for label, box in zip(["Place X / Å", "Place Y / Å", "Place Z / Å"], self.placement):
            box.setRange(-100000, 100000); box.setDecimals(6); form.addRow(label, box)
        place = QPushButton("Place fragment"); place.clicked.connect(self.place_fragment); form.addRow(place)
        attach = QPushButton("Attach to selected atom"); attach.clicked.connect(self.attach_fragment); form.addRow(attach)
        add = QPushButton("Add atom…"); add.clicked.connect(self.add_atom); form.addRow(add)
        delete = QPushButton("Delete selected atoms"); delete.clicked.connect(self.delete_atoms); form.addRow(delete)
        distance = QPushButton("Set distance…"); distance.clicked.connect(lambda: self.set_internal("distance")); form.addRow(distance)
        angle = QPushButton("Set angle…"); angle.clicked.connect(lambda: self.set_internal("angle")); form.addRow(angle)
        side = QWidget(); side.setLayout(form); side.setMaximumWidth(340)
        split = QSplitter(); split.addWidget(self.views); split.addWidget(side); split.setStretchFactor(0, 1)
        layout = QVBoxLayout(self); layout.setContentsMargins(0, 0, 0, 0); layout.addWidget(split)
        self.apply(reply, fit=True)

    def fragments_received(self, reply):
        if not self.closed and reply.get("ok"): self.fragment.addItems(reply.get("fragments", []))

    def command(self, action, callback=None, **arguments):
        def complete(reply):
            if self.closed: return
            if not reply.get("ok"): self.show_frame()
            if reply.get("ok") and "data" in reply:
                self.apply(reply)
            if callback: callback(reply)
        self.bridge.request(action, complete, document=self.key, frame=self.frame, **arguments)

    def apply(self, reply, fit=False):
        self.data = reply["data"]; self.dirty = reply["dirty"]
        self.can_undo = reply["canUndo"]; self.can_redo = reply["canRedo"]
        frames = self.data["frames"]
        self.frame = min(self.frame, max(0, len(frames) - 1))
        with QSignalBlocker(self.frames):
            self.frames.clear()
            for i, frame in enumerate(frames):
                energy = frame.get("energyHartree")
                self.frames.addItem(f"Geometry {i + 1}" + (f"  {energy:.12g} Eh" if energy is not None else "  energy unavailable"))
            self.frames.setCurrentIndex(self.frame)
        with QSignalBlocker(self.modes):
            self.modes.clear()
            for mode in self.data["modes"]:
                self.modes.addItem(f"{mode['index']}: {mode['frequencyCM1']:.2f}" + ("  imaginary" if mode["frequencyCM1"] < 0 else ""))
            self.mode = min(self.mode, len(self.data["modes"]) - 1)
            self.modes.setCurrentRow(self.mode)
        if not self.data["modes"]:
            self.animate_mode.setChecked(False)
        self.energy_plot.set_points([(i + 1, frame.get("energyHartree")) for i, frame in enumerate(frames)])
        self.source.setPlainText(self.data["source"])
        lines = [self.data["title"], self.data["sourceFormat"], "Coordinates: Å; energy: Hartree",
                 "Charge: " + str(self.data.get("charge", "unavailable")),
                 "Multiplicity: " + str(self.data.get("multiplicity", "unavailable"))]
        lines += self.data.get("warnings", [])
        for mode in self.data["modes"]:
            lines.append(f"Mode {mode['index']}: {mode['frequencyCM1']} cm⁻¹; IR intensity {mode.get('infraredIntensity', 'unavailable')}; Raman activity {mode.get('ramanActivity', 'unavailable')}")
        self.abstract.setPlainText("\n".join(lines))
        self.show_frame(fit); self.changed.emit()

    def show_frame(self, fit=False):
        frames = self.data["frames"]; frame = frames[self.frame] if frames else None
        self.viewport.set_frame(frame, fit=fit)
        self.viewport.selected = self.selection[:]
        with QSignalBlocker(self.coordinates):
            self.coordinates.setRowCount(len(frame["atoms"]) if frame else 0)
            for row, atom in enumerate(frame["atoms"] if frame else []):
                for col, value in enumerate([atom["element"], *atom["position"]]):
                    self.coordinates.setItem(row, col, QTableWidgetItem(str(value)))
        self.play.setEnabled(len(frames) > 1)

    def choose_frame(self, index):
        if index < 0: return
        self.animate_mode.setChecked(False); self.frame = index; self.selection = []
        self.show_frame(); self.measurement.setText("Click atoms to measure; Ctrl-click adds to the selection.")

    def play_trajectory(self, enabled):
        if enabled: self.animate_mode.setChecked(False)
        self.update_timer()

    def toggle_mode(self, enabled):
        if enabled:
            self.play.setChecked(False)
            if self.mode < 0 and self.modes.count(): self.modes.setCurrentRow(0)
        else: self.show_frame()
        self.update_timer()

    def update_timer(self):
        self.timer.start() if (self.play.isChecked() or self.animate_mode.isChecked()) else self.timer.stop()

    def choose_mode(self, index):
        self.mode = index; self.phase = 0
        if index >= 0:
            origin = self.data.get("vibrationalFrameIndex")
            if origin is not None and 0 <= origin < len(self.data["frames"]):
                self.frames.setCurrentIndex(origin)
            self.animate_mode.setChecked(True)

    def tick(self):
        if self.play.isChecked():
            self.trajectory_ticks += 1
            if self.trajectory_ticks % 8 == 0:
                self.frames.setCurrentIndex((self.frame + 1) % len(self.data["frames"]))
        elif self.animate_mode.isChecked() and self.mode >= 0 and self.data["frames"]:
            mode = self.data["modes"][self.mode]
            base = self.data["frames"][self.frame]["atoms"]
            if len(mode["displacements"]) != len(base): return
            self.phase += 0.12; scale = self.amplitude.value() * math.sin(self.phase)
            self.viewport.positions = [[p + scale * d for p, d in zip(atom["position"], displacement)]
                                       for atom, displacement in zip(base, mode["displacements"])]
            self.viewport.upload_needed = True; self.viewport.update()

    def deactivate(self):
        self.play.setChecked(False); self.animate_mode.setChecked(False); self.timer.stop()

    def pick(self, index, additive):
        if index < 0: self.selection = []
        elif additive:
            if index in self.selection: self.selection.remove(index)
            else: self.selection.append(index)
        else: self.selection = [index]
        self.selection = self.selection[-4:]
        self.viewport.selected = self.selection[:]; self.viewport.upload_needed = True; self.viewport.update()
        if 2 <= len(self.selection) <= 4:
            selected = self.selection[:]
            def measured(reply):
                if reply.get("ok") and selected == self.selection:
                    self.measurement.setText(f"Atoms {', '.join(str(i + 1) for i in selected)}: {reply['measurement']:.5f} " + ("Å" if len(selected) == 2 else "°"))
            self.bridge.request("measure", measured, document=self.key, frame=self.frame, indices=selected)
        else: self.measurement.setText("Selected: " + ", ".join(str(i + 1) for i in self.selection))

    def edit_coordinate(self, row, col):
        self.deactivate()
        try:
            if col == 0: self.command("element", atom=row, element=self.coordinates.item(row, col).text())
            else:
                p = [float(self.coordinates.item(row, i).text()) for i in (1, 2, 3)]
                if not all(math.isfinite(v) for v in p): raise ValueError("Use finite coordinates")
                self.command("position", atom=row, position=p)
        except ValueError as error:
            self.window().show_error(str(error)); self.show_frame()

    def delete_atoms(self):
        self.deactivate()
        selected = self.selection[:] or sorted({item.row() for item in self.coordinates.selectedItems()})
        self.command("delete", indices=selected, callback=lambda reply: self.clear_selection(reply))

    def clear_selection(self, reply):
        if reply.get("ok"): self.selection = []; self.viewport.selected = []; self.viewport.upload_needed = True; self.viewport.update()

    def add_atom(self):
        element, ok = QInputDialog.getText(self, "Add atom", "Element symbol or atomic number")
        if ok:
            self.deactivate(); self.command("add", element=element, position=[b.value() for b in self.placement])

    def place_fragment(self):
        self.deactivate(); self.command("fragment", fragment=self.fragment.currentIndex(), position=[b.value() for b in self.placement])

    def attach_fragment(self):
        if len(self.selection) != 1: self.window().show_error("Select one atom for attachment."); return
        self.deactivate(); self.command("fragment", fragment=self.fragment.currentIndex(), atom=self.selection[0])

    def set_internal(self, action):
        count = 2 if action == "distance" else 3
        if len(self.selection) != count: self.window().show_error(f"Select {count} atoms in order."); return
        value, ok = QInputDialog.getDouble(self, "Set " + action, "Distance / Å" if count == 2 else "Angle / degrees", 1.5 if count == 2 else 109.5, 0.00001 if count == 2 else 0, 10000 if count == 2 else 180, 6)
        if ok:
            self.deactivate(); self.command(action, indices=self.selection, value=value)

    def change_style(self, style):
        self.viewport.style = style; self.viewport.upload_needed = True; self.viewport.update()

    def change_labels(self, enabled):
        self.viewport.labels = enabled; self.viewport.update()


class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("ChemViewer — Windows/Linux desktop development")
        self.resize(1180, 780); self.setAcceptDrops(True)
        self.errors = []; self.dialogs_enabled = True
        self.bridge = CoreBridge(self); self.bridge.failed.connect(self.show_error)
        self.tabs = QTabWidget(); self.tabs.setTabsClosable(True); self.tabs.tabCloseRequested.connect(self.close_document)
        self.tabs.currentChanged.connect(self.tab_changed); self.setCentralWidget(self.tabs)
        self.bridge.busyChanged.connect(lambda busy: self.statusBar().showMessage("Working…" if busy else "Ready"))
        file_menu = self.menuBar().addMenu("&File")
        self.action(file_menu, "&New", QKeySequence.New, lambda: self.bridge.request("new", self.opened))
        self.action(file_menu, "&Open…", QKeySequence.Open, self.open_dialog)
        self.action(file_menu, "&Save project…", QKeySequence.Save, self.save_project)
        self.action(file_menu, "Export current XYZ…", None, self.export_xyz)
        self.action(file_menu, "Export trajectory XYZ…", None, lambda: self.export_xyz(all_frames=True))
        self.action(file_menu, "Export PNG…", None, self.export_png)
        self.action(file_menu, "Export energy CSV…", None, self.export_energy)
        self.action(file_menu, "&Close", QKeySequence.Close, lambda: self.close_document(self.tabs.currentIndex()))
        edit = self.menuBar().addMenu("&Edit")
        self.undo_action = self.action(edit, "Undo", QKeySequence.Undo, lambda: self.edit_action("undo"))
        self.redo_action = self.action(edit, "Redo", QKeySequence.Redo, lambda: self.edit_action("redo"))
        self.action(edit, "Copy current XYZ", None, self.copy_xyz)
        toolbar = QToolBar("File"); self.addToolBar(toolbar)
        for act in file_menu.actions()[:3]: toolbar.addAction(act)
        self.bridge.process.started.connect(lambda: self.statusBar().showMessage("Chemistry core connected"))
        self.bridge.start(); self.tab_changed(-1)

    def action(self, menu, title, shortcut, callback):
        action = QAction(title, self)
        if shortcut: action.setShortcut(shortcut)
        action.triggered.connect(callback); menu.addAction(action); return action

    def show_error(self, message):
        self.errors.append(message); self.statusBar().showMessage(message)
        if self.dialogs_enabled: QMessageBox.warning(self, "ChemViewer", message)

    def pane(self):
        return self.tabs.currentWidget()

    def opened(self, reply, path=None):
        if not reply.get("ok"): return
        pane = DocumentPane(self.bridge, reply, path)
        pane.changed.connect(self.refresh_titles)
        self.tabs.setCurrentIndex(self.tabs.addTab(pane, pane.data["title"]))
        self.refresh_titles()

    def open_path(self, path):
        path = str(Path(path).resolve())
        for i in range(self.tabs.count()):
            if self.tabs.widget(i).path == path: self.tabs.setCurrentIndex(i); return
        self.bridge.request("open", lambda reply: self.opened(reply, path), path=path)

    def open_dialog(self):
        paths, _ = QFileDialog.getOpenFileNames(self, "Open chemistry files", "", "Chemistry (*.xyz *.out *.log *.inp *.in *.cvdesktop);;All files (*)")
        for path in paths: self.open_path(path)

    def refresh_titles(self):
        for i in range(self.tabs.count()):
            pane = self.tabs.widget(i)
            self.tabs.setTabText(i, pane.data["title"] + (" *" if pane.dirty else ""))
        self.update_actions()

    def update_actions(self):
        pane = self.pane(); self.undo_action.setEnabled(bool(pane and pane.can_undo)); self.redo_action.setEnabled(bool(pane and pane.can_redo))

    def tab_changed(self, index):
        for i in range(self.tabs.count()):
            if i != index: self.tabs.widget(i).deactivate()
        if hasattr(self, "undo_action"): self.update_actions()

    def edit_action(self, action):
        if self.pane(): self.pane().deactivate(); self.pane().command(action)

    def save_project(self):
        pane = self.pane()
        if not pane: return
        path, _ = QFileDialog.getSaveFileName(self, "Save desktop project", pane.project_path or "structure.cvdesktop", "ChemViewer desktop project (*.cvdesktop)")
        if path:
            def saved(reply):
                if reply.get("ok"): pane.project_path = path
            pane.command("save_project", callback=saved, path=path, overwrite=True)

    def export_xyz(self, checked=False, all_frames=False):
        pane = self.pane()
        if not pane: return
        path, _ = QFileDialog.getSaveFileName(self, "Export equilibrium coordinates", "structure.xyz", "XYZ (*.xyz)")
        if path:
            self.bridge.request("export_xyz", document=pane.key, path=path, frame=None if all_frames else pane.frame, overwrite=True)

    def export_png(self):
        pane = self.pane()
        if not pane: return
        path, _ = QFileDialog.getSaveFileName(self, "Export current view", "molecule.png", "PNG (*.png)")
        if path and not pane.viewport.export_image().save(path, "PNG"): self.show_error("Cannot save PNG to " + path)

    def export_energy(self):
        pane = self.pane()
        if not pane: return
        path, _ = QFileDialog.getSaveFileName(self, "Export source energy values", "energies.csv", "CSV (*.csv)")
        if path:
            try: Path(path).write_bytes(pane.energy_plot.csv().encode("utf-8"))
            except OSError as error: self.show_error(str(error))

    def copy_xyz(self):
        pane = self.pane()
        if pane and pane.data["frames"]: QApplication.clipboard().setText(pane.data["frames"][pane.frame]["xyz"])

    def close_document(self, index):
        if index < 0: return
        pane = self.tabs.widget(index)
        if pane.dirty:
            choice = QMessageBox.question(self, "Unsaved geometry", "Discard unsaved changes to this document?", QMessageBox.Discard | QMessageBox.Cancel, QMessageBox.Cancel)
            if choice != QMessageBox.Discard: return
        pane.closed = True; pane.deactivate(); self.bridge.request("close", document=pane.key)
        self.tabs.removeTab(index); pane.deleteLater()

    def closeEvent(self, event):
        if any(self.tabs.widget(i).dirty for i in range(self.tabs.count())):
            choice = QMessageBox.question(self, "Unsaved geometry", "Discard unsaved changes and quit?", QMessageBox.Discard | QMessageBox.Cancel, QMessageBox.Cancel)
            if choice != QMessageBox.Discard: event.ignore(); return
        for i in range(self.tabs.count()): self.tabs.widget(i).deactivate()
        self.bridge.stop(); event.accept()

    def dragEnterEvent(self, event):
        if event.mimeData().hasUrls() and all(u.isLocalFile() for u in event.mimeData().urls()): event.acceptProposedAction()

    def dropEvent(self, event):
        for url in event.mimeData().urls():
            if url.isLocalFile(): self.open_path(url.toLocalFile())
        event.acceptProposedAction()


def main():
    parser = argparse.ArgumentParser(description="ChemViewer native Qt desktop")
    parser.add_argument("files", nargs="*")
    parser.add_argument("--acceptance-report", help=argparse.SUPPRESS)
    arguments = parser.parse_args()
    configure_graphics(); app = QApplication([sys.argv[0]])
    app.setApplicationName("ChemViewer"); app.setOrganizationName("ChemViewer")
    window = MainWindow(); window.dialogs_enabled = not bool(arguments.acceptance_report); window.show()
    if arguments.acceptance_report:
        if len(arguments.files) != 1: parser.error("Packaged acceptance requires water.xyz")
        from acceptance import run
        QTimer.singleShot(0, lambda: run(window, arguments.files[0], arguments.acceptance_report))
    else:
        for path in arguments.files: QTimer.singleShot(0, lambda p=path: window.open_path(p))
    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
