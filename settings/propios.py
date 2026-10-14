"""Paneles de System Preferences que escriben directo en la configuración del
programa, en vez de traer la interfaz de ese programa.

Cada uno es una clase con `id`, `nombre`, `panel` (para el buscador y el ícono) y
`construir()`, que devuelve el widget de la página. El diseño es el de la captura
de Catalina (Screen Shot 2026-10-14 at 12.12.52 AM, panel Dock).

Solo van los controles que de verdad hacen algo aquí. Los de Catalina que Linux o
nuestro Plank no tienen (Prefer tabs when opening documents) no se dibujan: un
control que no hace nada engaña.
"""
import os
import re

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gio, GLib, Gtk  # noqa: E402

import paneles  # noqa: E402

MAGIC_LAMP = "CinnamonMagicLamp@klangman"


def _plank():
    """El dock1 de Plank (nuestro fork): dconf, ruta relocatable."""
    return Gio.Settings.new_with_path("net.launchpad.plank.dock.settings", "/net/launchpad/plank/docks/dock1/")


# El tema de Plank se edita en su archivo: Plank lo vigila y recarga solo. Lo que
# había se guarda al apagar un control, para devolverlo igual al encenderlo.
_TEMA_DEFECTO = {"IndicatorSize": "0.75", "LaunchBounceHeight": "0.625"}
_RESPALDO = os.path.expanduser("~/.local/share/mint-macos/settings/dock-tema-original.json")


def _archivo_tema(plank):
    nombre = plank.get_string("theme")
    for base in (os.path.expanduser("~/.local/share/plank/themes"), "/usr/local/share/plank/themes",
                 "/usr/share/plank/themes"):
        ruta = os.path.join(base, nombre, "dock.theme")
        if os.path.exists(ruta):
            return ruta
    return None


def _leer_tema(ruta, clave):
    m = re.search(r"^%s=(.*)$" % re.escape(clave), open(ruta, encoding="utf-8").read(), re.M)
    return m.group(1).strip() if m else None


def _poner_tema(ruta, clave, valor):
    texto = open(ruta, encoding="utf-8").read()
    if re.search(r"^%s=" % re.escape(clave), texto, re.M):
        texto = re.sub(r"^%s=.*$" % re.escape(clave), "%s=%s" % (clave, valor), texto, flags=re.M)
    else:
        texto += "\n%s=%s\n" % (clave, valor)
    with open(ruta, "w", encoding="utf-8") as f:
        f.write(texto)


def _encender_tema(plank, clave, encendido):
    """Encendido: el valor de antes (o el de la casa). Apagado: 0, guardando el de antes."""
    ruta = _archivo_tema(plank)
    if ruta is None:
        return
    import json
    try:
        guardado = json.load(open(_RESPALDO, encoding="utf-8"))
    except (OSError, ValueError):
        guardado = {}
    actual = _leer_tema(ruta, clave)
    if encendido:
        _poner_tema(ruta, clave, guardado.get(clave) or _TEMA_DEFECTO[clave])
    else:
        if actual not in (None, "0", "0.0"):
            guardado[clave] = actual
            os.makedirs(os.path.dirname(_RESPALDO), exist_ok=True)
            json.dump(guardado, open(_RESPALDO, "w", encoding="utf-8"))
        _poner_tema(ruta, clave, "0")


def _tema_encendido(plank, clave):
    ruta = _archivo_tema(plank)
    if ruta is None:
        return True
    v = _leer_tema(ruta, clave)
    try:
        return v is not None and float(v) > 0
    except ValueError:
        return True


def _etiqueta(texto):
    l = Gtk.Label(label=texto, xalign=1.0)
    l.get_style_context().add_class("mp-fila-etiqueta")
    return l


def _escala(minimo, maximo, valor, pie_izq, pie_der, al_cambiar):
    """Un slider como el de Catalina: sin número, con marcas «Small … Large» debajo."""
    esc = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, minimo, maximo, 1)
    esc.set_draw_value(False)
    esc.set_value(valor)
    esc.set_size_request(200, -1)
    esc.add_mark(minimo, Gtk.PositionType.BOTTOM, pie_izq)
    esc.add_mark(maximo, Gtk.PositionType.BOTTOM, pie_der)
    esc.connect("value-changed", lambda s: al_cambiar(int(s.get_value())))
    return esc


class PanelDock:
    """Dock: Plank por dconf, el efecto genio por la extensión Magic Lamp y el
    doble clic de la barra de título por el gsettings del gestor de ventanas."""
    id = "com.apple.preference.dock"
    nombre = "Dock"
    claves = []
    externo = False
    propio = True
    celda = None

    def __init__(self):
        self.panel = paneles.Panel(self.id, self.nombre, [],
                                   palabras="dock, size, magnification, position, minimize, genie, hide, zoom, title bar")
        self.plank = None

    def coincide(self, texto):
        t = texto.lower().strip()
        return bool(t) and any(t in c.lower() for c in (self.nombre, self.panel.palabras, self.id))

    # ── la página ────────────────────────────────────────────────────────
    def construir(self):
        try:
            self.plank = _plank()
        except Exception:  # noqa: BLE001 — sin el esquema de Plank
            l = Gtk.Label(label="Plank is not installed.")
            l.show()
            return l
        p = self.plank
        cuadro = Gtk.Grid(column_spacing=14, row_spacing=14)
        cuadro.get_style_context().add_class("mp-propio")
        cuadro.set_halign(Gtk.Align.CENTER)
        cuadro.set_margin_top(22)
        cuadro.set_margin_bottom(22)
        cuadro.set_margin_start(30)
        cuadro.set_margin_end(30)
        fila = 0

        # Size
        cuadro.attach(_etiqueta("Size:"), 0, fila, 1, 1)
        cuadro.attach(_escala(16, 128, p.get_int("icon-size"), "Small", "Large",
                              lambda v: p.set_int("icon-size", v)), 1, fila, 2, 1)
        fila += 1

        # Magnification
        mag = Gtk.CheckButton(label="Magnification:")
        mag.set_active(p.get_boolean("zoom-enabled"))
        cuadro.attach(mag, 0, fila, 1, 1)
        zoom = _escala(100, 300, min(300, max(100, p.get_int("zoom-percent"))), "Min", "Max",
                       lambda v: p.set_int("zoom-percent", v))
        zoom.set_sensitive(mag.get_active())
        cuadro.attach(zoom, 1, fila, 2, 1)

        def al_magnificar(b):
            p.set_boolean("zoom-enabled", b.get_active())
            zoom.set_sensitive(b.get_active())
        mag.connect("toggled", al_magnificar)
        fila += 1

        # Position on screen
        cuadro.attach(_etiqueta("Position on screen:"), 0, fila, 1, 1)
        pos = Gtk.Box(spacing=18)
        grupo = None
        for clave, texto in (("left", "Left"), ("bottom", "Bottom"), ("right", "Right")):
            caja = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
            r = Gtk.RadioButton.new_from_widget(grupo)
            grupo = grupo or r
            r.set_active(p.get_string("position") == clave)
            r.connect("toggled", lambda b, c=clave: b.get_active() and p.set_string("position", c))
            caja.pack_start(r, False, False, 0)
            caja.pack_start(Gtk.Label(label=texto), False, False, 0)
            pos.pack_start(caja, False, False, 0)
        cuadro.attach(pos, 1, fila, 2, 1)
        fila += 1

        # Minimize windows using
        cuadro.attach(_etiqueta("Minimize windows using:"), 0, fila, 1, 1)
        efecto = Gtk.ComboBoxText()
        efecto.append("genie", "Genie effect")
        efecto.append("scale", "Scale effect")
        efecto.set_active_id("genie" if self._genio_activo() else "scale")
        efecto.connect("changed", lambda c: self._poner_genio(c.get_active_id() == "genie"))
        efecto.set_halign(Gtk.Align.START)
        cuadro.attach(efecto, 1, fila, 2, 1)
        fila += 1

        # Minimize windows into application icon (el Plank de mint-macos; con un Plank
        # sin esa clave el control no sale: no hay nada que escribir).
        if p.props.settings_schema.has_key("minimize-into-icon"):
            en_icono = Gtk.CheckButton(label="Minimize windows into application icon")
            en_icono.set_active(p.get_boolean("minimize-into-icon"))
            en_icono.connect("toggled", lambda b: p.set_boolean("minimize-into-icon", b.get_active()))
            cuadro.attach(en_icono, 0, fila, 3, 1)
            fila += 1

        # Double-click a window's title bar to
        wm = Gio.Settings.new("org.cinnamon.desktop.wm.preferences")
        dc = Gtk.CheckButton(label="Double-click a window’s title bar to")
        valor = wm.get_string("action-double-click-titlebar")
        dc.set_active(valor in ("toggle-maximize", "minimize"))
        combo = Gtk.ComboBoxText()
        combo.append("toggle-maximize", "zoom")
        combo.append("minimize", "minimize")
        combo.set_active_id(valor if valor in ("toggle-maximize", "minimize") else "toggle-maximize")
        combo.set_sensitive(dc.get_active())

        def doble_clic(*_):
            combo.set_sensitive(dc.get_active())
            wm.set_string("action-double-click-titlebar", combo.get_active_id() if dc.get_active() else "none")
        dc.connect("toggled", doble_clic)
        combo.connect("changed", doble_clic)
        caja_dc = Gtk.Box(spacing=8)
        caja_dc.pack_start(dc, False, False, 0)
        caja_dc.pack_start(combo, False, False, 0)
        cuadro.attach(caja_dc, 0, fila, 3, 1)
        fila += 1

        # Animate opening applications: el rebote al abrir (LaunchBounceHeight del tema)
        animar = Gtk.CheckButton(label="Animate opening applications")
        animar.set_active(_tema_encendido(p, "LaunchBounceHeight"))
        animar.connect("toggled", lambda b: _encender_tema(p, "LaunchBounceHeight", b.get_active()))
        cuadro.attach(animar, 0, fila, 3, 1)
        fila += 1

        # Automatically hide and show the Dock
        ocultar = Gtk.CheckButton(label="Automatically hide and show the Dock")
        ocultar.set_active(p.get_string("hide-mode") != "none")
        ocultar.connect("toggled", lambda b: p.set_string("hide-mode", "auto" if b.get_active() else "none"))
        cuadro.attach(ocultar, 0, fila, 3, 1)
        fila += 1

        # Show indicators for open applications: el punto bajo el ícono (IndicatorSize del tema)
        indic = Gtk.CheckButton(label="Show indicators for open applications")
        indic.set_active(_tema_encendido(p, "IndicatorSize"))
        indic.connect("toggled", lambda b: _encender_tema(p, "IndicatorSize", b.get_active()))
        cuadro.attach(indic, 0, fila, 3, 1)
        fila += 1

        # Show recent applications in Dock: las últimas tres apps cerradas se quedan
        # (clave show-recent-apps del Plank de mint-macos).
        if p.props.settings_schema.has_key("show-recent-apps"):
            recientes = Gtk.CheckButton(label="Show recent applications in Dock")
            recientes.set_active(p.get_boolean("show-recent-apps"))
            recientes.connect("toggled", lambda b: p.set_boolean("show-recent-apps", b.get_active()))
            cuadro.attach(recientes, 0, fila, 3, 1)

        cuadro.show_all()
        return cuadro

    # ── el efecto genio: encender o apagar la extensión Magic Lamp ──────
    @staticmethod
    def _genio_activo():
        return MAGIC_LAMP in Gio.Settings.new("org.cinnamon").get_strv("enabled-extensions")

    @staticmethod
    def _poner_genio(si):
        cfg = Gio.Settings.new("org.cinnamon")
        lista = [e for e in cfg.get_strv("enabled-extensions") if e != MAGIC_LAMP]
        if si:
            lista.append(MAGIC_LAMP)
        cfg.set_strv("enabled-extensions", lista)


PROPIOS = {p.id: p for p in (PanelDock(),)}
