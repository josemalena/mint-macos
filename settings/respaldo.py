"""Time Machine: el panel de Catalina (Screen Shot 2026-10-14 at 1.24.52 PM) sobre Timeshift.

Lee /etc/timeshift/timeshift.json (legible sin root): «Back Up Automatically» refleja si hay alguna
programación encendida, el disco sale de backup_device_uuid, y el texto de lo que se guarda usa los
conteos reales (cada hora, cada día, cada semana y cada mes). Select Backup Disk… y Options… abren
Timeshift (que pide la clave de administrador por su cuenta). Cambiar la programación desde aquí no se
puede sin root: los controles van en gris. Sin equivalente: Show Time Machine in menu bar.
La captura de la hoja Options… (1.24.59 PM) y de Select Disk (1.25.04 PM) no se imitan: Timeshift trae las suyas.
"""
import json
import os
import subprocess

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk  # noqa: E402

import paneles  # noqa: E402


def _config():
    for ruta in ("/etc/timeshift/timeshift.json", "/etc/timeshift/default.json"):
        try:
            return json.load(open(ruta, encoding="utf-8"))
        except (OSError, ValueError):
            continue
    return {}


def _disco(uuid):
    if not uuid:
        return None
    try:
        r = subprocess.run(["lsblk", "-no", "LABEL,NAME,MOUNTPOINT", "/dev/disk/by-uuid/" + uuid],
                           capture_output=True, text=True, timeout=10)
        partes = r.stdout.strip().split()
        return partes[0] if partes else uuid
    except (OSError, subprocess.SubprocessError):
        return uuid


def _gris(widget, motivo="Timeshift sets this itself; open it to change the schedule."):
    widget.set_sensitive(False)
    widget.set_tooltip_text(motivo)
    return widget


class PanelTimeMachine:
    id = "com.apple.prefs.backup"
    nombre = "Time Machine"
    claves = []
    externo = False
    propio = True
    celda = None
    PRUEBA = bool(os.environ.get("MINT_RESPALDO_PRUEBA"))     # no abre Timeshift

    def __init__(self):
        self.panel = paneles.Panel(self.id, self.nombre, [],
                                   palabras="time machine, backup, back up, timeshift, snapshot, restore")
        self.ventana = None

    def coincide(self, texto):
        t = texto.lower().strip()
        return bool(t) and any(t in c.lower() for c in (self.nombre, self.panel.palabras, self.id))

    def _abrir(self):
        if self.PRUEBA:
            return
        try:
            subprocess.Popen(["timeshift-launcher"], start_new_session=True,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except OSError:
            pass

    def construir(self):
        from propios import imagen_icono_panel
        cfg = _config()
        caja = Gtk.Box(spacing=0)
        caja.get_style_context().add_class("mp-propio")
        caja.set_margin_top(18)
        caja.set_margin_bottom(14)
        izq = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        izq.set_size_request(240, -1)
        izq.pack_start(imagen_icono_panel(self.id, 112), False, False, 10)
        t = Gtk.Label(label="Time Machine")
        t.get_style_context().add_class("mp-titulo-negrita")
        izq.pack_start(t, False, False, 0)
        activo = any(str(cfg.get("schedule_" + k, "false")) == "true" for k in ("monthly", "weekly", "daily",
                                                                                 "hourly", "boot"))
        auto = Gtk.CheckButton(label="Back Up Automatically")
        auto.set_active(activo)
        auto.set_halign(Gtk.Align.CENTER)
        izq.pack_start(_gris(auto), False, False, 0)
        caja.pack_start(izq, False, False, 0)
        caja.pack_start(Gtk.Separator(orientation=Gtk.Orientation.VERTICAL), False, False, 0)

        der = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        der.set_margin_start(30)
        der.set_margin_end(20)
        disco = _disco(cfg.get("backup_device_uuid"))
        titulo = Gtk.Label(label=disco or "No backup disk selected", xalign=0.5)
        titulo.get_style_context().add_class("mp-titulo-negrita")
        der.pack_start(titulo, False, False, 10)
        seleccionar = Gtk.Button(label="Select Backup Disk…")
        seleccionar.set_halign(Gtk.Align.CENTER)
        seleccionar.connect("clicked", lambda _b: self._abrir())
        der.pack_start(seleccionar, False, False, 0)
        lineas = ["Timeshift keeps:"]
        for clave, texto in (("hourly", "hourly"), ("daily", "daily"), ("weekly", "weekly"), ("monthly", "monthly")):
            if str(cfg.get("schedule_" + clave, "false")) == "true":
                lineas.append("• %s snapshots, up to %s" % (texto.capitalize(), cfg.get("count_" + clave, "?")))
        if len(lineas) == 1:
            lineas.append("• No schedule is turned on")
        l = Gtk.Label(label="\n".join(lineas), xalign=0)
        l.set_margin_top(20)
        der.pack_start(l, False, False, 0)
        der.pack_start(Gtk.Box(), True, True, 0)
        pie = Gtk.Box(spacing=8)
        menu = Gtk.CheckButton(label="Show Time Machine in menu bar")
        pie.pack_start(_gris(menu, "There is no Time Machine menu on this computer."), False, False, 0)
        opciones = Gtk.Button(label="Options…")
        opciones.connect("clicked", lambda _b: self._abrir())
        pie.pack_end(opciones, False, False, 0)
        der.pack_start(pie, False, False, 0)
        caja.pack_start(der, True, True, 0)
        caja.set_size_request(-1, 230)
        caja.show_all()
        return caja
