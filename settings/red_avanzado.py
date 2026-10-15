"""Network ▸ Advanced…: la hoja de Catalina con sus seis pestañas (TCP/IP, DNS, WINS, 802.1X, Proxies, Hardware).

Capturas: Screen Shot 2026-10-14 at 1.18.56 PM (TCP/IP), 1.18.59 (DNS), 1.19.01 (WINS), 1.19.04 (802.1X),
1.19.07 (Proxies) y 1.19.12 (Hardware).

Reales, por NetworkManager (nmcli connection modify):
  TCP/IP    Configure IPv4 y IPv6, dirección, máscara y router, DHCP Client ID (ipv4.*, ipv6.*)
  DNS       los servidores y los dominios de búsqueda (ipv4.dns, ipv4.dns-search)
  802.1X    solo «Enable automatic connection» (connection.autoconnect)
  Hardware  Configure Automatically/Manually, Speed, Duplex y MTU (802-3-ethernet.*)
En gris, como en una Mac sin esa función: WINS, Renew DHCP Lease, el perfil 802.1X y AVB/EAV. Proxies va en
gris: el proxy del sistema no es por conexión y la captura no trae el panel de servidor y puerto de cada
protocolo (hay que pedirla); la lista y los textos son los de la captura.

CAMBIAR LA RED ES DELICADO: OK no aplica a ciegas. Guarda los valores de antes, aplica (modify + up) y enseña
«Do you want to keep these network settings?» con 15 s: sin «Keep» vuelve a lo de antes. MINT_RED_SIMULAR=1 no
ejecuta nada: imprime lo que haría (y da por confirmado el cambio).
"""
import ipaddress
import os
import re
import subprocess
import sys

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import GLib, Gtk  # noqa: E402

SIMULAR = bool(os.environ.get("MINT_RED_SIMULAR"))
CAMPOS = ["connection.id", "connection.autoconnect", "ipv4.method", "ipv4.addresses", "ipv4.gateway",
          "ipv4.dns", "ipv4.dns-search", "ipv4.dhcp-client-id", "ipv6.method", "ipv6.addresses", "ipv6.gateway",
          "802-3-ethernet.mac-address", "802-3-ethernet.mtu", "802-3-ethernet.auto-negotiate",
          "802-3-ethernet.speed", "802-3-ethernet.duplex"]
MOTIVO = "Not available on this computer."


def _nmcli(*args, tiempo=20):
    if SIMULAR and args[:2] in (("connection", "modify"), ("connection", "up")):
        print("[simulación] nmcli", *args, file=sys.stderr)
        return True, ""
    try:
        r = subprocess.run(["nmcli", *args], capture_output=True, text=True, timeout=tiempo)
        return r.returncode == 0, (r.stdout if r.returncode == 0 else (r.stderr or r.stdout)).strip()
    except (OSError, subprocess.SubprocessError) as e:
        return False, str(e)


def _desescapar(v):
    return v.replace("\\:", ":").replace("\\\\", "\\")


def leer_perfil(nombre):
    """{campo: valor} de la conexión, con nmcli en modo terse (los «:» de IPv6 vienen escapados)."""
    ok, salida = _nmcli("-t", "-f", ",".join(CAMPOS), "connection", "show", nombre)
    perfil = {}
    if not ok:
        return perfil
    for linea in salida.splitlines():
        k, _, v = linea.partition(":")
        perfil[k] = _desescapar(v)
    return perfil


def mascara_de(prefijo):
    return str(ipaddress.IPv4Network("0.0.0.0/%d" % prefijo).netmask)


def prefijo_de(mascara):
    try:
        return ipaddress.IPv4Network("0.0.0.0/%s" % mascara).prefixlen
    except ValueError:
        return None


def _gris(w, motivo=MOTIVO):
    w.set_sensitive(False)
    w.set_tooltip_text(motivo)
    return w


def _marco():
    m = Gtk.Frame()
    m.get_style_context().add_class("mp-sd-lista")
    return m


def _etiqueta(texto):
    l = Gtk.Label(label=texto, xalign=1.0)
    l.get_style_context().add_class("mp-fila-etiqueta")
    return l


class HojaAvanzada(Gtk.Dialog):
    METODOS4 = [("auto", "Using DHCP"), ("auto+manual", "Using DHCP with manual address"),
                ("manual", "Manually"), ("disabled", "Off")]
    METODOS6 = [("auto", "Automatically"), ("manual", "Manually"), ("link-local", "Link-local only"),
                ("disabled", "Off")]

    def __init__(self, ventana, dispositivo, info_viva):
        super().__init__(transient_for=ventana, modal=True)
        self.set_decorated(False)
        self.get_style_context().add_class("mp-hoja")
        self.dispositivo = dispositivo
        self.viva = info_viva                       # lo que `nmcli device show` dice ahora
        self.nombre_con = dispositivo["conexion"]
        self.antes = leer_perfil(self.nombre_con)   # el perfil como estaba al abrir
        c = self.get_content_area()
        c.set_spacing(10)
        for lado in ("top", "bottom", "start", "end"):
            getattr(c, "set_margin_" + lado)(18)
        cab = Gtk.Box(spacing=10)
        cab.pack_start(Gtk.Image.new_from_icon_name("network-wired-symbolic", Gtk.IconSize.LARGE_TOOLBAR),
                       False, False, 0)
        cab.pack_start(Gtk.Label(label=dispositivo["nombre"]), False, False, 0)
        c.pack_start(cab, False, False, 0)

        self.pila = Gtk.Stack()
        self.pila.add_titled(self._tcpip(), "tcpip", "TCP/IP")
        self.pila.add_titled(self._dns(), "dns", "DNS")
        self.pila.add_titled(self._wins(), "wins", "WINS")
        self.pila.add_titled(self._dot1x(), "dot1x", "802.1X")
        self.pila.add_titled(self._proxies(), "proxies", "Proxies")
        self.pila.add_titled(self._hardware(), "hardware", "Hardware")
        pestanas = Gtk.StackSwitcher()
        pestanas.set_stack(self.pila)
        pestanas.set_halign(Gtk.Align.CENTER)
        pestanas.get_style_context().add_class("mp-pestanas")
        c.pack_start(pestanas, False, False, 0)
        marco = _marco()
        marco.add(self.pila)
        marco.set_size_request(620, 400)
        c.pack_start(marco, True, True, 0)

        ayuda = Gtk.Button(label="?")
        ayuda.set_sensitive(False)
        self.add_action_widget(ayuda, Gtk.ResponseType.HELP)
        self.add_button("Cancel", Gtk.ResponseType.CANCEL)
        ok = self.add_button("OK", Gtk.ResponseType.OK)
        ok.get_style_context().add_class("suggested-action")
        self.set_default_response(Gtk.ResponseType.OK)
        self.show_all()

    # ── TCP/IP ───────────────────────────────────────────────────────────
    def _viva(self, clave, indice=0):
        v = self.viva.get(clave) or []
        return v[indice] if len(v) > indice else ""

    def _tcpip(self):
        p = self.antes
        g = Gtk.Grid(column_spacing=12, row_spacing=10, margin=24)
        g.set_halign(Gtk.Align.CENTER)
        g.attach(_etiqueta("Configure IPv4:"), 0, 0, 1, 1)
        self.c4 = Gtk.ComboBoxText()
        for k, n in self.METODOS4:
            self.c4.append(k, n)
        metodo = p.get("ipv4.method", "auto")
        if metodo == "auto" and p.get("ipv4.addresses"):
            metodo = "auto+manual"
        if not self.c4.set_active_id(metodo):
            self.c4.append(metodo, metodo)
            self.c4.set_active_id(metodo)
        g.attach(self.c4, 1, 0, 2, 1)
        # La dirección del perfil (si es manual) o, con DHCP, la que tiene ahora.
        fuente = p.get("ipv4.addresses", "").split(",")[0] or self._viva("IP4.ADDRESS")
        ip4, _, pref4 = fuente.partition("/")
        self.e_ip4, self.e_mask, self.e_router = Gtk.Entry(text=ip4), Gtk.Entry(), Gtk.Entry(
            text=p.get("ipv4.gateway", "") or self._viva("IP4.GATEWAY"))
        if pref4.isdigit():
            self.e_mask.set_text(mascara_de(int(pref4)))
        for fila, (rot, e) in enumerate((("IPv4 Address:", self.e_ip4), ("Subnet Mask:", self.e_mask),
                                         ("Router:", self.e_router)), start=1):
            g.attach(_etiqueta(rot), 0, fila, 1, 1)
            g.attach(e, 1, fila, 1, 1)
        g.attach(_gris(Gtk.Button(label="Renew DHCP Lease"), "Reconnect the connection to renew the lease."),
                 2, 1, 1, 1)
        self.e_cid = Gtk.Entry(text=p.get("ipv4.dhcp-client-id", ""))
        caja_cid = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        fila_cid = Gtk.Box(spacing=8)
        fila_cid.pack_start(_etiqueta("DHCP Client ID:"), False, False, 0)
        fila_cid.pack_start(self.e_cid, True, True, 0)
        caja_cid.pack_start(fila_cid, False, False, 0)
        nota = Gtk.Label(label="(If required)")
        nota.get_style_context().add_class("mp-sd-detalle")
        caja_cid.pack_start(nota, False, False, 0)
        g.attach(caja_cid, 2, 2, 1, 2)
        self.c4.connect("changed", lambda _c: self._tipo4())
        self._tipo4()

        g.attach(Gtk.Separator(), 0, 4, 3, 1)
        g.attach(_etiqueta("Configure IPv6:"), 0, 5, 1, 1)
        self.c6 = Gtk.ComboBoxText()
        for k, n in self.METODOS6:
            self.c6.append(k, n)
        m6 = p.get("ipv6.method", "auto")
        if not self.c6.set_active_id(m6):
            self.c6.append(m6, m6)
            self.c6.set_active_id(m6)
        g.attach(self.c6, 1, 5, 2, 1)
        g.attach(_etiqueta("Router:"), 0, 6, 1, 1)
        g.attach(Gtk.Label(label=p.get("ipv6.gateway", "") or self._viva("IP6.GATEWAY"), xalign=0), 1, 6, 2, 1)
        lista = Gtk.ListStore(str, str)
        for d in self.viva.get("IP6.ADDRESS", []):
            dirc, _, pref = d.partition("/")
            lista.append([dirc, pref])
        arbol = Gtk.TreeView(model=lista)
        for i, t in enumerate(("IPv6 Address", "Prefix Length")):
            arbol.append_column(Gtk.TreeViewColumn(t, Gtk.CellRendererText(), text=i))
        pant = Gtk.ScrolledWindow()
        pant.set_size_request(-1, 90)
        pant.add(arbol)
        m = _marco()
        m.add(pant)
        g.attach(m, 1, 7, 2, 1)
        return g

    def _tipo4(self):
        """Dirección, máscara y router solo se escriben con una dirección manual; con DHCP se enseñan, quietos."""
        manual = self.c4.get_active_id() in ("manual", "auto+manual")
        for e in (self.e_ip4, self.e_mask):
            e.set_sensitive(manual)
        self.e_router.set_sensitive(self.c4.get_active_id() == "manual")

    # ── DNS ──────────────────────────────────────────────────────────────
    def _lista_editable(self, titulo, manuales, automaticos, nota=None):
        caja = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        caja.pack_start(Gtk.Label(label=titulo, xalign=0), False, False, 0)
        modelo = Gtk.ListStore(str, bool)          # texto, ¿es automático (en gris)?
        for t in manuales:
            modelo.append([t, False])
        for t in automaticos:
            if t not in manuales:
                modelo.append([t, True])
        arbol = Gtk.TreeView(model=modelo)
        arbol.set_headers_visible(False)
        celda = Gtk.CellRendererText()
        celda.set_property("editable", True)

        def editado(_c, ruta, texto):
            if modelo[ruta][1] is False and texto.strip():
                modelo[ruta][0] = texto.strip()
        celda.connect("edited", editado)
        col = Gtk.TreeViewColumn("", celda, text=0)
        col.set_cell_data_func(celda, lambda _c, r, m, it, _d: (
            r.set_property("foreground", "#7d7d7d" if m[it][1] else None),
            r.set_property("editable", not m[it][1])))
        arbol.append_column(col)
        pant = Gtk.ScrolledWindow()
        pant.set_size_request(-1, 280)
        pant.add(arbol)
        m = _marco()
        m.add(pant)
        caja.pack_start(m, True, True, 0)
        botones = Gtk.Box(spacing=0)
        lig = Gtk.Box()
        lig.get_style_context().add_class("linked")
        mas, menos = Gtk.Button(label="+"), Gtk.Button(label="−")
        mas.connect("clicked", lambda _b: self._nueva_fila(arbol, modelo))
        menos.connect("clicked", lambda _b: self._quitar_fila(arbol, modelo))
        lig.pack_start(mas, False, False, 0)
        lig.pack_start(menos, False, False, 0)
        botones.pack_start(lig, False, False, 0)
        if nota:
            n = Gtk.Label(label=nota, margin_start=10)
            botones.pack_start(n, False, False, 0)
        caja.pack_start(botones, False, False, 0)
        return caja, modelo

    @staticmethod
    def _nueva_fila(arbol, modelo):
        it = modelo.append(["", False])
        arbol.set_cursor(modelo.get_path(it), arbol.get_column(0), True)

    @staticmethod
    def _quitar_fila(arbol, modelo):
        _m, it = arbol.get_selection().get_selected()
        if it is not None and not modelo[it][1]:
            modelo.remove(it)

    def _dns(self):
        p = self.antes
        g = Gtk.Box(spacing=20, margin=24)
        c1, self.m_dns = self._lista_editable(
            "DNS Servers:", [x for x in p.get("ipv4.dns", "").split(",") if x],
            self.viva.get("IP4.DNS", []), "IPv4 or IPv6 addresses")
        c2, self.m_dom = self._lista_editable(
            "Search Domains:", [x for x in p.get("ipv4.dns-search", "").split(",") if x],
            self.viva.get("IP4.DOMAIN", []))
        g.pack_start(c1, True, True, 0)
        g.pack_start(c2, True, True, 0)
        return g

    # ── WINS, 802.1X, Proxies: lo que no se puede, como en la captura y en gris ───────────
    def _wins(self):
        g = Gtk.Grid(column_spacing=10, row_spacing=10, margin=30)
        g.set_halign(Gtk.Align.CENTER)
        g.attach(_etiqueta("NetBIOS Name:"), 0, 0, 1, 1)
        g.attach(_gris(Gtk.Entry(text=GLib.get_host_name().upper())), 1, 0, 1, 1)
        g.attach(_etiqueta("Workgroup:"), 0, 1, 1, 1)
        w = Gtk.ComboBoxText()
        w.append("w", "WORKGROUP")
        w.set_active(0)
        g.attach(_gris(w), 1, 1, 1, 1)
        g.attach(_etiqueta("WINS Servers:"), 0, 2, 1, 1)
        m = _marco()
        m.set_size_request(250, 130)
        g.attach(_gris(m), 1, 2, 1, 1)
        lig = Gtk.Box()
        lig.get_style_context().add_class("linked")
        for t in ("+", "−"):
            lig.pack_start(_gris(Gtk.Button(label=t)), False, False, 0)
        g.attach(lig, 1, 3, 1, 1)
        return g

    def _dot1x(self):
        caja = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10, margin=24)
        t = Gtk.Label(label="Use a configuration profile to add an 802.1X profile to your system. Contact your "
                            "system administrator for more information.", xalign=0)
        t.set_line_wrap(True)
        t.set_max_width_chars(70)
        caja.pack_start(t, False, False, 0)
        cuerpo = Gtk.Box(spacing=10)
        izq = _marco()
        izq.set_size_request(180, 200)
        cuerpo.pack_start(_gris(izq), False, False, 0)
        der = _marco()
        d = Gtk.Grid(column_spacing=10, row_spacing=8, margin=18)
        titulo = Gtk.Label(label="Profile Information", xalign=0)
        titulo.get_style_context().add_class("mp-titulo-negrita")
        d.attach(titulo, 0, 0, 2, 1)
        for i, rot in enumerate(("Name:", "Authentication:", "Wireless Network:", "Security Type:",
                                 "Trusted Certificate:", "Trusted Servers:"), start=1):
            e = _etiqueta(rot)
            e.get_style_context().add_class("mp-titulo-negrita")
            d.attach(e, 0, i, 1, 1)
        der.add(d)
        cuerpo.pack_start(_gris(der), True, True, 0)
        caja.pack_start(cuerpo, True, True, 0)
        self.auto = Gtk.CheckButton(label="Enable automatic connection")
        self.auto.set_active(self.antes.get("connection.autoconnect", "yes") == "yes")
        caja.pack_start(self.auto, False, False, 0)
        return caja

    def _proxies(self):
        caja = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8, margin=24)
        caja.pack_start(Gtk.Label(label="Select a protocol to configure:", xalign=0), False, False, 0)
        lista = Gtk.ListBox()
        for n in ("Auto Proxy Discovery", "Automatic Proxy Configuration", "Web Proxy (HTTP)",
                  "Secure Web Proxy (HTTPS)", "FTP Proxy", "SOCKS Proxy", "Streaming Proxy (RTSP)", "Gopher Proxy"):
            fila = Gtk.ListBoxRow()
            h = Gtk.Box(spacing=8, margin=3)
            h.pack_start(Gtk.CheckButton(), False, False, 0)
            h.pack_start(Gtk.Label(label=n, xalign=0), False, False, 0)
            fila.add(h)
            lista.add(fila)
        m = _marco()
        m.add(lista)
        m.set_halign(Gtk.Align.START)
        caja.pack_start(_gris(m, "The system proxy is not set per connection here."), False, False, 0)
        caja.pack_start(_gris(Gtk.CheckButton(label="Exclude simple hostnames")), False, False, 0)
        caja.pack_start(Gtk.Label(label="Bypass proxy settings for these Hosts & Domains:", xalign=0),
                        False, False, 0)
        tv = Gtk.TextView()
        tv.get_buffer().set_text("*.local, 169.254/16")
        mt = _marco()
        mt.set_size_request(-1, 70)
        mt.add(tv)
        caja.pack_start(_gris(mt), False, False, 0)
        pasivo = Gtk.CheckButton(label="Use Passive FTP Mode (PASV)")
        pasivo.set_active(True)
        pasivo.set_halign(Gtk.Align.CENTER)
        caja.pack_start(_gris(pasivo), False, False, 0)
        return caja

    # ── Hardware ─────────────────────────────────────────────────────────
    def _hardware(self):
        p = self.antes
        g = Gtk.Grid(column_spacing=12, row_spacing=10, margin=30)
        g.set_halign(Gtk.Align.CENTER)
        g.attach(_etiqueta("MAC Address:"), 0, 0, 1, 1)
        g.attach(Gtk.Label(label=(self._viva("GENERAL.HWADDR") or p.get("802-3-ethernet.mac-address", "")).lower(), xalign=0),
                 1, 0, 1, 1)
        g.attach(_etiqueta("Configure:"), 0, 1, 1, 1)
        self.c_hw = Gtk.ComboBoxText()
        self.c_hw.append("auto", "Automatically")
        self.c_hw.append("manual", "Manually")
        auto = p.get("802-3-ethernet.auto-negotiate", "no") == "yes" or \
            (p.get("802-3-ethernet.speed", "0") == "0" and not p.get("802-3-ethernet.duplex"))
        self.c_hw.set_active_id("auto" if auto else "manual")
        g.attach(self.c_hw, 1, 1, 1, 1)
        g.attach(_etiqueta("Speed:"), 0, 2, 1, 1)
        self.c_vel = Gtk.ComboBoxText()
        for v, n in (("10", "10baseT"), ("100", "100baseTX"), ("1000", "1000baseT")):
            self.c_vel.append(v, n)
        self.c_vel.set_active_id(p.get("802-3-ethernet.speed", "0") if p.get("802-3-ethernet.speed", "0") != "0"
                                 else "1000")
        g.attach(self.c_vel, 1, 2, 1, 1)
        g.attach(_etiqueta("Duplex:"), 0, 3, 1, 1)
        self.c_dup = Gtk.ComboBoxText()
        self.c_dup.append("half", "half-duplex")
        self.c_dup.append("full", "full-duplex")
        self.c_dup.set_active_id(p.get("802-3-ethernet.duplex") or "full")
        g.attach(self.c_dup, 1, 3, 1, 1)
        g.attach(_etiqueta("MTU:"), 0, 4, 1, 1)
        caja_mtu = Gtk.Box(spacing=8)
        self.c_mtu = Gtk.ComboBoxText()
        self.c_mtu.append("std", "Standard  (1500)")
        self.c_mtu.append("custom", "Custom")
        mtu = p.get("802-3-ethernet.mtu", "0")
        self.c_mtu.set_active_id("std" if mtu in ("", "0", "auto", "1500") else "custom")
        caja_mtu.pack_start(self.c_mtu, True, True, 0)
        self.e_mtu = Gtk.Entry(text=mtu if mtu not in ("", "0", "auto") else "1500", width_chars=6)
        caja_mtu.pack_start(self.e_mtu, False, False, 0)
        g.attach(caja_mtu, 1, 4, 1, 1)
        avb = Gtk.CheckButton(label="AVB/EAV Mode")
        avb.set_active(True)
        g.attach(_gris(avb), 1, 5, 1, 1)
        self.c_hw.connect("changed", lambda _c: self._tipo_hw())
        self.c_mtu.connect("changed", lambda _c: self._tipo_hw())
        self._tipo_hw()
        return g

    def _tipo_hw(self):
        manual = self.c_hw.get_active_id() == "manual"
        self.c_vel.set_sensitive(manual)
        self.c_dup.set_sensitive(manual)
        self.e_mtu.set_visible(self.c_mtu.get_active_id() == "custom")

    # ── lo que cambió ────────────────────────────────────────────────────
    def cambios(self):
        """{propiedad: valor nuevo (texto de nmcli)} solo de lo que el usuario cambió, y su valor anterior en
        self.antes. Devuelve (nuevos, error); un error de validación impide aplicar."""
        a = self.antes
        n = {}
        # IPv4
        m4 = self.c4.get_active_id()
        direccion = ""
        if m4 in ("manual", "auto+manual"):
            ip = self.e_ip4.get_text().strip()
            pref = prefijo_de(self.e_mask.get_text().strip())
            try:
                ipaddress.IPv4Address(ip)
            except ValueError:
                return {}, "The IPv4 address is not valid."
            if pref is None:
                return {}, "The subnet mask is not valid."
            direccion = "%s/%d" % (ip, pref)
        metodo_nm = "auto" if m4 == "auto+manual" else m4
        n["ipv4.method"] = metodo_nm
        n["ipv4.addresses"] = direccion
        if m4 == "manual":                      # con DHCP el router lo da el servidor: no se toca
            gw = self.e_router.get_text().strip()
            if gw:
                try:
                    ipaddress.IPv4Address(gw)
                except ValueError:
                    return {}, "The router address is not valid."
            n["ipv4.gateway"] = gw
        n["ipv4.dhcp-client-id"] = self.e_cid.get_text().strip()
        n["ipv6.method"] = self.c6.get_active_id()
        # DNS
        n["ipv4.dns"] = ",".join(r[0] for r in self.m_dns if not r[1] and r[0])
        n["ipv4.dns-search"] = ",".join(r[0] for r in self.m_dom if not r[1] and r[0])
        for r in self.m_dns:
            if not r[1] and r[0]:
                try:
                    ipaddress.ip_address(r[0])
                except ValueError:
                    return {}, "“%s” is not a valid DNS server address." % r[0]
        # 802.1X (solo la conexión automática)
        n["connection.autoconnect"] = "yes" if self.auto.get_active() else "no"
        # Hardware: se compara el estado EFECTIVO (con auto-negociación, o con la velocidad y el dúplex a mano),
        # no el texto crudo de nmcli (un perfil sin tocar dice auto-negotiate=no, speed=0 y mtu=auto).
        auto_antes = a.get("802-3-ethernet.auto-negotiate", "no") == "yes" or \
            (a.get("802-3-ethernet.speed", "0") in ("", "0") and not a.get("802-3-ethernet.duplex"))
        auto_ahora = self.c_hw.get_active_id() == "auto"
        vel_ahora, dup_ahora = self.c_vel.get_active_id(), self.c_dup.get_active_id()
        if auto_ahora != auto_antes or (not auto_ahora and (
                vel_ahora != a.get("802-3-ethernet.speed", "") or dup_ahora != a.get("802-3-ethernet.duplex", ""))):
            if auto_ahora:
                n["802-3-ethernet.auto-negotiate"] = "yes"
                n["802-3-ethernet.speed"] = "0"
                n["802-3-ethernet.duplex"] = ""
            else:
                n["802-3-ethernet.auto-negotiate"] = "no"
                n["802-3-ethernet.speed"] = vel_ahora
                n["802-3-ethernet.duplex"] = dup_ahora
        mtu_antes = a.get("802-3-ethernet.mtu", "0")
        mtu_antes = "0" if mtu_antes in ("", "auto") else mtu_antes
        if self.c_mtu.get_active_id() == "std":
            mtu_ahora = "0"
        else:
            t = self.e_mtu.get_text().strip()
            if not t.isdigit() or not 576 <= int(t) <= 9000:
                return {}, "The MTU must be a number between 576 and 9000."
            mtu_ahora = t
        if mtu_ahora != mtu_antes and not (mtu_ahora == "0" and mtu_antes == "1500"):
            n["802-3-ethernet.mtu"] = mtu_ahora
        # Solo lo que de verdad cambió respecto al perfil de antes.
        distintos = {}
        for k, v in n.items():
            antes = a.get(k, "")
            if k == "ipv4.method" and a.get("ipv4.method") == "auto" and a.get("ipv4.addresses") and \
                    m4 == "auto+manual":
                antes = "auto"
            if _normal(antes) != _normal(v):
                distintos[k] = v
        return distintos, None


def _normal(v):
    """Un valor de nmcli comparable: sin espacios de más."""
    return (v or "").strip()


def aplicar_con_vuelta_atras(ventana, nombre_con, antes, nuevos, confirmar):
    """Aplica `nuevos` a la conexión y, si `confirmar()` no da True, devuelve el perfil a `antes`.
    Devuelve (ok, mensaje)."""
    args = ["connection", "modify", nombre_con]
    for k, v in nuevos.items():
        args += [k, v]
    ok, msg = _nmcli(*args)
    if not ok:
        return False, msg
    ok, msg = _nmcli("connection", "up", nombre_con, tiempo=60)
    if not ok:
        _devolver(nombre_con, antes, nuevos)
        return False, msg or "The connection could not be brought up. The previous settings were restored."
    if confirmar():
        return True, ""
    _devolver(nombre_con, antes, nuevos)
    return False, "The previous network settings were restored."


def _devolver(nombre_con, antes, nuevos):
    args = ["connection", "modify", nombre_con]
    for k in nuevos:
        args += [k, antes.get(k, "")]
    _nmcli(*args)
    _nmcli("connection", "up", nombre_con, tiempo=60)


def confirmar_cambio(ventana):
    """«Do you want to keep these network settings?» con 15 s: sin «Keep» se devuelve lo anterior."""
    if SIMULAR:
        print("[simulación] confirmación: Keep", file=sys.stderr)
        return True
    d = Gtk.MessageDialog(transient_for=ventana, modal=True, message_type=Gtk.MessageType.QUESTION,
                          text="Do you want to keep these network settings?")
    d.add_button("Revert", Gtk.ResponseType.CANCEL)
    d.add_button("Keep", Gtk.ResponseType.OK)
    d.set_default_response(Gtk.ResponseType.CANCEL)
    resto = [15]

    def tic():
        resto[0] -= 1
        d.format_secondary_text("Reverting in %d seconds." % resto[0])
        if resto[0] <= 0:
            d.response(Gtk.ResponseType.CANCEL)
            return False
        return True
    d.format_secondary_text("Reverting in 15 seconds.")
    GLib.timeout_add_seconds(1, tic)
    r = d.run()
    d.destroy()
    return r == Gtk.ResponseType.OK


def abrir(ventana, dispositivo, info_viva, alterminar=None):
    """Enseña la hoja y, con OK, aplica los cambios con vuelta atrás."""
    hoja = HojaAvanzada(ventana, dispositivo, info_viva)
    while True:
        r = hoja.run()
        if r != Gtk.ResponseType.OK:
            break
        nuevos, error = hoja.cambios()
        if error:
            aviso = Gtk.MessageDialog(transient_for=hoja, modal=True, message_type=Gtk.MessageType.WARNING,
                                      buttons=Gtk.ButtonsType.OK, text=error)
            aviso.run()
            aviso.destroy()
            continue
        if nuevos:
            ok, msg = aplicar_con_vuelta_atras(ventana, hoja.nombre_con, hoja.antes, nuevos,
                                               lambda: confirmar_cambio(hoja))
            if not ok and msg:
                aviso = Gtk.MessageDialog(transient_for=hoja, modal=True, message_type=Gtk.MessageType.INFO,
                                          buttons=Gtk.ButtonsType.OK, text=msg)
                aviso.run()
                aviso.destroy()
        break
    hoja.destroy()
    if alterminar:
        alterminar()
