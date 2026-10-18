#!/usr/bin/env python3
"""org.mintmacos.Calendario1 de mentira: dos eventos hoy (uno con lugar y uno de todo el día). Uso: calendario-falso.py"""
import time
import gi
from gi.repository import Gio, GLib

XML = """<node><interface name="org.mintmacos.Calendario1">
<method name="Eventos"><arg type="x" direction="in"/><arg type="x" direction="in"/><arg type="aa{sv}" direction="out"/></method>
</interface></node>"""

def evento(titulo, inicio, fin, todo=False, lugar="", color="#ff2d55", calendario="Personal"):
    d = {"titulo": GLib.Variant("s", titulo), "inicio": GLib.Variant("x", inicio), "fin": GLib.Variant("x", fin),
         "todo_el_dia": GLib.Variant("b", todo), "calendario": GLib.Variant("s", calendario), "color": GLib.Variant("s", color),
         "id": GLib.Variant("s", titulo)}
    if lugar:
        d["lugar"] = GLib.Variant("s", lugar)
    return d

def metodo(con, remitente, ruta, ifaz, nombre, params, inv):
    desde, hasta = params.unpack()
    h = lambda hora, minuto=0: desde + (hora * 60 + minuto) * 60000
    inv.return_value(GLib.Variant("(aa{sv})", ([
        evento("Cumpleaños de prueba", desde, hasta, todo=True, color="#34c759"),
        evento("Reunión de prueba", h(18), h(19, 30), lugar="Parque las palmas"),
    ],)))

def al_conectar(con, nombre):
    con.register_object("/org/mintmacos/Calendario1", Gio.DBusNodeInfo.new_for_xml(XML).interfaces[0], metodo, None, None)

Gio.bus_own_name(Gio.BusType.SESSION, "org.mintmacos.Calendario1", Gio.BusNameOwnerFlags.NONE, al_conectar, None, None)
GLib.MainLoop().run()
