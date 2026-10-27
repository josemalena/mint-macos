#!/usr/bin/env python3
"""Una app de mentira que publica com.canonical.dbusmenu y un registrador de mentira (com.canonical.AppMenu.Registrar), para
probar org.mintmacos.Menu1 sin Firefox. Uso: dbusmenu-falso.py XID REGISTRO. Anota en REGISTRO cada AboutToShow y cada Event."""
import sys
import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gio, GLib, Gtk  # noqa: E402

xid = int(sys.argv[1])
registro = sys.argv[2]

def anotar(texto):
    with open(registro, "a") as f:
        f.write(texto + "\n")

XML_MENU = """<node><interface name="com.canonical.dbusmenu">
<method name="GetLayout"><arg type="i" direction="in"/><arg type="i" direction="in"/><arg type="as" direction="in"/><arg type="u" direction="out"/><arg type="(ia{sv}av)" direction="out"/></method>
<method name="AboutToShow"><arg type="i" direction="in"/><arg type="b" direction="out"/></method>
<method name="Event"><arg type="i" direction="in"/><arg type="s" direction="in"/><arg type="v" direction="in"/><arg type="u" direction="in"/></method>
<signal name="LayoutUpdated"><arg type="u"/><arg type="i"/></signal>
</interface></node>"""
XML_REG = """<node><interface name="com.canonical.AppMenu.Registrar">
<method name="GetMenuForWindow"><arg type="u" direction="in"/><arg type="s" direction="out"/><arg type="o" direction="out"/></method>
</interface></node>"""

def it(i, props, hijos=()):
    d = {k: GLib.Variant("s" if isinstance(v, str) else "b", v) for k, v in props.items()}
    return GLib.Variant("(ia{sv}av)", (i, d, [GLib.Variant("(ia{sv}av)", h) for h in hijos]))

def hoja(i, label, **extra):
    p = {"label": label}
    p.update(extra)
    d = {k: GLib.Variant("s" if isinstance(v, str) else "b", v) for k, v in p.items()}
    if "shortcut" in extra:
        d["shortcut"] = GLib.Variant("aas", [["Control", "n"]])
    return (i, d, [])

def arbol():
    d_ = lambda **p: {k: GLib.Variant("s" if isinstance(v, str) else "b", v) for k, v in p.items()}
    archivo = (1, d_(label="_File", **{"children-display": "submenu"}),
               [GLib.Variant("(ia{sv}av)", h) for h in [hoja(2, "_New", shortcut=True), (3, d_(type="separator"), []), hoja(4, "Quit")]])
    edicion = (5, d_(label="_Edit", **{"children-display": "submenu"}), [GLib.Variant("(ia{sv}av)", hoja(6, "Copy", enabled=False))])
    # El menú propio de la app (Cocotron, Fynder): primer hijo de la raíz, marcado x-constanza-app-menu
    app = (8, d_(label="FalsoApp", **{"children-display": "submenu", "x-constanza-app-menu": True}),
           [GLib.Variant("(ia{sv}av)", h) for h in [hoja(9, "About FalsoApp"), (10, d_(type="separator"), []), hoja(11, "Quit FalsoApp")]])
    return (0, {}, [GLib.Variant("(ia{sv}av)", app), GLib.Variant("(ia{sv}av)", archivo), GLib.Variant("(ia{sv}av)", edicion)])

def raiz():
    r = arbol()
    return GLib.Variant("(ia{sv}av)", r)

def buscar(v, i):
    """El subárbol (ia{sv}av) con ese id, o None."""
    if v.get_child_value(0).get_int32() == i:
        return v
    av = v.get_child_value(2)
    for k in range(av.n_children()):
        r = buscar(av.get_child_value(k).get_variant(), i)
        if r is not None:
            return r
    return None

def filtrar(v, nombres):
    """Como libdbusmenu: solo las propiedades que el cliente pide (propertyNames; vacío = todas), en todo el subárbol."""
    i = v.get_child_value(0).get_int32()
    dic = v.get_child_value(1)
    props = {}
    for k in range(dic.n_children()):
        par = dic.get_child_value(k)
        nombre = par.get_child_value(0).get_string()
        if not nombres or nombre in nombres:
            props[nombre] = par.get_child_value(1).get_variant()
    av = v.get_child_value(2)
    hijos = [filtrar(av.get_child_value(k).get_variant(), nombres) for k in range(av.n_children())]
    return GLib.Variant("(ia{sv}av)", (i, props, hijos))

def metodo_menu(con, remitente, ruta, ifaz, nombre, params, inv):
    if nombre == "GetLayout":
        padre, _prof, nombres = params.unpack()
        # Como el servidor real: el subárbol que pide el cliente.
        sub = buscar(raiz(), padre)
        if nombres:
            sub = filtrar(sub, nombres)
        inv.return_value(GLib.Variant.new_tuple(GLib.Variant.new_uint32(1), sub))
    elif nombre == "AboutToShow":
        anotar("AboutToShow %d" % params.unpack()[0])
        inv.return_value(GLib.Variant("(b)", (False,)))
    elif nombre == "Event":
        i, ev, _v, _t = params.unpack()
        anotar("Event %d %s" % (i, ev))
        inv.return_value(None)

def metodo_reg(con, remitente, ruta, ifaz, nombre, params, inv):
    if nombre == "GetMenuForWindow" and params.unpack()[0] == xid:
        inv.return_value(GLib.Variant("(so)", ("org.fake.dbusmenu", "/MenuBar")))
    else:
        inv.return_error_literal(Gio.dbus_error_quark(), 0, "sin menú")

def al_conectar(con, nombre):
    con.register_object("/MenuBar", Gio.DBusNodeInfo.new_for_xml(XML_MENU).interfaces[0], metodo_menu, None, None)
def al_conectar_reg(con, nombre):
    con.register_object("/com/canonical/AppMenu/Registrar", Gio.DBusNodeInfo.new_for_xml(XML_REG).interfaces[0], metodo_reg, None, None)

Gio.bus_own_name(Gio.BusType.SESSION, "org.fake.dbusmenu", Gio.BusNameOwnerFlags.NONE, al_conectar, None, None)
Gio.bus_own_name(Gio.BusType.SESSION, "com.canonical.AppMenu.Registrar", Gio.BusNameOwnerFlags.NONE, al_conectar_reg, None, None)
anotar("listo")
GLib.MainLoop().run()
