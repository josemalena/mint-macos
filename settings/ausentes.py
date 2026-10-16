"""Siri, Profiles y CDs & DVDs: los paneles de Catalina que Linux no tiene.

Se dibujan como en las capturas (Screen Shot 2026-10-14 at 12.13.06 AM Siri y 1.25.57 PM … 1.26.31 PM
Screen Time) pero en gris, como en una Mac que no tuviera esa función: nada se inventa ni se deja
funcionando de adorno. Screen Time no enseña datos (no hay uso que contar); solo el esqueleto.
La hoja Siri Suggestions & Privacy… y las otras pantallas de Screen Time (Pickups, Downtime, App Limits,
Communication, Always Allowed y Content & Privacy) no se dibujan: no hay nada que configurar.
Profiles (08-pref-com.apple.preferences.configurationprofiles) y CDs & DVDs (…digihub.discs): sin perfiles de
aprovisionamiento ni unidad óptica; se dibujan igual, vacíos y en gris.
"""
import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk  # noqa: E402

import paneles  # noqa: E402

MOTIVO = "This feature is not available on this computer."


def _gris(widget):
    widget.set_sensitive(False)
    widget.set_tooltip_text(MOTIVO)
    return widget


def _marco():
    m = Gtk.Frame()
    m.get_style_context().add_class("mp-sd-lista")
    return m


class _Ausente:
    claves = []
    externo = False
    propio = True
    celda = None

    def __init__(self):
        self.panel = paneles.Panel(self.id, self.nombre, [], palabras=self.palabras)
        self.ventana = None

    def coincide(self, texto):
        t = texto.lower().strip()
        return bool(t) and any(t in c.lower() for c in (self.nombre, self.panel.palabras, self.id))


class PanelSiri(_Ausente):
    id = "com.apple.preference.speech"
    nombre = "Siri"
    palabras = "siri, voice, ask siri, hey siri, dictation"

    def construir(self):
        from propios import imagen_icono_panel
        caja = Gtk.Box(spacing=0)
        caja.get_style_context().add_class("mp-propio")
        caja.set_margin_top(18)
        caja.set_margin_bottom(18)
        izq = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        izq.set_size_request(240, -1)
        izq.pack_start(imagen_icono_panel(self.id, 112), False, False, 10)
        t = Gtk.Label(label="Siri")
        t.get_style_context().add_class("mp-titulo-negrita")
        izq.pack_start(t, False, False, 0)
        c = Gtk.CheckButton(label="Enable Ask Siri")
        c.set_active(True)
        c.set_halign(Gtk.Align.CENTER)
        izq.pack_start(_gris(c), False, False, 0)
        caja.pack_start(izq, False, False, 0)
        caja.pack_start(Gtk.Separator(orientation=Gtk.Orientation.VERTICAL), False, False, 0)

        der = Gtk.Grid(column_spacing=10, row_spacing=10, margin=20)
        d = Gtk.Label(label="Siri helps you get things done, just by asking. Find files on your Mac, dictate a "
                            "note, check the weather, and more.", xalign=0)
        d.set_line_wrap(True)
        d.set_max_width_chars(52)
        der.attach(d, 0, 0, 2, 1)
        hey = Gtk.CheckButton(label="Listen for “Hey Siri” on headphones")
        der.attach(_gris(hey), 1, 1, 1, 1)
        filas = (("Keyboard Shortcut:", "Hold Command Space"), ("Language:", "English (United States)"),
                 ("Siri Voice:", "American (Female)"))
        for i, (t_, v) in enumerate(filas):
            e = Gtk.Label(label=t_, xalign=1.0)
            e.get_style_context().add_class("mp-fila-etiqueta")
            der.attach(e, 0, 2 + i, 1, 1)
            cb = Gtk.ComboBoxText()
            cb.append("v", v)
            cb.set_active(0)
            der.attach(_gris(cb), 1, 2 + i, 1, 1)
        e = Gtk.Label(label="Voice Feedback:", xalign=1.0)
        e.get_style_context().add_class("mp-fila-etiqueta")
        der.attach(e, 0, 5, 1, 1)
        vf = Gtk.Box(spacing=12)
        on = Gtk.RadioButton.new_with_label_from_widget(None, "On")
        off = Gtk.RadioButton.new_with_label_from_widget(on, "Off")
        vf.pack_start(on, False, False, 0)
        vf.pack_start(off, False, False, 0)
        der.attach(_gris(vf), 1, 5, 1, 1)
        e = Gtk.Label(label="Siri History:", xalign=1.0)
        e.get_style_context().add_class("mp-fila-etiqueta")
        der.attach(e, 0, 6, 1, 1)
        der.attach(_gris(Gtk.Button(label="Delete Siri & Dictation History")), 1, 6, 1, 1)
        menu = Gtk.CheckButton(label="Show Siri in menu bar")
        menu.set_active(True)
        der.attach(_gris(menu), 0, 7, 2, 1)
        der.attach(_gris(Gtk.Button(label="Siri Suggestions & Privacy…")), 1, 7, 1, 1)
        caja.pack_start(der, True, True, 0)
        caja.show_all()
        return caja


def _ayuda():
    """El «?» redondo de abajo a la derecha de los paneles de Catalina (aquí no hay Help Viewer: en gris)."""
    b = Gtk.Button(label="?")
    b.get_style_context().add_class("circular")
    b.set_size_request(24, 24)
    return _gris(b)


class PanelProfiles(_Ausente):
    id = "com.apple.preferences.configurationprofiles"
    nombre = "Profiles"
    palabras = "profiles, configuration profiles, provisioning profiles, mdm"

    def construir(self):
        caja = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        caja.get_style_context().add_class("mp-propio")
        for lado in ("top", "bottom", "start", "end"):
            getattr(caja, "set_margin_" + lado)(14)
        cuerpo = Gtk.Box(spacing=8)
        izq = _marco()
        izq.set_size_request(190, 300)
        lista = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        cab = Gtk.Label(label="Provisioning Profiles", xalign=0, margin=8)
        cab.get_style_context().add_class("mp-sd-detalle")
        lista.pack_start(cab, False, False, 0)
        izq.add(lista)
        der = _marco()
        cuerpo.pack_start(izq, False, False, 0)
        cuerpo.pack_start(der, True, True, 0)
        caja.pack_start(cuerpo, True, True, 0)
        pie = Gtk.Box()
        botones = Gtk.Box()
        botones.get_style_context().add_class("linked")
        for t in ("+", "\u2212"):
            botones.pack_start(_gris(Gtk.Button(label=t)), False, False, 0)
        pie.pack_start(botones, False, False, 0)
        pie.pack_end(_ayuda(), False, False, 0)
        caja.pack_start(pie, False, False, 0)
        caja.show_all()
        return caja


class PanelDiscs(_Ausente):
    id = "com.apple.preference.digihub.discs"
    nombre = "CDs & DVDs"
    palabras = "cd, dvd, disc, insert, blank, music cd, picture cd, video dvd, eject"

    def construir(self):
        caja = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        caja.get_style_context().add_class("mp-propio")
        for lado in ("top", "bottom", "start", "end"):
            getattr(caja, "set_margin_" + lado)(20)
        rejilla = Gtk.Grid(column_spacing=10, row_spacing=10)
        rejilla.set_halign(Gtk.Align.CENTER)
        filas = (("When you insert a blank CD:", "Ask what to do"), ("When you insert a blank DVD:", "Ask what to do"),
                 None,
                 ("When you insert a music CD:", "Ignore"), ("When you insert a picture CD:", "Ignore"),
                 ("When you insert a video DVD:", "Ignore"))
        for i, fila in enumerate(filas):
            if fila is None:
                rejilla.attach(Gtk.Box(), 0, i, 2, 1)
                rejilla.get_child_at(0, i).set_size_request(-1, 16)
                continue
            e = Gtk.Label(label=fila[0], xalign=1.0)
            e.get_style_context().add_class("mp-fila-etiqueta")
            rejilla.attach(e, 0, i, 1, 1)
            c = Gtk.ComboBoxText()
            c.append("v", fila[1])
            c.set_active(0)
            c.set_size_request(236, -1)
            rejilla.attach(_gris(c), 1, i, 1, 1)
        eject = Gtk.CheckButton(label="Show eject in menu bar")
        rejilla.attach(_gris(eject), 1, len(filas), 1, 1)
        caja.pack_start(rejilla, False, False, 0)
        pie = Gtk.Box()
        pie.pack_end(_ayuda(), False, False, 0)
        caja.pack_start(pie, False, False, 0)
        caja.show_all()
        return caja
