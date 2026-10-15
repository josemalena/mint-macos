"""Displays: el panel de Catalina con sus tres pestañas (Display, Color, Night Shift).

Capturas: Screen Shot 2026-10-14 at 1.18.18 PM (Display), 1.18.21 PM (Color), 1.18.36 PM (Night Shift).

Display: Rotation y Refresh Rate se aplican por el DisplayConfig de Cinnamon (org.cinnamon.Muffin.
DisplayConfig, el mismo que usa cinnamon-settings) en dos tiempos, como en cualquier cambio de pantalla
que puede dejarla en negro: primero temporal, y si no se confirma en 15 segundos vuelve a lo anterior.
«Scaled» se dibuja en gris: Catalina enseña ahí una lista de resoluciones que aún no tenemos capturada.
Color: los perfiles de colord (colormgr). Night Shift: org.cinnamon.settings-daemon.plugins.color.
Sin equivalente (en gris): AirPlay Display, «Show mirroring options», Open Profile, Delete Profile y
Calibrate…, y «Turn On Until Tomorrow».
"""
import os
import re
import subprocess

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gio, GLib, Gtk  # noqa: E402

import paneles  # noqa: E402

DISPLAYCONFIG = ("org.cinnamon.Muffin.DisplayConfig", "/org/cinnamon/Muffin/DisplayConfig",
                 "org.cinnamon.Muffin.DisplayConfig")
GIROS = [(0, "Standard"), (1, "90°"), (2, "180°"), (3, "270°")]
CALIDOS = list(range(4700, 1600, -300))      # Night Shift: de «Less Warm» a «More Warm», en kelvin


def _etiqueta(texto):
    l = Gtk.Label(label=texto, xalign=1.0)
    l.get_style_context().add_class("mp-fila-etiqueta")
    return l


def _gris(widget, motivo=None):
    widget.set_sensitive(False)
    if motivo:
        widget.set_tooltip_text(motivo)
    return widget


def _marco():
    m = Gtk.Frame()
    m.get_style_context().add_class("mp-sd-lista")
    return m


def _proxy():
    return Gio.DBusProxy.new_for_bus_sync(Gio.BusType.SESSION, Gio.DBusProxyFlags.NONE, None, *DISPLAYCONFIG, None)


def estado_actual():
    """(serie, monitores, lógicos) de GetCurrentState, o None si Cinnamon no contesta."""
    try:
        r = _proxy().call_sync("GetCurrentState", None, Gio.DBusCallFlags.NONE, 5000, None)
    except GLib.Error:
        return None
    return r.unpack()[:3]


def monitor_actual(estado):
    """El monitor y su lógico: el principal si hay varios."""
    _serie, monitores, logicos = estado
    for lg in logicos:
        if lg[4] and lg[5]:
            conector = lg[5][0][0]
            for m in monitores:
                if m[0][0] == conector:
                    return m, lg
    return (monitores[0], logicos[0]) if monitores and logicos else (None, None)


def modo_actual(monitor):
    for modo in monitor[1]:
        if modo[6].get("is-current"):
            return modo
    return monitor[1][0] if monitor[1] else None


def configuracion(estado, conector=None, giro=None, modo=None):
    """Los monitores lógicos listos para ApplyMonitorsConfig: cada uno con el modo que tiene ahora; al del
    `conector` se le cambia el giro y/o el modo."""
    _serie, monitores, logicos = estado
    actual = {m[0][0]: modo_actual(m)[0] for m in monitores if modo_actual(m)}
    salida = []
    for x, y, esc, rot, prim, mons, _props in logicos:
        if mons and mons[0][0] == conector:
            if giro is not None:
                rot = giro
        lista = [(c[0], modo if (c[0] == conector and modo) else actual[c[0]], {}) for c in mons]
        salida.append((x, y, esc, rot, prim, lista))
    return salida


def aplicar(serie, config, metodo):
    """ApplyMonitorsConfig: método 1 = temporal, 2 = persistente."""
    arg = GLib.Variant("(uua(iiduba(ssa{sv}))a{sv})", (serie, metodo, config, {}))
    _proxy().call_sync("ApplyMonitorsConfig", arg, Gio.DBusCallFlags.NONE, 10000, None)


class PanelDisplays:
    id = "com.apple.preference.displays"
    nombre = "Displays"
    claves = []
    externo = False
    propio = True
    celda = None
    PRUEBA = bool(os.environ.get("MINT_PANTALLAS_PRUEBA"))     # no aplica cambios de pantalla ni escribe nada

    def __init__(self):
        self.panel = paneles.Panel(self.id, self.nombre, [],
                                   palabras="displays, display, resolution, rotation, refresh rate, night shift, "
                                            "color, profile, monitor, temperature")
        self.ventana = None
        self._cargando = False

    def coincide(self, texto):
        t = texto.lower().strip()
        return bool(t) and any(t in c.lower() for c in (self.nombre, self.panel.palabras, self.id))

    # ── la página ────────────────────────────────────────────────────────
    def construir(self):
        self._cargando = True
        caja = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        caja.get_style_context().add_class("mp-propio")
        caja.set_margin_top(12)
        stack = Gtk.Stack()
        stack.add_titled(self._pagina_pantalla(), "display", "Display")
        stack.add_titled(self._pagina_color(), "color", "Color")
        stack.add_titled(self._pagina_noche(), "night", "Night Shift")
        pestanas = Gtk.StackSwitcher()
        pestanas.set_stack(stack)
        pestanas.set_halign(Gtk.Align.CENTER)
        pestanas.get_style_context().add_class("mp-pestanas")
        caja.pack_start(pestanas, False, False, 0)
        marco = _marco()
        marco.add(stack)
        caja.pack_start(marco, True, True, 0)

        pie = Gtk.Grid(column_spacing=10, row_spacing=8)
        pie.set_margin_top(6)
        pie.attach(_etiqueta("AirPlay Display:"), 0, 0, 1, 1)
        air = Gtk.ComboBoxText()
        air.append("off", "Off")
        air.set_active(0)
        pie.attach(_gris(air, "AirPlay displays are not available on this computer."), 1, 0, 1, 1)
        espejo = Gtk.CheckButton(label="Show mirroring options in the menu bar when available")
        espejo.set_active(True)
        pie.attach(_gris(espejo), 0, 1, 2, 1)
        caja.pack_start(pie, False, False, 0)
        caja.show_all()
        pedida = os.environ.get("MINT_PANTALLAS_PESTANA")      # solo para las pruebas visuales
        if pedida:
            stack.set_visible_child_name(pedida)
        self._cargando = False
        return caja

    # ── Display ──────────────────────────────────────────────────────────
    def _pagina_pantalla(self):
        pagina = Gtk.Box(spacing=24)
        pagina.set_margin_top(24)
        pagina.set_margin_start(24)
        pagina.set_margin_end(24)
        pagina.set_margin_bottom(24)
        vista = Gtk.DrawingArea()
        vista.set_size_request(210, 130)

        def pintar(_w, cr):
            ancho, alto = 210, 118
            g = __import__("cairo").LinearGradient(0, 0, ancho, alto)
            g.add_color_stop_rgb(0, 0.07, 0.07, 0.07)
            g.add_color_stop_rgb(0.5, 0.17, 0.17, 0.17)
            g.add_color_stop_rgb(1, 0.1, 0.1, 0.1)
            cr.set_source(g)
            cr.rectangle(0, 0, ancho, alto)
            cr.fill()
            cr.set_source_rgb(0.75, 0.75, 0.75)
            cr.rectangle(ancho / 2 - 30, alto, 60, 5)
            cr.fill()
            return False
        vista.connect("draw", pintar)
        pagina.pack_start(vista, False, False, 0)

        g = Gtk.Grid(column_spacing=10, row_spacing=10)
        self._estado = estado_actual()
        monitor, logico = monitor_actual(self._estado) if self._estado else (None, None)
        self._monitor, self._logico = monitor, logico

        g.attach(_etiqueta("Resolution:"), 0, 0, 1, 1)
        res = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        por_defecto = Gtk.RadioButton.new_with_label_from_widget(None, "Default for display")
        escalada = Gtk.RadioButton.new_with_label_from_widget(por_defecto, "Scaled")
        por_defecto.set_active(True)
        _gris(escalada, "The list of scaled resolutions is not available yet.")
        res.pack_start(por_defecto, False, False, 0)
        res.pack_start(escalada, False, False, 0)
        g.attach(res, 1, 0, 1, 1)

        g.attach(_etiqueta("Rotation:"), 0, 1, 1, 1)
        self._giro = Gtk.ComboBoxText()
        for v, n in GIROS:
            self._giro.append(str(v), n)
        self._giro.set_active_id(str(logico[3] if logico else 0))
        g.attach(self._giro, 1, 1, 1, 1)

        g.attach(_etiqueta("Refresh Rate:"), 0, 2, 1, 1)
        self._frecuencia = Gtk.ComboBoxText()
        actual = modo_actual(monitor) if monitor else None
        if actual:
            for modo in monitor[1]:
                if modo[1] == actual[1] and modo[2] == actual[2] and not modo[6].get("is-interlaced"):
                    self._frecuencia.append(modo[0], "%.2f Hertz" % modo[3])
            self._frecuencia.set_active_id(actual[0])
        g.attach(self._frecuencia, 1, 2, 1, 1)
        if monitor is None:
            for w in (self._giro, self._frecuencia):
                _gris(w, "Cinnamon did not report any display.")
        self._giro.connect("changed", lambda _c: self._cambiar())
        self._frecuencia.connect("changed", lambda _c: self._cambiar())
        pagina.pack_start(g, False, False, 0)
        return pagina

    def _cambiar(self):
        """Aplica el giro y la frecuencia elegidos, con vuelta atrás si no se confirma."""
        if self._cargando or self._estado is None or self._logico is None:
            return
        conector = self._monitor[0][0]
        antes = configuracion(self._estado)
        nuevo = configuracion(self._estado, conector, int(self._giro.get_active_id()),
                              self._frecuencia.get_active_id())
        if self.PRUEBA:
            print("[prueba] aplicaría", nuevo)
            return
        try:
            aplicar(self._estado[0], nuevo, 1)               # temporal
        except GLib.Error as e:
            self._aviso("Could not change the display: %s" % e.message)
            self._refrescar()
            return
        if self._confirmar():
            ahora = estado_actual()
            if ahora:
                aplicar(ahora[0], nuevo, 2)                  # persistente
        else:
            try:
                aplicar(estado_actual()[0], antes, 1)        # vuelta a lo de antes
            except (GLib.Error, TypeError):
                pass
        self._refrescar()

    def _refrescar(self):
        self._estado = estado_actual()
        if self._estado:
            self._monitor, self._logico = monitor_actual(self._estado)
        self._cargando = True
        self._restaurar_menus()
        self._cargando = False

    def _restaurar_menus(self):
        if self._logico:
            self._giro.set_active_id(str(self._logico[3]))
        actual = modo_actual(self._monitor) if self._monitor else None
        if actual:
            self._frecuencia.set_active_id(actual[0])

    def _confirmar(self):
        """¿Se queda este cambio? Sin respuesta en 15 s se devuelve lo anterior."""
        d = Gtk.MessageDialog(transient_for=self.ventana, modal=True, message_type=Gtk.MessageType.QUESTION,
                              text="Do you want to keep these display settings?")
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

    def _aviso(self, texto):
        d = Gtk.MessageDialog(transient_for=self.ventana, modal=True, message_type=Gtk.MessageType.WARNING,
                              buttons=Gtk.ButtonsType.OK, text=texto)
        d.run()
        d.destroy()

    # ── Color ────────────────────────────────────────────────────────────
    @staticmethod
    def _colormgr(*args):
        try:
            r = subprocess.run(["colormgr", *args], capture_output=True, text=True, timeout=15)
            return r.stdout if r.returncode == 0 else ""
        except (OSError, subprocess.SubprocessError):
            return ""

    def _pagina_color(self):
        pagina = Gtk.Box(spacing=24)
        pagina.set_margin_top(18)
        pagina.set_margin_start(24)
        pagina.set_margin_end(24)
        pagina.set_margin_bottom(18)
        izq = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        izq.pack_start(Gtk.Label(label="Display profile:", xalign=0), False, False, 0)
        lista = Gtk.ListStore(str, str)
        perfiles = []
        for bloque in self._colormgr("get-profiles").split("\n\n"):
            ruta = re.search(r"^Object Path:\s+(\S+)", bloque, re.M)
            titulo = re.search(r"^Title:\s+(.+)$", bloque, re.M)
            if ruta and titulo:
                perfiles.append((titulo.group(1).strip(), ruta.group(1)))
        for titulo, ruta in sorted(perfiles, key=lambda p: p[0].lower()):
            lista.append([titulo, ruta])
        arbol = Gtk.TreeView(model=lista)
        arbol.set_headers_visible(False)
        arbol.append_column(Gtk.TreeViewColumn("", Gtk.CellRendererText(), text=0))
        pant = Gtk.ScrolledWindow()
        pant.set_size_request(300, 220)
        pant.add(arbol)
        marco = _marco()
        marco.add(pant)
        izq.pack_start(marco, True, True, 0)
        solo = Gtk.CheckButton(label="Show profiles for this display only")
        _gris(solo, "All the installed profiles are shown.")
        izq.pack_start(solo, False, False, 0)
        pagina.pack_start(izq, False, False, 0)

        der = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        der.set_margin_top(26)
        for texto in ("Open Profile", "Delete Profile", "Calibrate…"):
            der.pack_start(_gris(Gtk.Button(label=texto), "Not available on this computer."), False, False, 0)
        pagina.pack_start(der, False, False, 0)
        # Elegir un perfil lo hace el predeterminado de la pantalla (colormgr).
        dispositivo = self._dispositivo()
        arbol.get_selection().connect("changed", lambda s: self._perfil_elegido(s, dispositivo))
        return pagina

    def _dispositivo(self):
        for bloque in self._colormgr("get-devices-by-kind", "display").split("\n\n"):
            ruta = re.search(r"^Object Path:\s+(\S+)", bloque, re.M)
            if ruta:
                return ruta.group(1)
        return None

    def _perfil_elegido(self, sel, dispositivo):
        modelo, it = sel.get_selected()
        if it is None or not dispositivo or self._cargando or self.PRUEBA:
            return
        perfil = modelo[it][1]
        self._colormgr("device-add-profile", dispositivo, perfil)
        self._colormgr("device-make-profile-default", dispositivo, perfil)

    # ── Night Shift ──────────────────────────────────────────────────────
    def _pagina_noche(self):
        cfg = Gio.Settings.new("org.cinnamon.settings-daemon.plugins.color")
        self._noche = cfg
        pagina = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
        pagina.set_margin_top(24)
        pagina.set_margin_start(24)
        pagina.set_margin_end(24)
        t = Gtk.Label(label="Night Shift automatically shifts the colors of your display to the warmer end of "
                            "the color spectrum after dark. This may help you get a better night’s sleep.")
        t.set_line_wrap(True)
        t.set_max_width_chars(70)
        t.set_justify(Gtk.Justification.CENTER)
        pagina.pack_start(t, False, False, 0)

        g = Gtk.Grid(column_spacing=10, row_spacing=12)
        g.set_halign(Gtk.Align.CENTER)
        g.attach(_etiqueta("Schedule:"), 0, 0, 1, 1)
        horario = Gtk.ComboBoxText()
        horario.append("off", "Off")
        horario.append("manual", "Custom")
        horario.append("auto", "Sunset to Sunrise")
        horario.set_active_id("off" if not cfg.get_boolean("night-light-enabled")
                              else ("auto" if cfg.get_string("night-light-schedule-mode") == "auto" else "manual"))
        horario.set_halign(Gtk.Align.START)
        g.attach(horario, 1, 0, 3, 1)

        g.attach(_etiqueta("From:"), 0, 1, 1, 1)
        desde = self._hora("night-light-schedule-from")
        g.attach(desde, 1, 1, 1, 1)
        g.attach(_etiqueta("to:"), 2, 1, 1, 1)
        hasta = self._hora("night-light-schedule-to")
        g.attach(hasta, 3, 1, 1, 1)
        g.attach(_etiqueta("Manual:"), 0, 2, 1, 1)
        manual = Gtk.CheckButton(label="Turn On Until Tomorrow")
        g.attach(_gris(manual, "Use the schedule to turn Night Shift on."), 1, 2, 3, 1)

        g.attach(_etiqueta("Color Temperature:"), 0, 3, 1, 1)
        actual = cfg.get_uint("night-light-temperature")
        indice = min(range(len(CALIDOS)), key=lambda i: abs(CALIDOS[i] - actual))
        esc = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0, len(CALIDOS) - 1, 1)
        esc.set_draw_value(False)
        esc.set_round_digits(0)
        esc.set_value(indice)
        esc.set_size_request(210, -1)
        esc.add_mark(0, Gtk.PositionType.BOTTOM, "Less Warm")
        esc.add_mark(len(CALIDOS) - 1, Gtk.PositionType.BOTTOM, "More Warm")
        esc.connect("value-changed", lambda s: self._escribir(
            lambda: cfg.set_uint("night-light-temperature", CALIDOS[int(round(s.get_value()))])))
        g.attach(esc, 1, 3, 3, 1)
        pagina.pack_start(g, False, False, 0)

        def al_horario(c):
            modo = c.get_active_id()
            for w in (desde, hasta):
                w.set_sensitive(modo == "manual")
            if modo == "off":
                self._escribir(lambda: cfg.set_boolean("night-light-enabled", False))
            else:
                def poner():
                    cfg.set_string("night-light-schedule-mode", modo)
                    cfg.set_boolean("night-light-enabled", True)
                self._escribir(poner)
        horario.connect("changed", al_horario)
        for w in (desde, hasta):
            w.set_sensitive(horario.get_active_id() == "manual")
        return pagina

    def _escribir(self, hacer):
        if self._cargando or self.PRUEBA:
            return
        hacer()

    def _hora(self, clave):
        """Un selector de hora en 12 h (7:00 PM), guardada como horas decimales en gsettings."""
        valor = self._noche.get_double(clave)
        caja = Gtk.Box(spacing=4)
        h = Gtk.SpinButton.new_with_range(1, 12, 1)
        m = Gtk.SpinButton.new_with_range(0, 59, 1)
        m.set_numeric(True)
        m.connect("output", lambda s: s.set_text("%02d" % int(s.get_value())) or True)
        ampm = Gtk.ComboBoxText()
        ampm.append("AM", "AM")
        ampm.append("PM", "PM")
        h24 = int(valor) % 24
        h.set_value(h24 % 12 or 12)
        m.set_value(round((valor - int(valor)) * 60))
        ampm.set_active_id("PM" if h24 >= 12 else "AM")

        def guardar(*_):
            hora = int(h.get_value()) % 12 + (12 if ampm.get_active_id() == "PM" else 0)
            self._escribir(lambda: self._noche.set_double(clave, hora + int(m.get_value()) / 60.0))
        for w in (h, m):
            w.connect("value-changed", guardar)
        ampm.connect("changed", guardar)
        for w in (h, m, ampm):
            caja.pack_start(w, False, False, 0)
        return caja
