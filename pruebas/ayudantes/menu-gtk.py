#!/usr/bin/env python3
"""menu-gtk.py X Y — una ventana pequeña que a los 1.5 s abre un menú de GTK (ítems normales, uno marcado, uno deshabilitado y un separador) en X,Y;
sirve para ver cómo pinta el tema los menús de GTK (caso 119 y las muestras de Samaná). Se cierra sola a los 8 s."""
import sys
import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, GLib
x, y = int(sys.argv[1]), int(sys.argv[2])
w = Gtk.Window(title='Menú')
w.set_default_size(100, 60)
w.move(x - 40, y - 40)
menu = Gtk.Menu()
for t in ('New Window', 'Open…', None, 'Copy', 'Paste', 'Disabled'):
    if t is None:
        menu.append(Gtk.SeparatorMenuItem()); continue
    it = Gtk.MenuItem(label=t)
    it.set_sensitive(t != 'Disabled')
    menu.append(it)
chk = Gtk.CheckMenuItem(label='Checked'); chk.set_active(True); menu.append(chk)
menu.show_all()
w.connect('destroy', Gtk.main_quit)
w.show_all()
GLib.timeout_add(1500, lambda: (menu.popup_at_pointer(None) if False else menu.popup(None, None, lambda m, d: (x, y, True), None, 0, Gtk.get_current_event_time()), False)[1])
GLib.timeout_add(8000, lambda: (Gtk.main_quit(), False)[1])
Gtk.main()
