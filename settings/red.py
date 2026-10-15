"""Network: el panel de Catalina (Screen Shot 2026-10-14 at 1.18.49 PM, Ethernet).

Los servicios de la izquierda son los dispositivos de NetworkManager (Ethernet, Wi-Fi, Bluetooth PAN, VLAN)
con su punto verde o rojo; a la derecha, el estado, la IP, la máscara, el router, el DNS, los dominios de
búsqueda y la IPv6, leídos con nmcli. Advanced… abre nm-connection-editor (TCP/IP, DNS, 802.1X, proxy…).
En Wi-Fi, Turn Wi-Fi On/Off enciende y apaga la radio (nmcli radio wifi).
Sin equivalente (en gris): Location, Configure IPv4 (se muestra el método actual: cambiarlo se hace en
Advanced…), +, −, el engranaje, Revert y Apply.
No hay captura de Wi-Fi escogido ni de la hoja + ni del menú ⚙.
"""
import os
import subprocess

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import GLib, Gtk  # noqa: E402

import paneles  # noqa: E402

NOMBRES = {"ethernet": "Ethernet", "wifi": "Wi-Fi", "bluetooth": "Bluetooth PAN", "vlan": "VLAN"}
ICONOS = {"ethernet": "network-wired-symbolic", "wifi": "network-wireless-symbolic",
          "bluetooth": "bluetooth-symbolic", "vlan": "network-wired-symbolic"}


def _nmcli(*args):
    try:
        r = subprocess.run(["nmcli", *args], capture_output=True, text=True, timeout=10)
        return r.stdout
    except (OSError, subprocess.SubprocessError):
        return ""


def dispositivos():
    """[{dev, tipo, nombre, estado, conexion}] de los tipos que Catalina llama servicios."""
    salida, vistos = [], {}
    for linea in _nmcli("-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "device", "status").splitlines():
        partes = linea.split(":")
        if len(partes) < 4 or partes[1] not in NOMBRES:
            continue
        dev, tipo, estado, con = partes[0], partes[1], partes[2], ":".join(partes[3:])
        n = vistos[tipo] = vistos.get(tipo, 0) + 1
        nombre = NOMBRES[tipo] + (" %d" % n if n > 1 else "")
        salida.append({"dev": dev, "tipo": tipo, "nombre": nombre, "estado": estado, "conexion": con})
    return salida


def detalle(dev):
    """Los campos de `nmcli device show` como {clave: [valores]}."""
    d = {}
    for linea in _nmcli("-t", "device", "show", dev).splitlines():
        k, _, v = linea.partition(":")
        d.setdefault(k.split("[")[0], []).append(v)
    return d


def mascara(prefijo):
    bits = (0xFFFFFFFF << (32 - prefijo)) & 0xFFFFFFFF
    return ".".join(str((bits >> s) & 255) for s in (24, 16, 8, 0))


def _gris(widget, motivo="Not available on this computer."):
    widget.set_sensitive(False)
    widget.set_tooltip_text(motivo)
    return widget


def _marco():
    m = Gtk.Frame()
    m.get_style_context().add_class("mp-sd-lista")
    return m


class PanelNetwork:
    id = "com.apple.preference.network"
    nombre = "Network"
    claves = []
    externo = False
    propio = True
    celda = None
    PRUEBA = bool(os.environ.get("MINT_RED_PRUEBA"))     # solo lee: no enciende ni apaga el Wi-Fi

    def __init__(self):
        self.panel = paneles.Panel(self.id, self.nombre, [],
                                   palabras="network, ethernet, wi-fi, wifi, ip address, dns, router, vpn, "
                                            "proxy, dhcp, bluetooth pan")
        self.ventana = None
        self._temporizador = None

    def coincide(self, texto):
        t = texto.lower().strip()
        return bool(t) and any(t in c.lower() for c in (self.nombre, self.panel.palabras, self.id))

    def construir(self):
        caja = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        caja.get_style_context().add_class("mp-propio")
        for lado in ("top", "bottom", "start", "end"):
            getattr(caja, "set_margin_" + lado)(14)
        loc = Gtk.Box(spacing=8)
        loc.set_halign(Gtk.Align.CENTER)
        loc.pack_start(Gtk.Label(label="Location:"), False, False, 0)
        combo = Gtk.ComboBoxText()
        combo.append("a", "Automatic")
        combo.set_active(0)
        loc.pack_start(_gris(combo, "Network locations do not exist on this computer."), False, False, 0)
        caja.pack_start(loc, False, False, 0)

        cuerpo = Gtk.Box(spacing=12)
        izq = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self._lista = Gtk.ListBox()
        self._lista.set_size_request(230, 270)
        self._lista.connect("row-selected", lambda _l, f: self._mostrar(f))
        ml = _marco()
        ml.add(self._lista)
        izq.pack_start(ml, True, True, 0)
        botones = Gtk.Box()
        botones.get_style_context().add_class("linked")
        for t in ("+", "−", "⚙"):
            botones.pack_start(_gris(Gtk.Button(label=t), "Use Advanced… to edit the connections."),
                               False, False, 0)
        izq.pack_start(botones, False, False, 4)
        cuerpo.pack_start(izq, False, False, 0)
        self._der = _marco()
        cuerpo.pack_start(self._der, True, True, 0)
        caja.pack_start(cuerpo, True, True, 0)

        pie = Gtk.Box(spacing=8)
        pie.pack_end(_gris(Gtk.Button(label="Apply")), False, False, 0)
        pie.pack_end(_gris(Gtk.Button(label="Revert")), False, False, 0)
        caja.pack_start(pie, False, False, 0)
        self._rellenar()
        caja.show_all()
        self._temporizador = GLib.timeout_add_seconds(5, self._refrescar)
        caja.connect("destroy", lambda _w: self._temporizador and GLib.source_remove(self._temporizador))
        return caja

    # ── la lista y el detalle ────────────────────────────────────────────
    def _rellenar(self):
        elegido = self._lista.get_selected_row()
        previo = getattr(elegido, "d", {}).get("dev") if elegido else None
        for f in self._lista.get_children():
            self._lista.remove(f)
        for d in dispositivos():
            fila = Gtk.ListBoxRow()
            fila.d = d
            h = Gtk.Box(spacing=8, margin=6)
            conectado = d["estado"].startswith("connected")
            punto = Gtk.Label()
            punto.set_markup('<span foreground="%s">●</span>' % ("#37c94b" if conectado else "#ff453a"))
            h.pack_start(punto, False, False, 0)
            v = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
            v.pack_start(Gtk.Label(label=d["nombre"], xalign=0), False, False, 0)
            estado = "Connected" if conectado else ("Off" if d["estado"] in ("unavailable", "disconnected")
                                                    and d["tipo"] == "wifi" and not self._wifi_encendido()
                                                    else "Not Connected")
            s = Gtk.Label(label=estado, xalign=0)
            s.get_style_context().add_class("mp-sd-detalle")
            v.pack_start(s, False, False, 0)
            h.pack_start(v, True, True, 0)
            h.pack_end(Gtk.Image.new_from_icon_name(ICONOS[d["tipo"]], Gtk.IconSize.LARGE_TOOLBAR), False, False, 0)
            fila.add(h)
            self._lista.add(fila)
            if d["dev"] == previo:
                self._lista.select_row(fila)
        self._lista.show_all()
        if self._lista.get_selected_row() is None and self._lista.get_children():
            self._lista.select_row(self._lista.get_row_at_index(0))

    def _refrescar(self):
        self._rellenar()
        return True

    @staticmethod
    def _wifi_encendido():
        return _nmcli("radio", "wifi").strip() == "enabled"

    def _mostrar(self, fila):
        for h in self._der.get_children():
            self._der.remove(h)
        if fila is None:
            return
        d = fila.d
        info = detalle(d["dev"])
        conectado = d["estado"].startswith("connected")
        g = Gtk.Grid(column_spacing=12, row_spacing=10, margin=18)
        fila_g = 0

        def poner(titulo, valor, gris=False, tip=None):
            nonlocal fila_g
            e = Gtk.Label(label=titulo, xalign=1.0)
            e.get_style_context().add_class("mp-fila-etiqueta")
            g.attach(e, 0, fila_g, 1, 1)
            v = Gtk.Label(label=valor, xalign=0)
            v.set_line_wrap(True)
            v.set_max_width_chars(40)
            v.set_selectable(True)
            g.attach(v, 1, fila_g, 1, 1)
            fila_g += 1
        e = Gtk.Label(label="Status:", xalign=1.0)
        e.get_style_context().add_class("mp-fila-etiqueta")
        g.attach(e, 0, 0, 1, 1)
        st = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        t = Gtk.Label(label="Connected" if conectado else "Not Connected", xalign=0)
        t.get_style_context().add_class("mp-titulo-negrita")
        st.pack_start(t, False, False, 0)
        ip4 = (info.get("IP4.ADDRESS") or [""])[0].split("/")[0]
        if conectado and ip4:
            s = Gtk.Label(label="%s is currently active and has the IP address %s." % (d["nombre"], ip4), xalign=0)
            s.set_line_wrap(True)
            s.set_max_width_chars(44)
            s.get_style_context().add_class("mp-sd-detalle")
            st.pack_start(s, False, False, 0)
        g.attach(st, 1, 0, 1, 1)
        fila_g = 1
        if d["tipo"] == "wifi":
            enc = self._wifi_encendido()
            b = Gtk.Button(label="Turn Wi-Fi %s" % ("Off" if enc else "On"))
            b.connect("clicked", lambda _b: self._alternar_wifi(enc))
            g.attach(b, 1, fila_g, 1, 1)
            fila_g += 1
        if conectado:
            # Configure IPv4: el método actual de la conexión; cambiarlo se hace en Advanced….
            metodo = _nmcli("-g", "ipv4.method", "connection", "show", d["conexion"]).strip()
            e = Gtk.Label(label="Configure IPv4:", xalign=1.0)
            e.get_style_context().add_class("mp-fila-etiqueta")
            g.attach(e, 0, fila_g, 1, 1)
            c = Gtk.ComboBoxText()
            c.append("m", {"auto": "Using DHCP", "manual": "Manually", "link-local": "Link-local only"}
                     .get(metodo, metodo or "Using DHCP"))
            c.set_active(0)
            g.attach(_gris(c, "Change the IPv4 method in Advanced…"), 1, fila_g, 1, 1)
            fila_g += 1
            prefijo = (info.get("IP4.ADDRESS") or [""])[0].partition("/")[2]
            poner("IP Address:", ip4)
            if prefijo.isdigit():
                poner("Subnet Mask:", mascara(int(prefijo)))
            poner("Router:", (info.get("IP4.GATEWAY") or [""])[0])
            poner("DNS Server:", ", ".join(info.get("IP4.DNS", [])))
            poner("Search Domains:", ", ".join(info.get("IP4.DOMAIN", [])))
            if info.get("IP6.ADDRESS"):
                poner("IPv6 Address:", info["IP6.ADDRESS"][0].split("/")[0])
        caja = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        caja.pack_start(g, False, False, 0)
        caja.pack_start(Gtk.Box(), True, True, 0)
        pie = Gtk.Box(margin=10)
        av = Gtk.Button(label="Advanced…")
        av.connect("clicked", lambda _b: self._avanzado())
        pie.pack_end(av, False, False, 0)
        caja.pack_start(pie, False, False, 0)
        self._der.add(caja)
        self._der.show_all()

    def _alternar_wifi(self, encendido):
        if self.PRUEBA:
            return
        _nmcli("radio", "wifi", "off" if encendido else "on")
        self._rellenar()

    def _avanzado(self):
        if self.PRUEBA:
            return
        try:
            subprocess.Popen(["nm-connection-editor"], start_new_session=True,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except OSError:
            pass
