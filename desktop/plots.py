"""Qt plots of source values; gaps stay gaps and missing values stay absent."""
import csv
import io
import math
from PySide6.QtCore import QPointF, Qt
from PySide6.QtGui import QColor, QPainter, QPen
from PySide6.QtWidgets import QWidget


class ScientificPlot(QWidget):
    def __init__(self, x_label, y_label, parent=None):
        super().__init__(parent)
        self.x_label = x_label; self.y_label = y_label; self.points = []
        self.setMinimumSize(300, 230)

    def set_points(self, points):
        self.points = points; self.update()

    def csv(self):
        output = io.StringIO(); writer = csv.writer(output)
        writer.writerow([self.x_label, self.y_label])
        writer.writerows((x, "" if y is None else repr(y)) for x, y in self.points)
        return output.getvalue()

    def paintEvent(self, event):
        painter = QPainter(self); painter.fillRect(self.rect(), QColor("white"))
        painter.setRenderHint(QPainter.Antialiasing)
        left, right, top, bottom = 85, self.width() - 25, 25, self.height() - 55
        painter.setPen(QColor("#26394c")); painter.drawLine(left, bottom, right, bottom); painter.drawLine(left, top, left, bottom)
        painter.drawText(left, self.height() - 15, self.x_label)
        painter.drawText(8, 18, self.y_label)
        finite = [(x, y) for x, y in self.points if y is not None and math.isfinite(x) and math.isfinite(y)]
        if not finite:
            painter.drawText(left + 15, top + 30, "No source values available"); return
        xmin, xmax = min(p[0] for p in finite), max(p[0] for p in finite)
        ymin, ymax = min(p[1] for p in finite), max(p[1] for p in finite)
        if xmin == xmax: xmin -= .5; xmax += .5
        if ymin == ymax: ymin -= .5; ymax += .5
        margin = (ymax - ymin) * .06; ymin -= margin; ymax += margin
        painter.drawText(3, top + 12, f"{ymax:.8g}"); painter.drawText(3, bottom, f"{ymin:.8g}")
        painter.drawText(left, bottom + 20, f"{xmin:.6g}"); painter.drawText(right - 50, bottom + 20, f"{xmax:.6g}")
        previous = None; painter.setPen(QPen(QColor("#2266ac"), 2))
        for x, y in self.points:
            if y is None or not math.isfinite(y): previous = None; continue
            point = QPointF(left + (x - xmin) / (xmax - xmin) * (right - left), bottom - (y - ymin) / (ymax - ymin) * (bottom - top))
            if previous is not None: painter.drawLine(previous, point)
            painter.drawEllipse(point, 2, 2); previous = point
