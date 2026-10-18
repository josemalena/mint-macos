#!/usr/bin/env python3
"""Los falsos de la prueba de mint-macos-tienda: un PackageKit de mentira en su
propio bus y un servidor HTTP que hace de Flathub y de ODRS.

    falsos.py pk BUS DPKG REGISTRO      PackageKit en el bus BUS (dirección)
    falsos.py web PUERTO_ARCHIVO        Flathub y ODRS en 127.0.0.1:<puerto libre>

El PackageKit conoce cuatro paquetes: juego-apt (se puede instalar), prohibido
(da NotAuthorized, como un polkit cancelado), editor-viejo (instalado, con
actualización: tiene ficha, va en «apps») y libalgo (actualización sin ficha:
«sistema»). Instalar y quitar escriben en el dpkg/status de la prueba, como dpkg.
"""
import http.server
import json
import socketserver
import sys
import threading

from gi.repository import Gio, GLib

TX_XML = """<node><interface name="org.freedesktop.PackageKit.Transaction">
<method name="SetHints"><arg type="as" direction="in"/></method>
<method name="Cancel"/>
<method name="Resolve"><arg type="t" direction="in"/><arg type="as" direction="in"/></method>
<method name="GetUpdates"><arg type="t" direction="in"/></method>
<method name="GetDetails"><arg type="as" direction="in"/></method>
<method name="InstallPackages"><arg type="t" direction="in"/><arg type="as" direction="in"/></method>
<method name="RemovePackages"><arg type="t" direction="in"/><arg type="as" direction="in"/><arg type="b" direction="in"/><arg type="b" direction="in"/></method>
<method name="UpdatePackages"><arg type="t" direction="in"/><arg type="as" direction="in"/></method>
<method name="RefreshCache"><arg type="b" direction="in"/></method>
<signal name="Package"><arg type="u"/><arg type="s"/><arg type="s"/></signal>
<signal name="Details"><arg type="a{sv}"/></signal>
<signal name="ErrorCode"><arg type="u"/><arg type="s"/></signal>
<signal name="Finished"><arg type="u"/><arg type="u"/></signal>
</interface></node>"""
PK_XML = """<node><interface name="org.freedesktop.PackageKit">
<method name="CreateTransaction"><arg type="o" direction="out"/></method>
</interface></node>"""

DISPONIBLES = {"juego-apt": "1.0", "prohibido": "1.0", "editor-viejo": "2.0", "libalgo": "1.1"}
ACTUALIZACIONES = {"editor-viejo": "2.0", "libalgo": "1.1"}


def pk(bus_dir, dpkg, registro):
    log = open(registro, "a", buffering=1)
    con = Gio.DBusConnection.new_for_address_sync(bus_dir, Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION, None, None)
    cuenta = [0]

    def instalados():
        out = {}
        for p in open(dpkg).read().split("\n\n"):
            d = dict(l.split(": ", 1) for l in p.splitlines() if ": " in l)
            if d.get("Status") == "install ok installed":
                out[d["Package"]] = d.get("Version", "")
        return out

    def escribir(nuevos):
        with open(dpkg, "w") as f:
            for n, v in nuevos.items():
                f.write("Package: %s\nStatus: install ok installed\nVersion: %s\n\n" % (n, v))

    def tx_llamada(c, remitente, ruta, iface, metodo, params, inv):
        args = params.unpack()
        log.write("%s %s\n" % (metodo, json.dumps(args)))
        inv.return_value(None)
        senales = []

        def pkg(info, nombre, version, resumen=""):
            senales.append(("Package", GLib.Variant("(uss)", (info, "%s;%s;amd64;ubuntu" % (nombre, version), resumen))))

        def props(pct, status):
            senales.append(("PropertiesChanged", GLib.Variant("(sa{sv}as)", ("org.freedesktop.PackageKit.Transaction", {"Percentage": GLib.Variant("u", pct), "Status": GLib.Variant("u", status)}, []))))

        exit_ = 1
        inst = instalados()
        if metodo == "Resolve":
            filtro, nombres = args
            for n in nombres:
                if filtro & 4 and n in inst:
                    pkg(1, n, inst[n])
                elif filtro & 8 and n not in inst and n in DISPONIBLES:
                    pkg(2, n, DISPONIBLES[n])
                elif not filtro & 12 and n in DISPONIBLES:
                    pkg(2, n, DISPONIBLES[n])
        elif metodo == "GetUpdates":
            for n, v in ACTUALIZACIONES.items():
                if n in inst and inst[n] != v:
                    pkg(5, n, v, "actualización de " + n)
        elif metodo == "GetDetails":
            senales.append(("Details", GLib.Variant("(a{sv})", ({"package-id": GLib.Variant("s", args[0][0]), "size": GLib.Variant("t", 4096000), "download-size": GLib.Variant("t", 1024000)},))))
        elif metodo in ("InstallPackages", "UpdatePackages", "RemovePackages"):
            ids = args[1]
            if any(i.startswith("prohibido;") for i in ids):
                props(0, 31)
                senales.append(("ErrorCode", GLib.Variant("(us)", (48, "Not authorized"))))
                exit_ = 2
            else:
                props(10, 31)
                props(40, 8)
                props(80, 6 if metodo == "RemovePackages" else 9)
                for i in ids:
                    n, v = i.split(";")[:2]
                    if metodo == "RemovePackages":
                        inst.pop(n, None)
                    else:
                        inst[n] = v
                escribir(inst)
                props(100, 18)
        elif metodo == "RefreshCache":
            props(50, 7)
            props(100, 18)
        if metodo in ("SetHints", "Cancel"):
            return
        senales.append(("Finished", GLib.Variant("(uu)", (exit_, 10))))

        def emitir():
            for nombre, cuerpo in senales:
                i = "org.freedesktop.DBus.Properties" if nombre == "PropertiesChanged" else iface
                c.emit_signal(None, ruta, i, nombre, cuerpo)
            return False
        GLib.timeout_add(50, emitir)

    tx_iface = Gio.DBusNodeInfo.new_for_xml(TX_XML).interfaces[0]

    def pk_llamada(c, remitente, ruta, iface, metodo, params, inv):
        cuenta[0] += 1
        r = "/t/%d" % cuenta[0]
        c.register_object(r, tx_iface, tx_llamada, None, None)
        inv.return_value(GLib.Variant("(o)", (r,)))

    con.register_object("/org/freedesktop/PackageKit", Gio.DBusNodeInfo.new_for_xml(PK_XML).interfaces[0], pk_llamada, None, None)
    con.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "RequestName", GLib.Variant("(su)", ("org.freedesktop.PackageKit", 4)), None, 0, -1, None)
    print("listo", flush=True)
    GLib.MainLoop().run()


RESPUESTAS = {
    "/api/v2/collection/popular": {"hits": [{"app_id": "org.mintmacos.Juguete"}, {"app_id": "no.esta.En.El.Catalogo"}]},
    "/api/v2/collection/trending": {"hits": [{"app_id": "org.mintmacos.Juguete"}]},
    "/api/v2/collection/recently-added": {"hits": []},
    "/api/v2/stats/org.mintmacos.Juguete": {"installs_last_month": 1234},
    "/odrs/ratings/org.mintmacos.Juguete": {"star0": 0, "star1": 1, "star2": 0, "star3": 0, "star4": 1, "star5": 2, "total": 4},
}


class Manejador(http.server.BaseHTTPRequestHandler):
    def responder(self, obj):
        if obj is None:
            self.send_response(404)
            self.end_headers()
            return
        b = json.dumps(obj).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b)

    def do_GET(self):
        ruta = self.path.split("?")[0]
        if ruta == "/icono.png":
            b = b"\x89PNG\r\n\x1a\n" + b"\0" * 64   # basta con la firma
            self.send_response(200)
            self.send_header("Content-Type", "image/png")
            self.end_headers()
            self.wfile.write(b)
            return
        if ruta.startswith("/api/v2/app-picks/app-of-the-day/"):
            return self.responder({"app_id": "org.mintmacos.Juguete", "day": ruta.rsplit("/", 1)[1]})
        self.responder(RESPUESTAS.get(ruta))

    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        pedido = json.loads(self.rfile.read(n) or b"{}")
        if self.path == "/odrs/fetch" and pedido.get("user_hash") == "0" * 40:
            return self.responder([
                {"summary": "Muy bueno", "description": "Lo uso todos los días", "rating": 100, "user_display": "Ana", "date_created": 1790000000.0, "version": "1", "distro": "Linux Mint", "reported": 0},
                {"summary": "Spam", "description": "x", "rating": 20, "reported": 1},
            ])
        self.responder(None)

    def log_message(self, *a):
        pass


def web(archivo_puerto):
    srv = socketserver.TCPServer(("127.0.0.1", 0), Manejador)
    open(archivo_puerto, "w").write(str(srv.server_address[1]))
    srv.serve_forever()


if __name__ == "__main__":
    if sys.argv[1] == "pk":
        pk(*sys.argv[2:5])
    else:
        web(sys.argv[2])
