"""Date & Time: el panel de Catalina con sus tres pestañas (Date & Time, Time Zone, Clock).

Capturas: Screen Shot 2026-10-14 at 1.22.06 PM, 1.22.09 PM y 1.22.14 PM.

Date & Time y Time Zone usan timedatectl: cambiar la zona, el NTP o la hora pide la clave de
administrador por polkit (timedated), que es lo que hace el candado de abajo: pulsarlo pide la clave una
vez y deja los controles listos. Clock escribe el formato del applet calendar@cinnamon.org (el reloj de la
barra de menús): los interruptores arman el formato strftime a partir de las casillas de Catalina.
Sin equivalente (en gris): Analog, Flash the time separators, Show date and time in menu bar, Announce
the time, Set time zone automatically y el mapa de zonas horarias (arte de Apple que no sale del disco).
"""
import glob
import json
import math
import os
import re
import subprocess
import time

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import GLib, Gtk  # noqa: E402

import paneles  # noqa: E402


def _timedatectl(*args):
    try:
        r = subprocess.run(["timedatectl", *args], capture_output=True, text=True, timeout=60)
        return r.returncode == 0, (r.stdout or r.stderr).strip()
    except (OSError, subprocess.SubprocessError) as e:
        return False, str(e)


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


def _archivos_reloj():
    """Los JSON del applet calendar@cinnamon.org (uno por instancia)."""
    return glob.glob(os.path.expanduser("~/.config/cinnamon/spices/calendar@cinnamon.org/*.json"))


class PanelDateTime:
    id = "com.apple.preference.datetime"
    nombre = "Date & Time"
    claves = []
    externo = False
    propio = True
    celda = None
    PRUEBA = bool(os.environ.get("MINT_FECHA_PRUEBA"))     # no cambia la hora, la zona ni el reloj de la barra

    def __init__(self):
        self.panel = paneles.Panel(self.id, self.nombre, [],
                                   palabras="date, time, clock, time zone, timezone, ntp, 24-hour, menu bar, "
                                            "calendar, seconds, am pm")
        self.ventana = None
        self._cargando = False
        self._desbloqueado = False

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
        stack.add_titled(self._pagina_fecha(), "fecha", "Date & Time")
        stack.add_titled(self._pagina_zona(), "zona", "Time Zone")
        stack.add_titled(self._pagina_reloj(), "reloj", "Clock")
        pestanas = Gtk.StackSwitcher()
        pestanas.set_stack(stack)
        pestanas.set_halign(Gtk.Align.CENTER)
        pestanas.get_style_context().add_class("mp-pestanas")
        caja.pack_start(pestanas, False, False, 0)
        marco = _marco()
        marco.add(stack)
        caja.pack_start(marco, True, True, 0)

        pie = Gtk.Box(spacing=8)
        self._candado = Gtk.Button()
        self._candado.set_relief(Gtk.ReliefStyle.NONE)
        self._candado.set_image(Gtk.Image.new_from_icon_name("changes-prevent-symbolic", Gtk.IconSize.LARGE_TOOLBAR))
        self._candado.connect("clicked", lambda _b: self._pedir_clave())
        pie.pack_start(self._candado, False, False, 0)
        self._nota = Gtk.Label(label="Click the lock to make changes.")
        pie.pack_start(self._nota, False, False, 0)
        caja.pack_start(pie, False, False, 6)
        caja.show_all()
        pedida = os.environ.get("MINT_FECHA_PESTANA")        # solo para las pruebas visuales
        if pedida:
            stack.set_visible_child_name(pedida)
        self._cargando = False
        GLib.timeout_add_seconds(1, self._tic)
        return caja

    # ── el candado: la clave de administrador por polkit (la misma acción de timedated) ─────────
    def _pedir_clave(self):
        if self._desbloqueado:
            return
        if self.PRUEBA:
            self._abrir_candado()
            return
        ok, actual = _timedatectl("show", "-p", "NTP", "--value")
        # Poner el NTP como está hace que polkit pida la clave y la recuerde unos minutos.
        ok, _msg = _timedatectl("set-ntp", "true" if actual == "yes" else "false")
        if ok:
            self._abrir_candado()

    def _abrir_candado(self):
        self._desbloqueado = True
        self._candado.set_image(Gtk.Image.new_from_icon_name("changes-allow-symbolic", Gtk.IconSize.LARGE_TOOLBAR))
        self._nota.set_text("Click the lock to prevent further changes.")
        for w in self._protegidos:
            w.set_sensitive(True)
        self._ajustar_manual()

    # ── Date & Time ──────────────────────────────────────────────────────
    def _pagina_fecha(self):
        pagina = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
        pagina.set_margin_top(18)
        pagina.set_margin_start(24)
        pagina.set_margin_end(24)
        pagina.set_margin_bottom(18)
        self._protegidos = []

        fila = Gtk.Box(spacing=8)
        fila.set_halign(Gtk.Align.CENTER)
        self._auto = Gtk.CheckButton(label="Set date and time automatically:")
        _, ntp = _timedatectl("show", "-p", "NTP", "--value")
        self._auto.set_active(ntp == "yes")
        self._auto.set_sensitive(False)
        self._auto.connect("toggled", lambda b: self._poner_ntp(b.get_active()))
        self._protegidos.append(self._auto)
        fila.pack_start(self._auto, False, False, 0)
        servidor = Gtk.ComboBoxText()
        _, estado = _timedatectl("timesync-status")
        m = re.search(r"Server:\s+(\S+)", estado)
        servidor.append("s", m.group(1) if m else "systemd-timesyncd")
        servidor.set_active(0)
        fila.pack_start(_gris(servidor, "The server is set in /etc/systemd/timesyncd.conf."), False, False, 0)
        pagina.pack_start(fila, False, False, 0)

        cuerpo = Gtk.Box(spacing=40)
        cuerpo.set_halign(Gtk.Align.CENTER)
        self._calendario = Gtk.Calendar()
        izq = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        izq.pack_start(self._calendario, False, False, 0)
        cuerpo.pack_start(izq, False, False, 0)
        der = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        hora = Gtk.Box(spacing=4)
        self._hh = Gtk.SpinButton.new_with_range(1, 12, 1)
        self._mm = Gtk.SpinButton.new_with_range(0, 59, 1)
        self._mm.connect("output", lambda s: s.set_text("%02d" % int(s.get_value())) or True)
        self._pm = Gtk.ComboBoxText()
        self._pm.append("AM", "AM")
        self._pm.append("PM", "PM")
        for w in (self._hh, self._mm, self._pm):
            hora.pack_start(w, False, False, 0)
        der.pack_start(hora, False, False, 0)
        self._reloj = Gtk.DrawingArea()
        self._reloj.set_size_request(130, 130)
        self._reloj.connect("draw", self._pintar_reloj)
        der.pack_start(self._reloj, False, False, 0)
        cuerpo.pack_start(der, False, False, 0)
        pagina.pack_start(cuerpo, False, False, 0)
        self._manual = [self._calendario, self._hh, self._mm, self._pm]
        for w in self._manual:
            w.set_sensitive(False)
        self._poner_hora_actual()
        for w in (self._hh, self._mm):
            w.connect("value-changed", lambda _w: self._fijar_hora())
        self._pm.connect("changed", lambda _w: self._fijar_hora())
        self._calendario.connect("day-selected", lambda _w: self._fijar_hora())

        pie = Gtk.Box(spacing=8)
        pie.set_halign(Gtk.Align.CENTER)
        pie.pack_start(Gtk.Label(label="To set date and time formats, use Language & Region preferences."),
                       False, False, 0)
        b = Gtk.Button(label="Open Language & Region…")
        b.connect("clicked", lambda _b: subprocess.Popen(
            [os.path.expanduser("~/.local/bin/mac-settings"), "Localization"], start_new_session=True))
        pie.pack_start(b, False, False, 0)
        pagina.pack_end(pie, False, False, 0)
        return pagina

    def _poner_hora_actual(self):
        ahora = time.localtime()
        previo, self._cargando = self._cargando, True
        self._calendario.select_month(ahora.tm_mon - 1, ahora.tm_year)
        self._calendario.select_day(ahora.tm_mday)
        self._hh.set_value(ahora.tm_hour % 12 or 12)
        self._mm.set_value(ahora.tm_min)
        self._pm.set_active_id("PM" if ahora.tm_hour >= 12 else "AM")
        self._cargando = previo

    def _tic(self):
        self._reloj.queue_draw()
        return True

    def _ajustar_manual(self):
        """La fecha y la hora a mano solo se pueden tocar con la clave y sin NTP."""
        manual = self._desbloqueado and not self._auto.get_active()
        for w in self._manual:
            w.set_sensitive(manual)

    def _poner_ntp(self, si):
        if self._cargando:
            return
        if not self.PRUEBA:
            ok, _m = _timedatectl("set-ntp", "true" if si else "false")
            if not ok:
                self._cargando = True
                self._auto.set_active(not si)
                self._cargando = False
        self._ajustar_manual()

    def _fijar_hora(self):
        if self._cargando or self.PRUEBA or not self._desbloqueado or self._auto.get_active():
            return
        a, m, d = self._calendario.get_date()
        h = int(self._hh.get_value()) % 12 + (12 if self._pm.get_active_id() == "PM" else 0)
        _timedatectl("set-time", "%04d-%02d-%02d %02d:%02d:00" % (a, m + 1, d, h, int(self._mm.get_value())))

    def _pintar_reloj(self, w, cr):
        ancho = w.get_allocated_width()
        alto = w.get_allocated_height()
        cx, cy, r = ancho / 2, alto / 2, min(ancho, alto) / 2 - 3
        cr.arc(cx, cy, r, 0, 2 * math.pi)
        cr.set_source_rgb(0.95, 0.95, 0.95)
        cr.fill_preserve()
        cr.set_source_rgb(0.5, 0.5, 0.52)
        cr.set_line_width(3)
        cr.stroke()
        cr.set_source_rgb(0.1, 0.1, 0.1)
        cr.select_font_face("sans")
        cr.set_font_size(r * 0.17)
        for n in range(1, 13):
            ang = n * math.pi / 6
            texto = str(n)
            ext = cr.text_extents(texto)
            cr.move_to(cx + math.sin(ang) * r * 0.78 - ext.width / 2 - ext.x_bearing,
                       cy - math.cos(ang) * r * 0.78 - ext.height / 2 - ext.y_bearing)
            cr.show_text(texto)
        t = time.localtime()
        for ang, largo, grosor, color in (
                (((t.tm_hour % 12) + t.tm_min / 60.0) * math.pi / 6, 0.5, 4, (0.1, 0.1, 0.1)),
                ((t.tm_min + t.tm_sec / 60.0) * math.pi / 30, 0.75, 3, (0.1, 0.1, 0.1)),
                (t.tm_sec * math.pi / 30, 0.82, 1.2, (0.85, 0.1, 0.1))):
            cr.set_source_rgb(*color)
            cr.set_line_width(grosor)
            cr.move_to(cx, cy)
            cr.line_to(cx + math.sin(ang) * r * largo, cy - math.cos(ang) * r * largo)
            cr.stroke()
        return False

    # ── Time Zone ────────────────────────────────────────────────────────
    def _pagina_zona(self):
        pagina = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        pagina.set_margin_top(18)
        pagina.set_margin_start(24)
        pagina.set_margin_end(24)
        pagina.set_margin_bottom(18)
        t = Gtk.Label(label="To select a time zone, choose a city from the Closest City menu.")
        pagina.pack_start(t, False, False, 0)
        auto = Gtk.CheckButton(label="Set time zone automatically using current location")
        auto.set_active(True)
        auto.set_halign(Gtk.Align.CENTER)
        pagina.pack_start(_gris(auto, "The time zone cannot be set from your location on this computer."),
                          False, False, 0)
        g = Gtk.Grid(column_spacing=10, row_spacing=10)
        g.set_halign(Gtk.Align.CENTER)
        g.set_margin_top(30)
        _, actual = _timedatectl("show", "-p", "Timezone", "--value")
        g.attach(_etiqueta("Time Zone:"), 0, 0, 1, 1)
        self._abrev = Gtk.Label(xalign=0)
        g.attach(self._abrev, 1, 0, 1, 1)
        g.attach(_etiqueta("Closest City:"), 0, 1, 1, 1)
        self._ciudad = Gtk.ComboBoxText()
        _, zonas = _timedatectl("list-timezones")
        for z in zonas.splitlines():
            self._ciudad.append(z, z.replace("_", " "))
        self._ciudad.set_active_id(actual)
        self._ciudad.set_sensitive(False)
        self._protegidos.append(self._ciudad)
        self._ciudad.connect("changed", lambda c: self._poner_zona(c.get_active_id()))
        g.attach(self._ciudad, 1, 1, 1, 1)
        self._abrev.set_text(time.strftime("%Z"))
        pagina.pack_start(g, False, False, 0)
        return pagina

    def _poner_zona(self, zona):
        if self._cargando or self.PRUEBA or not zona:
            return
        _timedatectl("set-timezone", zona)
        self._abrev.set_text(time.strftime("%Z"))

    # ── Clock ────────────────────────────────────────────────────────────
    def _pagina_reloj(self):
        formato = self._formato_actual()
        pagina = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        pagina.set_margin_top(18)
        pagina.set_margin_start(60)
        pagina.set_margin_bottom(18)
        menu = Gtk.CheckButton(label="Show date and time in menu bar")
        menu.set_active(True)
        pagina.pack_start(_gris(menu, "The clock lives in the Cinnamon panel."), False, False, 0)

        g = Gtk.Grid(column_spacing=10, row_spacing=6)
        g.set_margin_start(20)
        g.attach(_etiqueta("Time options:"), 0, 0, 1, 1)
        tipo = Gtk.Box(spacing=10)
        digital = Gtk.RadioButton.new_with_label_from_widget(None, "Digital")
        analogico = Gtk.RadioButton.new_with_label_from_widget(digital, "Analog")
        tipo.pack_start(digital, False, False, 0)
        tipo.pack_start(_gris(analogico, "The panel clock is digital on this computer."), False, False, 0)
        g.attach(tipo, 1, 0, 1, 1)
        self._opciones = {}
        filas = [("seconds", "Display the time with seconds", "%S" in formato, None),
                 ("flash", "Flash the time separators", False, "Not available on this computer."),
                 ("h24", "Use a 24-hour clock", "%H" in formato or "%k" in formato, None),
                 ("ampm", "Show AM/PM", "%p" in formato or "%P" in formato, None)]
        for i, (clave, texto, activo, gris) in enumerate(filas):
            c = Gtk.CheckButton(label=texto)
            c.set_active(activo)
            if gris:
                _gris(c, gris)
            else:
                c.connect("toggled", lambda _b: self._guardar_formato())
            self._opciones[clave] = c
            g.attach(c, 1, 1 + i, 1, 1)
        g.attach(_etiqueta("Date options:"), 0, 6, 1, 1)
        for i, (clave, texto, activo) in enumerate((("week", "Show the day of the week", "%a" in formato
                                                      or "%A" in formato),
                                                     ("date", "Show date", "%b" in formato or "%d" in formato
                                                      or "%-d" in formato or "%e" in formato))):
            c = Gtk.CheckButton(label=texto)
            c.set_active(activo)
            c.connect("toggled", lambda _b: self._guardar_formato())
            self._opciones[clave] = c
            g.attach(c, 1, 6 + i, 1, 1)
        pagina.pack_start(g, False, False, 0)

        voz = Gtk.Box(spacing=8)
        c = Gtk.CheckButton(label="Announce the time:")
        voz.pack_start(_gris(c, "Not available on this computer."), False, False, 0)
        combo = Gtk.ComboBoxText()
        combo.append("h", "On the hour")
        combo.set_active(0)
        voz.pack_start(_gris(combo), False, False, 0)
        voz.pack_start(_gris(Gtk.Button(label="Customize Voice…")), False, False, 0)
        pagina.pack_start(voz, False, False, 24)
        self._sincronizar_reloj()
        return pagina

    def _sincronizar_reloj(self):
        """AM/PM solo tiene sentido con el reloj de 12 horas."""
        self._opciones["ampm"].set_sensitive(not self._opciones["h24"].get_active())

    @staticmethod
    def _formato_actual():
        for ruta in _archivos_reloj():
            try:
                d = json.load(open(ruta, encoding="utf-8"))
                if d.get("use-custom-format", {}).get("value"):
                    return d.get("custom-format", {}).get("value", "")
            except (OSError, ValueError):
                continue
        return "%a %b %-d %-I:%M %p"

    def _armar_formato(self):
        o = self._opciones
        partes = []
        if o["week"].get_active():
            partes.append("%a")
        if o["date"].get_active():
            partes.append("%b %-d")
        if o["h24"].get_active():
            hora = "%H:%M" + (":%S" if o["seconds"].get_active() else "")
        else:
            hora = "%-I:%M" + (":%S" if o["seconds"].get_active() else "") + (" %p" if o["ampm"].get_active() else "")
        partes.append(hora)
        return " ".join(partes)

    def _guardar_formato(self):
        self._sincronizar_reloj()
        if self._cargando or self.PRUEBA:
            return
        nuevo = self._armar_formato()
        for ruta in _archivos_reloj():
            try:
                d = json.load(open(ruta, encoding="utf-8"))
                d["custom-format"]["value"] = nuevo
                d["use-custom-format"]["value"] = True
                with open(ruta + ".tmp", "w", encoding="utf-8") as f:
                    json.dump(d, f, indent=4)
                os.replace(ruta + ".tmp", ruta)
            except (OSError, ValueError, KeyError):
                continue
