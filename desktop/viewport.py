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
from OpenGL.GL.shaders import compileShader
from PySide6.QtCore import Qt, Signal
from PySide6.QtGui import QColor, QMatrix4x4, QPainter, QQuaternion, QVector3D, QVector4D
from PySide6.QtOpenGLWidgets import QOpenGLWidget
from PySide6.QtWidgets import QWidget

VERTEX = """#version 330 core
layout(location=0) in vec3 vertex;
layout(location=1) in vec3 normal;
layout(location=2) in mat4 instance;
layout(location=6) in vec3 color;
uniform mat4 viewProjection;
uniform mat4 normalView;
out vec3 litNormal;
out vec3 surfaceColor;
void main() {
    gl_Position = viewProjection * instance * vec4(vertex, 1.0);
    // Shade in camera space so the outline follows the visible sphere edge.
    litNormal = normalize(mat3(normalView * instance) * normal);
    surfaceColor = color;
}
"""
FRAGMENT = """#version 330 core
in vec3 litNormal;
in vec3 surfaceColor;
out vec4 pixel;
vec3 patonSRGB(vec3 c) {
    vec3 low = c * 12.92;
    vec3 high = 1.055 * pow(max(c, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055;
    return mix(low, high, step(vec3(0.0031308), c));
}
vec3 patonLinear(vec3 c) {
    vec3 low = c / 12.92;
    vec3 high = pow((c + 0.055) / 1.055, vec3(2.4));
    return mix(low, high, step(vec3(0.04045), c));
}
vec3 patonHSL(vec3 c) {
    float hi = max(c.r, max(c.g, c.b)), lo = min(c.r, min(c.g, c.b));
    float delta = hi - lo, l = (hi + lo) * 0.5;
    if (delta < 0.000001) return vec3(0.0, 0.0, l);
    float h = hi == c.r ? mod((c.g-c.b)/delta+6.0,6.0) : (hi == c.g ? (c.b-c.r)/delta+2.0 : (c.r-c.g)/delta+4.0);
    return vec3(h * 60.0, delta / (1.0 - abs(2.0*l - 1.0)), l);
}
vec3 patonRGB(vec3 hsl) {
    float c = (1.0 - abs(2.0*hsl.z - 1.0)) * hsl.y;
    float h = hsl.x/60.0, x = c * (1.0 - abs(mod(h,2.0)-1.0));
    vec3 rgb = h < 1.0 ? vec3(c,x,0) : h < 2.0 ? vec3(x,c,0) : h < 3.0 ? vec3(0,c,x) : h < 4.0 ? vec3(0,x,c) : h < 5.0 ? vec3(x,0,c) : vec3(c,0,x);
    return rgb + hsl.z - c*0.5;
}
vec3 patonGradient(vec3 linearColor, vec3 normal) {
    vec3 base = patonSRGB(linearColor), hsl = patonHSL(base), hi = hsl, lo = hsl;
    hi.x = mod(hsl.x + (mod(60.0-hsl.x+540.0,360.0)-180.0)*0.15+360.0,360.0);
    hi.y *= 0.9; hi.z += 0.1*(1.0-hi.z);
    lo.x = mod(hsl.x + (mod(240.0-hsl.x+540.0,360.0)-180.0)*0.15+360.0,360.0);
    lo.y += (1.0-lo.y)*0.1; lo.z *= 0.7;
    vec2 focal=vec2(-0.34,0.34), d=normal.xy-focal;
    float a=max(dot(d,d),0.000001), b=2.0*dot(focal,d), c=dot(focal,focal)-1.32*1.32;
    float boundary=(-b+sqrt(max(b*b-4.0*a*c,0.0)))/(2.0*a);
    float t=clamp(1.0/max(boundary,0.000001),0.0,1.0);
    vec3 color=t<0.4 ? mix(patonRGB(hi),base,t/0.4) : mix(base,patonRGB(lo),(t-0.4)/0.6);
    return patonLinear(color);
}
void main() {
    vec3 n = normalize(litNormal);
    if (abs(n.z) < 0.27 && dot(surfaceColor,surfaceColor) > 0.0003) {
        pixel=vec4(0.008,0.008,0.008,1.0); return;
    }
    pixel = vec4(patonGradient(surfaceColor,n),1.0);
}
"""


PATON_COLORS = {
    "X": 0x999999, "H": 0xFAFAFA, "He": 0xD9FFFF, "Li": 0xCC80FF,
    "Be": 0xC2FF00, "B": 0xFFB5B5, "C": 0xD9D9D9, "N": 0x7F7FBF,
    "O": 0xFF0D0D, "F": 0x90E050, "Ne": 0xB3E3F5, "Na": 0xAB5CF2,
    "Mg": 0x8AFF00, "Al": 0xBFA6A6, "Si": 0xF0C8A0, "P": 0xFF8000,
    "S": 0xFFFF30, "Cl": 0x1FF01F, "Ar": 0x80D1E3, "K": 0x8F40D4,
    "Ca": 0x3DFF00, "Sc": 0xE6E6E6, "Ti": 0xBFC2C7, "V": 0xA6A6AB,
    "Cr": 0x8A99C7, "Mn": 0x9C7AC7, "Fe": 0xE06633, "Co": 0xF090A0,
    "Ni": 0x50D050, "Cu": 0xC88033, "Zn": 0x7D80B0, "Ga": 0xC28F8F,
    "Ge": 0x668F8F, "As": 0xBD80E3, "Se": 0xFFA100, "Br": 0xA62929,
    "Kr": 0x5CB8D1, "Rb": 0x702EB0, "Sr": 0x00FF00, "Y": 0x94FFFF,
    "Zr": 0x94E0E0, "Nb": 0x73C2C9, "Mo": 0x54B5B5, "Tc": 0x3B9E9E,
    "Ru": 0x248F8F, "Rh": 0x0A7D8C, "Pd": 0x006985, "Ag": 0xC0C0C0,
    "Cd": 0xFFD98F, "In": 0xA67573, "Sn": 0x668080, "Sb": 0x9E63B5,
    "Te": 0xD47A00, "I": 0x940094, "Xe": 0x429EB0, "Cs": 0x57178F,
    "Ba": 0x00C900, "La": 0x70D4FF, "Ce": 0xFFFFC7, "Pr": 0xD9FFC7,
    "Nd": 0xC7FFC7, "Pm": 0xA3FFC7, "Sm": 0x8FFFC7, "Eu": 0x61FFC7,
    "Gd": 0x45FFC7, "Tb": 0x30FFC7, "Dy": 0x1FFFC7, "Ho": 0x00FF9C,
    "Er": 0x00E675, "Tm": 0x00D452, "Yb": 0x00BF38, "Lu": 0x00AB24,
    "Hf": 0x4DC2FF, "Ta": 0x4DA6FF, "W": 0x2194D6, "Re": 0x267DAB,
    "Os": 0x266696, "Ir": 0x175487, "Pt": 0xD0D0E0, "Au": 0xFFD123,
    "Hg": 0xB8B8D0, "Tl": 0xA6544D, "Pb": 0x575961, "Bi": 0x9E4FB5,
    "Po": 0xAB5C00, "At": 0x754F45, "Rn": 0x428296, "Fr": 0x420066,
    "Ra": 0x007D00, "Ac": 0x70ABFA, "Th": 0x00BAFF, "Pa": 0x00A1FF,
    "U": 0x008FFF, "Np": 0x0080FF, "Pu": 0x006BFF, "Am": 0x545CF2,
    "Cm": 0x785CE3, "Bk": 0x8A4FE3, "Cf": 0xA136D4, "Es": 0xB31FD4,
    "Fm": 0xB31FBA, "Md": 0xB30DA6, "No": 0xBD0D87, "Lr": 0xC70066,
    "Rf": 0xCC0059, "Db": 0xA0A0A0, "Sg": 0xA0A0A0, "Bh": 0xA0A0A0,
    "Hs": 0xA0A0A0, "Mt": 0xA0A0A0, "Ds": 0xA0A0A0, "Rg": 0xA0A0A0,
    "Cn": 0xA0A0A0, "Nh": 0xA0A0A0, "Fl": 0xA0A0A0, "Mc": 0xA0A0A0,
    "Lv": 0xA0A0A0, "Ts": 0xA0A0A0, "Og": 0xA0A0A0,
}


def linear_paton_color(element):
    rgb = PATON_COLORS.get(element, 0xA0A0A0)
    values = [((rgb >> shift) & 255) / 255 for shift in (16, 8, 0)]
    return [value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4 for value in values]


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


class AtomLabels(QWidget):
    """Raster overlay keeps Qt text painting out of the molecular GL context."""
    def __init__(self, viewport):
        super().__init__(viewport)
        self.viewport = viewport
        self.setAttribute(Qt.WA_TransparentForMouseEvents)
        self.setAttribute(Qt.WA_NoSystemBackground)
        self.setAttribute(Qt.WA_TranslucentBackground)

    def paintEvent(self, event):
        if self.viewport.labels:
            painter = QPainter(self)
            self.viewport.paint_labels(painter)
            painter.end()


class MoleculeViewport(QOpenGLWidget):
    atomPicked = Signal(int, bool)
    renderFailed = Signal(str)

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setObjectName("moleculeViewport")
        self.setMinimumSize(360, 300)
        self.atoms = []; self.bonds = []; self.positions = []
        self.selected = []; self.style = "xyzrender · Paton"; self.labels = False
        self.show_hydrogens = True
        self.label_mode = "Element + number"
        self.yaw = -20.0; self.pitch = 15.0; self.roll = 0.0; self.distance = 8.0
        self.pan = [0.0, 0.0]; self.center = QVector3D()
        self.last_mouse = None; self.press_mouse = None
        self.program = None; self.gpu_meshes = []; self.upload_needed = True
        self.error = None; self.render_count = 0
        self.label_overlay = AtomLabels(self)

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
        self.pan = [0.0, 0.0]; self.yaw = -20; self.pitch = 15; self.roll = 0
        self.update()

    def nudge(self, action):
        """Mirror the compact camera rail used by the native Mac workspace."""
        if action == "left": self.yaw -= 10
        elif action == "right": self.yaw += 10
        elif action == "up": self.pitch -= 10
        elif action == "down": self.pitch += 10
        elif action == "roll_left": self.roll -= 10
        elif action == "roll_right": self.roll += 10
        elif action == "pan_up": self.pan[1] += self.distance * 0.035
        elif action == "pan_down": self.pan[1] -= self.distance * 0.035
        elif action == "zoom_in": self.distance = max(0.2, self.distance * 0.82)
        elif action == "zoom_out": self.distance = min(1e6, self.distance / 0.82)
        elif action == "fit": self.fit(); return
        self.update()

    def initializeGL(self):
        try:
            self.context().aboutToBeDestroyed.connect(self.cleanup)
            version = GL.glGetString(GL.GL_VERSION).decode("ascii", "replace")
            major, minor = map(int, version.split()[0].split(".")[:2])
            self.gl_version = version
            self.gl_renderer = GL.glGetString(GL.GL_RENDERER).decode("ascii", "replace")
            self.shader_version = "330"
            vertex, fragment = VERTEX, FRAGMENT
            self.draw_instances = GL.glDrawArraysInstanced
            self.instance_divisor = GL.glVertexAttribDivisor
            if (major, minor) < (3, 3):
                # Qt's bundled Windows Mesa exposes GL 3.0 + ARB instancing.
                # Keep the same meshes, depth and instanced draws with GLSL 1.30.
                from OpenGL.GL.ARB.draw_instanced import glDrawArraysInstancedARB
                from OpenGL.GL.ARB.instanced_arrays import glVertexAttribDivisorARB
                if (major, minor) < (3, 0) or not glDrawArraysInstancedARB or not glVertexAttribDivisorARB:
                    raise RuntimeError("OpenGL 3.0 with ARB instancing (or OpenGL 3.3) is required: " + version)
                self.shader_version = "130"
                self.draw_instances = glDrawArraysInstancedARB
                self.instance_divisor = glVertexAttribDivisorARB
                vertex = vertex.replace("#version 330 core", "#version 130")
                fragment = fragment.replace("#version 330 core", "#version 130")
                for location in (0, 1, 2, 6):
                    vertex = vertex.replace(f"layout(location={location}) ", "")
            shaders = [compileShader(vertex, GL.GL_VERTEX_SHADER), compileShader(fragment, GL.GL_FRAGMENT_SHADER)]
            self.program = GL.glCreateProgram()
            for shader in shaders: GL.glAttachShader(self.program, shader)
            for location, name in [(0, "vertex"), (1, "normal"), (2, "instance"), (6, "color")]:
                GL.glBindAttribLocation(self.program, location, name)
            GL.glBindFragDataLocation(self.program, 0, "pixel")
            GL.glLinkProgram(self.program)
            for shader in shaders: GL.glDeleteShader(shader)
            if not GL.glGetProgramiv(self.program, GL.GL_LINK_STATUS):
                raise RuntimeError(GL.glGetProgramInfoLog(self.program).decode("utf-8", "replace"))
            # Qt creates its framebuffer after initializeGL; drawing is tested later.
            self.vp_location = GL.glGetUniformLocation(self.program, "viewProjection")
            self.normal_view_location = GL.glGetUniformLocation(self.program, "normalView")
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
                    self.instance_divisor(2 + col, 1)
                GL.glEnableVertexAttribArray(6)
                GL.glVertexAttribPointer(6, 3, GL.GL_FLOAT, False, 76, ctypes.c_void_p(64))
                self.instance_divisor(6, 1)
                self.gpu_meshes.append(dict(vao=vao, vbo=vbo, instances=instances, vertices=len(vertices), count=0))
            GL.glBindVertexArray(0)
            GL.glEnable(GL.GL_DEPTH_TEST)
            if hasattr(GL, "GL_FRAMEBUFFER_SRGB"):
                GL.glEnable(GL.GL_FRAMEBUFFER_SRGB)
            self.upload_needed = True
        except Exception as error:
            self.error = str(error); self.renderFailed.emit("Molecular renderer initialization failed: " + self.error)

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
        # Native Paton display sizes only; connectivity comes from ChemCraftCore.
        if self.style == "Sticks":
            return 0.10
        if self.style in ("Large spheres", "Space filling"):
            return 0.22 if atom["element"] == "H" else 0.56
        if self.style != "xyzrender · Paton":
            return 0.22 if atom["element"] in ("H", "X") else 0.36
        radii = {"H": 1.2, "C": 1.7, "N": 1.55, "O": 1.52, "F": 1.47,
                 "P": 1.8, "S": 1.8, "Cl": 1.75, "Br": 1.85, "I": 1.98}
        return radii.get(atom["element"], 1.5) * 0.1875 * (0.6 if atom["element"] == "H" else 1)

    def _upload(self):
        spheres = []; cylinders = []
        for i, (atom, p) in enumerate(zip(self.atoms, self.positions)):
            if not self.show_hydrogens and atom["element"] == "H":
                continue
            m = QMatrix4x4(); m.translate(QVector3D(*p))
            radius = self.radius(atom)
            m.scale(radius)
            if i in self.selected:
                color = [1.0, 0.4179, 0.0134]  # linearized Mac selection orange
            elif self.style == "xyzrender · Paton":
                color = linear_paton_color(atom["element"])
            else:
                color = atom["color"]
            spheres.append(matrix_values(m) + list(color))
        if self.style not in ("Large spheres", "Space filling"):
            for a, b in self.bonds:
                if not self.show_hydrogens and (self.atoms[a]["element"] == "H" or self.atoms[b]["element"] == "H"):
                    continue
                start, end = QVector3D(*self.positions[a]), QVector3D(*self.positions[b])
                midpoint = (start + end) * 0.5
                for p, q, index in [(start, midpoint, a), (midpoint, end, b)]:
                    direction = q - p
                    if direction.length() < 1e-7:
                        continue
                    m = QMatrix4x4(); m.translate((p + q) * 0.5)
                    m.rotate(QQuaternion.rotationTo(QVector3D(0, 1, 0), direction.normalized()))
                    m.scale(0.079, direction.length(), 0.079)
                    # Paton uses one thin black bond, not two atom-colored halves.
                    cylinders.append(matrix_values(m) + [0.008, 0.008, 0.008])
        for entry, rows in zip(self.gpu_meshes, (spheres, cylinders)):
            data = np.array(rows, dtype=np.float32)
            GL.glBindBuffer(GL.GL_ARRAY_BUFFER, entry["instances"])
            GL.glBufferData(GL.GL_ARRAY_BUFFER, max(4, data.nbytes), data if len(rows) else None, GL.GL_DYNAMIC_DRAW)
            entry["count"] = len(rows)
        self.upload_needed = False

    def camera_matrix(self):
        projection = QMatrix4x4()
        projection.perspective(40.0, self.width() / max(1, self.height()), max(0.01, self.distance / 1000), self.distance + 10000)
        return projection * self.view_matrix()

    def view_matrix(self):
        view = QMatrix4x4(); view.translate(self.pan[0], self.pan[1], -self.distance)
        view.rotate(self.roll, 0, 0, 1); view.rotate(self.pitch, 1, 0, 0); view.rotate(self.yaw, 0, 1, 0); view.translate(-self.center)
        return view

    def paintGL(self):
        # QPainter overlays can leave blending/scissor/depth-write state changed.
        # Restore explicit 3D state before clearing or drawing the next frame.
        GL.glDisable(GL.GL_BLEND); GL.glDisable(GL.GL_SCISSOR_TEST)
        GL.glDepthMask(GL.GL_TRUE); GL.glDepthFunc(GL.GL_LESS)
        GL.glColorMask(True, True, True, True)
        GL.glClearColor(1.0, 1.0, 1.0, 1.0)
        GL.glClear(GL.GL_COLOR_BUFFER_BIT | GL.GL_DEPTH_BUFFER_BIT)
        if not self.program or self.error:
            return
        if self.upload_needed:
            self._upload()
        GL.glUseProgram(self.program)
        GL.glUniformMatrix4fv(self.vp_location, 1, False, np.array(matrix_values(self.camera_matrix()), dtype=np.float32))
        GL.glUniformMatrix4fv(self.normal_view_location, 1, False, np.array(matrix_values(self.view_matrix()), dtype=np.float32))
        GL.glEnable(GL.GL_DEPTH_TEST)
        for entry in self.gpu_meshes:
            if entry["count"]:
                GL.glBindVertexArray(entry["vao"])
                self.draw_instances(GL.GL_TRIANGLES, 0, entry["vertices"], entry["count"])
        GL.glBindVertexArray(0); GL.glUseProgram(0)
        self.render_count += 1
        self.label_overlay.update()

    def resizeEvent(self, event):
        super().resizeEvent(event)
        self.label_overlay.setGeometry(self.rect())

    def paint_labels(self, painter):
        painter.setPen(QColor("#172b42"))
        for i, atom in enumerate(self.atoms):
            if not self.show_hydrogens and atom["element"] == "H":
                continue
            x, y = self.project(self.positions[i])
            if self.label_mode == "Numbers": text = str(i + 1)
            elif self.label_mode == "Elements": text = atom["element"]
            else: text = f"{atom['element']}{i + 1}"
            bounds = painter.fontMetrics().boundingRect(text)
            painter.drawText(int(x - bounds.width() / 2), int(y + bounds.height() / 3), text)

    def export_image(self):
        image = self.grabFramebuffer()
        if self.labels:
            image.setDevicePixelRatio(self.devicePixelRatioF())
            painter = QPainter(image); self.paint_labels(painter); painter.end()
        return image

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
            if not self.show_hydrogens and atom["element"] == "H":
                continue
            delta = start - QVector3D(*p)
            b = QVector3D.dotProduct(delta, direction)
            radius = self.radius(atom)
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
