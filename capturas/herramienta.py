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
    base = {"modo": "pantalla", "guardar_en": "", "destino": "carpeta", "temporizador": 0, "micro": "",
            "miniatura": True, "recordar": True}
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


# Save to de Catalina (Options): Desktop, Documents, [la carpeta escogida], Clipboard, Mail, Messages,
# Preview y Other Location… (al grabar: sin Clipboard, y QuickTime Player en lugar de Preview).
# Messages no existe aquí: sale en gris.
TEMPORALES = os.path.expanduser("~/.cache/mac-captura")


def carpeta_temporal():
    os.makedirs(TEMPORALES, exist_ok=True)
    return TEMPORALES


def entregar(destino, ruta):
    """Lo que se hace con el archivo cuando el destino no es una carpeta."""
    try:
        if destino == "clipboard":
            subprocess.run(["xclip", "-selection", "clipboard", "-t", "image/png", "-i", ruta],
                           timeout=10, check=True)
        elif destino == "mail":
            subprocess.Popen(["xdg-email", "--attach", ruta], start_new_session=True)
        elif destino == "preview":
            subprocess.Popen(["xdg-open", ruta], start_new_session=True)
    except Exception as e:
        print(f"No se pudo entregar la captura ({destino}): {e}", file=sys.stderr)


def capturar_ventana(wid, ruta):
    """Guarda la ventana con su canal alfa (import lo pierde y deja el margen transparente en negro).
    Si la ventana trae marco del gestor, se toma el marco; si dibuja su propia sombra con
    _GTK_FRAME_EXTENTS, se recorta. Devuelve True si la propia ventana ya trae una sombra o margen
    transparente en los bordes (entonces no se le añade la de la Mac)."""
    display = Gdk.Display.get_default()
    cliente = GdkX11.X11Window.foreign_new_for_display(display, int(wid))
    arriba, ox, oy = cliente, 0, 0
    padre = cliente.get_parent()
    if padre is not None and padre.get_window_type() != Gdk.WindowType.ROOT:
        arriba = padre
        ox, oy = cliente.get_position()
    izq, der, arr, aba = extensiones_gtk(wid)
    if any((izq, der, arr, aba)):
        x, y = ox + izq, oy + arr
        ancho, alto = cliente.get_width() - izq - der, cliente.get_height() - arr - aba
        arriba = padre if (ox or oy) else cliente
        pb = Gdk.pixbuf_get_from_window(arriba, x, y, ancho, alto)
    else:
        pb = Gdk.pixbuf_get_from_window(arriba, 0, 0, arriba.get_width(), arriba.get_height())
    if pb is None:
        raise RuntimeError("no se pudo leer la ventana")
    pb.savev(ruta, "png", [], [])
    if not pb.get_has_alpha():
        return False
    w, h, fila, canales, datos = pb.get_width(), pb.get_height(), pb.get_rowstride(), pb.get_n_channels(), pb.get_pixels()
    centros = [(w // 2, 0), (w // 2, h - 1), (0, h // 2), (w - 1, h // 2)]
    return any(datos[y * fila + x * canales + 3] < 250 for x, y in centros)


def con_sombra(ruta):
    """Como la captura de ventana de la Mac: sombra alrededor, en el canal alfa. Medida en una captura de
    Catalina (Screen Shot 1.31.45 PM): 56 px a los lados, 38 arriba, 74 abajo, alfa ~43 en el borde de la ventana."""
    subprocess.run(["convert", ruta, "(", "+clone", "-background", "black", "-shadow", "35x28+0+18", ")", "+swap",
                    "-background", "none", "-layers", "merge", "+repage", ruta], timeout=30, check=True)


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


def extensiones_gtk(xid):
    """(izq, der, arriba, abajo) de _GTK_FRAME_EXTENTS, o ceros si la ventana no dibuja sombra."""
    try:
        out = subprocess.run(["xprop", "-id", str(xid), "_GTK_FRAME_EXTENTS"],
                             capture_output=True, text=True, timeout=2).stdout
        if "=" in out:
            v = [int(n) for n in out.split("=", 1)[1].replace(",", " ").split()]
            if len(v) >= 4:
                return tuple(v[:4])
    except Exception:
        pass
    return (0, 0, 0, 0)


class Elegir(Gtk.Window):
    """Cursor de cámara: al pasar sobre una ventana (o la pantalla) se resalta; un clic la elige.
    Devuelve el id de la ventana ('root' para la pantalla) o None si se cancela con Esc."""

    def __init__(self, modo, alResolver, barra=None):
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
        if barra is None:
            self.get_display().get_default_seat().grab(gw, Gdk.SeatCapabilities.ALL, True, None, None, None)
        else:
            dejar_pasar_a_la_barra(self, barra)
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
                x, y, ancho, alto = r.x, r.y, r.width, r.height
                # Las ventanas que dibujan su propia sombra (GTK, Edge…) la incluyen en su geometría X
                # y lo avisan en _GTK_FRAME_EXTENTS: izquierda, derecha, arriba, abajo.
                izq, der, arr, aba = extensiones_gtk(w.get_xid())
                x, y, ancho, alto = x + izq, y + arr, ancho - izq - der, alto - arr - aba
                out.append((str(w.get_xid()) if hasattr(w, "get_xid") else None,
                            (x, y, ancho, alto), (izq, arr)))
            except Exception:
                continue
        return [o for o in out if o[0]]

    def _mover(self, _w, e):
        if self.modo == "ventana":
            x, y = e.x_root, e.y_root
            nuevo = None
            for wid, (rx, ry, rw, rh), sombra in self.ventanas:
                if rx <= x < rx + rw and ry <= y < ry + rh:
                    nuevo = ((wid, (rw, rh), sombra), (rx, ry, rw, rh))
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


# ── el marco de «Capture Selected Portion» y el hueco para la barra ─────────
def dejar_pasar_a_la_barra(ventana, barra):
    """La ventana a pantalla completa deja pasar los clics sobre la barra (y la barra sigue arriba)."""
    gw, gb = ventana.get_window(), barra.get_window()
    if not gw or not gb:
        return
    pant = ventana.get_screen()
    region = cairo.Region(cairo.RectangleInt(0, 0, pant.get_width(), pant.get_height()))
    r = gb.get_frame_extents()
    region.subtract(cairo.RectangleInt(r.x, r.y, r.width, r.height))
    gw.input_shape_combine_region(region, 0, 0)
    gb.raise_()
    ventana.hueco_barra = (r.x, r.y, r.width, r.height)


class Marco(Gtk.Window):
    """Como en la Mac: un marco ya puesto, que se mueve arrastrando por dentro y se ajusta por los
    bordes y las esquinas. El botón Capture toma lo que queda dentro (ver Barra._ejecutar)."""
    AGARRE = 9
    MINIMO = 40

    def __init__(self, rect, barra, alSalir):
        super().__init__(type=Gtk.WindowType.POPUP)
        self.barra = barra
        self.alSalir = alSalir
        scr = self.get_screen()
        if scr.get_rgba_visual():
            self.set_visual(scr.get_rgba_visual())
        self.set_app_paintable(True)
        self.set_decorated(False)
        self.set_keep_above(True)
        self.ancho, self.alto = scr.get_width(), scr.get_height()
        self.rect = list(rect)
        self.arrastre = None
        self.add_events(Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.BUTTON_RELEASE_MASK |
                        Gdk.EventMask.POINTER_MOTION_MASK)
        self.connect("draw", self._dibujar)
        self.connect("button-press-event", self._abajo)
        self.connect("motion-notify-event", self._mover)
        self.connect("button-release-event", self._arriba)
        self.move(0, 0)
        self.resize(self.ancho, self.alto)
        self.show_all()
        dejar_pasar_a_la_barra(self, barra)

    def get_rect(self):
        x, y, w, h = self.rect
        return (int(x), int(y), int(w), int(h))

    def _zona(self, px, py):
        x, y, w, h = self.rect
        g = self.AGARRE
        if not (x - g <= px <= x + w + g and y - g <= py <= y + h + g):
            return None
        izq, der = abs(px - x) <= g, abs(px - (x + w)) <= g
        arr, aba = abs(py - y) <= g, abs(py - (y + h)) <= g
        return (("n" if arr else "s" if aba else "") + ("w" if izq else "e" if der else "")) or "mover"

    def _cursor(self, zona):
        nombres = {"n": "ns-resize", "s": "ns-resize", "e": "ew-resize", "w": "ew-resize",
                   "nw": "nwse-resize", "se": "nwse-resize", "ne": "nesw-resize", "sw": "nesw-resize",
                   "mover": "move"}
        gw = self.get_window()
        if gw:
            gw.set_cursor(Gdk.Cursor.new_from_name(self.get_display(), nombres.get(zona, "default")))

    def _dibujar(self, _w, cr):
        x, y, w, h = self.rect
        cr.set_operator(cairo.OPERATOR_SOURCE)
        cr.set_source_rgba(0, 0, 0, 0.25)
        cr.paint()
        cr.set_source_rgba(0, 0, 0, 0.01)
        cr.rectangle(x, y, w, h)
        cr.fill()
        if getattr(self, "hueco_barra", None):      # la barra no se atenúa
            cr.set_source_rgba(0, 0, 0, 0)
            cr.rectangle(*self.hueco_barra)
            cr.fill()
        cr.set_operator(cairo.OPERATOR_OVER)
        cr.set_source_rgba(1, 1, 1, 0.95)
        cr.set_line_width(1)
        cr.rectangle(x + 0.5, y + 0.5, w, h)
        cr.stroke()
        for hx, hy in ((x, y), (x + w / 2, y), (x + w, y), (x, y + h / 2), (x + w, y + h / 2),
                       (x, y + h), (x + w / 2, y + h), (x + w, y + h)):
            cr.rectangle(hx - 3, hy - 3, 7, 7)
            cr.set_source_rgba(1, 1, 1, 1)
            cr.fill_preserve()
            cr.set_source_rgba(0, 0, 0, 0.5)
            cr.stroke()
        cr.set_source_rgba(1, 1, 1, 1)
        cr.set_font_size(12)
        cr.move_to(x + w + 6, y + h + 16)
        cr.show_text(f"{int(w)}×{int(h)}")
        return True

    def _abajo(self, _w, e):
        zona = self._zona(e.x_root, e.y_root)
        if zona and e.button == 1:
            self.arrastre = (zona, e.x_root, e.y_root, list(self.rect))

    def _mover(self, _w, e):
        if not self.arrastre:
            self._cursor(self._zona(e.x_root, e.y_root))
            return
        zona, px, py, r0 = self.arrastre
        dx, dy = e.x_root - px, e.y_root - py
        x, y, w, h = r0
        if zona == "mover":
            x = min(max(0, x + dx), self.ancho - w)
            y = min(max(0, y + dy), self.alto - h)
        else:
            if "w" in zona:
                nx = min(max(0, x + dx), x + w - self.MINIMO)
                w, x = w + (x - nx), nx
            if "e" in zona:
                w = min(max(self.MINIMO, w + dx), self.ancho - x)
            if "n" in zona:
                ny = min(max(0, y + dy), y + h - self.MINIMO)
                h, y = h + (y - ny), ny
            if "s" in zona:
                h = min(max(self.MINIMO, h + dy), self.alto - y)
        self.rect = [x, y, w, h]
        self.queue_draw()

    def _arriba(self, _w, _e):
        self.arrastre = None


# ── la barra ────────────────────────────────────────────────────────────────
# Qué pasa cuando la barra termina: suelto, el programa sale; dentro del ayudante
# residente (ayudante/ayudante.py) esto se cambia por una función que no hace nada.
SALIR = Gtk.main_quit


class Barra(Gtk.Window):
    def __init__(self):
        super().__init__(type=Gtk.WindowType.TOPLEVEL)
        self.cfg = cargar()
        if not self.cfg.get("recordar", True) or self.cfg["modo"] not in MODOS:
            self.cfg["modo"] = "pantalla"
        self.grabacion = None
        self.botones = {}
        self.marco = None           # el marco de «Selected Portion» mientras está puesto
        self.selector = None        # el cursor de cámara de «Selected Window»
        self.rect = None            # el último marco, para volver a ponerlo igual

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
        self.connect("destroy", lambda *_: SALIR())

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

        self._elegir(self.cfg["modo"], armar=False)
        self.show_all()
        pant = self.get_screen()
        self.move((pant.get_width() - self.get_allocated_width()) // 2, pant.get_height() - 150)
        GLib.idle_add(self._centrar)
        GLib.timeout_add(120, lambda: self._armar() or False)

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

    def _elegir(self, modo, armar=True):
        self.cfg["modo"] = modo
        for m, b in self.botones.items():
            ctx = b.get_style_context()
            ctx.add_class("elegido") if m == modo else ctx.remove_class("elegido")
        self.accion.set_label("Record" if modo.startswith("grabar") else "Capture")
        guardar(self.cfg)
        if getattr(self, "opciones", None) is not None:
            self.opciones.set_popup(self._menu())     # Save to cambia entre capturar y grabar
        if armar:
            self._armar()

    def _soltar_armado(self):
        if self.marco is not None:
            self.rect = self.marco.get_rect()
            self.marco.destroy()
            self.marco = None
        if self.selector is not None:
            self.selector.destroy()
            self.selector = None

    def _armar(self):
        """Lo que cada modo deja puesto antes de pulsar Capture, como en la Mac: la porción tiene su
        marco; la ventana, el cursor de cámara (se elige con un clic, sin usar Capture); la pantalla
        entera, nada: Capture la toma."""
        self._soltar_armado()
        modo = self.cfg["modo"]
        if modo in ("porcion", "grabar-porcion"):
            if self.rect is None:
                pant = self.get_screen()
                ancho, alto = pant.get_width() // 2, pant.get_height() // 2
                self.rect = (pant.get_width() // 4, pant.get_height() // 4, ancho, alto)
            self.marco = Marco(self.rect, self, self.destroy)
        elif modo == "ventana":
            self.selector = Elegir("ventana", self._tras_elegir_ventana, self)

    def destroy(self):
        self._soltar_armado()
        super().destroy()

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
        grabando = self.cfg["modo"].startswith("grabar")
        destino = self.cfg.get("destino", "carpeta")
        actual = self.cfg["guardar_en"] or escritorio()
        fijas = carpetas()[:2]               # Desktop y Documents
        for nombre, ruta in fijas:
            marca(nombre, destino == "carpeta" and ruta == actual, lambda r=ruta: self._carpeta_elegida(r))
        if actual not in [r for _n, r in fijas]:    # la carpeta escogida con Other Location…, como «SS» en la Mac
            marca(os.path.basename(actual.rstrip("/")) or actual, destino == "carpeta",
                  lambda r=actual: self._carpeta_elegida(r))
        if not grabando:
            marca("Clipboard", destino == "clipboard", lambda: self._set("destino", "clipboard"))
        marca("Mail", destino == "mail", lambda: self._set("destino", "mail"))
        mensajes = Gtk.CheckMenuItem(label="Messages")
        mensajes.set_sensitive(False)
        mensajes.set_draw_as_radio(False)
        menu.append(mensajes)
        marca("QuickTime Player" if grabando else "Preview", destino == "preview",
              lambda: self._set("destino", "preview"))
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

    def _carpeta_elegida(self, ruta):
        self.cfg["destino"] = "carpeta"
        self._set("guardar_en", ruta)

    def _otra_carpeta(self):
        d = Gtk.FileChooserDialog(title="Choose", parent=self, action=Gtk.FileChooserAction.SELECT_FOLDER)
        d.add_buttons("Cancel", Gtk.ResponseType.CANCEL, "Choose", Gtk.ResponseType.OK)
        if d.run() == Gtk.ResponseType.OK:
            self._carpeta_elegida(d.get_filename())
        d.destroy()
        self.opciones.set_popup(self._menu())

    # ── hacer la captura o la grabación ────────────────────────────────────
    def _ejecutar(self):
        """El botón Capture (o Record) hace la captura ya, con el modo escogido y el temporizador de Options."""
        modo = self.cfg["modo"]
        if modo == "ventana":
            return              # la ventana se elige con un clic, no con Capture (guía «Take a screenshot»)
        if modo in ("porcion", "grabar-porcion"):
            if self.marco is None:
                return
            self.rect = self.marco.get_rect()
            dato = self.rect
        else:
            dato = None
        self._soltar_armado()
        self.hide()
        self._con_temporizador(lambda: self._hacer(modo, dato))

    def _tras_elegir_ventana(self, wid):
        self.selector = None
        if wid is None:
            return
        self.hide()
        self._con_temporizador(lambda: self._hacer("ventana", wid))

    def _con_temporizador(self, fn):
        seg = int(self.cfg["temporizador"])
        GLib.timeout_add(max(seg, 0) * 1000 + 250, lambda: fn() or False)

    def _destino(self):
        d = self.cfg.get("destino", "carpeta")
        return "carpeta" if (d == "clipboard" and self.cfg["modo"].startswith("grabar")) else d

    def _carpeta(self):
        """Dónde se escribe el archivo: la carpeta escogida, o una temporal si va al portapapeles, al correo o a un visor."""
        if self._destino() != "carpeta":
            return carpeta_temporal()
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
            cmd = None
        else:
            x, y, w, h = dato
            cmd = ["import", "-window", "root", "-crop", f"{w}x{h}+{x}+{y}", "+repage", ruta]
        try:
            if modo == "ventana":
                if not capturar_ventana(dato[0], ruta):     # sin sombra propia: se le pone la de la Mac
                    con_sombra(ruta)
            else:
                subprocess.run(cmd, timeout=30, check=True)
        except Exception as e:
            print(f"No se pudo capturar: {e}", file=sys.stderr)
            self.destroy()
            return
        entregar(self._destino(), ruta)
        borrar = self._destino() == "clipboard"     # al portapapeles no se deja archivo
        if self.cfg.get("miniatura", True):
            self._miniatura(ruta, borrar)
        else:
            if borrar:
                try:
                    os.remove(ruta)
                except OSError:
                    pass
            self.destroy()

    def _miniatura(self, ruta, borrar=False):
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
        def fin(*_):
            if borrar:
                try:
                    os.remove(ruta)
                except OSError:
                    pass
            w.destroy()
            self.destroy()          # la barra (oculta); en el proceso suelto eso cierra el programa
        caja.connect("button-press-event", lambda *_: (subprocess.Popen(["xdg-open", ruta]), fin()))
        w.add(caja)
        w.show_all()
        w.move(scr.get_width() - w.get_allocated_width() - 20, scr.get_height() - w.get_allocated_height() - 40)
        GLib.timeout_add(5000, lambda: fin() or False)

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
        if self._destino() in ("preview", "mail"):
            entregar(self._destino(), ruta)     # QuickTime Player ↔ el reproductor predeterminado
        if self.cfg.get("miniatura", True):
            self.show_all()
            self.hide()
        self.destroy()


def main():
    Barra()
    Gtk.main()
    return 0


if __name__ == "__main__":
    sys.exit(main())
