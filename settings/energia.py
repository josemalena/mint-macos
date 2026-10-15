"""Energy Saver: el panel de Catalina para una Mac de escritorio (Screen Shot 2026-10-14 at 1.24.31 PM).

Conectado de verdad: Computer sleep (sleep-inactive-ac-timeout + tipo suspend) y Display sleep
(sleep-display-ac) de org.cinnamon.settings-daemon.plugins.power. Restore Defaults vuelve a «Never» y 15
minutos. Sin equivalente aquí (en gris): Put hard disks to sleep, Wake for network access, Start up
automatically after a power failure, Enable Power Nap y Schedule…

La escala de los sliders: Catalina rotula 1 min, 15 min, 1 hr, 3 hrs y Never; los pasos intermedios
(de 5 en 5 minutos hasta la hora y de 15 en 15 hasta las 3 horas) los puse siguiendo esas posiciones.
"""
import os

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gio, Gtk  # noqa: E402

import paneles  # noqa: E402

POWER = "org.cinnamon.settings-daemon.plugins.power"
# Minutos de cada paso del slider; el último es «Never» (0 en gsettings).
PASOS = [1, 3, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60, 75, 90, 105, 120, 135, 150, 165, 180, 0]
ROTULOS = {0: "1 min", 4: "15 min", 13: "1 hr", 21: "3 hrs", 23: "Never"}      # 22 y 23 son «Never»
PANTALLA_POR_DEFECTO = 4      # 15 min (el equipo por defecto es Never)


def _gris(widget, motivo="Not available on this computer."):
    widget.set_sensitive(False)
    widget.set_tooltip_text(motivo)
    return widget


def _paso_de(segundos):
    """El paso más cercano a los segundos de gsettings (0 es «Never»)."""
    if segundos <= 0:
        return len(PASOS)
    minutos = segundos / 60.0
    return min(range(len(PASOS) - 1), key=lambda i: abs(PASOS[i] - minutos))


class PanelEnergySaver:
    id = "com.apple.preference.energysaver"
    nombre = "Energy Saver"
    claves = []
    externo = False
    propio = True
    celda = None
    PRUEBA = bool(os.environ.get("MINT_ENERGIA_PRUEBA"))     # no escribe en gsettings

    def __init__(self):
        self.panel = paneles.Panel(self.id, self.nombre, [],
                                   palabras="energy saver, computer sleep, display sleep, power, suspend, "
                                            "power nap, wake, schedule")
        self.ventana = None
        self._cargando = False

    def coincide(self, texto):
        t = texto.lower().strip()
        return bool(t) and any(t in c.lower() for c in (self.nombre, self.panel.palabras, self.id))

    def construir(self):
        self._cfg = Gio.Settings.new(POWER)
        self._cargando = True
        caja = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        caja.get_style_context().add_class("mp-propio")
        caja.set_margin_top(16)
        caja.set_margin_start(24)
        caja.set_margin_end(24)
        caja.set_margin_bottom(16)

        marco = Gtk.Frame()
        marco.get_style_context().add_class("mp-sd-lista")
        g = Gtk.Grid(column_spacing=14, row_spacing=14)
        for lado in ("top", "bottom", "start", "end"):
            getattr(g, "set_margin_" + lado)(18)
        marco.add(g)
        self._sliders = {}
        for fila, (titulo, clave) in enumerate((("Computer sleep:", "computadora"), ("Display sleep:", "pantalla"))):
            e = Gtk.Label(label=titulo, xalign=1.0)
            e.get_style_context().add_class("mp-fila-etiqueta")
            g.attach(e, 0, fila, 1, 1)
            esc = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0, len(PASOS), 1)
            esc.set_draw_value(False)
            esc.set_round_digits(0)
            esc.set_size_request(500, -1)
            for i in range(len(PASOS) + 1):
                esc.add_mark(i, Gtk.PositionType.BOTTOM, ROTULOS.get(i))
            esc.connect("value-changed", lambda s, k=clave: self._cambio(k, int(round(s.get_value()))))
            self._sliders[clave] = esc
            g.attach(esc, 1, fila, 1, 1)
        self._leer()

        fila = 2
        for texto, activa, tip in (
                ("Put hard disks to sleep when possible", False, None),
                ("Wake for network access", True, None),
                ("Start up automatically after a power failure", True, None)):
            c = Gtk.CheckButton(label=texto)
            c.set_active(activa)
            g.attach(_gris(c), 1, fila, 1, 1)
            fila += 1
        nap = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        c = Gtk.CheckButton(label="Enable Power Nap")
        nap.pack_start(c, False, False, 0)
        d = Gtk.Label(label="While sleeping, your Mac can back up using Time Machine and periodically check for "
                            "new email, calendar, and other iCloud updates", xalign=0)
        d.set_line_wrap(True)
        d.set_max_width_chars(60)
        d.get_style_context().add_class("mp-sd-detalle")
        d.set_margin_start(24)
        nap.pack_start(d, False, False, 0)
        g.attach(_gris(nap), 1, fila, 1, 1)
        fila += 1
        restaurar = Gtk.Button(label="Restore Defaults")
        restaurar.set_halign(Gtk.Align.END)
        restaurar.connect("clicked", lambda _b: self._restaurar())
        g.attach(restaurar, 1, fila, 1, 1)
        caja.pack_start(marco, False, False, 0)

        pie = Gtk.Box()
        pie.pack_end(_gris(Gtk.Button(label="Schedule…")), False, False, 0)
        caja.pack_start(pie, False, False, 0)
        caja.show_all()
        self._cargando = False
        return caja

    def _leer(self):
        previo, self._cargando = self._cargando, True
        self._sliders["computadora"].set_value(_paso_de(self._cfg.get_int("sleep-inactive-ac-timeout")))
        self._sliders["pantalla"].set_value(_paso_de(self._cfg.get_int("sleep-display-ac")))
        self._cargando = previo

    def _cambio(self, cual, indice):
        if self._cargando or self.PRUEBA:
            return
        segundos = PASOS[min(indice, len(PASOS) - 1)] * 60
        if cual == "computadora":
            self._cfg.set_int("sleep-inactive-ac-timeout", segundos)
            if segundos:
                self._cfg.set_string("sleep-inactive-ac-type", "suspend")
        else:
            self._cfg.set_int("sleep-display-ac", segundos)

    def _restaurar(self):
        if self.PRUEBA:
            return
        self._cfg.set_int("sleep-inactive-ac-timeout", 0)
        self._cfg.set_int("sleep-display-ac", PASOS[PANTALLA_POR_DEFECTO] * 60)
        self._leer()
