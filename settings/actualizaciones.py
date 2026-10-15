"""Software Update: el panel de Catalina (Screen Shot 2026-10-14 at 1.22.23 PM y 1.22.26 PM, la hoja Advanced…).

Con todo al día dice «Your computer is up to date» con la versión de Linux Mint y cuándo se revisó
(refresh-last-run de com.linuxmint.updates). Con actualizaciones pendientes (`apt list --upgradable`)
dice cuántas hay y ofrece Update Now, que abre Update Manager de Mint. Catalina no tiene captura de ese
estado: el texto es sobrio y no se adorna.
La hoja Advanced…: «Check for updates» es refresh-schedule-enabled y «Install app updates» es
auto-update-flatpaks; «Download new updates», «Install macOS updates» y «Install system data files and
security updates» no tienen una clave que podamos escribir aquí y van en gris.
"""
import os
import subprocess
import time

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gio, Gtk  # noqa: E402

import paneles  # noqa: E402

AJUSTES = "com.linuxmint.updates"


def _version():
    try:
        datos = dict(l.strip().split("=", 1) for l in open("/etc/os-release", encoding="utf-8") if "=" in l)
        return "%s %s" % (datos["NAME"].strip('"'), datos["VERSION"].strip('"'))
    except (OSError, KeyError):
        return "Linux"


def _pendientes():
    """Cuántas actualizaciones de apt hay, o None si no se pudo mirar."""
    try:
        r = subprocess.run(["apt", "list", "--upgradable"], capture_output=True, text=True, timeout=30,
                           env=dict(os.environ, LC_ALL="C"))
    except (OSError, subprocess.SubprocessError):
        return None
    return sum(1 for l in r.stdout.splitlines() if "/" in l and "upgradable" in l)


def _cuando(segundos):
    ahora = time.localtime()
    t = time.localtime(segundos)
    dia = "Today" if (t.tm_year, t.tm_yday) == (ahora.tm_year, ahora.tm_yday) else time.strftime("%b %-d", t)
    return "%s at %s" % (dia, time.strftime("%-I:%M %p", t))


class PanelSoftwareUpdate:
    id = "com.apple.preferences.softwareupdate"
    nombre = "Software Update"
    claves = []
    externo = False
    propio = True
    celda = None
    PRUEBA = bool(os.environ.get("MINT_ACTUALIZACIONES_PRUEBA"))     # no escribe en gsettings

    def __init__(self):
        self.panel = paneles.Panel(self.id, self.nombre, [],
                                   palabras="software update, updates, upgrade, packages, security, "
                                            "automatically keep up to date")
        self.ventana = None

    def coincide(self, texto):
        t = texto.lower().strip()
        return bool(t) and any(t in c.lower() for c in (self.nombre, self.panel.palabras, self.id))

    def construir(self):
        from propios import imagen_icono_panel
        self._cfg = Gio.Settings.new(AJUSTES)
        caja = Gtk.Box(spacing=0)
        caja.get_style_context().add_class("mp-propio")
        caja.set_margin_top(20)
        caja.set_margin_bottom(14)
        izq = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        izq.set_size_request(240, -1)
        izq.pack_start(imagen_icono_panel(self.id, 112), False, False, 10)
        t = Gtk.Label(label="Software Update")
        t.get_style_context().add_class("mp-titulo-negrita")
        izq.pack_start(t, False, False, 0)
        caja.pack_start(izq, False, False, 0)
        caja.pack_start(Gtk.Separator(orientation=Gtk.Orientation.VERTICAL), False, False, 0)

        der = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        der.set_margin_start(40)
        der.set_margin_end(20)
        n = _pendientes()
        if n:
            titulo = Gtk.Label(label="%d update%s available." % (n, "" if n == 1 else "s"), xalign=0)
        else:
            titulo = Gtk.Label(label="Your computer is up to date — %s" % _version(), xalign=0)
        titulo.get_style_context().add_class("mp-titulo-negrita")
        der.pack_start(titulo, False, False, 0)
        ultima = self._cfg.get_value("refresh-last-run").unpack() if "refresh-last-run" in self._cfg.list_keys() else 0
        if ultima:
            d = Gtk.Label(label="Last checked: %s" % _cuando(ultima), xalign=0)
            d.get_style_context().add_class("mp-sd-detalle")
            der.pack_start(d, False, False, 0)
        if n:
            ir = Gtk.Button(label="Update Now")
            ir.set_halign(Gtk.Align.START)
            ir.connect("clicked", lambda _b: subprocess.Popen(["mintupdate"], start_new_session=True))
            der.pack_start(ir, False, False, 12)
        relleno = Gtk.Box()
        der.pack_start(relleno, True, True, 0)
        pie = Gtk.Box(spacing=8)
        auto = Gtk.CheckButton(label="Automatically keep my computer up to date")
        auto.set_active(False)
        auto.set_sensitive(False)
        auto.set_tooltip_text("Update Manager checks for updates; installing them stays manual.")
        pie.pack_start(auto, False, False, 0)
        av = Gtk.Button(label="Advanced…")
        av.connect("clicked", lambda _b: self._hoja())
        pie.pack_end(av, False, False, 0)
        der.pack_start(pie, False, False, 0)
        caja.pack_start(der, True, True, 0)
        caja.set_size_request(-1, 190)
        caja.show_all()
        return caja

    def _hoja(self):
        d = Gtk.Dialog(transient_for=self.ventana, modal=True)
        d.set_decorated(False)
        d.get_style_context().add_class("mp-hoja")
        c = d.get_content_area()
        c.set_spacing(8)
        for lado in ("top", "bottom", "start", "end"):
            getattr(c, "set_margin_" + lado)(20)
        c.pack_start(Gtk.Label(label="Automatically:", xalign=0), False, False, 0)
        filas = [("Check for updates", "refresh-schedule-enabled"),
                 ("Download new updates when available", None),
                 ("Install OS updates", None),
                 ("Install app updates", "auto-update-flatpaks"),
                 ("Install system data files and security updates", None)]
        for texto, clave in filas:
            b = Gtk.CheckButton(label=texto)
            if clave and clave in self._cfg.list_keys():
                b.set_active(self._cfg.get_boolean(clave))
                b.connect("toggled", lambda w, k=clave: self.PRUEBA or self._cfg.set_boolean(k, w.get_active()))
            else:
                b.set_active(False)
                b.set_sensitive(False)
                b.set_tooltip_text("Not available on this computer.")
            c.pack_start(b, False, False, 0)
        ok = d.add_button("OK", Gtk.ResponseType.OK)
        ok.get_style_context().add_class("suggested-action")
        d.set_default_response(Gtk.ResponseType.OK)
        d.show_all()
        d.run()
        d.destroy()
