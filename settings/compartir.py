"""Sharing: el panel de Catalina (Screen Shot 2026-10-14 at 1.22.52 PM Printer Sharing, 1.22.59 Screen Sharing,
1.23.05 File Sharing, 1.23.09 Remote Login; el resto de los servicios en 1.22.56 … 1.23.21).

Con equivalente real, por un ayudante de root con polkit (settings/sharing/, como Startup Disk):
  Remote Login   ssh.socket / ssh.service
  File Sharing   smbd (Samba)
  Printer Sharing  cupsctl --share-printers
Su estado se lee sin root (systemctl is-active, cupsctl). El Computer Name es el nombre bonito del equipo
(hostnamectl --pretty). Sin equivalente (en gris): DVD or CD Sharing, Screen Sharing (x11vnc está
instalado pero sin servicio), Media Sharing, Remote Management, Bluetooth Sharing, Remote Apple Events,
Internet Sharing, Content Caching, Allow access for…, las carpetas y los usuarios de File Sharing y Edit…
Las pantallas de «Off» de cada servicio y la hoja Edit… no tienen captura.
"""
import os
import re
import subprocess

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import GLib, Gtk  # noqa: E402

import paneles  # noqa: E402

AYUDANTE = "/usr/libexec/mint-macos/sharing"
# (nombre en Catalina, clave del ayudante o None)
SERVICIOS = [("DVD or CD Sharing", None), ("Screen Sharing", None), ("Media Sharing", None),
             ("File Sharing", "file-sharing"), ("Printer Sharing", "printer-sharing"),
             ("Remote Login", "remote-login"), ("Remote Management", None), ("Bluetooth Sharing", None),
             ("Remote Apple Events", None), ("Internet Sharing", None), ("Content Caching", None)]


def _salida(*cmd):
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        return r.stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return ""


def encendido(clave):
    if clave == "remote-login":
        return any(_salida("systemctl", "is-active", u) == "active" for u in ("ssh.socket", "ssh.service"))
    if clave == "file-sharing":
        return _salida("systemctl", "is-active", "smbd.service") == "active"
    if clave == "printer-sharing":
        return "_share_printers=1" in _salida("cupsctl")
    return False


def _gris(widget, motivo="Not available on this computer."):
    widget.set_sensitive(False)
    widget.set_tooltip_text(motivo)
    return widget


def _marco():
    m = Gtk.Frame()
    m.get_style_context().add_class("mp-sd-lista")
    return m


class PanelSharing:
    id = "com.apple.preferences.sharing"
    nombre = "Sharing"
    claves = []
    externo = False
    propio = True
    celda = None
    PRUEBA = bool(os.environ.get("MINT_COMPARTIR_PRUEBA"))     # solo lee: no enciende ni apaga nada

    def __init__(self):
        self.panel = paneles.Panel(self.id, self.nombre, [],
                                   palabras="sharing, remote login, ssh, file sharing, samba, printer sharing, "
                                            "screen sharing, computer name")
        self.ventana = None
        self._cargando = False

    def coincide(self, texto):
        t = texto.lower().strip()
        return bool(t) and any(t in c.lower() for c in (self.nombre, self.panel.palabras, self.id))

    def construir(self):
        self._cargando = True
        caja = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        caja.get_style_context().add_class("mp-propio")
        for lado in ("top", "bottom", "start", "end"):
            getattr(caja, "set_margin_" + lado)(16)
        # Computer Name
        g = Gtk.Grid(column_spacing=10, row_spacing=6)
        g.set_halign(Gtk.Align.CENTER)
        e = Gtk.Label(label="Computer Name:", xalign=1.0)
        e.get_style_context().add_class("mp-fila-etiqueta")
        g.attach(e, 0, 0, 1, 1)
        estatico = _salida("hostnamectl", "--static") or "localhost"
        bonito = _salida("hostnamectl", "--pretty") or estatico
        self._nombre = Gtk.Entry(text=bonito)
        self._nombre.set_width_chars(40)
        self._nombre.connect("activate", lambda en: self._poner_nombre(en.get_text()))
        g.attach(self._nombre, 1, 0, 2, 1)
        d = Gtk.Label(label="Computers on your local network can access your computer at:\n%s.local" % estatico,
                      xalign=0)
        d.get_style_context().add_class("mp-sd-detalle")
        g.attach(d, 1, 1, 1, 1)
        g.attach(_gris(Gtk.Button(label="Edit…")), 2, 1, 1, 1)
        caja.pack_start(g, False, False, 0)

        # La lista de servicios y su detalle
        cuerpo = Gtk.Box(spacing=14)
        izq = _marco()
        self._servicios = Gtk.ListStore(bool, str, str, bool)      # encendido, nombre, clave, ¿se puede?
        for nombre, clave in SERVICIOS:
            self._servicios.append([encendido(clave) if clave else False, nombre, clave or "", clave is not None])
        arbol = Gtk.TreeView(model=self._servicios)
        arbol.set_size_request(190, 270)
        ck = Gtk.CellRendererToggle()
        ck.connect("toggled", self._conmutar)
        col = Gtk.TreeViewColumn("On", ck, active=0, activatable=3, sensitive=3)
        arbol.append_column(col)
        arbol.append_column(Gtk.TreeViewColumn("Service", Gtk.CellRendererText(), text=1))
        arbol.get_selection().connect("changed", lambda s: self._elegido(s))
        self._arbol = arbol
        izq.add(arbol)
        cuerpo.pack_start(izq, False, False, 0)
        self._detalle = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        cuerpo.pack_start(self._detalle, True, True, 0)
        caja.pack_start(cuerpo, True, True, 0)
        caja.show_all()
        pedido = os.environ.get("MINT_COMPARTIR_SERVICIO")      # solo para las pruebas visuales
        indice = [n for n, _c in SERVICIOS].index(pedido) if pedido else [n for n, _c in SERVICIOS].index("Remote Login")
        arbol.get_selection().select_path(Gtk.TreePath(indice))
        self._cargando = False
        return caja

    # ── detalle de cada servicio ─────────────────────────────────────────
    def _elegido(self, sel):
        modelo, it = sel.get_selected()
        if it is None:
            return
        nombre, clave = modelo[it][1], modelo[it][2]
        for h in self._detalle.get_children():
            self._detalle.remove(h)
        on = modelo[it][0]
        cab = Gtk.Box(spacing=8)
        punto = Gtk.Label()
        punto.set_markup('<span foreground="%s">●</span>' % ("#37c94b" if on else "#8a8a8e"))
        cab.pack_start(punto, False, False, 0)
        t = Gtk.Label(label="%s: %s" % (nombre, "On" if on else "Off"), xalign=0)
        t.get_style_context().add_class("mp-titulo-negrita")
        cab.pack_start(t, False, False, 0)
        self._detalle.pack_start(cab, False, False, 0)
        host = _salida("hostnamectl", "--static") or "localhost"
        usuario = os.environ.get("USER", "user")
        if clave == "remote-login":
            self._texto("To log in to this computer remotely, type “ssh %s@%s.local”." % (usuario, host))
            self._acceso()
        elif clave == "file-sharing":
            self._texto("Other users can access shared folders on this computer at “smb://%s.local”." % host)
            self._carpetas_smb()
        elif clave == "printer-sharing":
            self._texto("Printer Sharing allows others on your network to use printers connected to this computer.")
            self._impresoras()
        else:
            self._texto("This service is not available on this computer.")
        self._detalle.show_all()

    def _texto(self, texto):
        t = Gtk.Label(label=texto, xalign=0)
        t.set_line_wrap(True)
        t.set_max_width_chars(60)
        t.get_style_context().add_class("mp-sd-detalle")
        self._detalle.pack_start(t, False, False, 0)

    def _acceso(self):
        self._detalle.pack_start(Gtk.Separator(), False, False, 8)
        f = Gtk.Box(spacing=12)
        f.pack_start(Gtk.Label(label="Allow access for:"), False, False, 0)
        c = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        todos = Gtk.RadioButton.new_with_label_from_widget(None, "All users")
        solo = Gtk.RadioButton.new_with_label_from_widget(todos, "Only these users:")
        todos.set_active(True)
        c.pack_start(_gris(todos, "Access is controlled by sshd on this computer."), False, False, 0)
        c.pack_start(_gris(solo), False, False, 0)
        f.pack_start(c, False, False, 0)
        self._detalle.pack_start(f, False, False, 0)

    def _carpetas_smb(self):
        marco = _marco()
        marco.set_size_request(-1, 120)
        lista = Gtk.ListStore(str)
        for linea in _salida("testparm", "-s", "--suppress-prompt").splitlines():
            m = re.match(r"^\[(.+)\]$", linea.strip())
            if m and m.group(1) not in ("global", "printers", "print$"):
                lista.append([m.group(1)])
        arbol = Gtk.TreeView(model=lista)
        arbol.set_headers_visible(False)
        arbol.append_column(Gtk.TreeViewColumn("", Gtk.CellRendererText(), text=0))
        marco.add(arbol)
        self._detalle.pack_start(Gtk.Label(label="Shared Folders:", xalign=0), False, False, 0)
        self._detalle.pack_start(_gris(marco, "Edit /etc/samba/smb.conf to change shared folders."), True, True, 0)

    def _impresoras(self):
        self._detalle.pack_start(Gtk.Label(label="Printers:", xalign=0), False, False, 0)
        marco = _marco()
        marco.set_size_request(-1, 100)
        caja = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, margin=6)
        for linea in _salida("lpstat", "-p").splitlines():
            m = re.match(r"^printer (\S+)", linea)
            if m:
                c = Gtk.CheckButton(label=m.group(1))
                c.set_active(True)
                caja.pack_start(_gris(c, "Every printer is shared when Printer Sharing is on."), False, False, 0)
        marco.add(caja)
        self._detalle.pack_start(marco, False, False, 0)

    # ── encender y apagar ────────────────────────────────────────────────
    def _conmutar(self, _celda, ruta):
        fila = self._servicios[ruta]
        if self._cargando or not fila[3]:
            return
        quiere = not fila[0]
        if self.PRUEBA:
            return
        try:
            r = subprocess.run(["pkexec", AYUDANTE, fila[2], "on" if quiere else "off"],
                               capture_output=True, text=True, timeout=120)
            ok = r.returncode == 0
            if not ok and r.returncode not in (126, 127):
                self._aviso("%s: %s" % (fila[1], (r.stderr or r.stdout or "The change was not applied.").strip()))
        except (OSError, subprocess.SubprocessError) as e:
            ok = False
            self._aviso("%s: %s" % (fila[1], e))
        fila[0] = encendido(fila[2])
        self._elegido(self._arbol.get_selection())

    def _poner_nombre(self, texto):
        texto = texto.strip()
        if not texto or self.PRUEBA:
            return
        try:
            subprocess.run(["hostnamectl", "set-hostname", "--pretty", texto], timeout=60)
        except (OSError, subprocess.SubprocessError):
            pass

    def _aviso(self, texto):
        d = Gtk.MessageDialog(transient_for=self.ventana, modal=True, message_type=Gtk.MessageType.WARNING,
                              buttons=Gtk.ButtonsType.OK, text=texto)
        d.run()
        d.destroy()
