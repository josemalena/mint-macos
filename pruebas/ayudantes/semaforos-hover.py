#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""semaforos-hover.py: una ventana con headerbar y sus tres botones; lleva el puntero al primero e imprime
cuáles botones quedaron en PRELIGHT (close,minimize,maximize como 0/1)."""
import subprocess
import gi
gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gtk, Gdk, GLib

w = Gtk.Window()
w.set_default_size(420, 120)
w.move(40, 30)
hb = Gtk.HeaderBar()
hb.set_show_close_button(True)
hb.set_decoration_layout("close,minimize,maximize:")
w.set_titlebar(hb)
w.connect("destroy", Gtk.main_quit)
w.show_all()

botones = []


def juntar(x):
    if isinstance(x, Gtk.Button) and x.get_style_context().has_class("titlebutton"):
        botones.append(x)
    elif isinstance(x, Gtk.Container):
        x.forall(juntar)


def mover():
    juntar(hb)
    primero = botones[0]
    # el centro del botón en la pantalla: su lugar dentro de la ventana (que lleva sombra) más el origen de la ventana
    tope = primero.get_toplevel()
    bx, by = primero.translate_coordinates(tope, primero.get_allocated_width() // 2, primero.get_allocated_height() // 2)
    _, ox, oy = tope.get_window().get_origin()
    rx, ry = ox + bx, oy + by
    # primero afuera: si el puntero ya estaba ahí de una corrida anterior, no habría «enter»
    subprocess.run(["xdotool", "mousemove", "400", "180"], check=True)
    subprocess.run(["sleep", "0.3"], check=True)
    subprocess.run(["xdotool", "mousemove", str(rx), str(ry)], check=True)
    GLib.timeout_add(700, leer)
    return False


def leer():
    print("".join("1" if b.get_state_flags() & Gtk.StateFlags.PRELIGHT else "0" for b in botones))
    Gtk.main_quit()
    return False


GLib.timeout_add(2000, mover)
Gtk.main()
