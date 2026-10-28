#!/usr/bin/env python3
"""ventana-darling.py NOMBRE BUNDLE_ID — una ventana como la de una app de Mac en Darling (caso 132): WM_CLASS = (NOMBRE, «darling-<id>»),
_DARLING_APP_NAME = NOMBRE (UTF8_STRING) y un ícono propio en _NET_WM_ICON (cuadrado rojo). Sin .desktop."""
import subprocess
import sys
import gi
gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gtk, Gdk, GdkPixbuf, GLib

nombre, bundle = sys.argv[1], sys.argv[2].lower()
w = Gtk.Window(title="Untitled 1 - " + nombre)       # el título de la ventana, distinto del nombre de la app
w.set_wmclass(nombre, "darling-" + bundle)
w.set_default_size(300, 200)
pb = GdkPixbuf.Pixbuf.new(GdkPixbuf.Colorspace.RGB, True, 8, 48, 48)
pb.fill(0xcc2222ff)
w.set_icon(pb)

def poner_nombre(*_):
    # xprop pone la propiedad como lo haría Darling (UTF8_STRING de formato 8)
    xid = w.get_window().get_xid()
    subprocess.run(["xprop", "-id", str(xid), "-f", "_DARLING_APP_NAME", "8u", "-set", "_DARLING_APP_NAME", nombre], check=True)

w.connect("map-event", poner_nombre)
w.connect("destroy", Gtk.main_quit)
w.show_all()
Gtk.main()
