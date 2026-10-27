#!/usr/bin/env python3
"""fondo-blanco.py — una ventana blanca del tamaño de la pantalla, de tipo escritorio (queda debajo de todo y sin marco ni sombra): el fondo
sobre el que se mide una sombra de ventana (caso 117). Cinnamon pinta su propio fondo, y xsetroot no lo cambia."""
import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, Gdk, GLib
w = Gtk.Window()
w.set_wmclass('fondo-blanco', 'Fondo-blanco')
w.set_type_hint(Gdk.WindowTypeHint.DESKTOP)
w.set_decorated(False)
w.override_background_color(Gtk.StateFlags.NORMAL, Gdk.RGBA(1, 1, 1, 1))
s = Gdk.Display.get_default().get_primary_monitor() or Gdk.Display.get_default().get_monitor(0)
g = s.get_geometry()
w.set_default_size(g.width, g.height)
w.move(g.x, g.y)
w.connect('destroy', Gtk.main_quit)
w.show_all()
Gtk.main()
