"""Asynchronous, private stdio connection to the shared Swift chemistry core."""
import json
import os
import sys
from pathlib import Path

from PySide6.QtCore import QObject, QProcess, QTimer, Signal


def service_path():
    explicit = os.environ.get("CHEMVIEWER_SERVICE")
    if explicit:
        return str(Path(explicit).resolve())
    suffix = ".exe" if sys.platform == "win32" else ""
    base = Path(getattr(sys, "_MEIPASS", Path(__file__).resolve().parent))
    candidates = [base / ("ChemViewerService" + suffix),
                  base.parent / ".build" / "debug" / ("ChemViewerService" + suffix)]
    for path in candidates:
        if path.is_file():
            return str(path.resolve())
    raise FileNotFoundError("ChemViewerService is missing. Build it with swift build --product ChemViewerService.")


class CoreBridge(QObject):
    received = Signal(dict)
    failed = Signal(str)
    busyChanged = Signal(bool)

    def __init__(self, parent=None):
        super().__init__(parent)
        self.process = QProcess(self)
        self.process.setProcessChannelMode(QProcess.SeparateChannels)
        self.process.readyReadStandardOutput.connect(self._read)
        self.process.readyReadStandardError.connect(self._stderr)
        self.process.errorOccurred.connect(lambda error: self.failed.emit(self.process.errorString()))
        self.process.finished.connect(self._finished)
        self.buffer = bytearray()
        self.next_id = 0
        self.pending = {}
        self.stopping = False

    def start(self):
        try:
            path = service_path()
        except OSError as error:
            QTimer.singleShot(0, lambda message=str(error): self.failed.emit(message))
            return
        self.process.start(path, [])

    def request(self, action, callback=None, **arguments):
        self.next_id += 1
        request = dict(id=self.next_id, action=action, **arguments)
        if self.process.state() == QProcess.NotRunning:
            reply = dict(id=self.next_id, ok=False, error="The chemistry process is unavailable. Reopen the application.")
            self.failed.emit(reply["error"])
            if callback: callback(reply)
            return self.next_id
        self.pending[self.next_id] = callback
        self.busyChanged.emit(True)
        # QProcess buffers writes, including while Starting. No shell quoting.
        self.process.write(json.dumps(request, allow_nan=False, ensure_ascii=False).encode("utf-8") + b"\n")
        return self.next_id

    def _read(self):
        self.buffer.extend(bytes(self.process.readAllStandardOutput()))
        while b"\n" in self.buffer:
            line, _, tail = self.buffer.partition(b"\n")
            self.buffer = bytearray(tail)
            try:
                reply = json.loads(line)
                callback = self.pending.pop(reply["id"])
            except (ValueError, KeyError) as error:
                self.failed.emit("Invalid core response: " + str(error))
                continue
            if not reply.get("ok"):
                self.failed.emit(reply.get("error", "Core request failed"))
            if callback:
                callback(reply)
            self.received.emit(reply)
        self.busyChanged.emit(bool(self.pending))

    def _stderr(self):
        message = bytes(self.process.readAllStandardError()).decode("utf-8", "replace").strip()
        if message:
            self.failed.emit(message)

    def _finished(self, code, status):
        self.pending.clear()
        self.busyChanged.emit(False)
        if not self.stopping:
            self.failed.emit(f"The chemistry process stopped (exit {code}). Reopen the application; unsaved documents remain visible.")

    def stop(self):
        self.stopping = True
        self.process.closeWriteChannel()
        if not self.process.waitForFinished(1500):
            self.process.terminate()
            if not self.process.waitForFinished(1000):
                self.process.kill()
                self.process.waitForFinished(1000)
