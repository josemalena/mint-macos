#!/usr/bin/env python3
"""org.mintmacos.AppleID1 de mentira: la clave «password» pide un código, el código «123456» abre la sesión y cualquier clave de app
da 2 calendarios. No guarda ni anota secretos; solo los pasos en $APPLEID_REGISTRO. Uso: appleid-falso.py"""
import os
import gi
from gi.repository import Gio, GLib

XML = """<node><interface name="org.mintmacos.AppleID1">
<method name="Estado"><arg type="a{sv}" direction="out"/></method>
<method name="IniciarSesion"><arg type="s" direction="in"/><arg type="s" direction="in"/><arg type="a{sv}" direction="out"/></method>
<method name="EnviarCodigo"><arg type="s" direction="in"/><arg type="a{sv}" direction="out"/></method>
<method name="ConfigurarMail"><arg type="s" direction="in"/><arg type="s" direction="in"/><arg type="s" direction="in"/><arg type="a{sv}" direction="out"/></method>
<method name="CerrarSesion"/>
<signal name="Cambio"/>
</interface></node>"""
est = {"apple_id": "", "icloud_con_sesion": False, "icloud_montado": False, "mail_configurado": False}
pendiente = {"id": ""}

def anotar(paso):
    with open(os.environ.get("APPLEID_REGISTRO", "/dev/null"), "a") as f:
        f.write(paso + "\n")

def resp(resultado, mensaje="", cuantos=None):
    d = {"resultado": GLib.Variant("s", resultado), "mensaje": GLib.Variant("s", mensaje)}
    if cuantos is not None:
        d["cuantos_calendarios"] = GLib.Variant("i", cuantos)
    return GLib.Variant("(a{sv})", (d,))

def metodo(con, remitente, ruta, ifaz, nombre, params, inv):
    cambio = False
    if nombre == "Estado":
        d = {"apple_id": GLib.Variant("s", est["apple_id"]), "icloud_con_sesion": GLib.Variant("b", est["icloud_con_sesion"]),
             "icloud_montado": GLib.Variant("b", est["icloud_montado"]), "mail_configurado": GLib.Variant("b", est["mail_configurado"])}
        inv.return_value(GLib.Variant("(a{sv})", (d,)))
        return
    if nombre == "IniciarSesion":
        apple_id, clave = params.unpack()
        anotar("IniciarSesion " + apple_id)
        if clave == "password":
            pendiente["id"] = apple_id
            inv.return_value(resp("necesita_codigo", "Enter the verification code."))
        else:
            inv.return_value(resp("error", "Your Apple ID or password was incorrect."))
    elif nombre == "EnviarCodigo":
        (codigo,) = params.unpack()
        anotar("EnviarCodigo")
        if codigo == "123456":
            est.update(apple_id=pendiente["id"], icloud_con_sesion=True, icloud_montado=True)
            inv.return_value(resp("ok"))
            cambio = True
        else:
            inv.return_value(resp("error", "That code is not valid."))
    elif nombre == "ConfigurarMail":
        anotar("ConfigurarMail")
        est["mail_configurado"] = True
        inv.return_value(resp("ok", "", 2))
        cambio = True
    elif nombre == "CerrarSesion":
        anotar("CerrarSesion")
        est.update(apple_id="", icloud_con_sesion=False, icloud_montado=False, mail_configurado=False)
        inv.return_value(None)
        cambio = True
    if cambio:
        con.emit_signal(None, ruta, ifaz, "Cambio", None)

def al_conectar(con, nombre):
    con.register_object("/org/mintmacos/AppleID1", Gio.DBusNodeInfo.new_for_xml(XML).interfaces[0], metodo, None, None)

Gio.bus_own_name(Gio.BusType.SESSION, "org.mintmacos.AppleID1", Gio.BusNameOwnerFlags.NONE, al_conectar, None, None)
GLib.MainLoop().run()
