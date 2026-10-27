#!/usr/bin/env python3
"""ventana-con-marco.py [X Y] — una ventana GTK3 simple SIN barra propia: el marco lo pone el gestor (Muffin), como en las apps de un solo
marco de siempre. Clase marco-de-prueba."""
import sys
import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, GLib
GLib.set_prgname('marco-de-prueba')
w = Gtk.Window(title='Marco de prueba')
w.set_default_size(600, 400)
w.set_wmclass('marco-de-prueba', 'Marco-de-prueba')
if len(sys.argv) > 2:
    w.move(int(sys.argv[1]), int(sys.argv[2]))
w.add(Gtk.Label(label='sombra'))
w.connect('destroy', Gtk.main_quit)
w.show_all()
Gtk.main()
