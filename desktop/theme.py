"""Qt translation of the light SwiftUI/AppKit ChemViewer appearance.

Values in this file follow ContentView, FileWorkspaceViews and
ClassicControls.  They are compatibility constants, not a separate Windows
design language.
"""

from PySide6.QtGui import QColor, QPalette


ACCENT = "#0a84ff"
WINDOW = "#ececec"
CONTROL = "#f4f4f4"
CANVAS = "#ffffff"
TEXT = "#000000"
SECONDARY = "#6b6f76"
HAIRLINE = "#b8b8b8"


STYLESHEET = f"""
QWidget {{
    color: {TEXT};
    font-family: "Segoe UI", sans-serif;
    font-size: 13px;
}}
QMainWindow, QWidget#applicationRoot {{ background: {WINDOW}; }}
QMenuBar {{
    background: white;
    border-bottom: 1px solid #d7d7d7;
    padding: 4px 12px;
    spacing: 2px;
    font-size: 17px;
}}
QMenuBar::item {{ padding: 3px 9px; background: transparent; }}
QMenuBar::item:selected, QMenu::item:selected {{ background: #dcecff; color: #111; }}
QMenu {{ background: #fbfbfb; border: 1px solid #9f9f9f; padding: 4px; font-size: 13px; }}
QMenu::item {{ padding: 5px 28px 5px 10px; }}

QTabWidget#documentTabs::pane {{ border: 0; background: {WINDOW}; }}
QTabWidget#documentTabs QTabBar {{ background: {WINDOW}; }}
QTabWidget#documentTabs QTabBar::tab {{
    min-width: 125px;
    min-height: 19px;
    padding: 8px 10px;
    background: {CONTROL};
    border: 0;
    border-right: 1px solid #c8c8c8;
}}
QTabWidget#documentTabs QTabBar::tab:selected {{
    background: {CANVAS};
    border-bottom: 2px solid {ACCENT};
}}
QTabWidget#documentTabs QTabBar::close-button {{ margin-left: 7px; }}

QTabBar#modeTabs {{ background: {WINDOW}; }}
QTabBar#modeTabs::tab {{
    min-width: 92px;
    max-width: 108px;
    min-height: 30px;
    padding: 1px 9px;
    margin: 4px 2px;
    background: transparent;
    border: 1px solid transparent;
    font-size: 17px;
}}
QTabBar#modeTabs::tab:selected {{
    background: white;
    border: 1px solid {ACCENT};
    font-weight: 600;
}}
QTabBar#modeTabs::tab:disabled {{ color: #989898; }}

QFrame#classicToolbar {{ background: {WINDOW}; border: 0; }}
QScrollArea#toolbarScroll {{ background: {WINDOW}; border: 0; }}
QToolButton#classicToolButton, QPushButton#classicButton {{
    min-width: 25px;
    min-height: 24px;
    padding: 2px 5px;
    background: #e8e8e8;
    border: 1px solid #7a7a7a;
    border-top-color: rgba(255,255,255,204);
    border-radius: 0;
    color: black;
}}
QToolButton#classicToolButton:hover, QPushButton#classicButton:hover {{ background: #f0f0f0; }}
QToolButton#classicToolButton:pressed, QPushButton#classicButton:pressed {{ background: #c7c7c7; }}
QToolButton#classicToolButton:checked, QPushButton#classicButton:checked {{
    background: #cfe5ff;
    border-color: {ACCENT};
}}
QToolButton#classicToolButton:disabled, QPushButton#classicButton:disabled {{
    color: #9b9b9b;
    background: #e4e4e4;
    border-color: #b7b7b7;
}}

QFrame#resultExplorer, QFrame#builderPanel {{
    background: {CONTROL};
    border-right: 1px solid {HAIRLINE};
}}
QFrame#builderPanel {{ border-right: 0; border-left: 1px solid {HAIRLINE}; }}
QLabel#sectionTitle {{ font-weight: 600; font-size: 14px; }}
QLabel#sectionCaption, QLabel#secondaryText, QLabel#brandLabel {{ color: {SECONDARY}; font-size: 12px; }}
QLabel#warningBanner {{
    background: #fff8d9;
    border-bottom: 1px solid #e5d794;
    padding: 5px 8px;
}}
QListWidget#geometryList, QListWidget#normalModes {{
    background: {CONTROL};
    border: 0;
    outline: 0;
}}
QListWidget#geometryList::item, QListWidget#normalModes::item {{ padding: 5px 8px; }}
QListWidget#geometryList::item:selected, QListWidget#normalModes::item:selected {{
    background: #d9ebff;
    color: {TEXT};
}}

QFrame#selectionInspector {{
    background: {CONTROL};
    border-top: 1px solid {HAIRLINE};
    border-bottom: 1px solid {HAIRLINE};
}}
QFrame#statusBar {{ background: {WINDOW}; border-top: 1px solid {HAIRLINE}; }}
QLabel#measurementValue {{ font-family: "Cascadia Mono", "Consolas", monospace; }}
QFrame#cameraRail {{ background: {WINDOW}; border-left: 1px solid {HAIRLINE}; }}
QFrame#cameraRail QToolButton {{ min-width: 27px; max-width: 27px; min-height: 25px; font-size: 15px; }}

QTextEdit, QPlainTextEdit, QTableWidget, QComboBox, QDoubleSpinBox, QListWidget {{
    background: white;
    border: 1px solid #b7b7b7;
    selection-background-color: #b9dcff;
    selection-color: {TEXT};
}}
QComboBox, QDoubleSpinBox {{ min-height: 24px; padding: 1px 5px; }}
QHeaderView::section {{ background: #e9e9e9; padding: 5px; border: 0; border-right: 1px solid #c7c7c7; border-bottom: 1px solid #b7b7b7; }}
QTableWidget {{ gridline-color: #dedede; }}
QSplitter::handle {{ background: #c5c5c5; }}
QSplitter::handle:horizontal {{ width: 1px; }}
QSplitter::handle:vertical {{ height: 1px; }}
QStatusBar {{ background: {WINDOW}; border-top: 1px solid {HAIRLINE}; color: {SECONDARY}; }}
"""


def apply_theme(app):
    """Apply the deterministic light Mac-compatibility appearance."""
    app.setStyle("Fusion")
    palette = QPalette()
    palette.setColor(QPalette.Window, QColor(WINDOW))
    palette.setColor(QPalette.WindowText, QColor(TEXT))
    palette.setColor(QPalette.Base, QColor(CANVAS))
    palette.setColor(QPalette.AlternateBase, QColor("#f5f5f5"))
    palette.setColor(QPalette.Text, QColor(TEXT))
    palette.setColor(QPalette.Button, QColor("#e8e8e8"))
    palette.setColor(QPalette.ButtonText, QColor(TEXT))
    palette.setColor(QPalette.Highlight, QColor("#b9dcff"))
    palette.setColor(QPalette.HighlightedText, QColor(TEXT))
    app.setPalette(palette)
    app.setStyleSheet(STYLESHEET)
