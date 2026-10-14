#!/usr/bin/env python3
"""La herramienta de capturas de Catalina (⇧⌘5): una barra flotante abajo, al centro.

  ✕  pantalla entera · ventana · porción  |  grabar pantalla · grabar porción  |  Options ⌄  | Capture / Record

Medidas de la captura de José (Screen Shot 2026-10-14 at 12.08.04 AM, 409 × 76 con la sombra):
barra de unos 390 × 46, esquinas redondeadas, fondo oscuro translúcido, el botón elegido
resaltado. Los íconos van dibujados con cairo: ningún archivo de Apple.

Capturas con ImageMagick (import) y grabación con ffmpeg (x11grab); el archivo se llama como
en la Mac: «Screen Shot 2026-10-14 at 3.00.00 PM.png» y «Screen Recording … .mov».

Opciones (Options ⌄): Save to, Timer, Microphone, Show Floating Thumbnail, Remember Last
Selection. Se guardan en ~/.config/mac-captura/config.json.
"""
import json
import os
import signal
import subprocess
import sys
import time

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
gi.require_version("GdkX11", "3.0")
from gi.repository import Gdk, GdkX11, GLib, Gtk  # noqa: E402,F401
import cairo  # noqa: E402
import math  # noqa: E402

CONFIG = os.path.expanduser("~/.config/mac-captura/config.json")
MODOS = ["pantalla", "ventana", "porcion", "grabar-pantalla", "grabar-porcion"]
TIPS = {
    "pantalla": "Capture Entire Screen",
    "ventana": "Capture Selected Window",
    "porcion": "Capture Selected Portion",
    "grabar-pantalla": "Record Entire Screen",
    "grabar-porcion": "Record Selected Portion",
}

CSS = b"""
#barra {
  background-color: rgba(44, 44, 46, 0.94);
  border: 1px solid rgba(255, 255, 255, 0.14);
  border-radius: 10px;
}
.boton-modo { background: none; border: none; box-shadow: none; border-radius: 6px; padding: 0; min-width: 40px; min-height: 30px; }
.boton-modo:hover { background-color: rgba(255, 255, 255, 0.08); }
.boton-modo.elegido { background-color: rgba(255, 255, 255, 0.20); }
#cerrar { background: none; border: none; box-shadow: none; padding: 0; min-width: 22px; min-height: 22px; }
#opciones { background: none; border: none; box-shadow: none; color: #e6e6e6; font-family: ".SF NS"; font-size: 13px; padding: 4px 8px; }
#opciones:hover { background-color: rgba(255, 255, 255, 0.08); border-radius: 6px; }
#accion { background-image: none; background-color: #2f7bf5; color: white; font-family: ".SF NS"; font-size: 13px;
          border: none; border-radius: 6px; padding: 3px 14px; box-shadow: none; text-shadow: none; }
#accion:hover { background-color: #4a8df7; }
#separador { background-color: rgba(255, 255, 255, 0.18); min-width: 1px; }
#pildora { background-color: rgba(44, 44, 46, 0.94); border: 1px solid rgba(255, 255, 255, 0.14); border-radius: 12px; }
#miniatura { background-color: rgba(44, 44, 46, 0.94); border: 1px solid rgba(255, 255, 255, 0.14); border-radius: 6px; padding: 6px; }
"""


# ── configuración ───────────────────────────────────────────────────────────
def cargar():
    base = {"modo": "pantalla", "guardar_en": "", "temporizador": 0, "micro": "", "miniatura": True, "recordar": True}
    try:
        with open(CONFIG) as f:
            base.update(json.load(f))
    except Exception:
        pass
    return base


def guardar(cfg):
    try:
        os.makedirs(os.path.dirname(CONFIG), exist_ok=True)
        with open(CONFIG, "w") as f:
            json.dump(cfg, f, indent=2)
    except Exception:
        pass


def escritorio():
    d = ""
    try:
        d = subprocess.run(["xdg-user-dir", "DESKTOP"], capture_output=True, text=True).stdout.strip()
    except Exception:
        pass
    if not d or d.rstrip("/") == os.path.expanduser("~"):
        d = os.path.expanduser("~/Desktop")
    return d


def carpetas():
    home = os.path.expanduser("~")
    return [("Desktop", escritorio()), ("Documents", os.path.join(home, "Documents")),
            ("Downloads", os.path.join(home, "Downloads"))]


def nombre_libre(carpeta, prefijo, ext):
    """«Screen Shot 2026-10-14 at 3.00.00 PM.png»; si existe, « (2)», « (3)»… como la Mac."""
    os.makedirs(carpeta, exist_ok=True)
    base = time.strftime(f"{prefijo} %Y-%m-%d at ") + time.strftime("%-I.%M.%S %p")
    ruta, n = os.path.join(carpeta, f"{base}.{ext}"), 2
    while os.path.exists(ruta):
        ruta = os.path.join(carpeta, f"{base} ({n}).{ext}")
        n += 1
    return ruta


def micros():
    try:
        out = subprocess.run(["pactl", "list", "short", "sources"], capture_output=True, text=True, timeout=3).stdout
    except Exception:
        return []
    return [l.split("\t")[1] for l in out.splitlines() if len(l.split("\t")) > 1 and ".monitor" not in l]


# ── íconos dibujados ────────────────────────────────────────────────────────
def _rect_redondo(cr, x, y, w, h, r):
    cr.new_sub_path()
    cr.arc(x + w - r, y + r, r, -math.pi / 2, 0)
    cr.arc(x + w - r, y + h - r, r, 0, math.pi / 2)
    cr.arc(x + r, y + h - r, r, math.pi / 2, math.pi)
    cr.arc(x + r, y + r, r, math.pi, 3 * math.pi / 2)
    cr.close_path()


def dibujar_icono(cr, modo, w, h):
    cr.set_source_rgba(0.93, 0.93, 0.93, 1)
    cr.set_line_width(1.4)
    cx, cy = w / 2, h / 2
    if modo == "pantalla":
        _rect_redondo(cr, cx - 11, cy - 8, 22, 16, 3)
        cr.stroke()
    elif modo == "ventana":
        _rect_redondo(cr, cx - 11, cy - 8, 22, 16, 3)
        cr.stroke()
        cr.move_to(cx - 11, cy - 3.5)
        cr.line_to(cx + 11, cy - 3.5)
        cr.stroke()
        for i in range(3):
            cr.arc(cx - 8 + i * 3.2, cy - 5.8, 0.8, 0, 2 * math.pi)
            cr.fill()
    elif modo == "porcion":
        cr.set_dash([3, 2.4])
        _rect_redondo(cr, cx - 11, cy - 8, 22, 16, 2)
        cr.stroke()
        cr.set_dash([])
    elif modo in ("grabar-pantalla", "grabar-porcion"):
        if modo == "grabar-porcion":
            cr.set_dash([3, 2.4])
        _rect_redondo(cr, cx - 11, cy - 8, 22, 16, 3)
        cr.stroke()
        cr.set_dash([])
        cr.set_source_rgba(0.17, 0.17, 0.18, 1)
        cr.arc(cx + 8, cy + 6, 6, 0, 2 * math.pi)
        cr.fill()
        cr.set_source_rgba(0.93, 0.93, 0.93, 1)
        cr.arc(cx + 8, cy + 6, 5, 0, 2 * math.pi)
        cr.stroke()
        cr.arc(cx + 8, cy + 6, 2.4, 0, 2 * math.pi)
        cr.fill()
    elif modo == "cerrar":
        cr.set_source_rgba(0.55, 0.55, 0.57, 1)
        cr.arc(cx, cy, 7, 0, 2 * math.pi)
        cr.fill()
        cr.set_source_rgba(0.15, 0.15, 0.16, 1)
        cr.set_line_width(1.5)
        cr.move_to(cx - 2.6, cy - 2.6); cr.line_to(cx + 2.6, cy + 2.6)
        cr.move_to(cx + 2.6, cy - 2.6); cr.line_to(cx - 2.6, cy + 2.6)
        cr.stroke()


def area_icono(modo, ancho=40, alto=30):
    a = Gtk.DrawingArea()
    a.set_size_request(ancho, alto)
    a.connect("draw", lambda w, cr: dibujar_icono(cr, modo, w.get_allocated_width(), w.get_allocated_height()))
    return a


# ── selección de una porción con el ratón ───────────────────────────────────
class Seleccion(Gtk.Window):
    """Pantalla completa, atenuada: se arrastra un rectángulo. Devuelve (x, y, w, h) o None."""

    def __init__(self, alResolver):
        super().__init__(type=Gtk.WindowType.POPUP)
        self.alResolver = alResolver
        scr = self.get_screen()
        visual = scr.get_rgba_visual()
        if visual:
            self.set_visual(visual)
        self.set_app_paintable(True)
        self.set_decorated(False)
        self.set_keep_above(True)
        self.set_default_cursor = None
        self.ini = self.fin = None
        self.add_events(Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.BUTTON_RELEASE_MASK |
                        Gdk.EventMask.POINTER_MOTION_MASK | Gdk.EventMask.KEY_PRESS_MASK)
        self.connect("draw", self._dibujar)
        self.connect("button-press-event", self._abajo)
        self.connect("motion-notify-event", self._mover)
        self.connect("button-release-event", self._arriba)
        self.connect("key-press-event", self._tecla)
        ancho, alto = scr.get_width(), scr.get_height()
        self.move(0, 0)
        self.resize(ancho, alto)
        self.show_all()
        gw = self.get_window()
        gw.set_cursor(Gdk.Cursor.new_from_name(self.get_display(), "crosshair"))
        gw.focus(Gdk.CURRENT_TIME)
        seat = self.get_display().get_default_seat()
        seat.grab(gw, Gdk.SeatCapabilities.ALL, True, None, None, None)

    def _rect(self):
        if not self.ini or not self.fin:
            return None
        x0, y0 = self.ini
        x1, y1 = self.fin
        return (min(x0, x1), min(y0, y1), abs(x1 - x0), abs(y1 - y0))

    def _dibujar(self, _w, cr):
        cr.set_operator(cairo.OPERATOR_SOURCE)
        cr.set_source_rgba(0, 0, 0, 0.25)
        cr.paint()
        r = self._rect()
        if r and r[2] > 1 and r[3] > 1:
            cr.set_source_rgba(0, 0, 0, 0)
            cr.rectangle(*r)
            cr.fill()
            cr.set_operator(cairo.OPERATOR_OVER)
            cr.set_source_rgba(1, 1, 1, 0.9)
            cr.set_line_width(1)
            cr.rectangle(r[0] + 0.5, r[1] + 0.5, r[2], r[3])
            cr.stroke()
            cr.set_source_rgba(1, 1, 1, 1)
            cr.set_font_size(12)
            cr.move_to(r[0] + r[2] + 6, r[1] + r[3] + 14)
            cr.show_text(f"{r[2]}×{r[3]}")
        return True

    def _abajo(self, _w, e):
        self.ini = self.fin = (int(e.x_root), int(e.y_root))

    def _mover(self, _w, e):
        if self.ini:
            self.fin = (int(e.x_root), int(e.y_root))
            self.queue_draw()

    def _arriba(self, _w, e):
        if not self.ini:
            return
        self.fin = (int(e.x_root), int(e.y_root))
        r = self._rect()
        self._cerrar(r if r and r[2] > 2 and r[3] > 2 else None)

    def _tecla(self, _w, e):
        if e.keyval == Gdk.KEY_Escape:
            self._cerrar(None)

    def _cerrar(self, r):
        self.get_display().get_default_seat().ungrab()
        self.destroy()
        self.alResolver(r)


# ── pantalla / ventana: cursor de cámara y resaltado al pasar ───────────────
def cursor_camara(display):
    """Cámara fotográfica de 32 × 32 dibujada con cairo (punto activo en el centro)."""
    s = cairo.ImageSurface(cairo.FORMAT_ARGB32, 32, 32)
    cr = cairo.Context(s)

    def forma():
        _rect_redondo(cr, 3, 9, 26, 17, 3)
        cr.new_sub_path()
        cr.move_to(11, 9); cr.line_to(13, 5); cr.line_to(19, 5); cr.line_to(21, 9); cr.close_path()

    forma()
    cr.set_source_rgba(1, 1, 1, 1)
    cr.set_line_width(4)
    cr.stroke_preserve()
    cr.set_source_rgba(0.1, 0.1, 0.1, 1)
    cr.fill()
    cr.arc(16, 17.5, 5.5, 0, 2 * math.pi)
    cr.set_source_rgba(1, 1, 1, 1)
    cr.fill()
    cr.arc(16, 17.5, 3.2, 0, 2 * math.pi)
    cr.set_source_rgba(0.1, 0.1, 0.1, 1)
    cr.fill()
    return Gdk.Cursor.new_from_surface(display, s, 16, 17)


class Elegir(Gtk.Window):
    """Cursor de cámara: al pasar sobre una ventana (o la pantalla) se resalta; un clic la elige.
    Devuelve el id de la ventana ('root' para la pantalla) o None si se cancela con Esc."""

    def __init__(self, modo, alResolver):
        super().__init__(type=Gtk.WindowType.POPUP)
        self.modo = modo
        self.alResolver = alResolver
        scr = self.get_screen()
        if scr.get_rgba_visual():
            self.set_visual(scr.get_rgba_visual())
        self.set_app_paintable(True)
        self.set_decorated(False)
        self.set_keep_above(True)
        self.sel = None
        self.add_events(Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.POINTER_MOTION_MASK |
                        Gdk.EventMask.KEY_PRESS_MASK)
        self.connect("draw", self._dibujar)
        self.connect("motion-notify-event", self._mover)
        self.connect("button-press-event", self._clic)
        self.connect("key-press-event", self._tecla)
        self.ventanas = self._listar() if modo == "ventana" else []
        self.move(0, 0)
        self.resize(scr.get_width(), scr.get_height())
        self.show_all()
        gw = self.get_window()
        gw.set_cursor(cursor_camara(self.get_display()))
        gw.focus(Gdk.CURRENT_TIME)
        self.get_display().get_default_seat().grab(gw, Gdk.SeatCapabilities.ALL, True, None, None, None)
        if modo == "pantalla":
            self.sel = ("root", (0, 0, scr.get_width(), scr.get_height()))

    def _listar(self):
        """Ventanas visibles de arriba hacia abajo: (id, (x, y, w, h)) con marco."""
        out = []
        for w in reversed(self.get_screen().get_window_stack() or []):
            try:
                if not w.is_visible() or w.get_state() & Gdk.WindowState.ICONIFIED:
                    continue
                if w.get_type_hint() in (Gdk.WindowTypeHint.DESKTOP, Gdk.WindowTypeHint.DOCK):
                    continue
                r = w.get_frame_extents()
                out.append((str(w.get_xid()) if hasattr(w, "get_xid") else None, (r.x, r.y, r.width, r.height)))
            except Exception:
                continue
        return [o for o in out if o[0]]

    def _mover(self, _w, e):
        if self.modo == "ventana":
            x, y = e.x_root, e.y_root
            nuevo = None
            for wid, (rx, ry, rw, rh) in self.ventanas:
                if rx <= x < rx + rw and ry <= y < ry + rh:
                    nuevo = (wid, (rx, ry, rw, rh))
                    break
            if nuevo != self.sel:
                self.sel = nuevo
                self.queue_draw()

    def _dibujar(self, _w, cr):
        cr.set_operator(cairo.OPERATOR_SOURCE)
        cr.set_source_rgba(0, 0, 0, 0.01)
        cr.paint()
        if self.sel:
            x, y, w, h = self.sel[1]
            cr.set_operator(cairo.OPERATOR_OVER)
            cr.set_source_rgba(0.25, 0.5, 0.95, 0.35)
            cr.rectangle(x, y, w, h)
            cr.fill()
        return True

    def _clic(self, _w, e):
        if e.button == 1 and self.sel:
            self._cerrar(self.sel[0])
        elif e.button != 1:
            self._cerrar(None)

    def _tecla(self, _w, e):
        if e.keyval == Gdk.KEY_Escape:
            self._cerrar(None)

    def _cerrar(self, r):
        self.get_display().get_default_seat().ungrab()
        self.destroy()
        self.alResolver(r)


# ── la barra ────────────────────────────────────────────────────────────────
class Barra(Gtk.Window):
    def __init__(self):
        super().__init__(type=Gtk.WindowType.TOPLEVEL)
        self.cfg = cargar()
        if not self.cfg.get("recordar", True) or self.cfg["modo"] not in MODOS:
            self.cfg["modo"] = "pantalla"
        self.grabacion = None
        self.botones = {}

        prov = Gtk.CssProvider()
        prov.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(self.get_screen(), prov, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 1)
        scr = self.get_screen()
        if scr.get_rgba_visual():
            self.set_visual(scr.get_rgba_visual())
        self.set_app_paintable(True)
        self.set_decorated(False)
        self.set_keep_above(True)
        self.set_skip_taskbar_hint(True)
        self.set_type_hint(Gdk.WindowTypeHint.DOCK)
        self.set_title("Screenshot")
        self.connect("key-press-event", self._tecla)
        self.connect("destroy", Gtk.main_quit)

        fila = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=2)
        fila.set_name("barra")
        fila.set_margin_top(14); fila.set_margin_bottom(14); fila.set_margin_start(14); fila.set_margin_end(14)
        fila.get_style_context()
        self.add(fila)

        cerrar = Gtk.Button()
        cerrar.set_name("cerrar")
        cerrar.add(area_icono("cerrar", 22, 22))
        cerrar.set_margin_start(8); cerrar.set_margin_end(6)
        cerrar.connect("clicked", lambda *_: self.destroy())
        fila.pack_start(cerrar, False, False, 0)

        for m in MODOS:
            if m == "grabar-pantalla":
                fila.pack_start(self._separador(), False, False, 8)
            b = Gtk.Button()
            b.get_style_context().add_class("boton-modo")
            b.add(area_icono(m))
            b.set_tooltip_text(TIPS[m])
            b.connect("clicked", lambda _b, mm=m: self._elegir(mm))
            self.botones[m] = b
            fila.pack_start(b, False, False, 0)
        fila.pack_start(self._separador(), False, False, 8)

        self.opciones = Gtk.MenuButton()
        self.opciones.set_name("opciones")
        self.opciones.set_label("Options ⌄")
        self.opciones.set_popup(self._menu())
        fila.pack_start(self.opciones, False, False, 0)
        fila.pack_start(self._separador(), False, False, 8)

        self.accion = Gtk.Button(label="Capture")
        self.accion.set_name("accion")
        self.accion.set_margin_end(8)
        self.accion.connect("clicked", lambda *_: self._ejecutar())
        fila.pack_start(self.accion, False, False, 0)

        self._elegir(self.cfg["modo"])
        self.show_all()
        pant = self.get_screen()
        self.move((pant.get_width() - self.get_allocated_width()) // 2, pant.get_height() - 150)
        GLib.idle_add(self._centrar)

    def _centrar(self):
        pant = self.get_screen()
        a = self.get_allocated_width()
        self.move((pant.get_width() - a) // 2, pant.get_height() - 150)
        return False

    @staticmethod
    def _separador():
        s = Gtk.Box()
        s.set_name("separador")
        s.set_margin_top(8); s.set_margin_bottom(8)
        return s

    def _elegir(self, modo):
        self.cfg["modo"] = modo
        for m, b in self.botones.items():
            ctx = b.get_style_context()
            ctx.add_class("elegido") if m == modo else ctx.remove_class("elegido")
        self.accion.set_label("Record" if modo.startswith("grabar") else "Capture")
        guardar(self.cfg)

    def _tecla(self, _w, e):
        if e.keyval == Gdk.KEY_Escape:
            self.destroy()
            return True
        if e.keyval in (Gdk.KEY_Return, Gdk.KEY_KP_Enter):
            self._ejecutar()
            return True
        return False

    # ── el menú Options ────────────────────────────────────────────────────
    def _menu(self):
        menu = Gtk.Menu()

        def titulo(t):
            i = Gtk.MenuItem(label=t)
            i.set_sensitive(False)
            menu.append(i)

        def marca(texto, activo, cb):
            i = Gtk.CheckMenuItem(label=texto)
            i.set_active(activo)
            i.set_draw_as_radio(False)
            i.connect("toggled", lambda it: it.get_active() and cb())
            menu.append(i)

        titulo("Save to")
        actual = self.cfg["guardar_en"] or escritorio()
        for nombre, ruta in carpetas():
            marca(nombre, ruta == actual, lambda r=ruta: self._set("guardar_en", r))
        otra = Gtk.MenuItem(label="Other Location…")
        otra.connect("activate", lambda *_: self._otra_carpeta())
        menu.append(otra)
        menu.append(Gtk.SeparatorMenuItem())
        titulo("Timer")
        for texto, seg in (("None", 0), ("5 Seconds", 5), ("10 Seconds", 10)):
            marca(texto, self.cfg["temporizador"] == seg, lambda s=seg: self._set("temporizador", s))
        menu.append(Gtk.SeparatorMenuItem())
        titulo("Microphone")
        marca("None", not self.cfg["micro"], lambda: self._set("micro", ""))
        for fuente in micros():
            marca(fuente, self.cfg["micro"] == fuente, lambda f=fuente: self._set("micro", f))
        menu.append(Gtk.SeparatorMenuItem())
        titulo("Options")
        for clave, texto in (("miniatura", "Show Floating Thumbnail"), ("recordar", "Remember Last Selection")):
            i = Gtk.CheckMenuItem(label=texto)
            i.set_active(bool(self.cfg.get(clave)))
            i.connect("toggled", lambda it, k=clave: self._set(k, it.get_active()))
            menu.append(i)
        menu.show_all()
        return menu

    def _set(self, clave, valor):
        self.cfg[clave] = valor
        guardar(self.cfg)

    def _otra_carpeta(self):
        d = Gtk.FileChooserDialog(title="Choose", parent=self, action=Gtk.FileChooserAction.SELECT_FOLDER)
        d.add_buttons("Cancel", Gtk.ResponseType.CANCEL, "Choose", Gtk.ResponseType.OK)
        if d.run() == Gtk.ResponseType.OK:
            self._set("guardar_en", d.get_filename())
            self.opciones.set_popup(self._menu())
        d.destroy()

    # ── hacer la captura o la grabación ────────────────────────────────────
    def _ejecutar(self):
        modo = self.cfg["modo"]
        self.hide()
        if modo in ("porcion", "grabar-porcion"):
            GLib.timeout_add(150, lambda: Seleccion(lambda r: self._tras_seleccion(modo, r)) and False)
        elif modo in ("ventana", "pantalla"):
            GLib.timeout_add(150, lambda: Elegir(modo, lambda w: self._tras_elegir(modo, w)) and False)
        else:
            self._con_temporizador(lambda: self._hacer(modo, None))

    def _tras_elegir(self, modo, wid):
        if wid is None:
            self.show()
            return
        self._con_temporizador(lambda: self._hacer(modo, wid))

    def _tras_seleccion(self, modo, r):
        if r is None:
            self.show()
            return
        self._con_temporizador(lambda: self._hacer(modo, r))

    def _con_temporizador(self, fn):
        seg = int(self.cfg["temporizador"])
        GLib.timeout_add(max(seg, 0) * 1000 + 250, lambda: fn() or False)

    def _carpeta(self):
        return self.cfg["guardar_en"] or escritorio()

    def _hacer(self, modo, dato):
        carpeta = self._carpeta()
        if modo.startswith("grabar"):
            self._grabar(carpeta, dato)
            return
        ruta = nombre_libre(carpeta, "Screen Shot", "png")
        if modo == "pantalla":
            cmd = ["import", "-window", "root", ruta]
        elif modo == "ventana":
            cmd = ["import", "-frame", "-window", str(dato), ruta]
        else:
            x, y, w, h = dato
            cmd = ["import", "-window", "root", "-crop", f"{w}x{h}+{x}+{y}", "+repage", ruta]
        try:
            subprocess.run(cmd, timeout=30, check=True)
        except Exception as e:
            print(f"No se pudo capturar: {e}", file=sys.stderr)
            Gtk.main_quit()
            return
        if self.cfg.get("miniatura", True):
            self._miniatura(ruta)
        else:
            Gtk.main_quit()

    def _miniatura(self, ruta):
        w = Gtk.Window(type=Gtk.WindowType.POPUP)
        scr = w.get_screen()
        if scr.get_rgba_visual():
            w.set_visual(scr.get_rgba_visual())
        w.set_app_paintable(True)
        caja = Gtk.EventBox()
        caja.set_name("miniatura")
        from gi.repository import GdkPixbuf
        try:
            pb = GdkPixbuf.Pixbuf.new_from_file_at_scale(ruta, 160, 100, True)
            caja.add(Gtk.Image.new_from_pixbuf(pb))
        except Exception:
            caja.add(Gtk.Label(label=os.path.basename(ruta)))
        caja.connect("button-press-event", lambda *_: (subprocess.Popen(["xdg-open", ruta]), Gtk.main_quit()))
        w.add(caja)
        w.show_all()
        w.move(scr.get_width() - w.get_allocated_width() - 20, scr.get_height() - w.get_allocated_height() - 40)
        GLib.timeout_add(5000, Gtk.main_quit)

    def _grabar(self, carpeta, region):
        ruta = nombre_libre(carpeta, "Screen Recording", "mov")
        scr = self.get_screen()
        if region is None:
            x, y, w, h = 0, 0, scr.get_width(), scr.get_height()
        else:
            x, y, w, h = region
        w -= w % 2
        h -= h % 2
        cmd = ["ffmpeg", "-y", "-loglevel", "error", "-f", "x11grab", "-framerate", "30",
               "-video_size", f"{w}x{h}", "-i", f"{os.environ.get('DISPLAY', ':0')}+{x},{y}"]
        if self.cfg["micro"]:
            cmd += ["-f", "pulse", "-i", self.cfg["micro"]]
        cmd += ["-c:v", "libx264", "-preset", "ultrafast", "-pix_fmt", "yuv420p"]
        if self.cfg["micro"]:
            cmd += ["-c:a", "aac"]
        cmd += [ruta]
        self.grabacion = subprocess.Popen(cmd, stdin=subprocess.PIPE)
        self._pildora(ruta)

    def _pildora(self, ruta):
        """El botón de parar, abajo al centro (en la Mac es un ícono de la barra de menú)."""
        w = Gtk.Window(type=Gtk.WindowType.POPUP)
        scr = w.get_screen()
        if scr.get_rgba_visual():
            w.set_visual(scr.get_rgba_visual())
        w.set_app_paintable(True)
        b = Gtk.Button(label="■  Stop Recording")
        b.set_name("accion")
        caja = Gtk.Box()
        caja.set_name("pildora")
        caja.set_margin_top(6); caja.set_margin_bottom(6); caja.set_margin_start(6); caja.set_margin_end(6)
        caja.pack_start(b, True, True, 4)
        w.add(caja)
        w.show_all()
        w.move((scr.get_width() - w.get_allocated_width()) // 2, scr.get_height() - 90)
        b.connect("clicked", lambda *_: self._parar(w, ruta))

    def _parar(self, w, ruta):
        if self.grabacion and self.grabacion.poll() is None:
            try:
                self.grabacion.stdin.write(b"q")
                self.grabacion.stdin.flush()
            except Exception:
                self.grabacion.send_signal(signal.SIGINT)
            try:
                self.grabacion.wait(timeout=10)
            except Exception:
                self.grabacion.kill()
        w.destroy()
        if self.cfg.get("miniatura", True):
            self.show_all()
            self.hide()
        Gtk.main_quit()


def main():
    Barra()
    Gtk.main()
    return 0


if __name__ == "__main__":
    sys.exit(main())
