#!/usr/bin/env python3
"""madre-y-hoja.py madre REGISTRO | hoja XID_MADRE [ROL] — para el caso 136 (hojas de macOS en Muffin).
madre: una ventana que anota en REGISTRO cada clic que recibe en su contenido.
hoja: una ventana DIALOG + MODAL, transient de la ventana XID_MADRE (que puede ser de otro proceso) y con WM_WINDOW_ROLE «mint-macos-hoja»,
como la que arma el selector Open/Save de Fynder."""
import sys
import gi
gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
gi.require_version("GdkX11", "3.0")
from gi.repository import Gtk, Gdk, GdkX11, GLib

modo = sys.argv[1]
if modo == "madre":
    registro = sys.argv[2]
    w = Gtk.Window(title="madre-hoja")
    w.set_wmclass("madre-hoja", "madre-hoja")
    w.set_default_size(520, 360)
    w.move(300, 200)
    caja = Gtk.EventBox()
    caja.add(Gtk.Label(label="contenido de la madre"))
    caja.add_events(Gdk.EventMask.BUTTON_PRESS_MASK)
    def clic(*_):
        with open(registro, "a") as f:
            f.write("clic\n")
        return True
    caja.connect("button-press-event", clic)
    w.add(caja)
else:
    xid = int(sys.argv[2])
    w = Gtk.Window(title="hoja-de-prueba")
    w.set_wmclass("hoja-de-prueba", "hoja-de-prueba")
    w.set_type_hint(Gdk.WindowTypeHint.DIALOG)
    w.set_modal(True)
    w.set_role(sys.argv[3] if len(sys.argv) > 3 else "mint-macos-hoja")
    w.set_decorated(False)     # la hoja no lleva barra de título propia
    w.set_skip_taskbar_hint(True)
    w.set_default_size(420, 120)
    w.add(Gtk.Label(label="hoja"))
    w.realize()
    display = GdkX11.X11Display.get_default() if hasattr(GdkX11.X11Display, "get_default") else Gdk.Display.get_default()
    madre = GdkX11.X11Window.foreign_new_for_display(Gdk.Display.get_default(), xid)
    w.get_window().set_transient_for(madre)
w.connect("destroy", Gtk.main_quit)
w.show_all()
Gtk.main()
