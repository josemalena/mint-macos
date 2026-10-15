"""Mouse y Trackpad: los dos paneles de Catalina.

Mouse (Screen Shot 2026-10-14 at 1.24.21 PM): Scroll direction: Natural, Tracking speed,
Scrolling speed, Double-Click speed, Primary mouse button y Set Up Bluetooth Mouse…
Escriben en org.cinnamon.desktop.peripherals.mouse. Scrolling speed no tiene equivalente
en libinput: se dibuja en gris, como en una Mac sin esa función.

Trackpad (1.24.14 PM): la Mac mini no trae trackpad y Catalina enseña «No trackpad found»
con la búsqueda de uno por Bluetooth. Eso es lo que sale aquí mientras no haya un touchpad;
con uno conectado el panel lo sirve el módulo de Cinnamon, porque no tenemos la captura de
Catalina con trackpad (hay que pedírsela a José).
"""
import os
import subprocess

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gio, Gtk  # noqa: E402

import paneles  # noqa: E402

MOUSE = "org.cinnamon.desktop.peripherals.mouse"
# Catalina pone diez marcas en Tracking y en Double-Click speed. Tracking va de -1 a 1 en libinput;
# Double-Click de lento (900 ms) a rápido (250 ms).
PASOS = 10
VELOCIDADES = [-1.0 + 2.0 * i / (PASOS - 1) for i in range(PASOS)]
DOBLE_CLIC = [int(900 - i * (650 / (PASOS - 1))) for i in range(PASOS)]


def hay_touchpad():
    """¿Hay un touchpad o trackpad conectado? (los dispositivos de entrada que lista el kernel)."""
    try:
        with open("/proc/bus/input/devices", encoding="utf-8", errors="replace") as f:
            return any(l.startswith("N:") and any(p in l.lower() for p in ("touchpad", "trackpad"))
                       for l in f)
    except OSError:
        return False


def _etiqueta(texto):
    l = Gtk.Label(label=texto)
    l.get_style_context().add_class("mp-fila-etiqueta")
    return l


def _gris(widget, motivo=None):
    widget.set_sensitive(False)
    if motivo:
        widget.set_tooltip_text(motivo)
    return widget


def _deslizador(indice, pie_izq, pie_der, al_cambiar):
    esc = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0, PASOS - 1, 1)
    esc.set_draw_value(False)
    esc.set_round_digits(0)
    esc.set_value(indice)
    esc.set_size_request(150, -1)
    for i in range(PASOS):
        esc.add_mark(i, Gtk.PositionType.BOTTOM, None)
    esc.add_mark(0, Gtk.PositionType.BOTTOM, pie_izq)
    esc.add_mark(PASOS - 1, Gtk.PositionType.BOTTOM, pie_der)
    esc.connect("value-changed", lambda s: al_cambiar(int(round(s.get_value()))))
    return esc


def _mas_cercano(valores, v):
    return min(range(len(valores)), key=lambda i: abs(valores[i] - v))


def _abrir_bluetooth():
    for prog in ("blueman-manager", "blueberry"):
        try:
            subprocess.Popen([prog], start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return
        except OSError:
            continue


class PanelMouse:
    id = "com.apple.preference.mouse"
    nombre = "Mouse"
    claves = []
    externo = False
    propio = True
    celda = None
    PRUEBA = bool(os.environ.get("MINT_RATON_PRUEBA"))     # no escribe en gsettings

    def __init__(self):
        self.panel = paneles.Panel(self.id, self.nombre, [],
                                   palabras="mouse, pointer, tracking speed, scrolling, double-click, "
                                            "primary button, natural scroll, left handed")
        self.ventana = None
        self._cargando = False

    def coincide(self, texto):
        t = texto.lower().strip()
        return bool(t) and any(t in c.lower() for c in (self.nombre, self.panel.palabras, self.id))

    def construir(self):
        cfg = Gio.Settings.new(MOUSE)
        self._cargando = True

        def poner(clave, valor, tipo):
            if self._cargando or self.PRUEBA:
                return
            getattr(cfg, "set_" + tipo)(clave, valor)

        caja = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
        caja.get_style_context().add_class("mp-propio")
        caja.set_margin_top(22)
        caja.set_margin_start(24)
        caja.set_margin_end(24)
        caja.set_margin_bottom(16)

        natural = Gtk.CheckButton(label="Scroll direction: Natural")
        natural.set_active(cfg.get_boolean("natural-scroll"))
        natural.connect("toggled", lambda b: poner("natural-scroll", b.get_active(), "boolean"))
        natural.set_halign(Gtk.Align.CENTER)
        caja.pack_start(natural, False, False, 0)

        cuerpo = Gtk.Box(spacing=0)
        cuerpo.set_halign(Gtk.Align.CENTER)
        izq = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=22)
        izq.set_margin_end(30)
        for titulo, esc in (
                ("Tracking speed", _deslizador(_mas_cercano(VELOCIDADES, cfg.get_double("speed")), "Slow", "Fast",
                                               lambda i: poner("speed", VELOCIDADES[i], "double"))),
                ("Scrolling speed", _gris(_deslizador(4, "Slow", "Fast", lambda i: None),
                                          "Scrolling speed is not available on this computer."))):
            c = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
            c.pack_start(Gtk.Label(label=titulo), False, False, 0)
            c.pack_start(esc, False, False, 0)
            izq.pack_start(c, False, False, 0)
        cuerpo.pack_start(izq, False, False, 0)
        cuerpo.pack_start(Gtk.Separator(orientation=Gtk.Orientation.VERTICAL), False, False, 0)

        der = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=22)
        der.set_margin_start(30)
        c = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        c.pack_start(Gtk.Label(label="Double-Click speed"), False, False, 0)
        c.pack_start(_deslizador(_mas_cercano(DOBLE_CLIC, cfg.get_int("double-click")), "Slow", "Fast",
                                 lambda i: poner("double-click", DOBLE_CLIC[i], "int")), False, False, 0)
        der.pack_start(c, False, False, 0)
        b = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        b.pack_start(Gtk.Label(label="Primary mouse button:", xalign=0), False, False, 0)
        izquierdo = Gtk.RadioButton.new_with_label_from_widget(None, "Left")
        derecho = Gtk.RadioButton.new_with_label_from_widget(izquierdo, "Right")
        (derecho if cfg.get_boolean("left-handed") else izquierdo).set_active(True)
        derecho.connect("toggled", lambda r: poner("left-handed", r.get_active(), "boolean"))
        b.pack_start(izquierdo, False, False, 0)
        b.pack_start(derecho, False, False, 0)
        der.pack_start(b, False, False, 0)
        cuerpo.pack_start(der, False, False, 0)
        caja.pack_start(cuerpo, False, False, 0)

        pie = Gtk.Box()
        bt = Gtk.Button(label="Set Up Bluetooth Mouse…")
        bt.connect("clicked", lambda _b: _abrir_bluetooth())
        pie.pack_end(bt, False, False, 0)
        caja.pack_end(pie, False, False, 0)
        caja.set_size_request(-1, 300)        # el botón de Bluetooth queda abajo a la derecha, como en Catalina
        caja.show_all()
        self._cargando = False
        return caja


class PanelTrackpad:
    id = "com.apple.preference.trackpad"
    nombre = "Trackpad"
    claves = []
    externo = False
    propio = True
    celda = None

    def __init__(self):
        self.panel = paneles.Panel(self.id, self.nombre, [],
                                   palabras="trackpad, touchpad, bluetooth trackpad, tap, scroll, gestures")
        self.ventana = None

    def coincide(self, texto):
        t = texto.lower().strip()
        return bool(t) and any(t in c.lower() for c in (self.nombre, self.panel.palabras, self.id))

    def construir(self):
        from propios import imagen_icono_panel
        caja = Gtk.Box(spacing=26)
        caja.get_style_context().add_class("mp-propio")
        caja.set_margin_top(26)
        caja.set_margin_start(26)
        caja.set_margin_end(26)
        caja.set_margin_bottom(20)
        caja.pack_start(imagen_icono_panel(self.id, 96), False, False, 0)
        der = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        t = Gtk.Label(label="Wait for a Bluetooth trackpad to be discovered.", xalign=0)
        t.set_line_wrap(True)
        t.get_style_context().add_class("mp-titulo-negrita")
        der.pack_start(t, False, False, 0)
        s = Gtk.Label(label="If your Bluetooth trackpad doesn’t appear, make sure it is turned on.", xalign=0)
        s.set_line_wrap(True)
        s.set_max_width_chars(44)
        der.pack_start(s, False, False, 0)
        n = Gtk.Label(label="No trackpad found")
        n.get_style_context().add_class("mp-titulo-negrita")
        der.pack_start(n, True, True, 30)
        pie = Gtk.Box(spacing=8)
        giro = Gtk.Spinner()
        giro.start()
        pie.pack_start(giro, False, False, 0)
        pie.pack_start(Gtk.Label(label="Searching…"), False, False, 0)
        seguir = Gtk.Button(label="Continue")
        pie.pack_end(_gris(seguir), False, False, 0)
        der.pack_start(pie, False, False, 0)
        caja.pack_start(der, True, True, 0)
        caja.show_all()
        return caja
