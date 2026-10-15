"""General: el panel de Catalina (Screen Shot 2026-10-14 at 12.11.59 AM).

Conectado de verdad: Default web browser (xdg-settings) y Show scroll bars (gtk-overlay-scrollbars).
Appearance solo tiene el tema oscuro de Constanza, que es el que está activo: Light y Auto se dibujan
en gris hasta que exista un tema claro. El resto (Accent y Highlight color, Sidebar icon size, ocultar
la barra de menús, Click in the scroll bar to, las casillas de documentos, Recent items, Handoff y
font smoothing) no tiene una clave que podamos escribir y comprobar aquí: se dibuja como en la
captura, en gris, como en una Mac sin esa función.

Las miniaturas de Light/Dark/Auto son arte de Apple y salen del disco de la Mac, no del repo
(`~/.local/share/mint-macos/settings/apariencia/`); sin ellas se ven los nombres solos.
"""
import os
import subprocess

import gi
gi.require_version("Gtk", "3.0")
gi.require_version("GdkPixbuf", "2.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, Gio, GdkPixbuf, GLib, Gtk  # noqa: E402

import paneles  # noqa: E402

# Los siete colores de acento y el grafito, tomados de la captura de Catalina.
ACENTOS = ["#006fff", "#9b469d", "#f64694", "#ff484d", "#f6771a", "#fcaf23", "#57b13d", "#818181"]
MINIATURAS = os.path.expanduser("~/.local/share/mint-macos/settings/apariencia")


def _etiqueta(texto):
    l = Gtk.Label(label=texto, xalign=1.0)
    l.get_style_context().add_class("mp-fila-etiqueta")
    return l


def _gris(widget, motivo=None):
    widget.set_sensitive(False)
    if motivo:
        widget.set_tooltip_text(motivo)
    return widget


def _linea():
    s = Gtk.Separator()
    s.set_margin_top(8)
    s.set_margin_bottom(8)
    return s


class PanelGeneral:
    id = "com.apple.preference.general"
    nombre = "General"
    claves = []
    externo = False
    propio = True
    celda = None
    PRUEBA = bool(os.environ.get("MINT_GENERAL_PRUEBA"))     # no escribe en gsettings ni en xdg-settings

    def __init__(self):
        self.panel = paneles.Panel(self.id, self.nombre, [],
                                   palabras="appearance, dark, light, accent color, highlight, scroll bars, "
                                            "default web browser, recent items, handoff, font smoothing")
        self.ventana = None
        self._cargando = False

    def coincide(self, texto):
        t = texto.lower().strip()
        return bool(t) and any(t in c.lower() for c in (self.nombre, self.panel.palabras, self.id))

    def construir(self):
        self._cargando = True
        caja = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        caja.get_style_context().add_class("mp-propio")
        for lado in ("top", "bottom"):
            getattr(caja, "set_margin_" + lado)(18)
        g = Gtk.Grid(column_spacing=12, row_spacing=10)
        g.set_halign(Gtk.Align.CENTER)
        fila = 0

        # Appearance: Light / Dark / Auto
        g.attach(_etiqueta("Appearance:"), 0, fila, 1, 1)
        opciones = Gtk.Box(spacing=14)
        self._areas, self._radios = {}, {}
        grupo = None
        for clave, texto in (("light", "Light"), ("dark", "Dark"), ("auto", "Auto")):
            c = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
            ruta = os.path.join(MINIATURAS, clave + ".png")
            miniatura = None
            if os.path.exists(ruta):
                try:
                    miniatura = GdkPixbuf.Pixbuf.new_from_file_at_scale(ruta, 68, 45, True)
                except GLib.Error:
                    miniatura = None
            area = Gtk.DrawingArea()
            area.set_size_request(72, 49)
            area.set_halign(Gtk.Align.CENTER)
            self._areas[clave] = (area, miniatura)
            area.connect("draw", self._pintar_miniatura, clave)
            c.pack_start(area, False, False, 0)
            r = Gtk.RadioButton.new_with_label_from_widget(grupo, texto)
            grupo = grupo or r
            r.set_active(clave == "dark")
            self._radios[clave] = r
            r.connect("toggled", lambda _r: [a.queue_draw() for a, _p in self._areas.values()])
            if clave != "dark":
                _gris(r, "Only the dark theme is installed on this computer.")
            c.pack_start(r, False, False, 0)
            opciones.pack_start(c, False, False, 0)
        g.attach(opciones, 1, fila, 2, 1)
        fila += 1

        # Accent color y Highlight color
        g.attach(_etiqueta("Accent color:"), 0, fila, 1, 1)
        puntos = Gtk.Box(spacing=8)
        grupo = None
        for i, color in enumerate(ACENTOS):
            r = Gtk.RadioButton.new_from_widget(grupo)
            grupo = grupo or r
            r.set_active(i == 0)
            r.set_name("mp-acento-%d" % i)
            puntos.pack_start(r, False, False, 0)
        g.attach(_gris(puntos, "The accent color is part of the theme on this computer."), 1, fila, 2, 1)
        fila += 1
        g.attach(_etiqueta("Highlight color:"), 0, fila, 1, 1)
        c = Gtk.ComboBoxText()
        c.append("blue", "Blue")
        c.set_active(0)
        g.attach(_gris(c), 1, fila, 2, 1)
        fila += 1
        g.attach(_etiqueta("Sidebar icon size:"), 0, fila, 1, 1)
        c = Gtk.ComboBoxText()
        c.append("m", "Medium")
        c.set_active(0)
        g.attach(_gris(c), 1, fila, 2, 1)
        fila += 1
        ocultar = Gtk.CheckButton(label="Automatically hide and show the menu bar")
        g.attach(_gris(ocultar), 1, fila, 2, 1)
        fila += 1

        g.attach(_linea(), 0, fila, 3, 1)
        fila += 1

        # Show scroll bars (la tercera opción, «Always», es la barra clásica de GTK)
        self._cfg = Gio.Settings.new("org.cinnamon.desktop.interface")
        overlay = self._cfg.get_boolean("gtk-overlay-scrollbars")
        g.attach(_etiqueta("Show scroll bars:"), 0, fila, 1, 1)
        barras = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        auto = Gtk.RadioButton.new_with_label_from_widget(None, "Automatically based on mouse or trackpad")
        scroll = Gtk.RadioButton.new_with_label_from_widget(auto, "When scrolling")
        siempre = Gtk.RadioButton.new_with_label_from_widget(auto, "Always")
        _gris(auto, "GTK cannot tell a mouse from a trackpad here.")
        (scroll if overlay else siempre).set_active(True)
        scroll.connect("toggled", lambda r: self._poner_overlay(r.get_active()))
        for r in (auto, scroll, siempre):
            barras.pack_start(r, False, False, 0)
        g.attach(barras, 1, fila, 2, 1)
        fila += 1
        g.attach(_etiqueta("Click in the scroll bar to:"), 0, fila, 1, 1)
        clic = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        r1 = Gtk.RadioButton.new_with_label_from_widget(None, "Jump to the next page")
        r2 = Gtk.RadioButton.new_with_label_from_widget(r1, "Jump to the spot that’s clicked")
        clic.pack_start(r1, False, False, 0)
        clic.pack_start(r2, False, False, 0)
        g.attach(_gris(clic, "This is decided by each app on this computer."), 1, fila, 2, 1)
        fila += 1

        g.attach(_linea(), 0, fila, 3, 1)
        fila += 1

        # Default web browser
        g.attach(_etiqueta("Default web browser:"), 0, fila, 1, 1)
        self._navegador = Gtk.ComboBoxText()
        actual = self._navegador_actual()
        encontrado = False
        for app in self._navegadores():
            self._navegador.append(app.get_id(), app.get_display_name())
            if app.get_id() == actual:
                self._navegador.set_active_id(actual)
                encontrado = True
        if not encontrado and actual:
            info = Gio.DesktopAppInfo.new(actual)
            self._navegador.append(actual, info.get_display_name() if info else actual)
            self._navegador.set_active_id(actual)
        self._navegador.connect("changed", lambda c: self._poner_navegador(c.get_active_id()))
        self._navegador.set_halign(Gtk.Align.START)
        g.attach(self._navegador, 1, fila, 2, 1)
        fila += 1

        g.attach(_linea(), 0, fila, 3, 1)
        fila += 1

        # Lo de los documentos, Recent items, Handoff y font smoothing: sin equivalente aquí, en gris.
        for texto, activo in (("Ask to keep changes when closing documents", False),
                              ("Close windows when quitting an app", True)):
            c = Gtk.CheckButton(label=texto)
            c.set_active(activo)
            g.attach(_gris(c, "Each app decides this on this computer."), 1, fila, 2, 1)
            fila += 1
        g.attach(_etiqueta("Recent items:"), 0, fila, 1, 1)
        rec = Gtk.Box(spacing=8)
        spin = Gtk.SpinButton.new_with_range(0, 50, 5)
        spin.set_value(10)
        rec.pack_start(spin, False, False, 0)
        rec.pack_start(Gtk.Label(label="Documents, Apps, and Servers"), False, False, 0)
        g.attach(_gris(rec, "The number of recent items is not adjustable on this computer."), 1, fila, 2, 1)
        fila += 1
        for texto, activo in (("Allow Handoff between this Mac and your iCloud devices", True),
                              ("Use font smoothing when available", True)):
            c = Gtk.CheckButton(label=texto)
            c.set_active(activo)
            g.attach(_gris(c), 1, fila, 2, 1)
            fila += 1

        caja.pack_start(g, False, False, 0)
        caja.show_all()
        self._cargando = False
        return caja

    def _pintar_miniatura(self, area, cr, clave):
        """La miniatura de Appearance con las esquinas redondeadas y, si es la escogida, el aro azul."""
        _a, pb = self._areas[clave]
        ancho, alto = area.get_allocated_width(), area.get_allocated_height()
        radio = 6
        cr.new_sub_path()
        cr.arc(ancho - radio - 2, radio + 2, radio, -1.5708, 0)
        cr.arc(ancho - radio - 2, alto - radio - 2, radio, 0, 1.5708)
        cr.arc(radio + 2, alto - radio - 2, radio, 1.5708, 3.1416)
        cr.arc(radio + 2, radio + 2, radio, 3.1416, 4.7124)
        cr.close_path()
        if pb is not None:
            cr.save()
            cr.clip_preserve()
            Gdk.cairo_set_source_pixbuf(cr, pb, (ancho - pb.get_width()) / 2, (alto - pb.get_height()) / 2)
            cr.paint()
            cr.restore()
        if self._radios.get(clave) is not None and self._radios[clave].get_active():
            cr.set_source_rgb(0.0, 0.48, 1.0)
            cr.set_line_width(2)
            cr.stroke()
        else:
            cr.new_path()
        return False

    # ── scroll bars ──────────────────────────────────────────────────────
    def _poner_overlay(self, si):
        if self._cargando or self.PRUEBA:
            return
        self._cfg.set_boolean("gtk-overlay-scrollbars", si)

    # ── Default web browser ──────────────────────────────────────────────
    @staticmethod
    def _navegadores():
        vistos, lista = set(), []
        for app in Gio.AppInfo.get_all_for_type("x-scheme-handler/https"):
            if app.get_id() not in vistos and app.should_show():
                vistos.add(app.get_id())
                lista.append(app)
        return sorted(lista, key=lambda a: a.get_display_name().lower())

    @staticmethod
    def _navegador_actual():
        try:
            return subprocess.run(["xdg-settings", "get", "default-web-browser"], capture_output=True,
                                  text=True, timeout=10).stdout.strip()
        except (OSError, subprocess.SubprocessError):
            return ""

    def _poner_navegador(self, ident):
        if self._cargando or self.PRUEBA or not ident:
            return
        try:
            subprocess.run(["xdg-settings", "set", "default-web-browser", ident], timeout=10, check=False)
        except (OSError, subprocess.SubprocessError):
            pass
