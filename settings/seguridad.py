"""Security & Privacy: el panel de Catalina con sus cuatro pestañas (General, FileVault, Firewall, Privacy).

Capturas: Screen Shot 2026-10-14 at 1.21.03 PM (General), 1.21.08 PM (FileVault), 1.21.11 PM (Firewall) y
1.21.15 PM (Privacy ▸ Location Services).

General: Require password … after sleep or screen saver begins es lock-enabled y lock-delay de
org.cinnamon.desktop.screensaver; «Show a message when the screen is locked» y Set Lock Message… son
default-message; Change Password… abre el módulo de usuario de Cinnamon. Las opciones de tiempo,
salvo «1 minute», no tienen captura.
FileVault: dice si el disco está cifrado (LUKS, con lsblk); Turn On FileVault… va en gris (cifrar el
disco ya instalado no se hace desde aquí). Firewall: dice si ufw está activo (systemctl); los botones
van en gris porque cambiarlo pide root. Privacy ▸ Location Services y el resto de categorías van en gris:
Linux no tiene ese permiso por app.
Sin equivalente (en gris): Disable automatic login, Allow apps downloaded from, Advanced…
Los controles de usuario no necesitan el candado, así que no se dibuja.
"""
import os
import subprocess

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gio, Gtk  # noqa: E402

import paneles  # noqa: E402

BLOQUEO = [(0, "immediately"), (5, "5 seconds"), (60, "1 minute"), (300, "5 minutes"), (900, "15 minutes"),
           (3600, "1 hour"), (14400, "4 hours"), (28800, "8 hours")]
CATEGORIAS = ["Location Services", "Contacts", "Calendars", "Reminders", "Photos", "Camera", "Microphone",
              "Speech Recognition", "Accessibility"]       # las que se ven en la captura


def _salida(*cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=10).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return ""


def _gris(widget, motivo="Not available on this computer."):
    widget.set_sensitive(False)
    widget.set_tooltip_text(motivo)
    return widget


def _marco():
    m = Gtk.Frame()
    m.get_style_context().add_class("mp-sd-lista")
    return m


class PanelSecurity:
    id = "com.apple.preference.security"
    nombre = "Security & Privacy"
    claves = []
    externo = False
    propio = True
    celda = None
    PRUEBA = bool(os.environ.get("MINT_SEGURIDAD_PRUEBA"))     # no cambia la configuración

    def __init__(self):
        self.panel = paneles.Panel(self.id, self.nombre, [],
                                   palabras="security, privacy, password, firewall, filevault, lock, "
                                            "location services, gatekeeper")
        self.ventana = None
        self._cargando = False

    def coincide(self, texto):
        t = texto.lower().strip()
        return bool(t) and any(t in c.lower() for c in (self.nombre, self.panel.palabras, self.id))

    def construir(self):
        self._cargando = True
        self._pantalla = Gio.Settings.new("org.cinnamon.desktop.screensaver")
        caja = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        caja.get_style_context().add_class("mp-propio")
        caja.set_margin_top(12)
        stack = Gtk.Stack()
        stack.add_titled(self._general(), "general", "General")
        stack.add_titled(self._filevault(), "filevault", "FileVault")
        stack.add_titled(self._firewall(), "firewall", "Firewall")
        stack.add_titled(self._privacidad(), "privacy", "Privacy")
        pestanas = Gtk.StackSwitcher()
        pestanas.set_stack(stack)
        pestanas.set_halign(Gtk.Align.CENTER)
        pestanas.get_style_context().add_class("mp-pestanas")
        caja.pack_start(pestanas, False, False, 0)
        marco = _marco()
        marco.add(stack)
        caja.pack_start(marco, True, True, 0)
        pie = Gtk.Box()
        pie.pack_end(_gris(Gtk.Button(label="Advanced…")), False, False, 6)
        caja.pack_start(pie, False, False, 4)
        caja.show_all()
        pedida = os.environ.get("MINT_SEGURIDAD_PESTANA")        # solo para las pruebas visuales
        if pedida:
            stack.set_visible_child_name(pedida)
        self._cargando = False
        return caja

    # ── General ──────────────────────────────────────────────────────────
    def _general(self):
        pagina = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        pagina.set_margin_top(28)
        pagina.set_margin_start(60)
        pagina.set_margin_bottom(20)
        f = Gtk.Box(spacing=12)
        f.pack_start(Gtk.Label(label="A login password has been set for this user"), False, False, 0)
        b = Gtk.Button(label="Change Password…")
        b.connect("clicked", lambda _b: self._cambiar_clave())
        f.pack_start(b, False, False, 0)
        pagina.pack_start(f, False, False, 0)

        g = Gtk.Box(spacing=8)
        g.set_margin_start(24)
        requerir = Gtk.CheckButton(label="Require password")
        requerir.set_active(self._pantalla.get_boolean("lock-enabled"))
        requerir.connect("toggled", lambda c: self._poner("lock-enabled", c.get_active(), "boolean"))
        g.pack_start(requerir, False, False, 0)
        self._retraso = Gtk.ComboBoxText()
        for s, n in BLOQUEO:
            self._retraso.append(str(s), n)
        actual = self._pantalla.get_uint("lock-delay")
        if not self._retraso.set_active_id(str(actual)):
            self._retraso.append(str(actual), "%d seconds" % actual)
            self._retraso.set_active_id(str(actual))
        self._retraso.connect("changed", lambda c: self._poner("lock-delay", int(c.get_active_id()), "uint"))
        g.pack_start(self._retraso, False, False, 0)
        g.pack_start(Gtk.Label(label="after sleep or screen saver begins"), False, False, 0)
        pagina.pack_start(g, False, False, 0)

        m = Gtk.Box(spacing=8)
        m.set_margin_start(24)
        msg = self._pantalla.get_string("default-message")
        self._mensaje_activo = Gtk.CheckButton(label="Show a message when the screen is locked")
        self._mensaje_activo.set_active(bool(msg))
        self._mensaje_activo.connect("toggled", lambda c: self._mensaje(c))
        m.pack_start(self._mensaje_activo, False, False, 0)
        fijar = Gtk.Button(label="Set Lock Message…")
        fijar.connect("clicked", lambda _b: self._dialogo_mensaje())
        m.pack_start(fijar, False, False, 0)
        pagina.pack_start(m, False, False, 0)
        auto = Gtk.CheckButton(label="Disable automatic login")
        auto.set_active(True)
        auto.set_margin_start(24)
        pagina.pack_start(_gris(auto, "Automatic login is set in the login window settings."), False, False, 0)

        pagina.pack_start(Gtk.Separator(), False, False, 24)
        pagina.pack_start(Gtk.Label(label="Allow apps downloaded from:", xalign=0), False, False, 0)
        grupo = None
        for texto, activa in (("App Store", False), ("App Store and identified developers", True)):
            r = Gtk.RadioButton.new_with_label_from_widget(grupo, texto)
            grupo = grupo or r
            r.set_active(activa)
            r.set_margin_start(24)
            pagina.pack_start(_gris(r, "Linux does not check where an app comes from."), False, False, 0)
        return pagina

    def _poner(self, clave, valor, tipo):
        if self._cargando or self.PRUEBA:
            return
        getattr(self._pantalla, "set_" + tipo)(clave, valor)

    def _cambiar_clave(self):
        if self.PRUEBA:
            return
        try:
            subprocess.Popen(["cinnamon-settings", "user"], start_new_session=True,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except OSError:
            pass

    def _mensaje(self, casilla):
        if self._cargando or self.PRUEBA:
            return
        if not casilla.get_active():
            self._pantalla.set_string("default-message", "")
        elif not self._pantalla.get_string("default-message"):
            self._dialogo_mensaje()

    def _dialogo_mensaje(self):
        d = Gtk.Dialog(transient_for=self.ventana, modal=True)
        d.set_decorated(False)
        d.get_style_context().add_class("mp-hoja")
        c = d.get_content_area()
        c.set_spacing(10)
        for lado in ("top", "bottom", "start", "end"):
            getattr(c, "set_margin_" + lado)(20)
        c.pack_start(Gtk.Label(label="Enter the message to show when the screen is locked:", xalign=0),
                     False, False, 0)
        e = Gtk.Entry(text=self._pantalla.get_string("default-message"), width_chars=40)
        c.pack_start(e, False, False, 0)
        d.add_button("Cancel", Gtk.ResponseType.CANCEL)
        ok = d.add_button("OK", Gtk.ResponseType.OK)
        ok.get_style_context().add_class("suggested-action")
        d.set_default_response(Gtk.ResponseType.OK)
        d.show_all()
        if d.run() == Gtk.ResponseType.OK and not self.PRUEBA:
            self._pantalla.set_string("default-message", e.get_text())
            previo, self._cargando = self._cargando, True
            self._mensaje_activo.set_active(bool(e.get_text()))
            self._cargando = previo
        d.destroy()

    # ── FileVault ────────────────────────────────────────────────────────
    def _filevault(self):
        pagina = Gtk.Box(spacing=18, margin=26)
        pagina.set_valign(Gtk.Align.START)
        from propios import imagen_icono_panel
        pagina.pack_start(imagen_icono_panel(self.id, 64), False, False, 0)
        c = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        f = Gtk.Box(spacing=12)
        t = Gtk.Label(label="FileVault secures the data on your disk by encrypting its contents automatically.",
                      xalign=0)
        t.set_line_wrap(True)
        t.set_max_width_chars(34)
        f.pack_start(t, True, True, 0)
        f.pack_end(_gris(Gtk.Button(label="Turn On FileVault…"),
                         "Encrypting the installed disk is not done from here."), False, False, 0)
        c.pack_start(f, False, False, 0)
        aviso = Gtk.Label(xalign=0)
        aviso.set_markup('<span foreground="#ff453a">WARNING:</span> You will need your login password or a '
                         'recovery key to access your data. If you forget both, the data will be lost.')
        aviso.set_line_wrap(True)
        aviso.set_max_width_chars(70)
        c.pack_start(aviso, False, False, 0)
        cifrado = "crypt" in _salida("lsblk", "-no", "TYPE").split()
        fuente = _salida("findmnt", "-no", "SOURCE", "/")
        disco = (_salida("lsblk", "-no", "LABEL", fuente).splitlines() or [""])[0].strip() if fuente else ""
        disco = disco or os.path.basename(fuente) or "this disk"
        c.pack_start(Gtk.Label(label="FileVault is turned %s for the disk \u201c%s\u201d." % (
            "on" if cifrado else "off", disco), xalign=0), False, False, 20)
        pagina.pack_start(c, True, True, 0)
        return pagina

    # ── Firewall ─────────────────────────────────────────────────────────
    def _firewall(self):
        pagina = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin=26)
        pagina.set_valign(Gtk.Align.START)
        activo = _salida("systemctl", "is-active", "ufw") == "active"
        f = Gtk.Box(spacing=8)
        punto = Gtk.Label()
        punto.set_markup('<span foreground="%s">●</span>' % ("#37c94b" if activo else "#d0d0d0"))
        f.pack_start(punto, False, False, 0)
        t = Gtk.Label(label="Firewall: %s" % ("On" if activo else "Off"), xalign=0)
        t.get_style_context().add_class("mp-titulo-negrita")
        f.pack_start(t, True, True, 0)
        f.pack_end(_gris(Gtk.Button(label="Turn %s Firewall" % ("Off" if activo else "On")),
                         "Changing the firewall needs the administrator."), False, False, 0)
        pagina.pack_start(f, False, False, 0)
        d = Gtk.Label(label=("This computer’s firewall is currently turned on." if activo else
                             "This computer’s firewall is currently turned off. All incoming connections "
                             "to this computer are allowed."), xalign=0)
        d.set_line_wrap(True)
        d.set_max_width_chars(60)
        pagina.pack_start(d, False, False, 0)
        o = Gtk.Box()
        o.pack_end(_gris(Gtk.Button(label="Firewall Options…")), False, False, 0)
        pagina.pack_start(o, False, False, 0)
        return pagina

    # ── Privacy ──────────────────────────────────────────────────────────
    def _privacidad(self):
        pagina = Gtk.Box(spacing=14, margin=16)
        lista = Gtk.ListBox()
        lista.set_size_request(210, 330)
        for n in CATEGORIAS:
            fila = Gtk.ListBoxRow()
            fila.add(Gtk.Label(label=n, xalign=0, margin=10))
            lista.add(fila)
        ml = _marco()
        ml.add(_gris(lista, "Linux has no per-app privacy permissions to show."))
        pagina.pack_start(ml, False, False, 0)
        der = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        c = Gtk.CheckButton(label="Enable Location Services")
        c.set_active(True)
        der.pack_start(_gris(c), False, False, 0)
        der.pack_start(Gtk.Label(label="Allow the apps and services below to determine your location.",
                                 xalign=0), False, False, 0)
        marco = _marco()
        marco.set_size_request(-1, 200)
        der.pack_start(_gris(marco), True, True, 0)
        b = Gtk.Box()
        b.pack_end(_gris(Gtk.Button(label="About Location Services & Privacy…")), False, False, 0)
        der.pack_start(b, False, False, 0)
        pagina.pack_start(der, True, True, 0)
        return pagina
