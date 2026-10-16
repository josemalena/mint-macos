"""Screen Time: las diez pantallas de Catalina, en gris.

Linux no tiene Screen Time: no hay uso que contar ni límites que aplicar. Se dibuja cada pantalla como en las capturas de
Catalina (08-pref-com.apple.preference.screentime--*, 16-screen-time-content-privacy-*) pero con la computadora de verdad:
el uso, las notificaciones y los «pickups» valen cero; la lista de Always Allowed son las aplicaciones instaladas con «0s».
Los estados (Downtime Off, App Limits On, Content & Privacy Off, Screen Time On) son los de la captura. Nada funciona ni debe.
Falta el ícono de cada fila de la barra lateral: son arte de Apple dentro de una hoja deepmap2 que no se puede abrir fuera de
macOS (ver tema/iconos/car.py); sin ellos las filas van solo con el texto.
"""
import getpass
import os
import pwd
import time

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gio, GLib, Gtk  # noqa: E402

import paneles  # noqa: E402

MOTIVO = "Screen Time is not available on this computer."


def _gris(widget):
    widget.set_sensitive(False)
    widget.set_tooltip_text(MOTIVO)
    return widget


def _marco():
    m = Gtk.Frame()
    m.get_style_context().add_class("mp-sd-lista")
    return m


def _etiqueta(texto, negrita=False, detalle=False, xalign=0.0):
    l = Gtk.Label(xalign=xalign)
    if negrita:
        l.set_markup("<b>%s</b>" % GLib.markup_escape_text(texto))
    else:
        l.set_text(texto)
    l.set_line_wrap(True)
    l.set_max_width_chars(40)     # sin tope, el ancho natural del texto ensancha toda la ventana
    if detalle:
        l.get_style_context().add_class("mp-sd-detalle")
    return l


def _nombre_usuario():
    try:
        n = pwd.getpwnam(getpass.getuser()).pw_gecos.split(",")[0]
        return n or getpass.getuser()
    except Exception:  # noqa: BLE001
        return getpass.getuser()


class _Graficas(Gtk.DrawingArea):
    """Las dos cuadrículas de App Usage / Notifications / Pickups, sin datos: la semana (S M T W T F S con la raya «avg»)
    y el día (12 AM, 6 AM, 12 PM, 6 PM), con su escala a la derecha."""

    def __init__(self, escala_semana, escala_dia):
        super().__init__()
        self.semana, self.dia = escala_semana, escala_dia
        self.set_size_request(410, 150)
        self.connect("draw", self._dibujar)

    def _cuadricula(self, cr, x, y, ancho, alto, escala, etiquetas, avg=False):
        cr.set_source_rgba(1, 1, 1, 0.12)
        cr.set_line_width(1)
        for i in range(4):
            yy = round(y + alto * i / 3) + 0.5
            cr.move_to(x, yy)
            cr.line_to(x + ancho, yy)
        for i in range(len(etiquetas) + 1):
            xx = round(x + ancho * i / len(etiquetas)) + 0.5
            cr.move_to(xx, y)
            cr.line_to(xx, y + alto)
        cr.stroke()
        cr.set_source_rgba(1, 1, 1, 0.55)
        cr.set_font_size(10)
        for i, txt in enumerate(escala):
            cr.move_to(x + ancho + 6, y + alto * i / 3 + 4)
            cr.show_text(txt)
        for i, txt in enumerate(etiquetas):
            cr.move_to(x + ancho * i / len(etiquetas) + 2, y + alto + 12)
            cr.show_text(txt)
        if avg:
            cr.set_source_rgba(0.2, 0.75, 0.3, 0.9)
            cr.set_dash([3, 3])
            yy = y + alto - 1.5
            cr.move_to(x, yy)
            cr.line_to(x + ancho, yy)
            cr.stroke()
            cr.set_dash([])
            cr.move_to(x + ancho + 6, yy + 3)
            cr.show_text("avg")

    def _dibujar(self, _w, cr):
        self._cuadricula(cr, 8, 6, 350, 52, self.semana, ["S", "M", "T", "W", "T", "F", "S"], avg=True)
        self._cuadricula(cr, 8, 82, 350, 44, self.dia, ["12 AM", "6 AM", "12 PM", "6 PM"])
        return False


class PanelScreenTime:
    id = "com.apple.preference.screentime"
    nombre = "Screen Time"
    claves = []
    externo = False
    propio = True
    celda = None
    FILAS = ["App Usage", "Notifications", "Pickups", None, "Downtime", "App Limits", "Communication",
             "Always Allowed", "Content & Privacy"]

    def __init__(self):
        self.panel = paneles.Panel(self.id, self.nombre, [],
                                   palabras="screen time, app usage, notifications, pickups, downtime, app limits, "
                                            "communication, always allowed, content privacy")
        self.ventana = None

    def coincide(self, texto):
        t = texto.lower().strip()
        return bool(t) and any(t in c.lower() for c in (self.nombre, self.panel.palabras, self.id))

    # ── la ventana ──────────────────────────────────────────────────────
    def construir(self):
        caja = Gtk.Box(spacing=0)
        caja.get_style_context().add_class("mp-propio")
        caja.set_margin_bottom(10)
        paginas = Gtk.Stack()
        paginas.add_named(self._pagina_uso("Usage", "0m", ["2h", "1h", "0", ""], ["60m", "30m", "0", ""],
                                          ["Time", "Limits"], "Productivity"), "App Usage")
        paginas.add_named(self._pagina_uso("Notifications", "0", ["30", "15", "0", ""], ["20", "10", "0", ""],
                                          ["Notifications"], None), "Notifications")
        paginas.add_named(self._pagina_uso("Pickups", "0", ["10", "5", "0", ""], ["10", "5", "0", ""],
                                          ["Pickups"], None), "Pickups")
        paginas.add_named(self._pagina_downtime(), "Downtime")
        paginas.add_named(self._pagina_limites(), "App Limits")
        paginas.add_named(self._pagina_comunicacion(), "Communication")
        paginas.add_named(self._pagina_permitidas(), "Always Allowed")
        paginas.add_named(self._pagina_contenido(), "Content & Privacy")
        paginas.add_named(self._pagina_opciones(), "Options")

        izq = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        izq.set_margin_top(14)
        izq.set_size_request(188, 480)
        izq.pack_start(_gris(Gtk.Image.new_from_icon_name("avatar-default", Gtk.IconSize.DIALOG)), False, False, 8)
        usuario = Gtk.ComboBoxText()
        usuario.append("u", _nombre_usuario())
        usuario.set_active(0)
        usuario.set_margin_start(14)
        usuario.set_margin_end(14)
        izq.pack_start(_gris(usuario), False, False, 8)
        lista = Gtk.ListBox()
        lista.set_selection_mode(Gtk.SelectionMode.SINGLE)
        for n in self.FILAS:
            fila = Gtk.ListBoxRow()
            if n is None:
                fila.set_selectable(False)
                fila.set_activatable(False)
                fila.add(Gtk.Separator())
            else:
                fila.add(Gtk.Label(label=n, xalign=0, margin=6))
                fila.nombre = n
            lista.add(fila)
        opciones = Gtk.ListBoxRow()
        opciones.add(Gtk.Label(label="Options", xalign=0, margin=6))
        opciones.nombre = "Options"
        def al_elegir(_l, f):
            if f is not None and getattr(f, "nombre", None):
                pie.unselect_all()
                paginas.set_visible_child_name(f.nombre)
        lista.connect("row-selected", al_elegir)
        izq.pack_start(lista, True, True, 0)
        pie = Gtk.ListBox()
        pie.set_selection_mode(Gtk.SelectionMode.SINGLE)
        pie.add(opciones)

        def al_elegir_opciones(_l, f):
            if f is not None:
                lista.unselect_all()
                paginas.set_visible_child_name("Options")
        pie.connect("row-selected", al_elegir_opciones)
        izq.pack_start(pie, False, False, 0)
        caja.pack_start(izq, False, False, 0)
        caja.pack_start(Gtk.Separator(orientation=Gtk.Orientation.VERTICAL), False, False, 0)
        der = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, margin=12)
        der.set_size_request(440, 480)
        der.pack_start(paginas, True, True, 0)
        ayuda = Gtk.Button(label="?")
        ayuda.get_style_context().add_class("circular")
        ayuda.set_size_request(24, 24)
        ayuda.set_halign(Gtk.Align.END)
        der.pack_end(_gris(ayuda), False, False, 0)
        caja.pack_start(der, True, True, 0)
        caja.show_all()
        paginas.show_all()
        lista.select_row(lista.get_row_at_index(0))
        paginas.set_visible_child_name("App Usage")
        return caja

    # ── App Usage, Notifications y Pickups ─────────────────────────────
    def _pagina_uso(self, titulo, valor, escala_semana, escala_dia, columnas, leyenda):
        pagina = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        fecha = Gtk.Box(spacing=6)
        hoy = time.strftime("Today, %B %-d")
        fecha.pack_end(_gris(Gtk.Button(label="›")), False, False, 0)
        fecha.pack_end(_gris(Gtk.Button(label="Today")), False, False, 0)
        fecha.pack_end(_gris(Gtk.Button(label="‹")), False, False, 0)
        etq = Gtk.Label(label=hoy + " ⌄", xalign=1.0)
        fecha.pack_end(_gris(etq), False, False, 8)
        pagina.pack_start(fecha, False, False, 0)
        marco = _marco()
        interior = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4, margin=12)
        interior.pack_start(_etiqueta(titulo, detalle=True), False, False, 0)
        grande = Gtk.Label(xalign=0.0)
        grande.set_markup('<span size="x-large">%s</span>' % valor)
        interior.pack_start(grande, False, False, 0)
        interior.pack_start(_Graficas(escala_semana, escala_dia), False, False, 0)
        if leyenda:
            interior.pack_start(_etiqueta("■ " + leyenda, detalle=True), False, False, 0)
            interior.pack_start(_etiqueta(valor), False, False, 0)
        else:
            interior.pack_start(_etiqueta("Total " + titulo, detalle=True), False, False, 0)
            interior.pack_start(_etiqueta(valor), False, False, 0)
        # La tabla: Show: Apps | Categories (solo en App Usage), columnas y la fila All Apps.
        tabla = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4, margin=8)
        cab = Gtk.Box(spacing=12)
        if titulo == "Usage":
            cab.pack_start(_etiqueta("Show:", detalle=True), False, False, 0)
            cab.pack_start(_gris(Gtk.Button(label="Apps")), False, False, 0)
            cab.pack_start(_etiqueta("Categories"), False, False, 0)
        else:
            cab.pack_start(_etiqueta("Apps", detalle=True), False, False, 0)
        for c in columnas:
            cab.pack_end(_etiqueta(c, detalle=True), False, False, 12)
        tabla.pack_start(cab, False, False, 0)
        fila = Gtk.Box(spacing=12)
        fila.pack_start(_etiqueta("All Apps"), False, False, 0)
        fila.pack_end(_etiqueta(valor), False, False, 12)
        tabla.pack_start(fila, False, False, 6)
        interior.pack_start(tabla, True, True, 0)
        marco.add(interior)
        pagina.pack_start(marco, True, True, 0)
        pie = Gtk.Box(spacing=8)
        todos = Gtk.ComboBoxText()
        todos.append("a", "All Devices")
        todos.set_active(0)
        pie.pack_start(_gris(todos), False, False, 0)
        pie.pack_end(_etiqueta(time.strftime("Updated today at %-I:%M %p"), detalle=True, xalign=1.0), False, False, 0)
        pagina.pack_start(pie, False, False, 0)
        return pagina

    # ── Downtime ───────────────────────────────────────────────────────
    def _cabecera(self, estado, valor, boton, texto):
        c = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        fila = Gtk.Box()
        t = Gtk.Label(xalign=0.0)
        t.set_markup("%s <b>%s</b>" % (GLib.markup_escape_text(estado), valor))
        fila.pack_start(t, True, True, 0)
        fila.pack_end(_gris(Gtk.Button(label=boton)), False, False, 0)
        c.pack_start(fila, False, False, 0)
        c.pack_start(_etiqueta(texto), False, False, 0)
        return c

    def _pagina_downtime(self):
        pagina = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        pagina.pack_start(self._cabecera("Downtime:", "Off", "Turn On…",
                                         "Set a schedule for time away from the screen. During downtime, only apps that "
                                         "you choose to allow and phone calls will be available."), False, False, 0)
        pagina.pack_start(_etiqueta("Schedule:", negrita=True), False, False, 0)
        pagina.pack_start(_etiqueta("Downtime will apply to all devices that are using iCloud for screen time. A "
                                    "downtime reminder will appear five minutes before downtime."), False, False, 0)
        r1 = Gtk.Box(spacing=8)
        every = Gtk.RadioButton.new_with_label_from_widget(None, "Every Day")
        r1.pack_start(every, False, False, 0)
        r1.pack_start(Gtk.Entry(text="10:00 PM", width_chars=9), False, False, 0)
        r1.pack_start(Gtk.Label(label="to"), False, False, 0)
        r1.pack_start(Gtk.Entry(text="6:00 AM", width_chars=9), False, False, 0)
        pagina.pack_start(_gris(r1), False, False, 0)
        pagina.pack_start(_gris(Gtk.RadioButton.new_with_label_from_widget(every, "Custom")), False, False, 0)
        return pagina

    # ── App Limits ─────────────────────────────────────────────────────
    def _pagina_limites(self):
        pagina = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        pagina.pack_start(self._cabecera("App Limits:", "On", "Turn Off…",
                                         "Set daily time limits for app categories you want to manage. App limits "
                                         "reset every day at midnight."), False, False, 0)
        marco = _marco()
        marco.set_size_request(-1, 230)
        cab = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        fila = Gtk.Box(spacing=12, margin=6)
        fila.pack_start(_etiqueta("Limits", detalle=True), True, True, 0)
        fila.pack_start(_etiqueta("Time Amount", detalle=True), True, True, 0)
        cab.pack_start(fila, False, False, 0)
        marco.add(cab)
        pagina.pack_start(_gris(marco), False, False, 0)
        pagina.pack_start(_etiqueta("App limits apply to all devices that are using iCloud for screen time. A "
                                    "notification will appear five minutes before the limit expires."), False, False, 0)
        pie = Gtk.Box()
        botones = Gtk.Box()
        botones.get_style_context().add_class("linked")
        for t in ("+", "−"):
            botones.pack_start(_gris(Gtk.Button(label=t)), False, False, 0)
        pie.pack_start(botones, False, False, 0)
        pie.pack_end(_gris(Gtk.Button(label="Edit Limit…")), False, False, 0)
        pagina.pack_start(pie, False, False, 0)
        return pagina

    # ── Communication ──────────────────────────────────────────────────
    def _radios(self, titulo, opciones, activa, nota, con_editar=None):
        caja = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        caja.pack_start(_etiqueta(titulo), False, False, 0)
        grupo = None
        for i, o in enumerate(opciones):
            r = Gtk.RadioButton.new_with_label_from_widget(grupo, o)
            grupo = grupo or r
            r.set_active(i == activa)
            fila = Gtk.Box(spacing=8)
            fila.pack_start(r, False, False, 0)
            if con_editar == i:
                fila.pack_start(Gtk.Button(label="Edit…"), False, False, 0)
            caja.pack_start(_gris(fila), False, False, 0)
        n = _etiqueta(nota, detalle=True)
        n.set_margin_start(20)
        caja.pack_start(n, False, False, 0)
        return caja

    def _pagina_comunicacion(self):
        pagina = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
        pagina.pack_start(_etiqueta("Limits apply to Phone, FaceTime, Messages, and iCloud contacts. Communication to "
                                    "known emergency numbers identified by your carrier is always allowed."), False, False, 0)
        pagina.pack_start(Gtk.Separator(), False, False, 0)
        pagina.pack_start(self._radios("During screen time, allow communication with:",
                                       ["Contacts Only", "Contacts & Groups with at Least One Contact", "Everyone"], 2,
                                       "Allow one-on-one and group conversations with anyone including unknown numbers."),
                          False, False, 0)
        pagina.pack_start(self._radios("During downtime, allow communication with:", ["Specific Contacts", "Everyone"], 1,
                                       "During downtime, allow one-on-one and group conversations with anyone including "
                                       "unknown numbers.", con_editar=0), False, False, 0)
        return pagina

    # ── Always Allowed ─────────────────────────────────────────────────
    def _pagina_permitidas(self):
        pagina = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        pagina.pack_start(_etiqueta("Always allowed apps and contacts are available during downtime, or if you selected "
                                    "the “All Apps & Categories” app limit."), False, False, 0)
        pagina.pack_start(self._radios("During downtime, allow communication with:", ["Specific Contacts", "Everyone"], 1,
                                       "During downtime, allow one-on-one and group conversations with anyone including "
                                       "unknown numbers.", con_editar=0), False, False, 0)
        cab = Gtk.Box()
        cab.pack_start(_etiqueta("Allowed Apps:"), True, True, 0)
        buscar = Gtk.SearchEntry()
        cab.pack_end(_gris(buscar), False, False, 0)
        pagina.pack_start(cab, False, False, 0)
        marco = _marco()
        desplazable = Gtk.ScrolledWindow()
        desplazable.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        desplazable.set_size_request(-1, 250)
        lista = Gtk.ListBox()
        lista.set_selection_mode(Gtk.SelectionMode.NONE)
        cab_t = Gtk.Box(spacing=12, margin=6)
        cab_t.pack_start(_etiqueta("Sort by Daily Usage ⌄"), True, True, 0)
        cab_t.pack_end(_etiqueta("Daily Usage", detalle=True), False, False, 6)
        lista.add(cab_t)
        def es_app(a):
            # Solo aplicaciones: los módulos de configuración de Cinnamon también son .desktop
            cat = (a.get_categories() or "") if isinstance(a, Gio.DesktopAppInfo) else ""
            return a.should_show() and "Settings" not in cat.split(";") and not a.get_id().startswith("cinnamon-settings")

        apps = sorted((a for a in Gio.AppInfo.get_all() if es_app(a)), key=lambda a: a.get_name().lower())
        for a in apps[:40]:
            fila = Gtk.Box(spacing=10, margin=5)
            fila.pack_start(Gtk.CheckButton(), False, False, 0)
            icono = a.get_icon()
            if icono is not None:
                imagen = Gtk.Image.new_from_gicon(icono, Gtk.IconSize.LARGE_TOOLBAR)
                imagen.set_pixel_size(24)
                fila.pack_start(imagen, False, False, 0)
            fila.pack_start(Gtk.Label(label=a.get_name(), xalign=0), True, True, 0)
            fila.pack_end(_etiqueta("0s"), False, False, 6)
            lista.add(fila)
        desplazable.add(lista)
        marco.add(_gris(desplazable))
        pagina.pack_start(marco, True, True, 0)
        return pagina

    # ── Content & Privacy ──────────────────────────────────────────────
    def _casillas(self, casillas, titulo=None, marcadas=None):
        """Una columna «Allow:» con sus casillas: (texto, marcada)."""
        fila = Gtk.Box(spacing=10)
        t = _etiqueta(titulo or "", detalle=True, xalign=1.0)
        t.set_size_request(80, -1)
        fila.pack_start(t, False, False, 0)
        col = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        for texto, marcada in casillas:
            c = Gtk.CheckButton(label=texto)
            c.set_active(marcada)
            col.pack_start(c, False, False, 0)
        fila.pack_start(col, False, False, 0)
        return fila

    def _pagina_contenido(self):
        pagina = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        pagina.pack_start(self._cabecera("Content & Privacy Restrictions:", "Off", "Turn On…",
                                         "Restrict explicit content, purchases, downloads, and privacy settings."),
                          False, False, 0)
        pestanas = Gtk.Stack()
        # Content
        c = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        web = Gtk.Box(spacing=10)
        t = _etiqueta("Web Content:", detalle=True, xalign=1.0)
        t.set_size_request(80, -1)
        web.pack_start(t, False, False, 0)
        radios = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        grupo = None
        for i, o in enumerate(("Unrestricted Access", "Limit Adult Websites", "Allowed Websites Only")):
            r = Gtk.RadioButton.new_with_label_from_widget(grupo, o)
            grupo = grupo or r
            r.set_active(i == 1)
            radios.pack_start(r, False, False, 0)
        radios.pack_start(Gtk.Button(label="Customize…"), False, False, 0)
        web.pack_start(radios, False, False, 0)
        c.pack_start(web, False, False, 0)
        c.pack_start(self._casillas([("Explicit Language in Siri & Dictionary", True),
                                     ("Web Search Content in Siri", True)], "Allow:"), False, False, 0)
        c.pack_start(self._casillas([("Music Profiles", True)]), False, False, 0)
        c.pack_start(self._casillas([("Multiplayer Games in Game Center", True), ("Adding Friends in Game Center", True)]),
                     False, False, 0)
        pestanas.add_titled(_gris(c), "Content", "Content")
        # Stores
        s = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        fila = Gtk.Box(spacing=10)
        t = _etiqueta("Ratings for:", detalle=True, xalign=1.0)
        t.set_size_request(80, -1)
        fila.pack_start(t, False, False, 0)
        pais = Gtk.ComboBoxText()
        pais.append("p", "Dominican Republic")
        pais.set_active(0)
        fila.pack_start(pais, True, True, 0)
        s.pack_start(fila, False, False, 0)
        for nombre in ("Movies", "TV Shows", "Apps"):
            f = Gtk.Box(spacing=10)
            e = _etiqueta("Allowed Content:" if nombre == "Movies" else "", detalle=True, xalign=1.0)
            e.set_size_request(80, -1)
            f.pack_start(e, False, False, 0)
            f.pack_start(_etiqueta(nombre), False, False, 0)
            f.pack_end(Gtk.ComboBoxText(), False, False, 0)
            s.pack_start(f, False, False, 0)
        s.pack_start(self._casillas([("Explicit Books", False), ("Explicit Music, Podcasts & News", False)]),
                     False, False, 0)
        s.pack_start(self._casillas([("Installing Apps", True), ("Deleting Apps", True), ("In-app Purchases", True)],
                                    "Allow on iOS:"), False, False, 0)
        pw = Gtk.Box(spacing=10)
        e = _etiqueta("Require Password:", detalle=True, xalign=1.0)
        e.set_size_request(80, -1)
        pw.pack_start(e, False, False, 0)
        col = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        a1 = Gtk.RadioButton.new_with_label_from_widget(None, "Always Require")
        a2 = Gtk.RadioButton.new_with_label_from_widget(a1, "Require after 15 minutes")
        a2.set_active(True)
        col.pack_start(a1, False, False, 0)
        col.pack_start(a2, False, False, 0)
        col.pack_start(_etiqueta("Require a password for additional purchases after making a purchase from the iTunes, "
                                 "Book, or App Store.", detalle=True), False, False, 0)
        pw.pack_start(col, False, False, 0)
        s.pack_start(pw, False, False, 0)
        pestanas.add_titled(_gris(s), "Stores", "Stores")
        # Apps
        a = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        a.pack_start(self._casillas([("Camera", True), ("Books Store", True), ("Siri & Dictation", True)], "Allow:"),
                     False, False, 0)
        a.pack_start(self._casillas([("Mail", True), ("Safari", True), ("FaceTime", True), ("Wallet", False),
                                     ("CarPlay", False), ("iTunes Store", True), ("Podcasts", True), ("AirDrop", True),
                                     ("Screen Recording", True)], "Allow on iOS:"), False, False, 0)
        pestanas.add_titled(_gris(a), "Apps", "Apps")
        # Other
        o = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        o.pack_start(_etiqueta("Restricting changes locks the current settings. The screen time passcode will be required "
                               "to make changes. Restrictions affect iOS only.", detalle=True), False, False, 0)
        o.pack_start(self._casillas([("Passcode Changes", True), ("Account Changes", True),
                                     ("Cellular Data Changes", True), ("Do Not Disturb While Driving", True),
                                     ("TV Provider", True), ("Background App Activities", True)], "Allow Changes:"),
                     False, False, 0)
        b = Gtk.Button(label="Open Privacy Settings…")
        b.set_halign(Gtk.Align.CENTER)
        o.pack_start(b, False, False, 12)
        pestanas.add_titled(_gris(o), "Other", "Other")
        # Los cuatro segmentos con su ancho natural (el StackSwitcher los iguala al más ancho y la ventana se ensancha).
        selector = Gtk.Box()
        selector.get_style_context().add_class("linked")
        selector.set_halign(Gtk.Align.CENTER)
        selector.get_style_context().add_class("mp-pestanas")
        primero = None
        for nombre in ("Content", "Stores", "Apps", "Other"):
            b = Gtk.RadioButton.new_with_label_from_widget(primero, nombre)
            b.set_mode(False)
            primero = primero or b
            b.connect("toggled", lambda w, n=nombre: w.get_active() and pestanas.set_visible_child_name(n))
            selector.pack_start(b, False, False, 0)
        pagina.pack_start(selector, False, False, 0)
        pagina.pack_start(pestanas, True, True, 0)
        return pagina

    # ── Options ────────────────────────────────────────────────────────
    def _pagina_opciones(self):
        pagina = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        pagina.pack_start(self._cabecera("Screen Time:", "On", "Turn Off…", ""), False, False, 0)
        compartir = Gtk.CheckButton(label="Share across devices")
        compartir.set_active(True)
        pagina.pack_start(_gris(compartir), False, False, 0)
        pagina.pack_start(_etiqueta("You can enable this on any iPhone, iPad, or Mac signed in to iCloud to report your "
                                    "combined screen time.", detalle=True), False, False, 0)
        clave = Gtk.Box()
        clave.pack_start(Gtk.CheckButton(label="Use Screen Time Passcode"), True, True, 0)
        clave.pack_end(Gtk.Button(label="Change Passcode…"), False, False, 0)
        pagina.pack_start(_gris(clave), False, False, 0)
        pagina.pack_start(_etiqueta("Use a passcode to secure Screen Time settings, and to allow for more time when "
                                    "limits expire.", detalle=True), False, False, 0)
        return pagina
