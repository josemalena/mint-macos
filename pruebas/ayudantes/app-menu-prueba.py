#!/usr/bin/env python3
"""Una ventana con un botón que abre un GtkMenu de tres ítems; cada ítem escribe «NOMBRE HORA» en el archivo que se pasa como argumento.
Sirve para probar el módulo GTK del parpadeo de menús (nativo/gtkmenu-flash)."""
import sys
import time
import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk

salida = sys.argv[1]


def escribir(nombre):
    with open(salida, "a") as f:
        f.write("%s %.3f\n" % (nombre, time.time()))


ventana = Gtk.Window(title="menu-prueba")
ventana.set_default_size(320, 240)
ventana.connect("destroy", Gtk.main_quit)
menu = Gtk.Menu()
for nombre in ("Uno", "Dos", "Tres"):
    item = Gtk.MenuItem(label=nombre)
    item.connect("activate", lambda _w, n=nombre: escribir(n))
    menu.append(item)
sub = Gtk.MenuItem(label="Con submenú")
submenu = Gtk.Menu()
dentro = Gtk.MenuItem(label="Dentro")
dentro.connect("activate", lambda _w: escribir("Dentro"))
submenu.append(dentro)
sub.set_submenu(submenu)
menu.append(sub)
menu.show_all()
boton = Gtk.Button(label="Abrir menú")
boton.connect("clicked", lambda b: menu.popup_at_widget(b, 3, 1, None))
ventana.add(boton)
ventana.show_all()
Gtk.main()
