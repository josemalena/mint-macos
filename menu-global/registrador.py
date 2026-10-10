#!/usr/bin/python3
"""El registrador del menú global: com.canonical.AppMenu.Registrar.

Las apps que publican su menú por DBusMenu (Qt, Chrome, Edge, Electron,
Thunderbird y Firefox con widget.gtk.global-menu.enabled) le dicen aquí qué
ventana es suya y en qué ruta está el menú; la barra (globalmenu@macos) se lo
pregunta al cambiar de ventana.

Existe porque el que trae Mint (appmenu-registrar de vala-panel) se cierra
solo a los pocos segundos aunque se le pase -r: la barra lo activa en cada
cambio de foco, muere, y se lleva los registros. Las apps registran una sola
vez, al abrir la ventana, así que un registrador que se reinicia es uno que no
sabe nada.

Las apps GTK no pasan por aquí: appmenu-gtk-module publica un GMenuModel y lo
anuncia en propiedades X11 de la ventana (_GTK_MENUBAR_OBJECT_PATH).

Corre como servicio de usuario (appmenu-registrador.service) y lleva el
nombre mientras viva; si otro lo tiene al arrancar, espera en la cola.
"""

import signal
import sys

from gi.repository import Gio, GLib

NOMBRE = "com.canonical.AppMenu.Registrar"
RUTA = "/com/canonical/AppMenu/Registrar"

INTERFAZ = """
<node>
  <interface name="com.canonical.AppMenu.Registrar">
    <method name="RegisterWindow">
      <arg name="windowId" type="u" direction="in"/>
      <arg name="menuObjectPath" type="o" direction="in"/>
    </method>
    <method name="UnregisterWindow">
      <arg name="windowId" type="u" direction="in"/>
    </method>
    <method name="GetMenuForWindow">
      <arg name="windowId" type="u" direction="in"/>
      <arg name="service" type="s" direction="out"/>
      <arg name="menuObjectPath" type="o" direction="out"/>
    </method>
    <method name="GetMenus">
      <arg name="menus" type="a(uso)" direction="out"/>
    </method>
    <signal name="WindowRegistered">
      <arg name="windowId" type="u"/>
      <arg name="service" type="s"/>
      <arg name="menuObjectPath" type="o"/>
    </signal>
    <signal name="WindowUnregistered">
      <arg name="windowId" type="u"/>
    </signal>
  </interface>
</node>
"""


class Registrador:
    def __init__(self, bus):
        self.bus = bus
        # xid → (nombre único de la app en el bus, ruta del menú)
        self.ventanas = {}
        # nombre único → id de la vigilancia de su salida del bus
        self.vigilados = {}
        info = Gio.DBusNodeInfo.new_for_xml(INTERFAZ).interfaces[0]
        bus.register_object(RUTA, info, self.llamada, None, None)

    def llamada(self, bus, remitente, ruta, interfaz, metodo, args, invocacion):
        if metodo == "RegisterWindow":
            xid, menu = args.unpack()
            self.registrar(xid, remitente, menu)
            invocacion.return_value(None)
        elif metodo == "UnregisterWindow":
            (xid,) = args.unpack()
            # Solo la app dueña quita su ventana.
            if self.ventanas.get(xid, (None,))[0] == remitente:
                self.quitar(xid)
            invocacion.return_value(None)
        elif metodo == "GetMenuForWindow":
            (xid,) = args.unpack()
            servicio, menu = self.ventanas.get(xid, ("", "/"))
            invocacion.return_value(GLib.Variant("(so)", (servicio, menu)))
        elif metodo == "GetMenus":
            menus = [(x, s, m) for x, (s, m) in self.ventanas.items()]
            invocacion.return_value(GLib.Variant("(a(uso))", (menus,)))

    def registrar(self, xid, remitente, menu):
        self.ventanas[xid] = (remitente, menu)
        if remitente not in self.vigilados:
            self.vigilados[remitente] = Gio.bus_watch_name_on_connection(
                self.bus, remitente, Gio.BusNameWatcherFlags.NONE,
                None, self.app_salio)
        self.emitir("WindowRegistered", GLib.Variant("(uso)", (xid, remitente, menu)))

    def quitar(self, xid):
        del self.ventanas[xid]
        self.emitir("WindowUnregistered", GLib.Variant("(u)", (xid,)))

    def app_salio(self, bus, nombre):
        # La app se cerró o se cayó sin despedirse: se van todas sus ventanas.
        for xid in [x for x, (s, _) in self.ventanas.items() if s == nombre]:
            self.quitar(xid)
        Gio.bus_unwatch_name(self.vigilados.pop(nombre))

    def emitir(self, senal, args):
        self.bus.emit_signal(None, RUTA, NOMBRE, senal, args)


def main():
    bucle = GLib.MainLoop()
    bus = Gio.bus_get_sync(Gio.BusType.SESSION)
    Registrador(bus)

    estado = {"dueno": False}

    def adquirido(conexion, nombre):
        estado["dueno"] = True

    def perdido(conexion, nombre):
        # Al arrancar con otro dueño GDBus avisa «perdido» aunque quedemos en
        # la cola: solo se sale si ya lo teníamos.
        if estado["dueno"]:
            print(f"registrador: se perdió el nombre {nombre}", file=sys.stderr)
            bucle.quit()

    Gio.bus_own_name_on_connection(bus, NOMBRE, Gio.BusNameOwnerFlags.REPLACE,
                                   adquirido, perdido)
    GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, bucle.quit)
    bucle.run()


if __name__ == "__main__":
    main()
