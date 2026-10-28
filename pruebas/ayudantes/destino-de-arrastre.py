#!/usr/bin/env python3
"""destino-de-arrastre.py SALIDA — una ventana que acepta soltar archivos (text/uri-list) y escribe en SALIDA «acción uri» por cada uno.
Hace de la ventana de Fynder a la que se arrastra desde la Pila del Muelle (caso 131)."""
import sys
import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, Gdk

from gi.repository import GLib
GLib.set_prgname("destino-de-arrastre")
salida = sys.argv[1]
w = Gtk.Window(title="destino-de-arrastre")
w.set_wmclass("destino-de-arrastre", "destino-de-arrastre")
w.set_skip_taskbar_hint(True)      # que el Muelle no le ponga un ícono y la pila quede sola, al centro
w.set_default_size(300, 200)
w.move(20, 20)
etiqueta = Gtk.Label(label="suelta aquí")
w.add(etiqueta)
w.drag_dest_set(Gtk.DestDefaults.ALL, [Gtk.TargetEntry.new("text/uri-list", 0, 0)], Gdk.DragAction.COPY | Gdk.DragAction.MOVE)

def recibido(widget, ctx, x, y, data, info, tiempo):
    with open(salida, "a") as f:
        for u in data.get_uris():
            f.write("%s %s\n" % ("+".join(ctx.get_selected_action().value_nicks), u))
    Gtk.drag_finish(ctx, True, False, tiempo)

w.connect("drag-data-received", recibido)
w.connect("destroy", Gtk.main_quit)
w.show_all()
Gtk.main()
