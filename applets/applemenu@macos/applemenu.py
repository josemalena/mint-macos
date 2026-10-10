#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Diálogos de la Mac para el menú Apple (applemenu@macos), en GTK3.

Modos:
  - forcequit : la ventana «Force Quit Applications» (lista por wmctrl, X11).
  - restart   : «Are you sure you want to restart…» con la cuenta regresiva.
  - shutdown  : lo mismo para apagar.
  - logoff    : lo mismo para cerrar la sesión.

Los tres de confirmación son el de Catalina medido en c42 (ver ConfirmDialog):
nunca sale encima el diálogo de Cinnamon, porque la acción va con --no-prompt
y sin plan B que lo abra. «Reopen windows when logging back in» es el guardado
de sesión de Cinnamon (org.cinnamon.SessionManager auto-save-session).

Uso:
    python3 applemenu.py --mode forcequit
    python3 applemenu.py --mode restart [--seconds 60] [--print-json]
    python3 applemenu.py --mode restart --prueba   # lo enseña y no hace nada
"""

import argparse
import json
import os
import re
import signal
import subprocess
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Set, Tuple

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, Gio, GLib, Gdk  # noqa: E402


# ──────────────────────────────────────────────────────────────────────────────
# Force Quit strings
# ──────────────────────────────────────────────────────────────────────────────
FQ_TITLE = "Force Quit Applications"
FQ_SUBTITLE = "If an app doesn’t respond for a while, select its name and click Force Quit."
FQ_HINT = "You can open this window by pressing Command-Option-Escape."


# ──────────────────────────────────────────────────────────────────────────────
# Confirm dialog presets (wording follows your screenshots)
# ──────────────────────────────────────────────────────────────────────────────
CONF_PRESETS: Dict[str, Dict[str, object]] = {
    "shutdown": {
        "title": "Are you sure you want to shut down your computer now?",
        "countdown": "If you do nothing, the computer will shut down automatically\nin {n} seconds.",
        "action_label": "Shut Down",
        "default_reopen": True,
        "primary_cmd": ["cinnamon-session-quit", "--power-off", "--no-prompt"],
        "fallback_cmds": [
            ["systemctl", "poweroff"],
            ["shutdown", "-h", "now"],
        ],
    },
    "restart": {
        "title": "Are you sure you want to restart your computer now?",
        "countdown": "If you do nothing, the computer will restart automatically\nin {n} seconds.",
        "action_label": "Restart",
        "default_reopen": True,
        "primary_cmd": ["cinnamon-session-quit", "--reboot", "--no-prompt"],
        "fallback_cmds": [
            ["systemctl", "reboot"],
            ["shutdown", "-r", "now"],
        ],
    },
    "logoff": {
        "title": "Are you sure you want to quit all applications\nand log out now?",
        "countdown": "If you do nothing, you will be logged out automatically in\n{n} seconds.",
        "action_label": "Log Out",
        "default_reopen": False,
        "primary_cmd": ["cinnamon-session-quit", "--logout", "--no-prompt"],
        # Sin plan B: «cinnamon-session-quit --logout» sin --no-prompt abría el
        # diálogo del sistema encima de este (José: que no salga).
        "fallback_cmds": [],
    },
}


DEFAULT_COUNTDOWN_SECONDS = 60


# ──────────────────────────────────────────────────────────────────────────────
# Force Quit: data + collection (wmctrl)
# ──────────────────────────────────────────────────────────────────────────────
@dataclass
class AppEntry:
    wmclass_raw: str
    name: str
    icon_name: str
    pids: List[int] = field(default_factory=list)


def prettify(s: str) -> str:
    if not s:
        return ""
    s = s.strip()
    s = re.sub(r"[_\-]+", " ", s)
    if s == s.lower():
        s = s[:1].upper() + s[1:]
    return s


def _run_wmctrl() -> str:
    return subprocess.check_output(["wmctrl", "-lpGx"], text=True, stderr=subprocess.DEVNULL)


def _parse_wmctrl(text: str) -> List[Tuple[str, int, str, str]]:
    out: List[Tuple[str, int, str, str]] = []
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue

        parts = line.split(None, 8)
        if len(parts) < 9:
            continue

        wid_hex = parts[0]
        pid_s = parts[2]
        wmclass = parts[7] or ""
        title = parts[8] or ""

        # Ignore Plank (any variant)
        if "plank" in wmclass.lower() or "plank" in title.lower():
            continue

        try:
            pid = int(pid_s)
        except Exception:
            pid = -1
        if pid <= 0:
            continue

        out.append((wid_hex, pid, wmclass, title))
    return out


def _resolve_icon_and_name(wmclass: str) -> Tuple[str, str]:
    """
    Map WM_CLASS -> (icon_name, display_name)
    Special cases:
      - nemo-desktop => name "Finder" + icon from Nemo (theme-based)
    """
    cls = wmclass
    if "." in wmclass:
        cls = wmclass.split(".")[-1]
    cls_low = cls.lower().strip()

    # Special-case: nemo-desktop acts as Finder
    if cls_low == "nemo-desktop":
        return ("nemo", "Finder")

    # Best-effort: match DesktopAppInfo via StartupWMClass / desktop id
    try:
        for appinfo in Gio.AppInfo.get_all():
            if not isinstance(appinfo, Gio.DesktopAppInfo):
                continue
            d: Gio.DesktopAppInfo = appinfo

            startup = (d.get_startup_wm_class() or "").lower()
            if startup and startup == cls_low:
                icon = d.get_icon()
                icon_name = icon.to_string() if icon else ""
                name = d.get_display_name() or d.get_name() or prettify(cls)
                return (icon_name, name)

            app_id = (d.get_id() or "").lower()
            if app_id.startswith(cls_low) or cls_low in app_id:
                icon = d.get_icon()
                icon_name = icon.to_string() if icon else ""
                name = d.get_display_name() or d.get_name() or prettify(cls)
                return (icon_name, name)
    except Exception:
        pass

    return ("application-x-executable", prettify(cls))


def collect_apps() -> List[AppEntry]:
    try:
        raw = _run_wmctrl()
    except Exception:
        return []

    rows = _parse_wmctrl(raw)

    grouped: Dict[str, Set[int]] = {}
    for _wid, pid, wmclass, _title in rows:
        if "plank" in (wmclass or "").lower():
            continue
        grouped.setdefault(wmclass, set()).add(pid)

    apps: List[AppEntry] = []
    for wmclass, pids_set in grouped.items():
        if "plank" in (wmclass or "").lower():
            continue
        icon_name, name = _resolve_icon_and_name(wmclass)
        pids = sorted(list(pids_set))
        apps.append(AppEntry(wmclass_raw=wmclass, name=name, icon_name=icon_name, pids=pids))

    # Finder first, then alpha
    def sort_key(a: AppEntry):
        return (0 if a.name == "Finder" else 1, a.name.lower())

    apps.sort(key=sort_key)
    return apps


# ──────────────────────────────────────────────────────────────────────────────
# Force Quit window (GTK3)
# ──────────────────────────────────────────────────────────────────────────────
class ForceQuitWindow(Gtk.Window):
    def __init__(self):
        super().__init__(title=FQ_TITLE)
        # macOS reference size: ~360x390, resizable
        self.set_default_size(360, 390)
        self.set_resizable(True)
        # Hint as dialog so WM avoids maximize controls on Cinnamon themes.
        self.set_type_hint(Gdk.WindowTypeHint.DIALOG)
        self.set_border_width(12)
        self.connect("realize", self._on_realize_disable_maximize)

        self._apps: List[AppEntry] = collect_apps()
        self._selected: Optional[AppEntry] = None

        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        self.add(vbox)

        subtitle = Gtk.Label(label=FQ_SUBTITLE)
        subtitle.set_xalign(0.0)
        subtitle.set_line_wrap(True)
        vbox.pack_start(subtitle, False, False, 0)

        scroller = Gtk.ScrolledWindow()
        scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroller.set_hexpand(True)
        scroller.set_vexpand(True)
        vbox.pack_start(scroller, True, True, 0)

        self.listbox = Gtk.ListBox()
        self.listbox.set_hexpand(True)
        self.listbox.set_vexpand(True)
        self.listbox.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self.listbox.connect("row-selected", self._on_row_selected)
        scroller.add(self.listbox)

        self._populate()

        bottom = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        vbox.pack_start(bottom, False, False, 0)

        hint = Gtk.Label(label=FQ_HINT)
        hint.set_xalign(0.0)
        hint.set_line_wrap(True)
        hint.set_hexpand(True)
        bottom.pack_start(hint, True, True, 0)

        self.force_btn = Gtk.Button(label="Force Quit")
        self.force_btn.set_sensitive(False)
        self.force_btn.connect("clicked", self._on_force_quit)
        bottom.pack_start(self.force_btn, False, False, 0)

        self.connect("destroy", Gtk.main_quit)

    def _on_realize_disable_maximize(self, *_args):
        # Keep manual resize but disable maximize capability when supported by WM.
        try:
            gdk_win = self.get_window()
            if gdk_win is None:
                return
            funcs = Gdk.WMFunction.MOVE | Gdk.WMFunction.RESIZE | Gdk.WMFunction.CLOSE
            gdk_win.set_functions(funcs)
        except Exception:
            pass

    def _populate(self):
        for child in self.listbox.get_children():
            self.listbox.remove(child)

        if not self._apps:
            row = Gtk.ListBoxRow()
            lbl = Gtk.Label(label="No running applications")
            lbl.set_xalign(0.0)
            lbl.set_line_wrap(True)
            for m in ("top", "bottom", "start", "end"):
                getattr(lbl, f"set_margin_{m}")(8)
            row.add(lbl)
            row.set_selectable(False)
            self.listbox.add(row)
            self.listbox.show_all()
            return

        theme = Gtk.IconTheme.get_default()

        for app in self._apps:
            row = Gtk.ListBoxRow()
            row._app = app  # type: ignore

            h = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
            h.set_margin_top(6)
            h.set_margin_bottom(6)
            h.set_margin_start(10)
            h.set_margin_end(10)

            icon_name = (app.icon_name or "").strip()
            img = None

            # 1) icon name exists in theme
            if icon_name and theme.has_icon(icon_name):
                img = Gtk.Image.new_from_icon_name(icon_name, Gtk.IconSize.DND)

            # 2) icon string looks like a path
            if img is None and icon_name.startswith("/"):
                try:
                    img = Gtk.Image.new_from_file(icon_name)
                except Exception:
                    img = None

            # 3) fallback
            if img is None:
                img = Gtk.Image.new_from_icon_name("application-x-executable", Gtk.IconSize.DND)

            img.set_pixel_size(20)
            h.pack_start(img, False, False, 0)

            lbl = Gtk.Label(label=app.name)
            lbl.set_xalign(0.0)
            lbl.set_hexpand(True)
            lbl.set_ellipsize(3)  # END
            h.pack_start(lbl, True, True, 0)

            row.add(h)
            self.listbox.add(row)

        self.listbox.show_all()

    def _on_row_selected(self, _lb, row):
        self._selected = None
        self.force_btn.set_sensitive(False)
        if not row:
            return
        app = getattr(row, "_app", None)
        if isinstance(app, AppEntry) and app.pids:
            self._selected = app
            self.force_btn.set_sensitive(True)

    def _on_force_quit(self, _btn):
        if not self._selected or not self._selected.pids:
            return

        pids = list(self._selected.pids)

        # TERM then (after 1.2s) KILL
        for pid in pids:
            try:
                os.kill(pid, signal.SIGTERM)
            except Exception:
                pass

        def kill_later():
            for pid in pids:
                try:
                    os.kill(pid, signal.SIGKILL)
                except Exception:
                    pass
            return False

        GLib.timeout_add(1200, kill_later)
        self.close()


# ──────────────────────────────────────────────────────────────────────────────
# Diálogo de Restart / Shut Down / Log Out, como el de Catalina (c42)
# ──────────────────────────────────────────────────────────────────────────────
# Medido en la captura de la Mac mini a 1x:
#   ventana de 416 × 196: franja superior de 21 px (degradado #3B3B3C → #313233,
#   línea negra debajo), cuerpo #2A2B2C, borde de 1 px #545556, esquinas de 5;
#   ícono: círculo #8B8D8E de 64 px a 20 px del borde y 21 px bajo la franja;
#   texto desde x 91, #DEDFDF: título en negrita (13 px) y la cuenta regresiva
#   en chico (11 px); casilla de 14 × 14 #4B4E51;
#   botones de 70 × 19 a 20 px del borde derecho y del de abajo, 14 px entre
#   ellos: Cancel #5F6061 y la acción en azul (#165EE1 → #1555CB).
# La fuente es SF (obligatoria): «.SF NS».
# Los íconos se dibujan aquí: ningún archivo de Apple.

ANCHO, ALTO, FRANJA, SOMBRA = 416, 196, 21, 24

CSS_DIALOGO = b"""
#mac-dialogo { background: transparent; }
#mac-caja {
  background-color: #2a2b2c;
  border: 1px solid #545556;
  border-radius: 5px;
  box-shadow: 0 10px 24px rgba(0, 0, 0, 0.55);
}
#mac-franja {
  background-image: linear-gradient(to bottom, #3b3b3c, #313233);
  border-bottom: 1px solid #000000;
  border-radius: 5px 5px 0 0;
}
#mac-titulo { font-family: ".SF NS"; font-weight: bold; font-size: 13px; color: #dedfdf; }
#mac-cuenta { font-family: ".SF NS"; font-size: 11px; color: #dedfdf; }
#mac-casilla, #mac-casilla label { font-family: ".SF NS"; font-size: 13px; color: #dedfdf; }
#mac-casilla check {
  min-width: 14px; min-height: 14px; margin: 0 6px 0 0;
  border-radius: 3px; border: 1px solid #5a5d60;
  background-image: none; background-color: #4b4e51;
}
#mac-casilla check:checked { background-color: #165ee1; border-color: #165ee1; color: #ffffff; }
button.mac-boton {
  font-family: ".SF NS"; font-size: 13px; color: #e7e7e7;
  min-height: 19px; min-width: 50px; padding: 0 10px; margin: 0; outline: none;
  border-radius: 5px; border: none; box-shadow: none; text-shadow: none;
  background-image: none; background-color: #5f6061;
}
button.mac-boton label { padding: 0; margin: 0; min-width: 0; }
button.mac-boton:hover { background-color: #6a6b6c; }
button.mac-boton.mac-boton-accion { background-image: linear-gradient(to bottom, #165ee1, #1555cb); color: #ffffff; }
button.mac-boton.mac-boton-accion:hover { background-image: linear-gradient(to bottom, #2a6cec, #1a5ed6); }
"""


def _dibujar_icono(modo, cr):
    """El círculo gris de Catalina con su signo en blanco, a 64 × 64."""
    import math
    cr.set_source_rgb(139 / 255, 141 / 255, 142 / 255)
    cr.arc(32, 32, 32, 0, 2 * math.pi)
    cr.fill()
    cr.set_source_rgb(1, 1, 1)
    cr.set_line_width(2.6)
    cr.set_line_join(1)  # redondo
    cr.set_line_cap(1)
    if modo == "restart":
        # ◁ como en c42.
        cr.move_to(20, 32)
        cr.line_to(41, 19.5)
        cr.line_to(41, 44.5)
        cr.close_path()
        cr.stroke()
    elif modo == "shutdown":
        # ⏻: el arco con la raya arriba.
        cr.arc(32, 33, 13, -math.pi / 2 + 0.55, 3 * math.pi / 2 - 0.55)
        cr.stroke()
        cr.move_to(32, 16)
        cr.line_to(32, 31)
        cr.stroke()
    else:
        # La persona: Log Out cierra la sesión de alguien.
        cr.arc(32, 24, 7.5, 0, 2 * math.pi)
        cr.stroke()
        cr.arc(32, 50, 15, math.pi + 0.15, 2 * math.pi - 0.15)
        cr.stroke()


class ConfirmDialog(Gtk.Window):
    """Restart / Shut Down / Log Out con la cuenta regresiva de 60 s (c42)."""

    def __init__(self, mode: str, countdown_seconds: int, reopen_default: bool):
        if mode not in CONF_PRESETS:
            raise ValueError(f"Unknown mode: {mode}")
        super().__init__(title="")
        self.mode = mode
        self.p = CONF_PRESETS[mode]
        self.remaining = max(1, int(countdown_seconds))
        self.respuesta = Gtk.ResponseType.CANCEL
        self._timer_id = 0

        self.set_name("mac-dialogo")
        self.set_decorated(False)
        self.set_resizable(False)
        self.set_keep_above(True)
        self.set_skip_taskbar_hint(True)
        self.set_type_hint(Gdk.WindowTypeHint.DIALOG)
        self.set_position(Gtk.WindowPosition.CENTER)
        pantalla = self.get_screen()
        visual = pantalla.get_rgba_visual()
        if visual is not None and pantalla.is_composited():
            self.set_visual(visual)
            self.set_app_paintable(True)
            margen = SOMBRA
        else:
            margen = 0
        self.set_default_size(ANCHO + 2 * margen, ALTO + 2 * margen)

        css = Gtk.CssProvider()
        css.load_from_data(CSS_DIALOGO)
        Gtk.StyleContext.add_provider_for_screen(pantalla, css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 1)

        # El fondo, el borde y la sombra van en una caja: el Fixed (que pone
        # cada pieza en su píxel) no pinta su propio CSS.
        fondo = Gtk.Box()
        fondo.set_name("mac-caja")
        fondo.set_size_request(ANCHO, ALTO)
        fondo.set_margin_top(margen); fondo.set_margin_bottom(margen)
        fondo.set_margin_start(margen); fondo.set_margin_end(margen)
        caja = Gtk.Fixed()
        caja.set_size_request(ANCHO, ALTO)
        fondo.pack_start(caja, True, True, 0)
        self.add(fondo)

        franja = Gtk.Box()
        franja.set_name("mac-franja")
        franja.set_size_request(ANCHO - 2, FRANJA)
        caja.put(franja, 1, 1)

        icono = Gtk.DrawingArea()
        icono.set_size_request(64, 64)
        icono.connect("draw", lambda _w, cr: _dibujar_icono(self.mode, cr))
        caja.put(icono, 20, FRANJA + 21)

        derecha = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        derecha.set_size_request(ANCHO - 91 - 20, -1)
        caja.put(derecha, 91, FRANJA + 20)

        titulo = Gtk.Label(label=str(self.p["title"]).replace("\n", " "))
        titulo.set_name("mac-titulo")
        titulo.set_xalign(0.0)
        titulo.set_line_wrap(True)
        titulo.set_size_request(ANCHO - 91 - 20, -1)
        derecha.pack_start(titulo, False, False, 0)

        self.countdown_lbl = Gtk.Label()
        self.countdown_lbl.set_name("mac-cuenta")
        self.countdown_lbl.set_xalign(0.0)
        self.countdown_lbl.set_line_wrap(True)
        self.countdown_lbl.set_size_request(ANCHO - 91 - 20, -1)
        self.countdown_lbl.set_margin_top(8)
        derecha.pack_start(self.countdown_lbl, False, False, 0)

        self.reopen_cb = Gtk.CheckButton.new_with_label("Reopen windows when logging back in")
        self.reopen_cb.set_name("mac-casilla")
        self.reopen_cb.set_active(bool(reopen_default))
        self.reopen_cb.set_can_focus(False)
        self.reopen_cb.set_margin_top(6)
        derecha.pack_start(self.reopen_cb, False, False, 0)

        cancelar = Gtk.Button(label="Cancel")
        cancelar.get_style_context().add_class("mac-boton")
        cancelar.set_size_request(70, 19)
        cancelar.connect("clicked", lambda *_: self._terminar(Gtk.ResponseType.CANCEL))
        accion = Gtk.Button(label=str(self.p["action_label"]))
        accion.get_style_context().add_class("mac-boton")
        accion.get_style_context().add_class("mac-boton-accion")
        accion.set_size_request(70, 19)
        accion.connect("clicked", lambda *_: self._terminar(Gtk.ResponseType.OK))
        # Pegados a la derecha, a 16 px del borde interior (con el borde quedan
        # los 20 de la Mac: c42, x 241–310 y 325–394), 14 entre ellos. Miden 70
        # como mínimo y crecen con el texto, como «Shut Down» en la Mac.
        fila = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=14)
        fila.set_size_request(ANCHO - 16, 19)
        fila.pack_end(accion, False, False, 0)
        fila.pack_end(cancelar, False, False, 0)
        caja.put(fila, 0, ALTO - 20 - 19)

        # ⏎ hace la acción, ⎋ cancela: como en la Mac.
        self.connect("key-press-event", self._on_tecla)
        self.connect("delete-event", lambda *_: (self._terminar(Gtk.ResponseType.CANCEL), True)[1])
        self.connect("destroy", self._on_destroy)

        self._timer_id = GLib.timeout_add(1000, self._tick)
        self._update_countdown()
        self.show_all()
        accion.grab_focus()
        # Al frente y con el teclado, como en la Mac: ⏎ y ⎋ funcionan de una.
        GLib.idle_add(self._al_frente)

    def _al_frente(self):
        try:
            self.present_with_time(Gdk.CURRENT_TIME)
            ventana = self.get_window()
            if ventana is not None:
                ventana.focus(Gdk.CURRENT_TIME)
        except Exception:
            pass
        return False

    def _on_tecla(self, _w, event):
        if event.keyval in (Gdk.KEY_Return, Gdk.KEY_KP_Enter):
            self._terminar(Gtk.ResponseType.OK)
            return True
        if event.keyval == Gdk.KEY_Escape:
            self._terminar(Gtk.ResponseType.CANCEL)
            return True
        return False

    def _terminar(self, respuesta):
        self.respuesta = respuesta
        Gtk.main_quit()

    def run(self):
        Gtk.main()
        return self.respuesta

    def _update_countdown(self):
        tmpl = str(self.p["countdown"]).replace("\n", " ")
        self.countdown_lbl.set_text(tmpl.format(n=self.remaining))

    def _tick(self):
        self.remaining -= 1
        if self.remaining <= 0:
            self._timer_id = 0
            self._terminar(Gtk.ResponseType.OK)
            return False
        self._update_countdown()
        return True

    def _on_destroy(self, *_args):
        if self._timer_id:
            try:
                GLib.source_remove(self._timer_id)
            except Exception:
                pass
            self._timer_id = 0


def _reabrir_ventanas_actual() -> bool:
    """«Reopen windows» es el guardado de sesión de Cinnamon."""
    try:
        return bool(Gio.Settings.new("org.cinnamon.SessionManager").get_boolean("auto-save-session"))
    except Exception:
        return False


def _guardar_reabrir_ventanas(valor: bool) -> None:
    try:
        Gio.Settings.new("org.cinnamon.SessionManager").set_boolean("auto-save-session", bool(valor))
        Gio.Settings.sync()
    except Exception:
        pass


def _run_command(cmd: List[str]) -> bool:
    try:
        subprocess.Popen(cmd)
        return True
    except Exception:
        return False


def execute_action(mode: str, reopen_windows: bool) -> bool:
    """
    Execute shutdown/restart/logoff. Returns True if we successfully launched a command.
    """
    preset = CONF_PRESETS[mode]
    primary = list(preset["primary_cmd"])  # type: ignore
    if _run_command(primary):
        return True

    for fb in preset.get("fallback_cmds", []):  # type: ignore
        if _run_command(list(fb)):
            return True

    return False


# ──────────────────────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────────────────────
def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", required=True, choices=["forcequit", "shutdown", "restart", "logoff"])
    ap.add_argument("--seconds", type=int, default=DEFAULT_COUNTDOWN_SECONDS, help="Countdown seconds (confirm dialogs).")
    ap.add_argument("--print-json", action="store_true", help="Print result JSON to stdout (for applet).")
    ap.add_argument("--prueba", action="store_true",
                    help="Enseña el diálogo y no hace nada al confirmar ni al agotarse la cuenta: para medirlo.")
    args = ap.parse_args()

    if args.mode == "forcequit":
        win = ForceQuitWindow()
        win.show_all()
        Gtk.main()
        return 0

    # Restart / Shut Down / Log Out: la casilla arranca como esté guardada
    # la sesión (en c42, desmarcada).
    dlg = ConfirmDialog(mode=args.mode, countdown_seconds=args.seconds,
                        reopen_default=_reabrir_ventanas_actual())
    resp = dlg.run()
    reopen = bool(dlg.reopen_cb.get_active())
    dlg.destroy()

    did_execute = False
    if resp == Gtk.ResponseType.OK and not args.prueba:
        _guardar_reabrir_ventanas(reopen)
        did_execute = execute_action(args.mode, reopen)

    if args.print_json:
        out = {
            "mode": args.mode,
            "confirmed": (resp == Gtk.ResponseType.OK),
            "reopen": reopen,
            "executed": did_execute,
            "prueba": bool(args.prueba),
            "seconds": int(args.seconds),
        }
        print(json.dumps(out, ensure_ascii=False))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
