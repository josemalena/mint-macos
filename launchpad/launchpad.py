#!/usr/bin/python3
"""Launchpad de Catalina para Cinnamon.

Muestra el contenido de /Applications (los lanzadores que arma aplicaciones.py)
en pantalla completa, sobre el fondo de escritorio desenfocado y oscurecido:
buscador arriba al centro, rejilla paginada con puntos de página abajo, el
nombre debajo de cada ícono y la carpeta «Other» con lo de Utilities.

Todas las medidas salen de las capturas de Catalina de José (14-10-2026,
«Screen Shot 2026-10-14 at 1.05.32 PM» y siguientes, de 1920×1200: 1 px = 1 px)
y se escalan con el tamaño de la pantalla. Los glifos del buscador son los de
Apple (SearchMagGlass y Cancel), sacados de la Mac por tema/iconos/finder.py.

    mac-launchpad              abre (o esconde, si ya está abierto); si no hay proceso, lo arma
    mac-launchpad --residente  se arma oculto (lo arranca la sesión) y espera el atajo
    mac-launchpad --lista  lo que mostraría, sin abrir nada
    Esc                    borra la búsqueda, cierra la carpeta o cierra
"""
import hashlib
import math
import os
import sys
import time

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
gi.require_version("GdkPixbuf", "2.0")
gi.require_version("Pango", "1.0")
gi.require_version("PangoCairo", "1.0")
from gi.repository import Gdk, GdkPixbuf, Gio, GLib, Gtk, Pango, PangoCairo  # noqa: E402

import cairo  # noqa: E402

DESTINO = os.environ.get("LAUNCHPAD_DESTINO", "/Applications")
GLIFOS = os.path.expanduser("~/.local/share/constanza/glifos-finder")
CACHE = os.path.expanduser("~/.cache/mint-macos")
APP_ID = "io.github.josemalena.MintMacosLaunchpad"
FUENTE = ".SF NS"

# ── medidas de la captura de Catalina (pantalla de 1920×1200) ────────────────
REF_W, REF_H = 1920, 1200
COLUMNAS, FILAS = 7, 5            # 35 por página
ICONO = 112                       # lado del ícono
PASO_X, PASO_Y = 215, 193         # de una celda a la siguiente
COL0_X = 312                      # centro de la primera columna
FILA0_Y = 98                      # arriba del ícono de la primera fila
ETIQUETA_Y = 135                  # del tope del ícono a la línea base del nombre (98 → 232 en la captura)
ETIQUETA_PX = 13.5
CELDA_SEL = (233, 75, 158, 171)   # el resaltado del primer resultado (x, y, ancho, alto)
BUSCADOR = (835, 29, 250, 23)     # x, y, ancho, alto
PUNTOS_Y, PUNTO_D, PUNTO_PASO = 1066.5, 8, 20
CARPETA = 124                     # el cuadro de la carpeta en la rejilla
CARPETA_RADIO = 11
MINI, MINI_PASO, MINI_X, MINI_Y = 26, 34, 16, 13
PANEL_X, PANEL_ANCHO = 185, 1550  # la carpeta abierta
PANEL_ARRIBA, PANEL_PRIMERA, PANEL_ABAJO = 70, 70, 24
PANEL_RADIO = 28
PANEL_FILAS = 3                   # una carpeta muestra hasta 3 filas (21) por página
TITULO_PX = 26

# El fondo: gaussiano de ~30 px y, por canal, y = a·x + k sobre el fondo de escritorio
# (ajustado por mínimos cuadrados contra la captura, error medio 1.6 de 255).
FONDO_BLUR = 30
FONDO_A = (0.344, 0.499, 0.649)
FONDO_K = (9.3, 14.4, 14.9)


def _quitar_sufijo(n):
    return n[:-4] if n.lower().endswith(".app") else n


class App:
    def __init__(self, info, ruta):
        self.info = info
        self.ruta = ruta
        self.nombre = _quitar_sufijo(info.get_name() or os.path.basename(ruta))
        self.clave = self.nombre.casefold()
        self.palabras = _palabras(self.nombre)
        self.icono = None            # superficie cairo, se carga al pintar
        self.mini = None

    def lanzar(self):
        try:
            self.info.launch([], Gdk.Display.get_default().get_app_launch_context())
        except GLib.Error as e:
            print(f"No se pudo abrir {self.nombre}: {e}", file=sys.stderr)


class Carpeta:
    def __init__(self, nombre, apps):
        self.nombre = nombre
        self.apps = apps
        self.clave = nombre.casefold()


def _palabras(nombre):
    """Las palabras de un nombre, partiendo también «ColorSync» en Color y Sync."""
    out, actual = [], ""
    for i, c in enumerate(nombre):
        corte = not c.isalnum() or (c.isupper() and actual and actual[-1].islower())
        if corte and actual:
            out.append(actual.casefold())
            actual = ""
        if c.isalnum():
            actual += c
    if actual:
        out.append(actual.casefold())
    return out


def leer_carpeta(ruta):
    apps = []
    try:
        nombres = sorted(os.listdir(ruta))
    except OSError:
        return apps
    for n in nombres:
        if not n.endswith(".desktop"):
            continue
        p = os.path.join(ruta, n)
        if n in ("launchpad.desktop", "mint-macos-launchpad.desktop"):
            continue
        info = Gio.DesktopAppInfo.new_from_filename(p)
        if info is None or info.get_nodisplay():
            continue
        apps.append(App(info, p))
    apps.sort(key=lambda a: a.clave)
    return apps


def leer_aplicaciones():
    """Los elementos de la rejilla: las apps de /Applications en orden de nombre y,
    al final, la carpeta Other con las de Utilities."""
    arriba = leer_carpeta(DESTINO)
    util = leer_carpeta(os.path.join(DESTINO, "Utilities"))
    elementos = list(arriba)
    if util:
        elementos.append(Carpeta("Other", util))
    return elementos, arriba + util


def buscar(todas, q):
    q = q.strip().casefold()
    if not q:
        return []
    prim, resto = [], []
    for a in todas:
        if a.clave.startswith(q):
            prim.append(a)
        elif any(p.startswith(q) for p in a.palabras) or (" " in q and q in a.clave):
            resto.append(a)
    return prim + resto


# ── fondo ────────────────────────────────────────────────────────────────────
def fondo_de_escritorio():
    if os.environ.get("LAUNCHPAD_FONDO"):      # para las pruebas
        return os.environ["LAUNCHPAD_FONDO"]
    try:
        uri = Gio.Settings.new("org.cinnamon.desktop.background").get_string("picture-uri")
    except Exception:  # noqa: BLE001
        return None
    return Gio.File.new_for_uri(uri).get_path() if uri else None


def construir_fondo(ancho, alto):
    """La imagen de fondo: el escritorio desenfocado y oscurecido con la receta medida.
    Se guarda en caché por archivo, fecha y tamaño. None si no hay con qué hacerla."""
    ruta = fondo_de_escritorio()
    if not ruta or not os.path.exists(ruta):
        return None
    sello = f"{ruta}|{os.path.getmtime(ruta)}|{ancho}x{alto}|{FONDO_BLUR}|{FONDO_A}|{FONDO_K}"
    cache = os.path.join(CACHE, "launchpad-fondo-" + hashlib.sha1(sello.encode()).hexdigest()[:16] + ".png")
    if os.path.exists(cache):
        return cache
    try:
        import numpy as np
        from PIL import Image, ImageFilter
        im = Image.open(ruta).convert("RGB")
        # «cover»: llena la pantalla sin deformar
        esc = max(ancho / im.width, alto / im.height)
        im = im.resize((max(ancho, round(im.width * esc)), max(alto, round(im.height * esc))), Image.LANCZOS)
        x0, y0 = (im.width - ancho) // 2, (im.height - alto) // 2
        im = im.crop((x0, y0, x0 + ancho, y0 + alto))
        k = ancho / REF_W
        # se desenfoca en pequeño (es más rápido y el resultado es el mismo)
        chico = im.resize((ancho // 4, alto // 4), Image.LANCZOS).filter(ImageFilter.GaussianBlur(FONDO_BLUR * k / 4))
        a = np.asarray(chico.resize((ancho, alto), Image.BICUBIC)).astype(float)
        a = a * np.array(FONDO_A) + np.array(FONDO_K)
        os.makedirs(CACHE, exist_ok=True)
        Image.fromarray(np.clip(a, 0, 255).astype("uint8")).save(cache)
        return cache
    except Exception as e:  # noqa: BLE001
        print(f"Sin fondo desenfocado: {e}", file=sys.stderr)
        return None


# ── la ventana ───────────────────────────────────────────────────────────────
def superficie_de(pb):
    sup = cairo.ImageSurface(cairo.FORMAT_ARGB32, pb.get_width(), pb.get_height())
    cr = cairo.Context(sup)
    Gdk.cairo_set_source_pixbuf(cr, pb, 0, 0)
    cr.paint()
    return sup


def icono_de(app, lado):
    tema = Gtk.IconTheme.get_default()
    ic = app.info.get_icon()
    pb = None
    try:
        if isinstance(ic, Gio.ThemedIcon):
            for n in ic.get_names() + ["application-x-executable"]:
                if tema.has_icon(n):
                    pb = tema.load_icon(n, lado, Gtk.IconLookupFlags.FORCE_SIZE)
                    break
        elif isinstance(ic, Gio.FileIcon):
            pb = GdkPixbuf.Pixbuf.new_from_file_at_size(ic.get_file().get_path(), lado, lado)
        if pb is None:
            pb = tema.load_icon("application-x-executable", lado, Gtk.IconLookupFlags.FORCE_SIZE)
    except GLib.Error:
        return None
    return superficie_de(pb)


def glifo(nombre):
    for esc in ("@2x", "@1x"):
        try:
            pb = GdkPixbuf.Pixbuf.new_from_file(os.path.join(GLIFOS, nombre + esc + ".png"))
            return superficie_de(pb), (2 if esc == "@2x" else 1)
        except GLib.Error:
            continue
    return None, 1


def rect_redondo(cr, x, y, w, h, r):
    r = min(r, w / 2, h / 2)
    cr.new_sub_path()
    cr.arc(x + w - r, y + r, r, -math.pi / 2, 0)
    cr.arc(x + w - r, y + h - r, r, 0, math.pi / 2)
    cr.arc(x + r, y + h - r, r, math.pi / 2, math.pi)
    cr.arc(x + r, y + r, r, math.pi, 3 * math.pi / 2)
    cr.close_path()


class Ventana(Gtk.Window):
    def __init__(self, app):
        super().__init__(application=app, title="Launchpad")
        self.set_app_paintable(True)
        self.set_decorated(False)
        self.set_skip_taskbar_hint(True)
        self.set_skip_pager_hint(True)
        self.set_keep_above(True)
        self.set_role("launchpad")
        self.fullscreen()

        pant = Gdk.Display.get_default().get_primary_monitor() or Gdk.Display.get_default().get_monitor(0)
        geo = pant.get_geometry()
        self.W, self.H = geo.width, geo.height
        if os.environ.get("LAUNCHPAD_TAM"):       # para las pruebas: pintar a otro tamaño
            self.W, self.H = (int(v) for v in os.environ["LAUNCHPAD_TAM"].split("x"))
        self.esc = min(self.W / REF_W, self.H / REF_H)
        self.dx = (self.W - REF_W * self.esc) / 2     # centrado si la pantalla no es 16:10
        self.elementos, self.todas = leer_aplicaciones()
        self.por_pagina = COLUMNAS * FILAS
        self.paginas = max(1, math.ceil(len(self.elementos) / self.por_pagina))
        self.pagina = 0
        self.pos = 0.0                  # página mostrada (con animación)
        self.consulta = ""
        self.sel = 0                    # resultado resaltado
        self.carpeta = None             # Carpeta abierta
        self.pag_carpeta = 0
        self.t0 = time.monotonic()
        self.arrastre = None
        self.scroll_acum = 0.0
        self.scroll_hasta = 0.0
        self.cierra = False

        ruta = construir_fondo(self.W, self.H)
        self.fondo = None
        if ruta:
            try:
                self.fondo = cairo.ImageSurface.create_from_png(ruta)
            except Exception:  # noqa: BLE001
                self.fondo = None
        self.lupa, self.lupa_esc = glifo("SearchMagGlass")
        self.borrar, self.borrar_esc = glifo("Cancel")

        self.add_events(Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.BUTTON_RELEASE_MASK
                        | Gdk.EventMask.POINTER_MOTION_MASK | Gdk.EventMask.KEY_PRESS_MASK
                        | Gdk.EventMask.SCROLL_MASK | Gdk.EventMask.SMOOTH_SCROLL_MASK)
        self.connect("draw", self.al_pintar)
        self.connect("key-press-event", self.al_tecla)
        self.connect("button-press-event", self.al_pulsar)
        self.connect("button-release-event", self.al_soltar)
        self.connect("motion-notify-event", self.al_mover)
        self.connect("scroll-event", self.al_scroll)
        self.add_tick_callback(self._cuadro)
        self.ruta_fondo = ruta
        self.sello = self._sello_apps()

    # ── residente: se arma una vez y se muestra y oculta ─────────────────
    @staticmethod
    def _sello_apps():
        """Qué hay hoy en /Applications y en Utilities (nombre y fecha de cada lanzador)."""
        sello = []
        for d in (DESTINO, os.path.join(DESTINO, "Utilities")):
            try:
                with os.scandir(d) as it:
                    sello.extend((e.path, e.stat().st_mtime_ns) for e in it if e.name.endswith(".desktop"))
            except OSError:
                pass
        return sorted(sello)

    def precalentar(self):
        """Pinta un cuadro fuera de pantalla para que los íconos queden cargados antes del primer atajo."""
        t0 = self.t0
        self.t0 -= 10
        sup = cairo.ImageSurface(cairo.FORMAT_ARGB32, self.W, self.H)
        self.al_pintar(self, cairo.Context(sup))
        self.t0 = t0

    def mostrar(self):
        """Lo deja como recién abierto (página 1, sin búsqueda, sin carpeta) y lo enseña."""
        sello = self._sello_apps()
        if sello != self.sello:                      # se instaló o quitó una app
            self.sello = sello
            self.elementos, self.todas = leer_aplicaciones()
            self.paginas = max(1, math.ceil(len(self.elementos) / self.por_pagina))
        ruta = construir_fondo(self.W, self.H)       # de caché; cambia si cambió el escritorio
        if ruta != self.ruta_fondo:
            self.ruta_fondo = ruta
            try:
                self.fondo = cairo.ImageSurface.create_from_png(ruta) if ruta else None
            except Exception:  # noqa: BLE001
                self.fondo = None
        self.pagina, self.pos = 0, 0.0
        self.consulta, self.sel = "", 0
        self.carpeta, self.pag_carpeta = None, 0
        self.arrastre = None
        self.scroll_acum = self.scroll_hasta = 0.0
        self.cierra = False
        self.t0 = time.monotonic()
        self.show_all()
        self.present_with_time(Gdk.CURRENT_TIME)

    def ocultar(self):
        self.hide()

    # ── geometría ────────────────────────────────────────────────────────
    def px(self, v):
        return v * self.esc

    def celda(self, i, y_primera=None):
        """(centro x, arriba del ícono) de la posición i de una página."""
        col, fila = i % COLUMNAS, i // COLUMNAS
        cx = self.dx + self.px(COL0_X + col * PASO_X)
        y = self.px((FILA0_Y if y_primera is None else y_primera) + fila * PASO_Y)
        return cx, y

    def pagina_de(self, elems):
        return [elems[i:i + self.por_pagina] for i in range(0, len(elems), self.por_pagina)] or [[]]

    # ── animación ────────────────────────────────────────────────────────
    def _cuadro(self, _w, _clock):
        mover = abs(self.pos - self.pagina) > 0.001
        if mover:
            self.pos += (self.pagina - self.pos) * 0.22
            if abs(self.pos - self.pagina) < 0.002:
                self.pos = float(self.pagina)
        if mover or time.monotonic() - self.t0 < 0.3:
            self.queue_draw()
        return GLib.SOURCE_CONTINUE

    # ── pintar ───────────────────────────────────────────────────────────
    def al_pintar(self, _w, cr):
        alfa = min(1.0, (time.monotonic() - self.t0) / 0.18)
        if self.fondo is not None:
            cr.set_source_surface(self.fondo, 0, 0)
            cr.paint()
        else:
            cr.set_source_rgb(0.05, 0.12, 0.25)
            cr.paint()
        cr.push_group()
        if self.carpeta is not None:
            self.pintar_carpeta(cr)
        else:
            self.pintar_buscador(cr)
            if self.consulta:
                self.pintar_resultados(cr)
            else:
                self.pintar_paginas(cr)
                if self.paginas > 1:
                    self.pintar_puntos(cr)
        cr.pop_group_to_source()
        cr.paint_with_alpha(alfa)
        return False

    def texto(self, cr, s, cx, y, px, color=(1, 1, 1, 1), ancho=None, peso=300, sombra=True, alineado="centro"):
        lay = PangoCairo.create_layout(cr)
        fd = Pango.FontDescription(FUENTE)
        fd.set_absolute_size(px * Pango.SCALE)
        fd.set_weight(peso)
        lay.set_font_description(fd)
        lay.set_text(s, -1)
        if ancho:
            lay.set_width(int(ancho * Pango.SCALE))
            lay.set_ellipsize(Pango.EllipsizeMode.END)
        w, h = lay.get_pixel_size()
        x = cx - w / 2 if alineado == "centro" else cx
        base = lay.get_baseline() / Pango.SCALE
        top = y - base
        if sombra:
            cr.move_to(x, top + 1)
            cr.set_source_rgba(0, 0, 0, 0.45 * color[3])
            PangoCairo.show_layout(cr, lay)
        cr.move_to(x, top)
        cr.set_source_rgba(*color)
        PangoCairo.show_layout(cr, lay)
        return w

    def icono(self, app, lado):
        if app.icono is None:
            app.icono = icono_de(app, ICONO) or False
        return app.icono or None

    def pintar_icono(self, cr, app, cx, y, lado):
        sup = self.icono(app, lado)
        if sup is None:
            return
        cr.save()
        cr.translate(cx - lado / 2, y)
        cr.scale(lado / sup.get_width(), lado / sup.get_height())
        cr.set_source_surface(sup, 0, 0)
        cr.paint()
        cr.restore()

    def pintar_celda(self, cr, el, cx, y):
        lado = self.px(ICONO)
        if isinstance(el, Carpeta):
            self.pintar_cuadro_carpeta(cr, el, cx, y)
        else:
            self.pintar_icono(cr, el, cx, y, lado)
        self.texto(cr, el.nombre, cx, y + self.px(ETIQUETA_Y + 0), self.px(ETIQUETA_PX), ancho=self.px(190))

    def pintar_cuadro_carpeta(self, cr, carpeta, cx, y):
        lado = self.px(CARPETA)
        x = cx - lado / 2
        y0 = y + self.px(ICONO) / 2 - lado / 2 - self.px(0.5)
        rect_redondo(cr, x, y0, lado, lado, self.px(CARPETA_RADIO))
        cr.set_source_rgba(0.88, 0.90, 0.95, 0.55)
        cr.fill()
        for i, a in enumerate(carpeta.apps[:9]):
            sup = a.mini
            if sup is None:
                a.mini = sup = icono_de(a, MINI) or False
            if not sup:
                continue
            mx = x + self.px(MINI_X + (i % 3) * MINI_PASO)
            my = y0 + self.px(MINI_Y + (i // 3) * MINI_PASO)
            cr.save()
            cr.translate(mx, my)
            cr.scale(self.px(MINI) / sup.get_width(), self.px(MINI) / sup.get_height())
            cr.set_source_surface(sup, 0, 0)
            cr.paint()
            cr.restore()

    def pintar_paginas(self, cr):
        paginas = self.pagina_de(self.elementos)
        for p, elems in enumerate(paginas):
            desp = (p - self.pos) * self.W
            if desp <= -self.W or desp >= self.W:
                continue
            cr.save()
            cr.translate(desp, 0)
            for i, el in enumerate(elems):
                cx, y = self.celda(i)
                self.pintar_celda(cr, el, cx, y)
            cr.restore()

    def resultados(self):
        return buscar(self.todas, self.consulta)

    def pintar_resultados(self, cr):
        res = self.resultados()[:self.por_pagina]
        if not res:
            self.texto(cr, "No Results", self.W / 2, self.px(300), self.px(26), color=(1, 1, 1, 0.5), sombra=False)
            return
        self.sel = min(self.sel, len(res) - 1)
        cx, y = self.celda(self.sel)
        x, ys, w, h = CELDA_SEL
        # el resaltado es una celda de 158×171 con el ícono centrado
        rect_redondo(cr, cx - self.px(w) / 2, y - self.px(FILA0_Y - ys), self.px(w), self.px(h), self.px(8))
        cr.set_source_rgba(0, 0, 0.157, 0.72)
        cr.fill()
        for i, a in enumerate(res):
            cx, y = self.celda(i)
            self.pintar_celda(cr, a, cx, y)

    def pintar_puntos(self, cr):
        n = self.paginas
        cx0 = self.W / 2 - (n - 1) * self.px(PUNTO_PASO) / 2
        for i in range(n):
            cr.arc(cx0 + i * self.px(PUNTO_PASO), self.px(PUNTOS_Y), self.px(PUNTO_D) / 2, 0, 2 * math.pi)
            cr.set_source_rgba(1, 1, 1, 1.0 if i == self.pagina else 0.3)
            cr.fill()

    def pintar_buscador(self, cr):
        x, y, w, h = BUSCADOR
        x = self.W / 2 - self.px(w) / 2
        y, w, h = self.px(y), self.px(w), self.px(h)
        rect_redondo(cr, x + 0.5, y + 0.5, w - 1, h - 1, self.px(3.5))
        cr.set_source_rgba(1, 1, 1, 0.066)
        cr.fill_preserve()
        cr.set_source_rgba(1, 1, 1, 0.2)
        cr.set_line_width(1)
        cr.stroke()
        px = self.px(15.5)
        lupa_w = 14 * self.esc
        if self.consulta:
            self._glifo(cr, self.lupa, self.lupa_esc, x + self.px(7), y + h / 2 - lupa_w / 2, lupa_w, 0.7)
            self.texto(cr, self.consulta, x + self.px(27), y + h / 2 + px * 0.36, px, ancho=w - self.px(55),
                       sombra=False, alineado="izq")
            self._glifo(cr, self.borrar, self.borrar_esc, x + w - self.px(21), y + h / 2 - lupa_w / 2, lupa_w, 0.6)
        else:
            ancho_t = self.texto(cr, "Search", 0, -100, px, sombra=False)  # solo mide
            total = lupa_w + self.px(6) + ancho_t
            ix = self.W / 2 - total / 2
            self._glifo(cr, self.lupa, self.lupa_esc, ix, y + h / 2 - lupa_w / 2, lupa_w, 0.55)
            self.texto(cr, "Search", ix + lupa_w + self.px(6), y + h / 2 + px * 0.36, px,
                       color=(1, 1, 1, 0.5), sombra=False, alineado="izq")

    def _glifo(self, cr, sup, esc, x, y, lado, alfa):
        if sup is None:
            return
        cr.save()
        cr.translate(x, y)
        cr.scale(lado / sup.get_width(), lado / sup.get_height())
        cr.set_source_rgba(1, 1, 1, alfa)
        cr.mask_surface(sup, 0, 0)
        cr.restore()

    def apps_carpeta(self):
        n = PANEL_FILAS * COLUMNAS
        return self.carpeta.apps[self.pag_carpeta * n:(self.pag_carpeta + 1) * n]

    def paginas_carpeta(self):
        return max(1, math.ceil(len(self.carpeta.apps) / (PANEL_FILAS * COLUMNAS)))

    def geom_carpeta(self):
        filas = min(PANEL_FILAS, max(1, math.ceil(len(self.carpeta.apps) / COLUMNAS)))
        alto = PANEL_ARRIBA + filas * PASO_Y + PANEL_ABAJO
        y = REF_H / 2 - alto / 2 - 1.5
        return y, alto

    def pintar_carpeta(self, cr):
        y, alto = self.geom_carpeta()
        x = self.dx + self.px(PANEL_X)
        w = self.px(PANEL_ANCHO)
        y, alto = self.px(y), self.px(alto)
        # la sombra suave que oscurece el fondo alrededor
        for i in range(10, 0, -1):
            rect_redondo(cr, x - i * 6, y - i * 6, w + i * 12, alto + i * 12, self.px(PANEL_RADIO) + i * 6)
            cr.set_source_rgba(0, 0, 0, 0.022)
            cr.fill()
        rect_redondo(cr, x, y, w, alto, self.px(PANEL_RADIO))
        cr.set_source_rgba(0.88, 0.90, 0.95, 0.55)
        cr.fill()
        self.texto(cr, self.carpeta.nombre, self.W / 2, y - self.px(24), self.px(TITULO_PX), peso=200)
        primera = y / self.esc + PANEL_PRIMERA
        for i, a in enumerate(self.apps_carpeta()):
            cx, ya = self.celda(i, primera)
            self.pintar_celda(cr, a, cx, ya)
        n = self.paginas_carpeta()
        if n > 1:
            cx0 = self.W / 2 - (n - 1) * self.px(PUNTO_PASO) / 2
            for i in range(n):
                cr.arc(cx0 + i * self.px(PUNTO_PASO), y + alto - self.px(14), self.px(PUNTO_D) / 2, 0, 2 * math.pi)
                cr.set_source_rgba(1, 1, 1, 1.0 if i == self.pag_carpeta else 0.35)
                cr.fill()

    # ── entrada ──────────────────────────────────────────────────────────
    def hit(self, mx, my):
        """El elemento bajo el puntero (App o Carpeta) o None."""
        if self.carpeta is not None:
            lista, primera = self.apps_carpeta(), self.geom_carpeta()[0] + PANEL_PRIMERA
        elif self.consulta:
            lista, primera = self.resultados()[:self.por_pagina], FILA0_Y
        else:
            lista = self.pagina_de(self.elementos)[self.pagina]
            primera = FILA0_Y
        for i, el in enumerate(lista):
            cx, y = self.celda(i, primera)
            if abs(mx - cx) <= self.px(PASO_X) / 2 - 20 and y - 10 <= my <= y + self.px(ETIQUETA_Y + 12):
                return el
        return None

    def abrir_elemento(self, el):
        if isinstance(el, Carpeta):
            self.carpeta = el
            self.pag_carpeta = 0
            self.t0 = time.monotonic()
            self.queue_draw()
        else:
            el.lanzar()
            self.cerrar()

    def cerrar(self):
        # Como en la Mac, el Launchpad no sale: se esconde y el siguiente atajo lo vuelve a enseñar.
        self.ocultar()

    def ir_pagina(self, n):
        n = max(0, min(self.paginas - 1, n))
        if n != self.pagina:
            self.pagina = n
            self.queue_draw()

    def al_tecla(self, _w, ev):
        k = ev.keyval
        if k == Gdk.KEY_Escape:
            if self.consulta:
                self.consulta, self.sel = "", 0
            elif self.carpeta is not None:
                self.carpeta = None
            else:
                self.cerrar()
            self.queue_draw()
            return True
        if k in (Gdk.KEY_Return, Gdk.KEY_KP_Enter):
            if self.consulta:
                res = self.resultados()
                if res:
                    self.abrir_elemento(res[min(self.sel, len(res) - 1)])
            return True
        if k == Gdk.KEY_BackSpace:
            self.consulta = self.consulta[:-1]
            self.sel = 0
            self.queue_draw()
            return True
        if k in (Gdk.KEY_Left, Gdk.KEY_Right, Gdk.KEY_Up, Gdk.KEY_Down):
            d = {Gdk.KEY_Left: -1, Gdk.KEY_Right: 1, Gdk.KEY_Up: -COLUMNAS, Gdk.KEY_Down: COLUMNAS}[k]
            if self.consulta:
                n = len(self.resultados()[:self.por_pagina])
                self.sel = max(0, min(n - 1, self.sel + d))
            elif abs(d) == 1 and self.carpeta is None:
                self.ir_pagina(self.pagina + d)
            elif abs(d) == 1:
                self.pag_carpeta = max(0, min(self.paginas_carpeta() - 1, self.pag_carpeta + d))
            self.queue_draw()
            return True
        if k == Gdk.KEY_Tab:
            return True
        ch = ev.string
        if ch and ch.isprintable() and not (ev.state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.MOD1_MASK)):
            self.carpeta = None
            self.consulta += ch
            self.sel = 0
            self.queue_draw()
            return True
        return False

    def al_pulsar(self, _w, ev):
        if ev.button != 1:
            return True
        self.arrastre = (ev.x, ev.y, self.pagina)
        return True

    def al_mover(self, _w, ev):
        return False

    def al_soltar(self, _w, ev):
        if ev.button != 1 or self.arrastre is None:
            return True
        x0, y0, _p = self.arrastre
        self.arrastre = None
        dx = ev.x - x0
        if abs(dx) > self.px(80) and not self.consulta:
            d = -1 if dx > 0 else 1
            if self.carpeta is None:
                self.ir_pagina(self.pagina + d)
            else:
                self.pag_carpeta = max(0, min(self.paginas_carpeta() - 1, self.pag_carpeta + d))
                self.queue_draw()
            return True
        if abs(dx) > 8 or abs(ev.y - y0) > 8:
            return True
        # un clic
        if self.carpeta is not None:
            el = self.hit(ev.x, ev.y)
            if el is not None:
                self.abrir_elemento(el)
                return True
            y, alto = self.geom_carpeta()
            x = self.dx + self.px(PANEL_X)
            dentro = x <= ev.x <= x + self.px(PANEL_ANCHO) and self.px(y) <= ev.y <= self.px(y + alto)
            if not dentro:
                self.carpeta = None
                self.queue_draw()
            return True
        # un clic en el buscador no cierra: ya escribe ahí
        bx, by, bw, bh = BUSCADOR
        if abs(ev.x - self.W / 2) <= self.px(bw) / 2 and self.px(by) - 4 <= ev.y <= self.px(by + bh) + 4:
            if not (self.consulta and ev.x > self.W / 2 + self.px(bw) / 2 - self.px(26)):   # salvo el botón de borrar
                return True
        # los puntos de página
        if not self.consulta and self.paginas > 1 and abs(ev.y - self.px(PUNTOS_Y)) < self.px(14):
            n = self.paginas
            cx0 = self.W / 2 - (n - 1) * self.px(PUNTO_PASO) / 2
            i = round((ev.x - cx0) / self.px(PUNTO_PASO))
            if 0 <= i < n:
                self.ir_pagina(i)
                return True
        # el botón de borrar de la búsqueda
        if self.consulta:
            bx, by, bw, bh = BUSCADOR
            if abs(ev.x - (self.W / 2 + self.px(bw) / 2 - self.px(14))) < self.px(10) and abs(ev.y - self.px(by + bh / 2)) < self.px(12):
                self.consulta, self.sel = "", 0
                self.queue_draw()
                return True
        el = self.hit(ev.x, ev.y)
        if el is not None:
            self.abrir_elemento(el)
        else:
            self.cerrar()     # un clic en el vacío cierra, como en Catalina
        return True

    def al_scroll(self, _w, ev):
        if self.consulta or self.carpeta is not None:
            return True
        if ev.direction == Gdk.ScrollDirection.SMOOTH:
            ok, dx, dy = ev.get_scroll_deltas()
            d = dx if abs(dx) > abs(dy) else dy
            self.scroll_acum += d
            if time.monotonic() > self.scroll_hasta and abs(self.scroll_acum) >= 1.0:
                self.ir_pagina(self.pagina + (1 if self.scroll_acum > 0 else -1))
                self.scroll_acum = 0.0
                self.scroll_hasta = time.monotonic() + 0.4
        elif ev.direction in (Gdk.ScrollDirection.RIGHT, Gdk.ScrollDirection.DOWN):
            self.ir_pagina(self.pagina + 1)
        elif ev.direction in (Gdk.ScrollDirection.LEFT, Gdk.ScrollDirection.UP):
            self.ir_pagina(self.pagina - 1)
        return True


class Aplicacion(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.FLAGS_NONE)
        self.ventana = None
        self.solo_armar = False

    def _prueba(self):
        """LAUNCHPAD_PNG=archivo: pinta un cuadro a LAUNCHPAD_TAM y sale (sin ventana útil)."""
        v = self.ventana
        v.t0 -= 10
        v.pos = v.pagina = int(os.environ.get("LAUNCHPAD_PAGINA", "0"))
        v.consulta = os.environ.get("LAUNCHPAD_CONSULTA", "")
        if os.environ.get("LAUNCHPAD_CARPETA"):
            v.carpeta = [e for e in v.elementos if isinstance(e, Carpeta)][0]
        sup = cairo.ImageSurface(cairo.FORMAT_ARGB32, v.W, v.H)
        v.al_pintar(v, cairo.Context(sup))
        sup.write_to_png(os.environ["LAUNCHPAD_PNG"])
        self.quit()
        return False

    def do_startup(self):
        Gtk.Application.do_startup(self)
        self.hold()                       # residente: sigue vivo con la ventana oculta

    def do_activate(self):
        # Pedirlo estando abierto lo esconde (F4 abre y cierra); si no existe, se arma.
        if self.ventana is None:
            self.ventana = Ventana(self)
            if os.environ.get("LAUNCHPAD_PNG"):
                GLib.timeout_add(300, self._prueba)
                return
            self.ventana.precalentar()
            if self.solo_armar:           # --residente: arranca con la sesión, sin enseñarse
                self.solo_armar = False
                return
            self.ventana.mostrar()
            return
        if self.ventana.get_visible():
            self.ventana.ocultar()
        else:
            self.ventana.mostrar()


def main():
    if "--lista" in sys.argv:
        elementos, _ = leer_aplicaciones()
        for e in elementos:
            if isinstance(e, Carpeta):
                print(f"[{e.nombre}] " + ", ".join(a.nombre for a in e.apps))
            else:
                print(e.nombre)
        return 0
    GLib.set_prgname("mac-launchpad")
    app = Aplicacion()
    # --residente: lo arranca la sesión; se arma y espera oculto al primer atajo.
    app.solo_armar = "--residente" in sys.argv
    return app.run([sys.argv[0]])


if __name__ == "__main__":
    sys.exit(main())
