"""Notifications: el panel de Catalina (Screen Shot 2026-10-14 at 12.14.19 AM con Do Not Disturb y
12.14.33 AM con una app escogida).

Cinnamon no filtra las notificaciones por app ni tiene horario de No Molestar: todo lo de esta pantalla
se dibuja como en la captura, en gris, como en una Mac sin esa función. La lista de la izquierda son las
apps instaladas. Lo que Cinnamon sí sabe (duración, posición, pantalla) no está en Catalina y queda en
«Advanced».
"""
import os

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gio, Gtk  # noqa: E402

import paneles  # noqa: E402

TEXTO = ("Notification Center shows your alerts in the upper-right of your screen, without interrupting "
         "what you’re doing. Show and hide Notification Center by clicking its icon in the menu bar.")
MOTIVO = "Notifications cannot be set per app on this computer."


def _gris(widget, motivo=MOTIVO):
    widget.set_sensitive(False)
    widget.set_tooltip_text(motivo)
    return widget


def _marco():
    m = Gtk.Frame()
    m.get_style_context().add_class("mp-sd-lista")
    return m


class PanelNotifications:
    id = "com.apple.preference.notifications"
    nombre = "Notifications"
    claves = []
    externo = False
    propio = True
    celda = None

    def __init__(self):
        self.panel = paneles.Panel(self.id, self.nombre, [],
                                   palabras="notifications, alerts, banners, do not disturb, badges, "
                                            "notification center")
        self.ventana = None

    def coincide(self, texto):
        t = texto.lower().strip()
        return bool(t) and any(t in c.lower() for c in (self.nombre, self.panel.palabras, self.id))

    def construir(self):
        caja = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        caja.get_style_context().add_class("mp-propio")
        for lado in ("top", "bottom", "start", "end"):
            getattr(caja, "set_margin_" + lado)(16)
        t = Gtk.Label(label=TEXTO, xalign=0)
        t.set_line_wrap(True)
        t.set_max_width_chars(80)
        caja.pack_start(t, False, False, 0)

        cuerpo = Gtk.Box(spacing=12)
        lista = Gtk.ListBox()
        lista.set_size_request(215, 330)
        derecha = Gtk.Stack()
        derecha.add_named(self._pagina_no_molestar(), "dnd")
        derecha.add_named(self._pagina_app(), "app")
        filas = [("Do Not Disturb", "dnd", "")]
        apps = sorted((a for a in Gio.AppInfo.get_all() if a.should_show()
                       and "Settings" not in (getattr(a, "get_categories", lambda: "")() or "")),
                      key=lambda a: a.get_display_name().lower())
        filas += [(a.get_display_name(), "app", "Badges, Sounds, Banners") for a in apps[:60]]
        for nombre, pagina, sub in filas:
            fila = Gtk.ListBoxRow()
            c = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, margin=5)
            c.pack_start(Gtk.Label(label=nombre, xalign=0), False, False, 0)
            if sub:
                s = Gtk.Label(label=sub, xalign=0)
                s.get_style_context().add_class("mp-sd-detalle")
                c.pack_start(s, False, False, 0)
            fila.add(c)
            fila.pagina, fila.nombre = pagina, nombre
            lista.add(fila)

        def elegida(_l, f):
            if f is not None:
                derecha.set_visible_child_name(f.pagina)
                self._titulo.set_text("Allow Notifications from %s" % f.nombre)
                self._estilo.set_text("%s alert style:" % f.nombre)
        lista.connect("row-selected", elegida)
        pant = Gtk.ScrolledWindow()
        pant.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        pant.set_min_content_width(215)
        pant.add(lista)
        m1, m2 = _marco(), _marco()
        m1.add(pant)
        m2.add(derecha)
        cuerpo.pack_start(m1, False, False, 0)
        cuerpo.pack_start(m2, True, True, 0)
        caja.pack_start(cuerpo, True, True, 0)

        pie = Gtk.Box(spacing=8)
        pie.pack_start(Gtk.Label(label="Notification Center sort order:"), False, False, 0)
        orden = Gtk.ComboBoxText()
        orden.append("r", "Recents")
        orden.set_active(0)
        pie.pack_start(_gris(orden), False, False, 0)
        caja.pack_start(pie, False, False, 0)
        caja.show_all()
        derecha.show_all()
        lista.select_row(lista.get_row_at_index(0))
        derecha.set_visible_child_name("dnd")
        return caja

    def _pagina_no_molestar(self):
        p = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8, margin=16)
        t = Gtk.Label(label="Turn on Do Not Disturb in Notification Center", xalign=0)
        t.get_style_context().add_class("mp-titulo-negrita")
        p.pack_start(t, False, False, 0)
        d = Gtk.Label(label="Banners and alerts will be hidden and notification sounds will be silenced.",
                      xalign=0)
        d.set_line_wrap(True)
        d.set_max_width_chars(48)
        d.get_style_context().add_class("mp-sd-detalle")
        p.pack_start(d, False, False, 0)
        p.pack_start(Gtk.Label(label="Turn on Do Not Disturb:", xalign=0), False, False, 8)
        desde = Gtk.Box(spacing=8)
        c = Gtk.CheckButton(label="From:")
        desde.pack_start(_gris(c), False, False, 0)
        for hora in ("10:00 PM", "7:00 AM"):
            e = Gtk.Entry(text=hora, width_chars=9)
            desde.pack_start(_gris(e), False, False, 0)
            if hora.startswith("10"):
                desde.pack_start(Gtk.Label(label="to:"), False, False, 0)
        p.pack_start(desde, False, False, 0)
        for texto, activo in (("When the display is sleeping", True), ("When the screen is locked", True),
                              ("When mirroring to TVs and projectors", True)):
            c = Gtk.CheckButton(label=texto)
            c.set_active(activo)
            p.pack_start(_gris(c), False, False, 0)
        p.pack_start(Gtk.Label(label="When Do Not Disturb is turned on:", xalign=0), False, False, 8)
        for texto in ("Allow calls from everyone", "Allow repeated calls"):
            p.pack_start(_gris(Gtk.CheckButton(label=texto)), False, False, 0)
        return p

    def _pagina_app(self):
        p = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10, margin=16)
        sw = Gtk.Switch()
        sw.set_active(True)
        fila = Gtk.Box(spacing=10)
        fila.pack_start(_gris(sw), False, False, 0)
        self._titulo = Gtk.Label(label="Allow Notifications", xalign=0)
        self._titulo.get_style_context().add_class("mp-titulo-negrita")
        fila.pack_start(self._titulo, False, False, 0)
        p.pack_start(fila, False, False, 0)
        self._estilo = Gtk.Label(label="Alert style:", xalign=0)
        p.pack_start(self._estilo, False, False, 0)
        estilos = Gtk.Box(spacing=14)
        grupo = None
        for clave, nombre in (("none", "None"), ("banners", "Banners"), ("alerts", "Alerts")):
            r = Gtk.RadioButton.new_with_label_from_widget(grupo, nombre)
            grupo = grupo or r
            r.set_active(clave == "banners")
            estilos.pack_start(r, False, False, 0)
        p.pack_start(_gris(estilos), False, False, 0)
        nota = Gtk.Label(label="Banners appear in the upper-right corner and go away automatically. "
                               "Alerts stay on screen until dismissed.", xalign=0)
        nota.set_line_wrap(True)
        nota.set_max_width_chars(48)
        nota.get_style_context().add_class("mp-sd-detalle")
        p.pack_start(nota, False, False, 0)
        for texto in ("Show notifications on lock screen", "Show notification preview", "Show in Notification Center",
                      "Badge app icon", "Play sound for notifications"):
            c = Gtk.CheckButton(label=texto)
            c.set_active(True)
            p.pack_start(_gris(c), False, False, 0)
        return p
