#!/usr/bin/env python3
"""El motor del App Store de mentira (org.mintmacos.Tienda1) para probar las pantallas sin instalar nada de verdad. Una sola app,
«fake:app» (Fake App): Instalar emite Progreso 30 → 80 y Terminado; Quitar emite Terminado. Uso: tienda-falsa.py REGISTRO."""
import sys
import gi
from gi.repository import Gio, GLib

registro = sys.argv[1]

def anotar(t):
    with open(registro, "a") as f:
        f.write(t + "\n")

XML = """<node><interface name="org.mintmacos.Tienda1">
<method name="Estantes"><arg type="s" direction="in"/><arg type="a(ssssaa{sv})" direction="out"/></method>
<method name="Secciones"><arg type="a(ssas)" direction="out"/></method>
<method name="Categorias"><arg type="a(ssas)" direction="out"/></method>
<method name="Ficha"><arg type="s" direction="in"/><arg type="a{sv}" direction="out"/></method>
<method name="Instalar"><arg type="s" direction="in"/><arg type="s" direction="out"/></method>
<method name="Quitar"><arg type="s" direction="in"/><arg type="s" direction="out"/></method>
<method name="Actualizar"><arg type="s" direction="in"/><arg type="as" direction="in"/><arg type="s" direction="out"/></method>
<method name="Actualizaciones"><arg type="s" direction="in"/><arg type="aa{sv}" direction="out"/></method>
<method name="Buscar"><arg type="s" direction="in"/><arg type="as" direction="in"/><arg type="u" direction="in"/><arg type="aa{sv}" direction="out"/></method>
<method name="Resenas"><arg type="s" direction="in"/><arg type="u" direction="in"/><arg type="aa{sv}" direction="out"/></method>
<method name="Cancelar"><arg type="s" direction="in"/><arg type="b" direction="out"/></method>
<signal name="Progreso"><arg type="s"/><arg type="u"/><arg type="s"/><arg type="t"/><arg type="t"/></signal>
<signal name="Terminado"><arg type="s"/><arg type="b"/><arg type="s"/><arg type="s"/></signal>
</interface></node>"""

estado = {"instalada": False, "n": 0}
conexion = None

def ficha():
    d = {
        "id": GLib.Variant("s", "fake:app"), "appstream_id": GLib.Variant("s", "org.fake.App"),
        "nombre": GLib.Variant("s", "Fake App"), "resumen": GLib.Variant("s", "An app that is not there"),
        "origen": GLib.Variant("s", "flatpak"), "desarrollador": GLib.Variant("s", "Fake Team"),
        "instalada": GLib.Variant("b", estado["instalada"]), "descripcion": GLib.Variant("s", "<p>A pretend application.</p>"),
        "version": GLib.Variant("s", "1.0"),
    }
    return GLib.Variant("(a{sv})", (d,))

def emitir(nombre, params):
    conexion.emit_signal(None, "/org/mintmacos/Tienda1", "org.mintmacos.Tienda1", nombre, params)

def trabajo(tipo):
    estado["n"] += 1
    t = "t%d" % estado["n"]
    if tipo == "instalar":
        GLib.timeout_add(300, lambda: (emitir("Progreso", GLib.Variant("(sustt)", (t, 30, "descargando", 0, 0))) or False))
        GLib.timeout_add(900, lambda: (emitir("Progreso", GLib.Variant("(sustt)", (t, 80, "instalando", 0, 0))) or False))
        def fin():
            estado["instalada"] = True
            emitir("Terminado", GLib.Variant("(sbss)", (t, True, "", "")))
            return False
        GLib.timeout_add(1500, fin)
    else:
        def fin():
            estado["instalada"] = False
            emitir("Terminado", GLib.Variant("(sbss)", (t, True, "", "")))
            return False
        GLib.timeout_add(500, fin)
    return t

def metodo(con, remitente, ruta, ifaz, nombre, params, inv):
    global conexion
    conexion = con
    anotar(nombre)
    if nombre == "Estantes":
        inv.return_value(GLib.Variant("(a(ssssaa{sv}))", ([],)))
    elif nombre in ("Secciones", "Categorias"):
        inv.return_value(GLib.Variant("(a(ssas))", ([],)))
    elif nombre == "Ficha":
        inv.return_value(ficha())
    elif nombre == "Instalar":
        inv.return_value(GLib.Variant("(s)", (trabajo("instalar"),)))
    elif nombre == "Quitar":
        inv.return_value(GLib.Variant("(s)", (trabajo("quitar"),)))
    elif nombre == "Actualizar":
        inv.return_value(GLib.Variant("(s)", (trabajo("instalar"),)))
    elif nombre in ("Actualizaciones", "Buscar", "Resenas"):
        inv.return_value(GLib.Variant("(aa{sv})", ([],)))
    elif nombre == "Cancelar":
        inv.return_value(GLib.Variant("(b)", (False,)))

def al_conectar(con, nombre):
    global conexion
    conexion = con
    con.register_object("/org/mintmacos/Tienda1", Gio.DBusNodeInfo.new_for_xml(XML).interfaces[0], metodo, None, None)

Gio.bus_own_name(Gio.BusType.SESSION, "org.mintmacos.Tienda1", Gio.BusNameOwnerFlags.NONE, al_conectar, None, None)
anotar("listo")
GLib.MainLoop().run()
