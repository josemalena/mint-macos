"""Language & Region: el panel de Catalina (Screen Shot 2026-10-14 at 12.13.52 AM General y 12.13.55 AM Apps).

Lo que enseña es lo que el sistema tiene de verdad: el idioma de LANG (iso-codes), la región de
LC_NUMERIC / LC_MONETARY (en esta Mac mini el idioma es inglés y los formatos son de República
Dominicana, como en Catalina), el primer día de la semana y el ejemplo de fecha, hora, número y moneda
con esos formatos. Cambiar el idioma o los formatos se hace con root (/etc/default/locale), así que todos
los controles van en gris; Keyboard Preferences… abre el panel Keyboard.
Advanced… (hojas General, Dates y Times: 12.14.01 a 12.14.07) y la hoja + no están hechas.
Sin equivalente (en gris): Calendar, Temperature y la pestaña Apps (el idioma por app).
"""
import json
import locale
import os
import subprocess
import time

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gio, Gtk  # noqa: E402

import paneles  # noqa: E402


def _nombre_idioma(codigo):
    try:
        for x in json.load(open("/usr/share/iso-codes/json/iso_639-3.json", encoding="utf-8"))["639-3"]:
            if x.get("alpha_2") == codigo:
                return x["name"]
    except (OSError, ValueError, KeyError):
        pass
    return codigo


def _nombre_pais(codigo):
    try:
        for x in json.load(open("/usr/share/iso-codes/json/iso_3166-1.json", encoding="utf-8"))["3166-1"]:
            if x["alpha_2"] == codigo:
                return x["name"]
    except (OSError, ValueError, KeyError):
        pass
    return codigo


def _gris(widget, motivo="Changing the language or the formats needs the administrator."):
    widget.set_sensitive(False)
    widget.set_tooltip_text(motivo)
    return widget


def _marco():
    m = Gtk.Frame()
    m.get_style_context().add_class("mp-sd-lista")
    return m


class PanelLanguage:
    id = "com.apple.Localization"
    nombre = "Language & Region"
    claves = []
    externo = False
    propio = True
    celda = None

    def __init__(self):
        self.panel = paneles.Panel(self.id, self.nombre, [],
                                   palabras="language, region, formats, first day of week, calendar, time format, "
                                            "temperature, preferred languages, currency")
        self.ventana = None

    def coincide(self, texto):
        t = texto.lower().strip()
        return bool(t) and any(t in c.lower() for c in (self.nombre, self.panel.palabras, self.id))

    def construir(self):
        from propios import imagen_icono_panel
        caja = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        caja.get_style_context().add_class("mp-propio")
        for lado in ("top", "bottom", "start", "end"):
            getattr(caja, "set_margin_" + lado)(14)
        cab = Gtk.Box(spacing=14)
        cab.pack_start(imagen_icono_panel(self.id, 48), False, False, 0)
        t = Gtk.Label(label="Language & Region preferences control the language you see in menus and dialogs, and "
                            "the formats of dates, times, and currencies.", xalign=0)
        t.set_line_wrap(True)
        t.set_max_width_chars(70)
        cab.pack_start(t, True, True, 0)
        caja.pack_start(cab, False, False, 0)

        stack = Gtk.Stack()
        stack.add_titled(self._general(), "general", "General")
        stack.add_titled(self._apps(), "apps", "Apps")
        pestanas = Gtk.StackSwitcher()
        pestanas.set_stack(stack)
        pestanas.set_halign(Gtk.Align.CENTER)
        pestanas.get_style_context().add_class("mp-pestanas")
        caja.pack_start(pestanas, False, False, 0)
        marco = _marco()
        marco.add(stack)
        caja.pack_start(marco, True, True, 0)

        pie = Gtk.Box(spacing=8)
        teclado = Gtk.Button(label="Keyboard Preferences…")
        teclado.connect("clicked", lambda _b: subprocess.Popen(
            [os.path.expanduser("~/.local/bin/mac-settings"), "keyboard"], start_new_session=True))
        avanzado = Gtk.Button(label="Advanced…")
        _gris(avanzado, "This sheet is not available yet.")
        pie.pack_end(avanzado, False, False, 0)
        pie.pack_end(teclado, False, False, 0)
        caja.pack_start(pie, False, False, 0)
        caja.show_all()
        return caja

    def _general(self):
        try:
            locale.setlocale(locale.LC_ALL, "")
        except locale.Error:
            pass
        lang = (os.environ.get("LANG") or "en_US.UTF-8").split(".")[0]
        idioma = _nombre_idioma(lang.split("_")[0])
        pais = _nombre_pais((locale.getlocale(locale.LC_NUMERIC)[0] or lang).split("_")[-1])
        pagina = Gtk.Box(spacing=18, margin=16)
        izq = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        izq.pack_start(Gtk.Label(label="Preferred languages:", xalign=0), False, False, 0)
        lista = Gtk.ListBox()
        lista.set_size_request(200, 220)
        fila = Gtk.ListBoxRow()
        v = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, margin=6)
        v.pack_start(Gtk.Label(label=idioma, xalign=0), False, False, 0)
        s = Gtk.Label(label="%s — Primary" % idioma, xalign=0)
        s.get_style_context().add_class("mp-sd-detalle")
        v.pack_start(s, False, False, 0)
        fila.add(v)
        lista.add(fila)
        m = _marco()
        m.add(_gris(lista))
        izq.pack_start(m, True, True, 0)
        botones = Gtk.Box()
        botones.get_style_context().add_class("linked")
        for t in ("+", "−"):
            botones.pack_start(_gris(Gtk.Button(label=t)), False, False, 0)
        izq.pack_start(botones, False, False, 0)
        pagina.pack_start(izq, False, False, 0)

        der = Gtk.Grid(column_spacing=10, row_spacing=10)
        der.set_valign(Gtk.Align.START)

        def combo(titulo, texto, fila_g):
            e = Gtk.Label(label=titulo, xalign=1.0)
            e.get_style_context().add_class("mp-fila-etiqueta")
            der.attach(e, 0, fila_g, 1, 1)
            c = Gtk.ComboBoxText()
            c.append("v", texto)
            c.set_active(0)
            der.attach(_gris(c), 1, fila_g, 1, 1)
        dias = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        primero = Gio.Settings.new("org.cinnamon.desktop.interface").get_int("first-day-of-week")
        dia = dias[primero - 1] if 1 <= primero <= 7 and primero != 7 else "Sunday"
        combo("Region:", pais, 0)
        combo("First day of week:", dia, 1)
        combo("Calendar:", "Gregorian", 2)
        e = Gtk.Label(label="Time format:", xalign=1.0)
        e.get_style_context().add_class("mp-fila-etiqueta")
        der.attach(e, 0, 3, 1, 1)
        h24 = Gtk.CheckButton(label="24-Hour Time")
        h24.set_active(Gio.Settings.new("org.cinnamon.desktop.interface").get_boolean("clock-use-24h"))
        der.attach(_gris(h24, "Use the Clock tab of Date & Time for the clock in the menu bar."), 1, 3, 1, 1)
        combo("Temperature:", "°C — Celsius", 4)
        ahora = time.localtime()
        ejemplo = [time.strftime("%A, %B %-d, %Y at %-I:%M:%S %p %Z", ahora),
                   time.strftime("%x, %-I:%M %p", ahora),
                   "%s    %s" % (locale.format_string("%.2f", 12345.67, grouping=True),
                                  locale.currency(45678.9, grouping=True))]
        for i, linea in enumerate(ejemplo):
            l = Gtk.Label(label=linea, xalign=0)
            l.get_style_context().add_class("mp-sd-detalle")
            l.set_margin_top(14 if i == 0 else 0)
            der.attach(l, 0, 5 + i, 2, 1)
        pagina.pack_start(der, True, True, 0)
        return pagina

    def _apps(self):
        pagina = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8, margin=16)
        pagina.pack_start(Gtk.Label(label="Customize language settings for the apps below:", xalign=0),
                          False, False, 0)
        m = _marco()
        m.set_size_request(-1, 230)
        pagina.pack_start(_gris(m, "The language per app is not available on this computer."), True, True, 0)
        botones = Gtk.Box()
        botones.get_style_context().add_class("linked")
        for t in ("+", "−"):
            botones.pack_start(_gris(Gtk.Button(label=t)), False, False, 0)
        pagina.pack_start(botones, False, False, 0)
        return pagina
