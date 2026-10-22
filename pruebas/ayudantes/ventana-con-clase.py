#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""ventana-con-clase.py CLASE [desktop]: una ventana con esa WM_CLASS (y tipo DESKTOP si se pide), para probar Force Quit."""
import sys
import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, Gdk

clase = sys.argv[1]
w = Gtk.Window(title=clase)
w.set_wmclass(clase, clase)
w.set_default_size(300, 200)
if len(sys.argv) > 2 and sys.argv[2] == "desktop":
    w.set_type_hint(Gdk.WindowTypeHint.DESKTOP)
    w.set_skip_taskbar_hint(False)
w.show_all()
Gtk.main()
