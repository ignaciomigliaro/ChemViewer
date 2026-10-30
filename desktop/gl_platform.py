"""Keep PyOpenGL and Qt on the same explicit Windows software GL driver."""
import ctypes
import os
from OpenGL.platform import baseplatform
from OpenGL.platform.win32 import Win32Platform


class SoftwareWin32Platform(Win32Platform):
    @baseplatform.lazy_property
    def GL(self):
        return ctypes.WinDLL(os.environ["QT_OPENGL_DLL"])
