"""Native Qt OpenGL molecular viewport; scientific coordinates remain in Swift.

Two instanced GPU draws (spheres/cylinders), depth-tested lighting, explicit
camera transforms, and analytic ray/sphere picking. No browser or remote server.
"""
import ctypes
import math
import os
import sys
from pathlib import Path

import numpy as np
# Qt's software mode loads Mesa rather than Windows' system OpenGL library.
# Both Qt and PyOpenGL must resolve symbols/context from that same DLL.
if sys.platform == "win32" and os.environ.get("QT_OPENGL") == "software":
    import PySide6
    from OpenGL.plugins import PlatformPlugin
    os.environ.setdefault("QT_OPENGL_DLL", str(Path(PySide6.__file__).parent / "opengl32sw.dll"))
    os.environ["PYOPENGL_PLATFORM"] = "chemviewer-software"
    PlatformPlugin("chemviewer-software", "gl_platform.SoftwareWin32Platform")
from OpenGL import GL
from OpenGL.GL.shaders import compileProgram, compileShader
from PySide6.QtCore import Qt, Signal
from PySide6.QtGui import QColor, QMatrix4x4, QPainter, QQuaternion, QVector3D, QVector4D
from PySide6.QtOpenGLWidgets import QOpenGLWidget

VERTEX = """#version 330 core
layout(location=0) in vec3 vertex;
layout(location=1) in vec3 normal;
layout(location=2) in mat4 instance;
layout(location=6) in vec3 color;
uniform mat4 viewProjection;
out vec3 litNormal;
out vec3 surfaceColor;
void main() {
    gl_Position = viewProjection * instance * vec4(vertex, 1.0);
    litNormal = normalize(transpose(inverse(mat3(instance))) * normal);
    surfaceColor = color;
}
"""
FRAGMENT = """#version 330 core
in vec3 litNormal;
in vec3 surfaceColor;
out vec4 pixel;
void main() {
    float diffuse = max(dot(normalize(litNormal), normalize(vec3(-0.4,0.7,1.0))),0.0);
    pixel = vec4(surfaceColor * (0.30 + 0.70 * diffuse), 1.0);
}
"""


def mesh(kind):
    vertices = []
    if kind == "sphere":
        for row in range(16):
            for col in range(24):
                for dr, dc in [(0, 0), (1, 0), (1, 1), (0, 0), (1, 1), (0, 1)]:
                    phi, theta = math.pi * (row + dr) / 16, 2 * math.pi * (col + dc) / 24
                    p = (math.sin(phi) * math.cos(theta), math.cos(phi), math.sin(phi) * math.sin(theta))
                    vertices.append((*p, *p))
    else:
        for col in range(16):
            for y, side in [(-0.5, 0), (0.5, 0), (0.5, 1), (-0.5, 0), (0.5, 1), (-0.5, 1)]:
                a = 2 * math.pi * (col + side) / 16
                vertices.append((math.cos(a), y, math.sin(a), math.cos(a), 0, math.sin(a)))
    return np.array(vertices, dtype=np.float32)


def matrix_values(matrix):
    return list(matrix.data())  # Qt column-major, matching GLSL.


class MoleculeViewport(QOpenGLWidget):
    atomPicked = Signal(int, bool)
    renderFailed = Signal(str)

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setObjectName("moleculeViewport")
        self.setMinimumSize(360, 300)
        self.atoms = []; self.bonds = []; self.positions = []
        self.selected = []; self.style = "Ball and stick"; self.labels = False
        self.yaw = -20.0; self.pitch = 15.0; self.distance = 8.0
        self.pan = [0.0, 0.0]; self.center = QVector3D()
        self.last_mouse = None; self.press_mouse = None
        self.program = None; self.gpu_meshes = []; self.upload_needed = True
        self.error = None; self.render_count = 0

    def set_frame(self, frame, fit=False):
        self.atoms = frame.get("atoms", []) if frame else []
        self.bonds = frame.get("bonds", []) if frame else []
        self.positions = [list(a["position"]) for a in self.atoms]
        self.selected = [i for i in self.selected if i < len(self.atoms)]
        if fit:
            self.fit()
        self.upload_needed = True; self.update()

    def fit(self):
        if self.positions:
            points = np.array(self.positions)
            midpoint = (points.min(axis=0) + points.max(axis=0)) / 2
            self.center = QVector3D(*map(float, midpoint))
            radius = max(0.8, float(np.linalg.norm(points - midpoint, axis=1).max()) + 0.65)
            aspect = max(0.1, self.width() / max(1, self.height()))
            self.distance = radius / math.sin(math.atan(math.tan(math.radians(20)) * min(1, aspect))) * 1.15
        else:
            self.center = QVector3D(); self.distance = 8.0
        self.pan = [0.0, 0.0]; self.yaw = -20; self.pitch = 15
        self.update()

    def initializeGL(self):
        try:
            self.context().aboutToBeDestroyed.connect(self.cleanup)
            # Qt creates its widget framebuffer after initializeGL. Compile/link now;
            # draw validation belongs to paintGL, when that framebuffer exists.
            self.program = compileProgram(compileShader(VERTEX, GL.GL_VERTEX_SHADER), compileShader(FRAGMENT, GL.GL_FRAGMENT_SHADER), validate=False)
            self.vp_location = GL.glGetUniformLocation(self.program, "viewProjection")
            for kind in ("sphere", "cylinder"):
                vertices = mesh(kind)
                vao = GL.glGenVertexArrays(1); GL.glBindVertexArray(vao)
                vbo = GL.glGenBuffers(1); GL.glBindBuffer(GL.GL_ARRAY_BUFFER, vbo)
                GL.glBufferData(GL.GL_ARRAY_BUFFER, vertices.nbytes, vertices, GL.GL_STATIC_DRAW)
                for location, offset in [(0, 0), (1, 12)]:
                    GL.glEnableVertexAttribArray(location)
                    GL.glVertexAttribPointer(location, 3, GL.GL_FLOAT, False, 24, ctypes.c_void_p(offset))
                instances = GL.glGenBuffers(1); GL.glBindBuffer(GL.GL_ARRAY_BUFFER, instances)
                for col in range(4):
                    GL.glEnableVertexAttribArray(2 + col)
                    GL.glVertexAttribPointer(2 + col, 4, GL.GL_FLOAT, False, 76, ctypes.c_void_p(col * 16))
                    GL.glVertexAttribDivisor(2 + col, 1)
                GL.glEnableVertexAttribArray(6)
                GL.glVertexAttribPointer(6, 3, GL.GL_FLOAT, False, 76, ctypes.c_void_p(64))
                GL.glVertexAttribDivisor(6, 1)
                self.gpu_meshes.append(dict(vao=vao, vbo=vbo, instances=instances, vertices=len(vertices), count=0))
            GL.glBindVertexArray(0)
            GL.glEnable(GL.GL_DEPTH_TEST)
            self.upload_needed = True
        except Exception as error:
            self.error = str(error); self.renderFailed.emit("OpenGL 3.3 initialization failed: " + self.error)

    def cleanup(self):
        self.makeCurrent()
        for entry in self.gpu_meshes:
            GL.glDeleteBuffers(2, [entry["vbo"], entry["instances"]])
            GL.glDeleteVertexArrays(1, [entry["vao"]])
        self.gpu_meshes = []
        if self.program:
            GL.glDeleteProgram(self.program); self.program = None
        self.doneCurrent()

    def radius(self, atom):
        # Display sizes only; bond connectivity comes from ChemCraftCore.
        return 0.22 if atom["element"] in ("H", "X") else 0.36

    def _upload(self):
        spheres = []; cylinders = []
        for i, (atom, p) in enumerate(zip(self.atoms, self.positions)):
            m = QMatrix4x4(); m.translate(QVector3D(*p))
            radius = self.radius(atom) * (2.2 if self.style == "Space filling" else 1)
            m.scale(radius)
            color = [1.0, 0.65, 0.05] if i in self.selected else atom["color"]
            spheres.append(matrix_values(m) + list(color))
        if self.style != "Space filling":
            for a, b in self.bonds:
                start, end = QVector3D(*self.positions[a]), QVector3D(*self.positions[b])
                midpoint = (start + end) * 0.5
                for p, q, index in [(start, midpoint, a), (midpoint, end, b)]:
                    direction = q - p
                    if direction.length() < 1e-7:
                        continue
                    m = QMatrix4x4(); m.translate((p + q) * 0.5)
                    m.rotate(QQuaternion.rotationTo(QVector3D(0, 1, 0), direction.normalized()))
                    m.scale(0.095, direction.length(), 0.095)
                    cylinders.append(matrix_values(m) + list(self.atoms[index]["color"]))
        for entry, rows in zip(self.gpu_meshes, (spheres, cylinders)):
            data = np.array(rows, dtype=np.float32)
            GL.glBindBuffer(GL.GL_ARRAY_BUFFER, entry["instances"])
            GL.glBufferData(GL.GL_ARRAY_BUFFER, max(4, data.nbytes), data if len(rows) else None, GL.GL_DYNAMIC_DRAW)
            entry["count"] = len(rows)
        self.upload_needed = False

    def camera_matrix(self):
        projection = QMatrix4x4()
        projection.perspective(40.0, self.width() / max(1, self.height()), max(0.01, self.distance / 1000), self.distance + 10000)
        view = QMatrix4x4(); view.translate(self.pan[0], self.pan[1], -self.distance)
        view.rotate(self.pitch, 1, 0, 0); view.rotate(self.yaw, 0, 1, 0); view.translate(-self.center)
        return projection * view

    def paintGL(self):
        # QPainter overlays can leave blending/scissor/depth-write state changed.
        # Restore explicit 3D state before clearing or drawing the next frame.
        GL.glDisable(GL.GL_BLEND); GL.glDisable(GL.GL_SCISSOR_TEST)
        GL.glDepthMask(GL.GL_TRUE); GL.glDepthFunc(GL.GL_LESS)
        GL.glColorMask(True, True, True, True)
        GL.glClearColor(0.96, 0.97, 0.99, 1.0)
        GL.glClear(GL.GL_COLOR_BUFFER_BIT | GL.GL_DEPTH_BUFFER_BIT)
        if not self.program or self.error:
            return
        if self.upload_needed:
            self._upload()
        GL.glUseProgram(self.program)
        GL.glUniformMatrix4fv(self.vp_location, 1, False, np.array(matrix_values(self.camera_matrix()), dtype=np.float32))
        GL.glEnable(GL.GL_DEPTH_TEST)
        for entry in self.gpu_meshes:
            if entry["count"]:
                GL.glBindVertexArray(entry["vao"])
                GL.glDrawArraysInstanced(GL.GL_TRIANGLES, 0, entry["vertices"], entry["count"])
        GL.glBindVertexArray(0); GL.glUseProgram(0)
        self.render_count += 1
        if self.labels:
            painter = QPainter(self); painter.setPen(QColor("#172b42"))
            for i, atom in enumerate(self.atoms):
                x, y = self.project(self.positions[i])
                painter.drawText(int(x + 8), int(y - 8), f"{i + 1} {atom['element']}")
            painter.end()

    def project(self, position):
        clip = self.camera_matrix().map(QVector3D(*position))
        return ((clip.x() + 1) * self.width() / 2,
                (1 - clip.y()) * self.height() / 2)

    def pick(self, x, y):
        inverse, valid = self.camera_matrix().inverted()
        if not valid:
            return -1
        start = inverse.map(QVector3D(2 * x / self.width() - 1, 1 - 2 * y / self.height(), -1))
        far = inverse.map(QVector3D(2 * x / self.width() - 1, 1 - 2 * y / self.height(), 1))
        direction = (far - start).normalized()
        best, index = float("inf"), -1
        for i, (atom, p) in enumerate(zip(self.atoms, self.positions)):
            delta = start - QVector3D(*p)
            b = QVector3D.dotProduct(delta, direction)
            radius = self.radius(atom) * (2.2 if self.style == "Space filling" else 1)
            discriminant = b * b - delta.lengthSquared() + radius * radius
            if discriminant >= 0:
                distance = -b - math.sqrt(discriminant)
                if 0 <= distance < best:
                    best, index = distance, i
        return index

    def mousePressEvent(self, event):
        self.last_mouse = event.position(); self.press_mouse = event.position()

    def mouseMoveEvent(self, event):
        if self.last_mouse is None:
            return
        delta = event.position() - self.last_mouse; self.last_mouse = event.position()
        if event.buttons() & Qt.MiddleButton or event.modifiers() & Qt.ShiftModifier:
            factor = 2 * self.distance * math.tan(math.radians(20)) / max(1, self.height())
            self.pan[0] += delta.x() * factor; self.pan[1] -= delta.y() * factor
        else:
            self.yaw += delta.x() * 0.5; self.pitch += delta.y() * 0.5
        self.update()

    def mouseReleaseEvent(self, event):
        if event.button() == Qt.LeftButton and self.press_mouse is not None and (event.position() - self.press_mouse).manhattanLength() < 4:
            self.atomPicked.emit(self.pick(event.position().x(), event.position().y()), bool(event.modifiers() & Qt.ControlModifier))
        self.last_mouse = None; self.press_mouse = None

    def wheelEvent(self, event):
        self.distance = max(0.2, min(1e6, self.distance * math.exp(-event.angleDelta().y() / 1000)))
        self.update(); event.accept()
