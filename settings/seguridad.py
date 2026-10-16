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
from gi.repository import Gio, GLib, Gtk  # noqa: E402

import iconos_catalina  # noqa: E402
import paneles  # noqa: E402

BLOQUEO = [(0, "immediately"), (5, "5 seconds"), (60, "1 minute"), (300, "5 minutes"), (900, "15 minutes"),
           (3600, "1 hour"), (14400, "4 hours"), (28800, "8 hours")]
# Privacy: cada categoría y su página. Los textos salen de Security.prefPane/Resources/en.lproj/Localizable.strings del
# disco de la Mac (y de las capturas 16-privacy-*). Las nueve primeras y su orden son los de la captura; el orden de las
# demás, que en la Mac quedan fuera de la vista de la barra lateral, es el de la guía «Change Privacy preferences on Mac»
# de macOS 10.15 (https://support.apple.com/guide/mac-help/mh32356/10.15/mac/10.15): orden de la guía, sin captura.
# Developer Tools no sale: Catalina la oculta mientras no tenga aplicaciones.
# Íconos de la lista (08-pref-…security--Privacy…): los de Security.prefPane y los de las apps. Solo las nueve de la captura.
ICONOS_PRIVACIDAD = {"Location Services": "locationservices", "Contacts": "contacts", "Calendars": "calendars",
                     "Reminders": "reminders", "Photos": "photos", "Camera": "cameraservices",
                     "Microphone": "microphoneservices", "Speech Recognition": "microphoneservices",
                     "Accessibility": "accessibilityservices"}
SIN_APPS = "Apps that have requested access to %s will appear here."
CATEGORIAS = [
    ("Location Services", "ubicacion", None),
    ("Contacts", "vacia", SIN_APPS % "your contacts"),
    ("Calendars", "vacia", SIN_APPS % "your calendars"),
    ("Reminders", "vacia", SIN_APPS % "your reminders"),
    ("Photos", "vacia", SIN_APPS % "your photos"),
    ("Camera", "vacia", SIN_APPS % "your camera"),
    ("Microphone", "vacia", SIN_APPS % "your microphone"),
    ("Speech Recognition", "vacia", "Apps that have requested access to speech recognition will appear here. Speech "
                                    "recognition sends recorded voice to Apple to process your requests."),
    ("Accessibility", "lista", ("Allow the apps below to control your computer.", True)),
    ("Input Monitoring", "lista", ("Allow the apps below to monitor input from your keyboard even while using other apps.",
                                   True)),
    ("Full Disk Access", "lista", ("Allow the apps below to access data like Mail, Messages, Safari, Home, Time Machine "
                                   "backups, and certain administrative settings for all users on this Mac.", True)),
    ("Files and Folders", "lista", ("Allow the apps below to access files and folders.", True)),
    ("Screen Recording", "vacia", SIN_APPS % "record the contents of your screen"),
    ("Automation", "lista", ("Allow the apps below to control other apps. This will provide access to documents and data "
                             "in those apps, and to perform actions within them.", False)),
    ("Advertising", "publicidad", None),
    ("Analytics & Improvements", "analitica", None),
]


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
        desplazable = Gtk.ScrolledWindow()
        desplazable.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        desplazable.set_size_request(210, 330)
        paginas = Gtk.Stack()
        for nombre, tipo, dato in CATEGORIAS:
            fila = Gtk.ListBoxRow()
            caja_fila = Gtk.Box(spacing=10, margin=8)
            icono = iconos_catalina.de_privacidad(ICONOS_PRIVACIDAD.get(nombre, ""), 24)
            if icono is not None:
                caja_fila.pack_start(icono, False, False, 0)
            caja_fila.pack_start(Gtk.Label(label=nombre, xalign=0), True, True, 0)
            fila.add(caja_fila)
            fila.nombre = nombre
            lista.add(fila)
            paginas.add_named(self._pagina_privacidad(tipo, dato), nombre)
        lista.connect("row-selected", lambda _l, f: f and paginas.set_visible_child_name(f.nombre))
        desplazable.add(lista)
        ml = _marco()
        ml.add(desplazable)
        pagina.pack_start(ml, False, False, 0)
        pagina.pack_start(paginas, True, True, 0)
        paginas.show_all()
        lista.select_row(lista.get_row_at_index(0))
        paginas.set_visible_child_name(CATEGORIAS[0][0])
        return pagina

    def _pagina_privacidad(self, tipo, dato):
        der = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)

        def texto(t, negrita=False):
            l = Gtk.Label(xalign=0)
            if negrita:
                l.set_markup("<b>%s</b>" % GLib.markup_escape_text(t))
            else:
                l.set_text(t)
            l.set_line_wrap(True)
            l.set_max_width_chars(48)
            return l

        def boton(t):
            b = Gtk.Button(label=t)
            b.set_halign(Gtk.Align.END)
            return _gris(b)

        if tipo == "ubicacion":
            c = Gtk.CheckButton(label="Enable Location Services")
            c.set_active(True)
            der.pack_start(_gris(c), False, False, 0)
            der.pack_start(texto("Allow the apps and services below to determine your location."), False, False, 0)
            marco = _marco()
            marco.set_size_request(-1, 200)
            der.pack_start(_gris(marco), True, True, 0)
            b = Gtk.Box()
            b.pack_end(boton("About Location Services & Privacy…"), False, False, 0)
            der.pack_start(b, False, False, 0)
        elif tipo == "vacia":
            marco = _marco()
            centro = Gtk.Label(label=dato, justify=Gtk.Justification.CENTER)
            centro.set_line_wrap(True)
            centro.set_max_width_chars(32)
            marco.add(centro)
            der.pack_start(_gris(marco), True, True, 0)
        elif tipo == "lista":
            resumen, con_barra = dato
            der.pack_start(texto(resumen), False, False, 0)
            marco = _marco()
            marco.set_size_request(-1, 200)
            der.pack_start(_gris(marco), True, True, 0)
            if con_barra:
                botones = Gtk.Box()
                botones.get_style_context().add_class("linked")
                for t in ("+", "\u2212"):
                    botones.pack_start(_gris(Gtk.Button(label=t)), False, False, 0)
                der.pack_start(botones, False, False, 0)
        elif tipo == "publicidad":
            der.pack_start(texto("All Advertisers", negrita=True), False, False, 0)
            limitar = Gtk.CheckButton(label="Limit Ad Tracking")
            der.pack_start(_gris(limitar), False, False, 0)
            der.pack_start(texto("Opt out of receiving ads targeted to your interests in Apple Apps and your iOS devices. "
                                 "You may still receive the same number of ads, but the ads may be less relevant to you."),
                           False, False, 0)
            der.pack_start(boton("Reset Advertising Identifier"), False, False, 0)
            der.pack_start(texto("Advertising in Apple Apps", negrita=True), False, False, 12)
            der.pack_start(texto("View the information used by Apple to deliver more relevant ads to you in Apple News, "
                                 "Stocks, and the iOS App Store. Your personal data is not provided to third parties."),
                           False, False, 0)
            der.pack_start(boton("View Ad Information"), False, False, 0)
            pie = Gtk.Box()
            pie.pack_end(boton("About Advertising & Privacy…"), False, False, 0)
            der.pack_end(pie, False, False, 0)
        else:   # analitica
            der.pack_start(texto("Help Apple and app developers improve their products and services automatically."),
                           False, False, 0)
            marco = _marco()
            desplazable = Gtk.ScrolledWindow()
            desplazable.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
            desplazable.set_size_request(-1, 240)
            col = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6, margin=8)
            for titulo, detalle in (
                    ("Share Mac Analytics", "Help Apple improve its products and services by automatically sending "
                                            "diagnostics and usage data. Diagnostic data may include locations."),
                    ("Improve Siri & Dictation", "Help improve Siri and Dictation by allowing Apple to store and review "
                                                 "audio of your Siri and Dictation interactions from this device."),
                    ("Share with App Developers", "Help app developers improve their apps by allowing Apple to share crash "
                                                  "and usage data with them.")):
                c = Gtk.CheckButton(label=titulo)
                col.pack_start(c, False, False, 0)
                d = texto(detalle)
                d.set_margin_start(26)
                d.get_style_context().add_class("mp-sd-detalle")
                col.pack_start(d, False, False, 0)
            desplazable.add(col)
            marco.add(desplazable)
            der.pack_start(_gris(marco), True, True, 0)
            pie = Gtk.Box()
            pie.pack_end(boton("About Analytics and Privacy…"), False, False, 0)
            der.pack_start(pie, False, False, 0)
        return der
