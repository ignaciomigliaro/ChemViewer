"""ChemViewer Windows-first Qt desktop, visually aligned with the native Mac app."""

import argparse
import math
import sys
from pathlib import Path

from PySide6.QtCore import QSize, Qt, QTimer, Signal, QSignalBlocker
from PySide6.QtGui import QAction, QActionGroup, QColor, QKeySequence, QSurfaceFormat
from PySide6.QtWidgets import (
    QAbstractItemView, QApplication, QButtonGroup, QCheckBox, QComboBox,
    QDoubleSpinBox, QFileDialog, QFormLayout, QFrame, QHBoxLayout, QInputDialog,
    QLabel, QListWidget, QListWidgetItem, QMainWindow, QMessageBox, QPushButton,
    QScrollArea, QSizePolicy, QSplitter, QStackedWidget, QTabBar, QTabWidget,
    QTableWidget, QTableWidgetItem, QTextEdit, QToolButton, QVBoxLayout, QWidget,
)

from bridge import CoreBridge
from plots import ScientificPlot
from theme import apply_theme
from viewport import MoleculeViewport


def configure_graphics():
    fmt = QSurfaceFormat()
    fmt.setRenderableType(QSurfaceFormat.OpenGL)
    fmt.setProfile(QSurfaceFormat.CoreProfile)
    fmt.setVersion(3, 3)
    fmt.setDepthBufferSize(24)
    fmt.setSamples(4)
    QSurfaceFormat.setDefaultFormat(fmt)


class ModeTabBar(QTabBar):
    """Match the fixed tab widths used by the native SwiftUI workspace."""

    def tabSizeHint(self, index):
        return QSize(115 if self.tabText(index) == "Image/Abs" else 100, 39)


class DocumentPane(QWidget):
    changed = Signal()

    def __init__(self, bridge, reply, path=None, parent=None):
        super().__init__(parent)
        self.setObjectName("applicationRoot")
        self.bridge = bridge
        self.key = reply["document"]
        self.path = path
        self.project_path = path if path and path.lower().endswith(".cvdesktop") else None
        self.frame = 0
        self.mode = -1
        self.phase = 0.0
        self.selection = []
        self.closed = False
        self.data = {}
        self.dirty = False
        self.can_undo = False
        self.can_redo = False
        self.timer = QTimer(self)
        self.timer.setInterval(33)
        self.timer.timeout.connect(self.tick)
        self.trajectory_ticks = 0

        self.viewport = MoleculeViewport(self)
        self.viewport.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)
        self.viewport.atomPicked.connect(self.pick)
        self.viewport.renderFailed.connect(lambda message: self.window().show_error(message))

        # Public controls remain stable for automation and accessibility.
        self.frames = QComboBox(self)
        self.frames.setObjectName("frameSelector")
        self.frames.hide()
        self.frames.currentIndexChanged.connect(self.choose_frame)
        self.play = QPushButton("▶ Frames")
        self.play.setObjectName("classicButton")
        self.play.setCheckable(True)
        self.play.toggled.connect(self.play_trajectory)
        self.fit = QPushButton("Fit")
        self.fit.setObjectName("classicButton")
        self.fit.clicked.connect(self.viewport.fit)
        self.style = QComboBox()
        self.style.addItems(["Ball and stick", "Space filling"])
        self.style.currentTextChanged.connect(self.change_style)
        self.labels = QCheckBox("Labels")
        self.labels.toggled.connect(self.change_labels)

        self.image_content = self.build_image_workspace()
        self.coordinates = self.build_coordinate_editor()
        self.energy_plot = ScientificPlot("Geometry index (1-based)", "Energy / Hartree")
        self.abstract = QTextEdit()
        self.abstract.setObjectName("calculationAbstract")
        self.abstract.setReadOnly(True)
        self.abstract_tabs = QTabWidget()
        self.abstract_tabs.addTab(self.abstract, "Summary")
        self.abstract_tabs.addTab(self.energy_plot, "Energy plot")
        self.abstract_panel = QFrame()
        abstract_layout = QVBoxLayout(self.abstract_panel)
        abstract_layout.setContentsMargins(10, 10, 10, 10)
        title = QLabel("Calculation abstract")
        title.setObjectName("sectionTitle")
        abstract_layout.addWidget(title)
        abstract_layout.addWidget(self.abstract_tabs, 1)
        self.source = QTextEdit()
        self.source.setObjectName("sourceView")
        self.source.setReadOnly(True)
        self.source.setFontFamily("Cascadia Mono")

        self.image_page = QWidget()
        self.image_page_layout = QVBoxLayout(self.image_page)
        self.image_page_layout.setContentsMargins(0, 0, 0, 0)
        self.image_page_layout.addWidget(self.image_content)
        self.abstract_page = QWidget()
        self.abstract_page_layout = QVBoxLayout(self.abstract_page)
        self.abstract_page_layout.setContentsMargins(0, 0, 0, 0)
        self.abstract_page_layout.addWidget(self.abstract_panel)
        self.combined_page = QWidget()
        self.combined_layout = QHBoxLayout(self.combined_page)
        self.combined_layout.setContentsMargins(0, 0, 0, 0)
        self.combined_layout.setSpacing(1)

        self.views = QStackedWidget()
        self.mode_tabs = ModeTabBar()
        self.mode_tabs.setObjectName("modeTabs")
        self.mode_tabs.setExpanding(False)
        self.mode_tabs.setDrawBase(False)
        self.mode_tabs.setMaximumWidth(820)
        pages = [
            ("Image", self.image_page),
            ("Abstract", self.abstract_page),
            ("Source", self.source),
            ("Coord", self.coordinates),
            ("Image/Abs", self.combined_page),
            ("ChemRefine", self.unavailable_page(
                "ChemRefine", "Workflow execution and SSH integration are being ported from the validated Mac workspace.")),
            ("Draw", self.unavailable_page(
                "Draw", "The native 2D chemical drawing workspace is not yet connected on Windows.")),
            ("BOS-TMC", self.unavailable_page(
                "BOS-TMC", "The catalog screen remains available on Mac while its desktop port is completed.")),
        ]
        for name, page in pages:
            self.mode_tabs.addTab(name)
            self.views.addWidget(page)
        self.mode_tabs.currentChanged.connect(self.change_view)

        self.geometry_list = QListWidget()
        self.geometry_list.setObjectName("geometryList")
        self.geometry_list.setMinimumHeight(58)
        self.geometry_list.setMaximumHeight(260)
        self.geometry_list.setSizePolicy(QSizePolicy.Preferred, QSizePolicy.Fixed)
        self.geometry_list.currentRowChanged.connect(self.select_geometry_row)
        self.modes = QListWidget()
        self.modes.setObjectName("normalModes")
        self.modes.currentRowChanged.connect(self.choose_mode)
        self.amplitude = QDoubleSpinBox()
        self.amplitude.setRange(0, 3)
        self.amplitude.setSingleStep(0.1)
        self.amplitude.setValue(0.5)
        self.animate_mode = QCheckBox("Animate mode (illustrative)")
        self.animate_mode.toggled.connect(self.toggle_mode)

        self.fragment = QComboBox()
        self.bridge.request("hello", self.fragments_received)
        self.placement = [QDoubleSpinBox() for _ in range(3)]
        self.builder = self.build_builder()
        self.explorer = self.result_explorer()

        self.workspace_split = QSplitter()
        self.workspace_split.addWidget(self.explorer)
        self.workspace_split.addWidget(self.views)
        self.workspace_split.addWidget(self.builder)
        self.workspace_split.setStretchFactor(0, 0)
        self.workspace_split.setStretchFactor(1, 1)
        self.workspace_split.setStretchFactor(2, 0)
        self.workspace_split.setSizes([270, 920, 0])

        self.warning_banner = QLabel()
        self.warning_banner.setObjectName("warningBanner")
        self.warning_banner.setWordWrap(True)
        self.warning_banner.hide()
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(0)
        layout.addWidget(self.warning_banner)
        layout.addWidget(self.mode_tabs)
        layout.addWidget(self.classic_toolbar())
        layout.addWidget(self.workspace_split, 1)
        self.apply(reply, fit=True)

    def classic_button(self, text, tooltip, callback, checkable=False):
        button = QToolButton()
        button.setObjectName("classicToolButton")
        button.setText(text)
        button.setToolTip(tooltip)
        button.setAccessibleName(tooltip)
        button.setCheckable(checkable)
        (button.toggled if checkable else button.clicked).connect(callback)
        return button

    def classic_toolbar(self):
        bar = QFrame()
        bar.setObjectName("classicToolbar")
        row = QHBoxLayout(bar)
        row.setContentsMargins(8, 5, 8, 5)
        row.setSpacing(5)
        row.addWidget(self.classic_button("📂", "Open chemistry file", lambda: self.window().open_dialog()))
        row.addWidget(self.classic_button("📷", "Export PNG image", lambda: self.window().export_png()))
        row.addSpacing(5)
        row.addWidget(self.classic_button("Build", "Show Build & Edit panel", self.toggle_builder, True))
        row.addWidget(self.classic_button("+", "Add atom", self.add_atom))
        explorer = self.classic_button("⌕", "Show result explorer", self.toggle_explorer, True)
        explorer.setChecked(True)
        row.addWidget(explorer)
        row.addWidget(self.fit)
        row.addWidget(self.classic_button("↶", "Undo coordinate edit", lambda: self.window().edit_action("undo")))
        row.addWidget(self.classic_button("↷", "Redo coordinate edit", lambda: self.window().edit_action("redo")))
        row.addWidget(self.classic_button("⇩", "Export XYZ coordinates", lambda: self.window().export_xyz()))
        row.addSpacing(5)

        self.label_group = QButtonGroup(self)
        self.label_group.setExclusive(True)
        for text, mode in [("H", "Elements"), ("1", "Numbers"), ("C1", "Element + number"), ("●", "None")]:
            button = self.classic_button(
                text, "Atom captions: " + mode,
                lambda checked, label_mode=mode: self.set_label_mode(label_mode) if checked else None, True)
            self.label_group.addButton(button)
            row.addWidget(button)
            if mode == "None":
                button.setChecked(True)

        row.addSpacing(5)
        row.addWidget(self.play)
        self.mode_play = self.classic_button(
            "▶ Mode", "Animate selected frequency", lambda checked: self.animate_mode.setChecked(checked), True)
        row.addWidget(self.mode_play)
        vectors = self.classic_button("Vectors", "Displacement vectors are not yet ported", lambda: None)
        vectors.setEnabled(False)
        row.addWidget(vectors)
        row.addWidget(self.classic_button("Energy", "Show calculation energy plot", self.show_energy))
        spectrum = self.classic_button("Spectrum", "Spectrum presentation is not yet ported", lambda: None)
        spectrum.setEnabled(False)
        row.addWidget(spectrum)
        row.addWidget(self.style)
        row.addStretch()
        brand = QLabel("ChemViewer")
        brand.setObjectName("secondaryText")
        row.addWidget(brand)

        scroll = QScrollArea()
        scroll.setWidget(bar)
        scroll.setWidgetResizable(True)
        scroll.setFrameShape(QFrame.NoFrame)
        scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarAsNeeded)
        scroll.setVerticalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        scroll.setFixedHeight(45)
        return scroll

    def build_image_workspace(self):
        content = QFrame()
        layout = QVBoxLayout(content)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(0)
        viewer_row = QHBoxLayout()
        viewer_row.setContentsMargins(0, 0, 0, 0)
        viewer_row.setSpacing(0)
        viewer_row.addWidget(self.viewport, 1)
        viewer_row.addWidget(self.camera_rail())
        layout.addLayout(viewer_row, 1)

        inspector = QFrame()
        inspector.setObjectName("selectionInspector")
        inspector.setFixedHeight(140)
        inspector_layout = QVBoxLayout(inspector)
        inspector_layout.setContentsMargins(10, 8, 10, 8)
        inspector_layout.setSpacing(6)
        header = QHBoxLayout()
        self.selection_title = QLabel("Selection (0)")
        self.selection_title.setObjectName("sectionTitle")
        header.addWidget(self.selection_title)
        header.addStretch()
        clear = QPushButton("Clear")
        clear.setObjectName("classicButton")
        clear.clicked.connect(lambda: self.pick(-1, False))
        header.addWidget(clear)
        inspector_layout.addLayout(header)
        self.measurement = QLabel("Click atoms to measure; Ctrl-click adds to the selection.")
        self.measurement.setObjectName("measurementValue")
        inspector_layout.addWidget(self.measurement)
        hint = QLabel("Select two, three or four atoms for distance, angle or signed dihedral. Selection never resizes the viewport.")
        hint.setObjectName("secondaryText")
        inspector_layout.addWidget(hint)
        inspector_layout.addStretch()
        layout.addWidget(inspector)

        status = QFrame()
        status.setObjectName("statusBar")
        status.setFixedHeight(30)
        status_layout = QHBoxLayout(status)
        status_layout.setContentsMargins(10, 3, 10, 3)
        self.document_status = QLabel()
        self.document_status.setObjectName("secondaryText")
        status_layout.addWidget(self.document_status)
        status_layout.addStretch()
        interaction = QLabel("Drag to rotate • Shift-drag to pan • Ctrl-click adds • scroll to zoom")
        interaction.setObjectName("secondaryText")
        status_layout.addWidget(interaction)
        layout.addWidget(status)
        return content

    def camera_rail(self):
        rail = QFrame()
        rail.setObjectName("cameraRail")
        rail.setFixedWidth(38)
        layout = QVBoxLayout(rail)
        layout.setContentsMargins(5, 6, 5, 6)
        layout.setSpacing(5)
        for text, tooltip, action in [
            ("↶", "Rotate left", "left"), ("↷", "Rotate right", "right"),
            ("↑", "Rotate up", "up"), ("↓", "Rotate down", "down"),
            ("⟲", "Roll left", "roll_left"), ("⟳", "Roll right", "roll_right"),
            ("⇧", "Pan up", "pan_up"), ("⇩", "Pan down", "pan_down"),
            ("＋", "Zoom in", "zoom_in"), ("−", "Zoom out", "zoom_out"),
            ("◎", "Fit and center", "fit"),
        ]:
            layout.addWidget(self.classic_button(text, tooltip, lambda selected=action: self.viewport.nudge(selected)))
        layout.addStretch()
        return rail

    def build_coordinate_editor(self):
        table = QTableWidget(0, 4)
        table.setObjectName("coordinates")
        table.setHorizontalHeaderLabels(["Element", "X / Å", "Y / Å", "Z / Å"])
        table.setSelectionBehavior(QAbstractItemView.SelectRows)
        table.setAlternatingRowColors(True)
        table.horizontalHeader().setStretchLastSection(True)
        table.cellChanged.connect(self.edit_coordinate)
        return table

    def result_explorer(self):
        panel = QFrame()
        panel.setObjectName("resultExplorer")
        panel.setMinimumWidth(230)
        panel.setMaximumWidth(380)
        layout = QVBoxLayout(panel)
        layout.setContentsMargins(9, 10, 9, 8)
        layout.setSpacing(5)
        self.explorer_title = QLabel("Untitled")
        self.explorer_title.setObjectName("sectionTitle")
        self.explorer_title.setWordWrap(True)
        layout.addWidget(self.explorer_title)
        geometries = QLabel("GEOMETRIES")
        geometries.setObjectName("sectionCaption")
        layout.addWidget(geometries)
        layout.addWidget(self.geometry_list, 2)
        frequencies = QLabel("FREQUENCIES (cm⁻¹)")
        frequencies.setObjectName("sectionCaption")
        layout.addWidget(frequencies)
        layout.addWidget(self.modes, 2)
        mode_controls = QFormLayout()
        mode_controls.addRow("Amplitude", self.amplitude)
        mode_controls.addRow(self.animate_mode)
        layout.addLayout(mode_controls)
        nav = QHBoxLayout()
        previous = QPushButton("▲")
        previous.setObjectName("classicButton")
        previous.clicked.connect(lambda: self.frames.setCurrentIndex(max(0, self.frame - 1)))
        self.frame_count = QLabel("0 / 0")
        self.frame_count.setAlignment(Qt.AlignCenter)
        following = QPushButton("▼")
        following.setObjectName("classicButton")
        following.clicked.connect(lambda: self.frames.setCurrentIndex(min(self.frames.count() - 1, self.frame + 1)))
        nav.addWidget(previous)
        nav.addWidget(self.frame_count, 1)
        nav.addWidget(following)
        layout.addLayout(nav)
        return panel

    def build_builder(self):
        panel = QFrame()
        panel.setObjectName("builderPanel")
        panel.setMinimumWidth(285)
        panel.setMaximumWidth(340)
        layout = QVBoxLayout(panel)
        layout.setContentsMargins(12, 10, 12, 10)
        title = QLabel("Build & Edit")
        title.setObjectName("sectionTitle")
        layout.addWidget(title)
        caption = QLabel("Place a fragment at Cartesian coordinates or attach it to one selected atom.")
        caption.setObjectName("secondaryText")
        caption.setWordWrap(True)
        layout.addWidget(caption)
        form = QFormLayout()
        form.addRow("Fragment", self.fragment)
        for label, box in zip(["Place X / Å", "Place Y / Å", "Place Z / Å"], self.placement):
            box.setRange(-100000, 100000)
            box.setDecimals(6)
            form.addRow(label, box)
        layout.addLayout(form)
        for text, callback in [
            ("Place fragment", self.place_fragment),
            ("Attach to selected atom", self.attach_fragment),
            ("Add atom…", self.add_atom),
            ("Delete selected atoms", self.delete_atoms),
            ("Set distance…", lambda: self.set_internal("distance")),
            ("Set angle…", lambda: self.set_internal("angle")),
        ]:
            button = QPushButton(text)
            button.setObjectName("classicButton")
            button.clicked.connect(callback)
            layout.addWidget(button)
        layout.addStretch()
        panel.hide()
        return panel

    def unavailable_page(self, title, message):
        page = QWidget()
        layout = QVBoxLayout(page)
        layout.addStretch()
        heading = QLabel(title)
        heading.setObjectName("sectionTitle")
        heading.setAlignment(Qt.AlignCenter)
        copy = QLabel(message)
        copy.setObjectName("secondaryText")
        copy.setWordWrap(True)
        copy.setAlignment(Qt.AlignCenter)
        copy.setMaximumWidth(560)
        layout.addWidget(heading)
        layout.addWidget(copy, alignment=Qt.AlignCenter)
        layout.addStretch()
        return page

    def change_view(self, index):
        if index == 4:
            self.combined_layout.addWidget(self.image_content, 3)
            self.combined_layout.addWidget(self.abstract_panel, 2)
        else:
            self.image_page_layout.addWidget(self.image_content)
            self.abstract_page_layout.addWidget(self.abstract_panel)
        self.views.setCurrentIndex(max(0, index))

    def show_energy(self):
        self.mode_tabs.setCurrentIndex(1)
        self.abstract_tabs.setCurrentIndex(1)

    def toggle_builder(self, visible):
        self.builder.setVisible(visible)
        if visible:
            self.workspace_split.setSizes([270 if self.explorer.isVisible() else 0, 800, 310])

    def toggle_explorer(self, visible):
        self.explorer.setVisible(visible)
        if visible:
            self.workspace_split.setSizes([270, 900, 310 if self.builder.isVisible() else 0])

    def set_label_mode(self, mode):
        self.viewport.label_mode = mode
        self.viewport.labels = mode != "None"
        with QSignalBlocker(self.labels):
            self.labels.setChecked(self.viewport.labels)
        self.viewport.update()

    def fragments_received(self, reply):
        if not self.closed and reply.get("ok"):
            self.fragment.addItems(reply.get("fragments", []))

    def command(self, action, callback=None, **arguments):
        def complete(reply):
            if self.closed:
                return
            if not reply.get("ok"):
                self.show_frame()
            if reply.get("ok") and "data" in reply:
                self.apply(reply)
            if callback:
                callback(reply)
        self.bridge.request(action, complete, document=self.key, frame=self.frame, **arguments)

    def apply(self, reply, fit=False):
        self.data = reply["data"]
        self.dirty = reply["dirty"]
        self.can_undo = reply["canUndo"]
        self.can_redo = reply["canRedo"]
        frames = self.data["frames"]
        self.frame = min(self.frame, max(0, len(frames) - 1))
        with QSignalBlocker(self.frames), QSignalBlocker(self.geometry_list):
            self.frames.clear()
            self.geometry_list.clear()
            for i, frame in enumerate(frames):
                energy = frame.get("energyHartree")
                suffix = f"  {energy:.12g} Eh" if energy is not None else "  energy unavailable"
                text = f"Geometry {i + 1}" + suffix
                self.frames.addItem(text)
                self.geometry_list.addItem(text)
            self.frames.setCurrentIndex(self.frame if frames else -1)
            self.geometry_list.setCurrentRow(self.frame if frames else -1)
        self.geometry_list.setFixedHeight(min(260, max(58, len(frames) * 29 + 8)))
        with QSignalBlocker(self.modes):
            self.modes.clear()
            for mode in self.data["modes"]:
                item = QListWidgetItem(f"Mode {mode['index']}     {mode['frequencyCM1']:.2f}")
                if mode["frequencyCM1"] < 0:
                    item.setText(item.text() + "  imaginary")
                    item.setForeground(QColor("#c62828"))
                self.modes.addItem(item)
            self.mode = min(self.mode, len(self.data["modes"]) - 1)
            self.modes.setCurrentRow(self.mode)
        if not self.data["modes"]:
            self.animate_mode.setChecked(False)
        self.energy_plot.set_points([(i + 1, frame.get("energyHartree")) for i, frame in enumerate(frames)])
        self.source.setPlainText(self.data["source"])
        summary = [
            self.data["title"], self.data["sourceFormat"], "Coordinates: Å; energy: Hartree",
            "Charge: " + str(self.data.get("charge", "unavailable")),
            "Multiplicity: " + str(self.data.get("multiplicity", "unavailable")),
        ]
        summary += self.data.get("warnings", [])
        for mode in self.data["modes"]:
            summary.append(
                f"Mode {mode['index']}: {mode['frequencyCM1']} cm⁻¹; "
                f"IR intensity {mode.get('infraredIntensity', 'unavailable')}; "
                f"Raman activity {mode.get('ramanActivity', 'unavailable')}")
        self.abstract.setPlainText("\n".join(summary))
        warnings = self.data.get("warnings", [])
        self.warning_banner.setText("ⓘ  " + "  ".join(warnings))
        self.warning_banner.setVisible(bool(warnings))
        self.explorer_title.setText(self.data["title"])
        self.show_frame(fit)
        self.changed.emit()

    def show_frame(self, fit=False):
        frames = self.data["frames"]
        frame = frames[self.frame] if frames else None
        self.viewport.set_frame(frame, fit=fit)
        self.viewport.selected = self.selection[:]
        with QSignalBlocker(self.coordinates):
            self.coordinates.setRowCount(len(frame["atoms"]) if frame else 0)
            for row, atom in enumerate(frame["atoms"] if frame else []):
                for col, value in enumerate([atom["element"], *atom["position"]]):
                    self.coordinates.setItem(row, col, QTableWidgetItem(str(value)))
        with QSignalBlocker(self.geometry_list):
            self.geometry_list.setCurrentRow(self.frame if frame else -1)
        self.play.setEnabled(len(frames) > 1)
        self.frame_count.setText(f"{self.frame + 1 if frames else 0} / {len(frames)}")
        atoms = len(frame["atoms"]) if frame else 0
        self.document_status.setText(
            f"{self.data.get('sourceFormat', '')}    Frame {self.frame + 1 if frames else 0}/{len(frames)}    {atoms} atoms")

    def select_geometry_row(self, index):
        if index >= 0 and index != self.frames.currentIndex():
            self.frames.setCurrentIndex(index)

    def choose_frame(self, index):
        if index < 0:
            return
        self.animate_mode.setChecked(False)
        self.frame = index
        self.selection = []
        self.show_frame()
        self.update_selection_text()

    def play_trajectory(self, enabled):
        self.play.setText("Ⅱ Frames" if enabled else "▶ Frames")
        if enabled:
            self.animate_mode.setChecked(False)
        self.update_timer()

    def toggle_mode(self, enabled):
        with QSignalBlocker(self.mode_play):
            self.mode_play.setChecked(enabled)
        if enabled:
            self.play.setChecked(False)
            if self.mode < 0 and self.modes.count():
                self.modes.setCurrentRow(0)
        else:
            self.show_frame()
        self.update_timer()

    def update_timer(self):
        self.timer.start() if (self.play.isChecked() or self.animate_mode.isChecked()) else self.timer.stop()

    def choose_mode(self, index):
        self.mode = index
        self.phase = 0
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
            if len(mode["displacements"]) != len(base):
                return
            self.phase += 0.12
            scale = self.amplitude.value() * math.sin(self.phase)
            self.viewport.positions = [
                [p + scale * d for p, d in zip(atom["position"], displacement)]
                for atom, displacement in zip(base, mode["displacements"])
            ]
            self.viewport.upload_needed = True
            self.viewport.update()

    def deactivate(self):
        self.play.setChecked(False)
        self.animate_mode.setChecked(False)
        self.timer.stop()

    def pick(self, index, additive):
        if index < 0:
            self.selection = []
        elif additive:
            if index in self.selection:
                self.selection.remove(index)
            else:
                self.selection.append(index)
        else:
            self.selection = [index]
        self.selection = self.selection[-4:]
        self.viewport.selected = self.selection[:]
        self.viewport.upload_needed = True
        self.viewport.update()
        self.update_selection_text()
        if 2 <= len(self.selection) <= 4:
            selected = self.selection[:]

            def measured(reply):
                if reply.get("ok") and selected == self.selection:
                    unit = "Å" if len(selected) == 2 else "°"
                    self.measurement.setText(
                        f"Atoms {', '.join(str(i + 1) for i in selected)}: {reply['measurement']:.5f} {unit}")
            self.bridge.request("measure", measured, document=self.key, frame=self.frame, indices=selected)

    def update_selection_text(self):
        self.selection_title.setText(f"Selection ({len(self.selection)})")
        if not self.selection:
            self.measurement.setText("Click atoms to measure; Ctrl-click adds to the selection.")
        elif len(self.selection) == 1:
            self.measurement.setText("Selected atom: " + str(self.selection[0] + 1))

    def edit_coordinate(self, row, col):
        self.deactivate()
        try:
            if col == 0:
                self.command("element", atom=row, element=self.coordinates.item(row, col).text())
            else:
                position = [float(self.coordinates.item(row, index).text()) for index in (1, 2, 3)]
                if not all(math.isfinite(value) for value in position):
                    raise ValueError("Use finite coordinates")
                self.command("position", atom=row, position=position)
        except ValueError as error:
            self.window().show_error(str(error))
            self.show_frame()

    def delete_atoms(self):
        self.deactivate()
        selected = self.selection[:] or sorted({item.row() for item in self.coordinates.selectedItems()})
        self.command("delete", indices=selected, callback=self.clear_selection)

    def clear_selection(self, reply):
        if reply.get("ok"):
            self.selection = []
            self.viewport.selected = []
            self.viewport.upload_needed = True
            self.viewport.update()
            self.update_selection_text()

    def add_atom(self):
        element, ok = QInputDialog.getText(self, "Add atom", "Element symbol or atomic number")
        if ok:
            self.deactivate()
            self.command("add", element=element, position=[box.value() for box in self.placement])

    def place_fragment(self):
        self.deactivate()
        self.command("fragment", fragment=self.fragment.currentIndex(), position=[box.value() for box in self.placement])

    def attach_fragment(self):
        if len(self.selection) != 1:
            self.window().show_error("Select one atom for attachment.")
            return
        self.deactivate()
        self.command("fragment", fragment=self.fragment.currentIndex(), atom=self.selection[0])

    def set_internal(self, action):
        count = 2 if action == "distance" else 3
        if len(self.selection) != count:
            self.window().show_error(f"Select {count} atoms in order.")
            return
        value, ok = QInputDialog.getDouble(
            self, "Set " + action, "Distance / Å" if count == 2 else "Angle / degrees",
            1.5 if count == 2 else 109.5, 0.00001 if count == 2 else 0,
            10000 if count == 2 else 180, 6)
        if ok:
            self.deactivate()
            self.command(action, indices=self.selection, value=value)

    def change_style(self, style):
        self.viewport.style = style
        self.viewport.upload_needed = True
        self.viewport.update()

    def change_labels(self, enabled):
        self.viewport.labels = enabled
        if enabled and self.viewport.label_mode == "None":
            self.viewport.label_mode = "Element + number"
        self.viewport.update()


class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("ChemViewer")
        self.resize(1440, 900)
        self.setMinimumSize(980, 640)
        self.setAcceptDrops(True)
        self.errors = []
        self.dialogs_enabled = True
        self.bridge = CoreBridge(self)
        self.bridge.failed.connect(self.show_error)

        self.tabs = QTabWidget()
        self.tabs.setObjectName("documentTabs")
        self.tabs.setDocumentMode(True)
        self.tabs.setMovable(True)
        self.tabs.setTabsClosable(True)
        self.tabs.tabCloseRequested.connect(self.close_document)
        self.tabs.currentChanged.connect(self.tab_changed)
        self.central = QStackedWidget()
        self.welcome = self.welcome_page()
        self.central.addWidget(self.welcome)
        self.central.addWidget(self.tabs)
        self.setCentralWidget(self.central)

        self.build_menus()
        self.bridge.busyChanged.connect(
            lambda busy: self.statusBar().showMessage("Working…" if busy else "Ready"))
        self.bridge.process.started.connect(
            lambda: self.statusBar().showMessage("Chemistry core connected"))
        self.bridge.start()
        self.tab_changed(-1)

    def welcome_page(self):
        page = QWidget()
        layout = QVBoxLayout(page)
        layout.addStretch()
        symbol = QLabel("⚛")
        symbol.setAlignment(Qt.AlignCenter)
        symbol.setStyleSheet("font-size: 72px; color: #6b6f76;")
        title = QLabel("ChemViewer")
        title.setAlignment(Qt.AlignCenter)
        title.setStyleSheet("font-size: 30px; font-weight: 600;")
        subtitle = QLabel("Molecular structures and computational-chemistry calculations")
        subtitle.setObjectName("secondaryText")
        subtitle.setAlignment(Qt.AlignCenter)
        new = QPushButton("New molecule / Build fragments")
        new.setObjectName("classicButton")
        new.setMaximumWidth(250)
        new.clicked.connect(lambda: self.bridge.request("new", self.opened))
        opened = QPushButton("Open chemistry file…")
        opened.setObjectName("classicButton")
        opened.setMaximumWidth(250)
        opened.clicked.connect(self.open_dialog)
        layout.addWidget(symbol)
        layout.addWidget(title)
        layout.addWidget(subtitle)
        layout.addSpacing(12)
        layout.addWidget(new, alignment=Qt.AlignCenter)
        layout.addWidget(opened, alignment=Qt.AlignCenter)
        layout.addStretch()
        return page

    def build_menus(self):
        file_menu = self.menuBar().addMenu("&File")
        self.action(file_menu, "&New", QKeySequence.New, lambda: self.bridge.request("new", self.opened))
        self.action(file_menu, "&Open…", QKeySequence.Open, self.open_dialog)
        self.action(file_menu, "&Save project…", QKeySequence.Save, self.save_project)
        file_menu.addSeparator()
        self.action(file_menu, "Export current XYZ…", None, self.export_xyz)
        self.action(file_menu, "Export trajectory XYZ…", None, lambda: self.export_xyz(all_frames=True))
        self.action(file_menu, "Export PNG…", None, self.export_png)
        self.action(file_menu, "Export energy CSV…", None, self.export_energy)
        file_menu.addSeparator()
        self.action(file_menu, "&Close", QKeySequence.Close, lambda: self.close_document(self.tabs.currentIndex()))

        edit = self.menuBar().addMenu("&Edit")
        self.undo_action = self.action(edit, "Undo", QKeySequence.Undo, lambda: self.edit_action("undo"))
        self.redo_action = self.action(edit, "Redo", QKeySequence.Redo, lambda: self.edit_action("redo"))
        edit.addSeparator()
        self.action(edit, "Copy current XYZ", None, self.copy_xyz)

        view = self.menuBar().addMenu("&View")
        for title, shortcut, index in [
            ("Image", "Ctrl+1", 0), ("Abstract", "Ctrl+2", 1), ("Source", "Ctrl+3", 2),
            ("Coordinates", "Ctrl+4", 3), ("Image / Abstract", "Ctrl+5", 4),
        ]:
            self.action(view, title, QKeySequence(shortcut), lambda checked=False, selected=index: self.select_mode(selected))
        view.addSeparator()
        self.action(view, "Result Explorer", None, lambda: self.toggle_current("explorer"))
        self.action(view, "Build & Edit Panel", None, lambda: self.toggle_current("builder"))

        display = self.menuBar().addMenu("&Display")
        style_group = QActionGroup(self)
        for name in ("Ball and stick", "Space filling"):
            action = self.action(display, name, None, lambda checked=False, selected=name: self.set_display_style(selected))
            action.setCheckable(True)
            action.setChecked(name == "Ball and stick")
            style_group.addAction(action)
        tools = self.menuBar().addMenu("&Tools")
        self.action(tools, "Fit and Center", None, lambda: self.pane().viewport.fit() if self.pane() else None)
        self.action(tools, "Energy Landscape", None, lambda: self.pane().show_energy() if self.pane() else None)
        compute = self.menuBar().addMenu("&Compute")
        self.action(compute, "ChemRefine…", None, lambda: self.select_mode(5))
        help_menu = self.menuBar().addMenu("&Help")
        self.action(help_menu, "About ChemViewer", None, self.about)

    def action(self, menu, title, shortcut, callback):
        action = QAction(title, self)
        if shortcut:
            action.setShortcut(shortcut)
        action.triggered.connect(callback)
        menu.addAction(action)
        return action

    def about(self):
        QMessageBox.information(
            self, "About ChemViewer",
            "ChemViewer 0.12.1 desktop development\n\n"
            "Shared scientific parsing and geometry algorithms with the native Apple Silicon application.")

    def show_error(self, message):
        self.errors.append(message)
        self.statusBar().showMessage(message)
        if self.dialogs_enabled:
            QMessageBox.warning(self, "ChemViewer", message)

    def pane(self):
        return self.tabs.currentWidget() if self.tabs.count() else None

    def opened(self, reply, path=None):
        if not reply.get("ok"):
            return
        pane = DocumentPane(self.bridge, reply, path)
        pane.changed.connect(self.refresh_titles)
        self.tabs.setCurrentIndex(self.tabs.addTab(pane, pane.data["title"]))
        self.central.setCurrentWidget(self.tabs)
        self.refresh_titles()

    def open_path(self, path):
        path = str(Path(path).resolve())
        for index in range(self.tabs.count()):
            if self.tabs.widget(index).path == path:
                self.tabs.setCurrentIndex(index)
                return
        self.bridge.request("open", lambda reply: self.opened(reply, path), path=path)

    def open_dialog(self):
        paths, _ = QFileDialog.getOpenFileNames(
            self, "Open chemistry files", "",
            "Chemistry (*.xyz *.out *.log *.inp *.in *.cvdesktop);;All files (*)")
        for path in paths:
            self.open_path(path)

    def refresh_titles(self):
        for index in range(self.tabs.count()):
            pane = self.tabs.widget(index)
            self.tabs.setTabText(index, pane.data["title"] + (" •" if pane.dirty else ""))
        self.update_actions()

    def update_actions(self):
        pane = self.pane()
        self.undo_action.setEnabled(bool(pane and pane.can_undo))
        self.redo_action.setEnabled(bool(pane and pane.can_redo))

    def tab_changed(self, index):
        for position in range(self.tabs.count()):
            if position != index:
                self.tabs.widget(position).deactivate()
        if hasattr(self, "undo_action"):
            self.update_actions()

    def select_mode(self, index):
        if self.pane():
            self.pane().mode_tabs.setCurrentIndex(index)

    def toggle_current(self, target):
        pane = self.pane()
        if not pane:
            return
        widget = getattr(pane, target)
        getattr(pane, "toggle_" + target)(not widget.isVisible())

    def set_display_style(self, name):
        if self.pane():
            self.pane().style.setCurrentText(name)

    def edit_action(self, action):
        if self.pane():
            self.pane().deactivate()
            self.pane().command(action)

    def save_project(self):
        pane = self.pane()
        if not pane:
            return
        path, _ = QFileDialog.getSaveFileName(
            self, "Save desktop project", pane.project_path or "structure.cvdesktop",
            "ChemViewer desktop project (*.cvdesktop)")
        if path:
            def saved(reply):
                if reply.get("ok"):
                    pane.project_path = path
            pane.command("save_project", callback=saved, path=path, overwrite=True)

    def export_xyz(self, checked=False, all_frames=False):
        pane = self.pane()
        if not pane:
            return
        path, _ = QFileDialog.getSaveFileName(
            self, "Export equilibrium coordinates", "structure.xyz", "XYZ (*.xyz)")
        if path:
            self.bridge.request(
                "export_xyz", document=pane.key, path=path,
                frame=None if all_frames else pane.frame, overwrite=True)

    def export_png(self):
        pane = self.pane()
        if not pane:
            return
        path, _ = QFileDialog.getSaveFileName(
            self, "Export current view", "molecule.png", "PNG (*.png)")
        if path and not pane.viewport.export_image().save(path, "PNG"):
            self.show_error("Cannot save PNG to " + path)

    def export_energy(self):
        pane = self.pane()
        if not pane:
            return
        path, _ = QFileDialog.getSaveFileName(
            self, "Export source energy values", "energies.csv", "CSV (*.csv)")
        if path:
            try:
                Path(path).write_bytes(pane.energy_plot.csv().encode("utf-8"))
            except OSError as error:
                self.show_error(str(error))

    def copy_xyz(self):
        pane = self.pane()
        if pane and pane.data["frames"]:
            QApplication.clipboard().setText(pane.data["frames"][pane.frame]["xyz"])

    def close_document(self, index):
        if index < 0:
            return
        pane = self.tabs.widget(index)
        if pane.dirty:
            choice = QMessageBox.question(
                self, "Unsaved geometry", "Discard unsaved changes to this document?",
                QMessageBox.Discard | QMessageBox.Cancel, QMessageBox.Cancel)
            if choice != QMessageBox.Discard:
                return
        pane.closed = True
        pane.deactivate()
        self.bridge.request("close", document=pane.key)
        self.tabs.removeTab(index)
        pane.deleteLater()
        if not self.tabs.count():
            self.central.setCurrentWidget(self.welcome)

    def closeEvent(self, event):
        if any(self.tabs.widget(index).dirty for index in range(self.tabs.count())):
            choice = QMessageBox.question(
                self, "Unsaved geometry", "Discard unsaved changes and quit?",
                QMessageBox.Discard | QMessageBox.Cancel, QMessageBox.Cancel)
            if choice != QMessageBox.Discard:
                event.ignore()
                return
        for index in range(self.tabs.count()):
            self.tabs.widget(index).deactivate()
        self.bridge.stop()
        event.accept()

    def dragEnterEvent(self, event):
        if event.mimeData().hasUrls() and all(url.isLocalFile() for url in event.mimeData().urls()):
            event.acceptProposedAction()

    def dropEvent(self, event):
        for url in event.mimeData().urls():
            if url.isLocalFile():
                self.open_path(url.toLocalFile())
        event.acceptProposedAction()


def main():
    parser = argparse.ArgumentParser(description="ChemViewer native Qt desktop")
    parser.add_argument("files", nargs="*")
    parser.add_argument("--acceptance-report", help=argparse.SUPPRESS)
    arguments = parser.parse_args()
    configure_graphics()
    app = QApplication([sys.argv[0]])
    app.setApplicationName("ChemViewer")
    app.setOrganizationName("ChemViewer")
    apply_theme(app)
    window = MainWindow()
    window.dialogs_enabled = not bool(arguments.acceptance_report)
    window.show()
    if arguments.acceptance_report:
        if len(arguments.files) != 1:
            parser.error("Packaged acceptance requires water.xyz")
        from acceptance import run
        QTimer.singleShot(0, lambda: run(window, arguments.files[0], arguments.acceptance_report))
    else:
        for path in arguments.files:
            QTimer.singleShot(0, lambda file_path=path: window.open_path(file_path))
    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
