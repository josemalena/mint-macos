#!/usr/bin/env python3
"""org.mintmacos.Apariencia1 de mentira: guarda lo que le ponen en $APARIENCIA_REGISTRO (una línea por Poner) y no toca el tema. Uso: apariencia-falsa.py"""
import os
import gi
from gi.repository import Gio, GLib

XML = """<node><interface name="org.mintmacos.Apariencia1">
<method name="Estado"><arg type="a{sv}" direction="out"/></method>
<method name="Poner"><arg type="s" direction="in"/><arg type="s" direction="in"/><arg type="s" direction="in"/><arg type="b" direction="out"/></method>
<signal name="Cambio"/>
</interface></node>"""
ACENTOS = ["Blue", "Purple", "Pink", "Red", "Orange", "Yellow", "Green", "Graphite"]
estado = {"apariencia": "dark", "acento": "Blue", "resaltado": "acento"}

def metodo(con, remitente, ruta, ifaz, nombre, params, inv):
    if nombre == "Estado":
        d = {k: GLib.Variant("s", v) for k, v in estado.items()}
        d["oscuro"] = GLib.Variant("b", estado["apariencia"] == "dark")
        d["tema"] = GLib.Variant("s", "Constanza-Oscuro")
        d["acentos"] = GLib.Variant("as", ACENTOS)
        inv.return_value(GLib.Variant("(a{sv})", (d,)))
        return
    a, ac, r = params.unpack()
    ok = a in ("", "light", "dark", "auto") and (ac == "" or ac in ACENTOS)
    if ok:
        for k, v in (("apariencia", a), ("acento", ac), ("resaltado", r)):
            if v:
                estado[k] = v
        with open(os.environ.get("APARIENCIA_REGISTRO", "/dev/null"), "a") as f:
            f.write("%s|%s|%s\n" % (a, ac, r))
        con.emit_signal(None, ruta, ifaz, "Cambio", None)
    inv.return_value(GLib.Variant("(b)", (ok,)))

def al_conectar(con, nombre):
    con.register_object("/org/mintmacos/Apariencia1", Gio.DBusNodeInfo.new_for_xml(XML).interfaces[0], metodo, None, None)

Gio.bus_own_name(Gio.BusType.SESSION, "org.mintmacos.Apariencia1", Gio.BusNameOwnerFlags.NONE, al_conectar, None, None)
GLib.MainLoop().run()
