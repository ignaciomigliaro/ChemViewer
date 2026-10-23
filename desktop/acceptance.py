"""Isolated packaged-app acceptance, driven through the real Qt/core lifecycle."""
import json
from pathlib import Path
from PySide6.QtCore import QTimer
from PySide6.QtWidgets import QApplication


def run(window, source, report_path):
    destination = Path(report_path).resolve(); destination.parent.mkdir(parents=True, exist_ok=True)
    window.dialogs_enabled = False
    state = {"finished": False, "stage": "open"}
    app = QApplication.instance()

    def finish(ok, error=None):
        if state["finished"]: return
        state["finished"] = True
        result = dict(ok=ok, stage=state["stage"], error=error, errors=window.errors)
        pane = window.pane()
        result["graphics"] = {name: getattr(pane.viewport, name, None) for name in ("gl_version", "gl_renderer", "shader_version")} if pane else None
        destination.write_text(json.dumps(result, indent=2), encoding="utf-8")
        for i in range(window.tabs.count()): window.tabs.widget(i).dirty = False
        window.close(); app.exit(0 if ok else 1)

    def checked(callback):
        def wrapper(reply):
            if state["finished"]: return
            try:
                assert reply["ok"], reply
                callback(reply)
            except Exception as error: finish(False, str(error))
        return wrapper

    def undo_done(reply):
        pane = window.pane()
        assert reply["data"]["frames"][0]["atoms"] == state["original"], "Undo changed original atoms"
        pane.apply(reply)
        screenshot = destination.with_suffix(".png")
        assert pane.viewport.export_image().save(str(screenshot), "PNG"), "PNG export failed"
        assert window.grab().save(str(destination.with_name(destination.stem + "-window.png")), "PNG")
        finish(True)

    def edited(reply):
        state["stage"] = "undo"
        assert reply["dirty"] and reply["canUndo"]
        assert reply["data"]["frames"][0]["atoms"][1]["position"][0] == 1.5
        window.pane().apply(reply)
        window.bridge.request("undo", checked(undo_done), document=window.pane().key)

    def measured(reply):
        state["stage"] = "edit"
        assert abs(reply["measurement"] - .9572) < 1e-5
        window.bridge.request("position", checked(edited), document=window.pane().key, atom=1, position=[1.5, 0, 0])

    def poll():
        if state["finished"]: return
        if window.errors: finish(False, window.errors[-1]); return
        pane = window.pane()
        if not pane or pane.viewport.render_count == 0:
            QTimer.singleShot(50, poll); return
        try:
            state["stage"] = "render-and-pick"
            assert pane.viewport.program is not None and pane.viewport.error is None
            image = pane.viewport.grabFramebuffer(); assert not image.isNull()
            red = 0
            for y in range(0, image.height(), 4):
                for x in range(0, image.width(), 4):
                    color = image.pixelColor(x, y)
                    red += color.red() > 1.5 * color.green() and color.red() > 1.5 * color.blue()
            assert red > 10, "No oxygen pixels: blank or incorrect rendering"
            state["original"] = pane.data["frames"][0]["atoms"]
            assert len(state["original"]) == 3, "Packaged acceptance requires independent water.xyz"
            for index in (0, 1):
                x, y = pane.viewport.project(pane.viewport.positions[index])
                assert pane.viewport.pick(x, y) == index, "Picking mismatch"
            state["stage"] = "measure"
            window.bridge.request("measure", checked(measured), document=pane.key, indices=[0, 1])
        except Exception as error: finish(False, str(error))

    QTimer.singleShot(90000, lambda: finish(False, "Packaged acceptance timed out"))
    window.open_path(source)
    QTimer.singleShot(50, poll)
