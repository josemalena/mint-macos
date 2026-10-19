#!/usr/bin/env python3
"""Los controles de Catalina en el tema GTK: los semáforos de las ventanas,
las casillas y los radios, sacados de los catálogos de apariencia del disco
de la Mac.

    controles.py <SystemAppearance.car> <DarkAquaAppearance.car> <tema> [--claro] [--acento ACENTO]

--claro: las piezas de la apariencia clara (SystemAppearance) y los colores de Catalina claro.
--acento: Purple, Pink, Red, Orange, Yellow, Green o Graphite; lo que en Catalina va del color de
acento (la doble flecha del menú desplegable, el interruptor encendido, la pista llena del
deslizador) se tiñe con ese color. Sin --acento, el azul de siempre.

<tema> es la carpeta del tema ya construido (~/.themes/Constanza-Oscuro).
Cambia:
  - metacity-1/*.png: los botones de las ventanas que dibuja Muffin;
  - gtk-3.0/gtk.gresource: los titlebutton-* de las ventanas con barra
    propia (Nemo, Fynder…) y los checkbox-* y radio-*. Se desempaca, se
    cambian los PNG y se vuelve a compilar, así que el CSS de Mojave sigue
    valiendo tal cual.
Cada imagen se ajusta al tamaño del archivo que reemplaza. Nada de esto va
al repo: se genera en local desde el disco de la Mac.
"""
import os
import re
import subprocess
import sys
import tempfile
import xml.sax.saxutils

from PIL import Image

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "iconos"))
import car  # noqa: E402

SEMAFOROS = "WindowFrame_WindowControlButtons_Regular"
# dimensión1 de WindowControlButtons: qué botón es.
BOTON = {"close": 0, "minimize": 1, "maximize": 4, "restore": 5, "unmaximize": 5}
# (presentación, estado): presentación 1 = ventana sin foco; estado 1 =
# encima, 2 = apretado, 0 = quieto (sin foco: gris).
QUIETO, ENCIMA, APRETADO = (0, 0), (0, 1), (0, 2)
SIN_FOCO, SIN_FOCO_ENCIMA, SIN_FOCO_APRETADO = (1, 0), (1, 1), (1, 2)


def semaforos(ruta):
    """{(escala, botón, presentación, estado): imagen} de un catálogo."""
    cat = car.Catalogo(ruta)
    salida = {}
    for atr, im in cat.imagenes():
        if not im.nombre.startswith(SEMAFOROS):
            continue
        img = car.pixeles_de(im)
        if img is None:
            continue
        clave = (int(im.escala), atr.get("dimensión1", 0), atr.get("presentación", 0), atr.get("estado", 0))
        salida[clave] = img
    return salida


# Casillas y radios: CheckBox_CheckBox_Regular y RadioButton_RadioButton_
# Regular. elemento 1 = casilla, 2 = radio; valor 0 = sin marcar, 1 = marcada,
# 2 = mixta; estado 0 = quieto, 2 = apretado, 4 = desactivado; presentación
# 1 = ventana sin foco.
MARCAS = {"CheckBox_CheckBox_Regular": "checkbox", "RadioButton_RadioButton_Regular": "radio"}
VALOR = {"unchecked": 0, "checked": 1, "mixed": 2}


def marcas(ruta):
    """{(escala, 'checkbox'|'radio', valor, estado): imagen} de un catálogo,
    con la ventana activa (presentación 0)."""
    salida = {}
    for atr, im in car.Catalogo(ruta).imagenes():
        tipo = next((t for n, t in MARCAS.items() if im.nombre.startswith(n)), None)
        if not tipo or atr.get("presentación", 0):
            continue
        img = car.pixeles_de(im)
        if img is not None:
            salida[(int(im.escala), tipo, atr.get("valor", 0), atr.get("estado", 0))] = img
    return salida


def ajustar(img, tam):
    return img if img.size == tam else img.resize(tam, Image.LANCZOS)


def metacity(tema, s):
    """metacity-1: <botón>_<focused|unfocused>[_normal|_prelight|_pressed].png"""
    carpeta = os.path.join(tema, "metacity-1")
    hechos = 0
    for f in sorted(os.listdir(carpeta)):
        m = re.fullmatch(r"(close|minimize|maximize|unmaximize)(?:_(focused|unfocused))?(?:_(normal|prelight|pressed))?\.png", f)
        if not m:
            continue
        boton, foco, estado = m.group(1), m.group(2) or "focused", m.group(3) or "normal"
        pe = {("focused", "normal"): QUIETO, ("focused", "prelight"): ENCIMA,
              ("focused", "pressed"): APRETADO, ("unfocused", "normal"): SIN_FOCO,
              ("unfocused", "prelight"): SIN_FOCO_ENCIMA, ("unfocused", "pressed"): SIN_FOCO_APRETADO}[(foco, estado)]
        img = s.get((1, BOTON[boton]) + pe)
        if img is None:
            continue
        ruta = os.path.join(carpeta, f)
        ajustar(img, Image.open(ruta).size).save(ruta)
        hechos += 1
    return hechos


def marca_para(ruta, claras, oscuras):
    """La imagen de Catalina para un checkbox-*/radio-* de Mojave, o None.
    «-selected» (dentro de una fila resaltada) va igual que la normal: macOS
    no la cambia; «selectionmode» no tiene equivalente y se deja."""
    m = re.search(r"/(checkbox|radio)-(unchecked|checked|mixed)(-insensitive)?(-selected)?(-dark)?(@2)?\.png$", ruta)
    if not m:
        return None
    fuente = oscuras if m.group(5) else claras
    return fuente.get((2 if m.group(6) else 1, m.group(1), VALOR[m.group(2)], 4 if m.group(3) else 0))


def gresource(tema, claros, oscuros, claras, oscuras):
    """gtk-3.0/gtk.gresource: titlebutton-<botón>[-hover|-active|-backdrop
    |-backdrop-hover][-dark][@2].png, y se vuelve a compilar."""
    archivo = os.path.join(tema, "gtk-3.0", "gtk.gresource")
    rutas = subprocess.run(["gresource", "list", archivo], capture_output=True, text=True,
                           check=True).stdout.split()
    hechos = 0
    with tempfile.TemporaryDirectory() as tmp:
        for r in rutas:
            destino = os.path.join(tmp, r.lstrip("/"))
            os.makedirs(os.path.dirname(destino), exist_ok=True)
            with open(destino, "wb") as f:
                f.write(subprocess.run(["gresource", "extract", archivo, r], capture_output=True,
                                       check=True).stdout)
            img = marca_para(r, claras, oscuras)
            if img is not None:
                ajustar(img, Image.open(destino).size).save(destino)
                hechos += 1
                continue
            m = re.search(r"/titlebutton-(close|minimize|maximize|restore)"
                          r"(-hover|-active|-backdrop-hover|-backdrop)?(-dark)?(@2)?\.png$", r)
            if not m:
                continue
            pe = {None: QUIETO, "-hover": ENCIMA, "-active": APRETADO,
                  "-backdrop": SIN_FOCO, "-backdrop-hover": SIN_FOCO_ENCIMA}[m.group(2)]
            fuente = oscuros if m.group(3) else claros
            img = fuente.get((2 if m.group(4) else 1, BOTON[m.group(1)]) + pe)
            if img is None:
                continue
            ajustar(img, Image.open(destino).size).save(destino)
            hechos += 1
        xml_ruta = os.path.join(tmp, "gtk.gresource.xml")
        prefijo = os.path.commonpath(rutas)
        with open(xml_ruta, "w") as f:
            f.write(f'<?xml version="1.0" encoding="UTF-8"?>\n<gresources>\n'
                    f'  <gresource prefix="{prefijo}">\n')
            for r in rutas:
                f.write(f"    <file>{xml.sax.saxutils.escape(os.path.relpath(r, prefijo))}</file>\n")
            f.write("  </gresource>\n</gresources>\n")
        nuevo = archivo + ".nuevo"
        subprocess.run(["glib-compile-resources", f"--sourcedir={os.path.join(tmp, prefijo.lstrip('/'))}",
                        f"--target={nuevo}", xml_ruta], check=True)
        os.replace(nuevo, archivo)
    return hechos


# Lo que el CSS de Mojave dibuja con colores y degradados: los menús
# desplegables, el interruptor, el slider y la barra de desplazamiento. Van a
# gtk-3.0/catalina/*.png y gtk-3.0/catalina.css, que se importa al final.
PIEZAS = {
    "popup": "PopUpButton_PopUpButton_Regular",
    "pista": "Slider_SliderTrack_Regular_Horizontal",
    "perilla": "Slider_SliderKnob_Regular_Horizontal",
    "barra-v": "ScrollBarOverlay_Thumb_Regular_Vertical",
    "barra-h": "ScrollBarOverlay_Thumb_Regular_Horizontal",
    "sw-relleno": "Switch_Fill_Regular",
    "sw-mascara": "Switch_FillMask_Regular",
    "sw-borde": "Switch_Border_Regular",
    "sw-perilla": "Switch_Knob_Regular",
}


def piezas(ruta):
    """{(pieza, escala, presentación, estado, valor, capa, dimensión1): imagen}"""
    salida = {}
    for atr, im in car.Catalogo(ruta).imagenes():
        pieza = next((k for k, n in PIEZAS.items()
                      if im.nombre in (n + ".psd", n + "@2x.psd")), None)
        if not pieza:
            continue
        img = car.pixeles_de(im)
        if img is not None:
            salida[(pieza, int(im.escala), atr.get("presentación", 0), atr.get("estado", 0),
                    atr.get("valor", 0), atr.get("capa", 0), atr.get("dimensión1", 0))] = img
    return salida


def interruptor(p, esc, pres, estado, valor):
    """El riel del interruptor: relleno recortado con la máscara, y el borde."""
    relleno = p.get(("sw-relleno", esc, pres, estado, valor, 0, 0))
    mascara = p.get(("sw-mascara", esc, 0, 0, 0, 0, 0))
    borde = p.get(("sw-borde", esc, 0, 4 if estado == 4 else 0, 0, 0, 0))
    if relleno is None or mascara is None:
        return None
    from PIL import ImageChops, ImageFilter
    alfa = mascara.getchannel("A")
    lienzo = Image.new("RGBA", relleno.size, (0, 0, 0, 0))
    lienzo.paste(relleno, (0, 0), alfa)
    if borde is not None:
        # El borde trae las esquinas sin recortar: se recorta con la máscara
        # un píxel más ancha, para no comerse el trazo de afuera.
        borde = borde.copy()
        borde.putalpha(ImageChops.multiply(borde.getchannel("A"), alfa.filter(ImageFilter.MaxFilter(3))))
        lienzo.alpha_composite(borde)
    return lienzo


def tres(selector, imagen, borde, vertical=False, extra=""):
    """Una imagen de tres partes de Apple: las puntas con border-image y el
    centro de fondo, porque GTK 3 no pinta el centro de un border-image."""
    bw = f"{borde}px 0" if vertical else f"0 {borde}px"
    sl = f"{borde} 0 {borde} 0" if vertical else f"0 {borde} 0 {borde}"
    return (f"{selector} {{\n  border-style: solid; border-width: {bw}; border-radius: 0; box-shadow: none;\n"
            f'  border-image: -gtk-scaled(url("catalina/{imagen}.png"), url("catalina/{imagen}@2.png")) {sl} stretch;\n'
            f'  background: -gtk-scaled(url("catalina/{imagen}-centro.png"), url("catalina/{imagen}-centro@2.png")) '
            f"center / 100% 100% no-repeat;\n  background-clip: padding-box;{extra} }}\n")


def hoja_css(claro=False):
    c = """/* Controles de Catalina (controles.py). Las imágenes se generan en local
   desde el disco de la Mac; nada de Apple va al repo. */
@define-color catalina_texto %s;
""" % ('#262626' if claro else '#e5e5e5') + """
/* Menús desplegables: el botón con la flecha doble azul. */
"""
    combo = "combobox button.combo"
    c += tres(f"{combo}, .background {combo}, .linked:not(.vertical) > combobox > box > button.combo, {combo}:hover",
              "popup", 0, extra="\n  min-height: 25px; padding: 0 4px 1px 2px; color: @catalina_texto; outline-color: transparent;")
    # Las puntas de Apple miden distinto (7 y 23 px): se corrige el ancho del borde.
    c = c.replace("border-width: 0 0px;", "border-width: 0 23px 0 7px;").replace(" 0 0 0 0 stretch", " 0 23 0 7 stretch")
    for estado, img in ((":active", "popup-apretado"), (":checked", "popup-apretado"),
                        (":backdrop", "popup-sin-foco"), (":disabled", "popup-desactivado")):
        bloque = tres(f"{combo}{estado}", img, 0)
        c += bloque.replace("border-width: 0 0px;", "border-width: 0 23px 0 7px;").replace(" 0 0 0 0 stretch", " 0 23 0 7 stretch")
    c += "combobox button.combo:disabled { color: alpha(@catalina_texto, 0.4); }\n"
    c += """combobox button.combo arrow, .background combobox button.combo arrow,
.linked:not(.vertical) > combobox > box > button.combo arrow,
.linked:not(.vertical) > combobox > box > button.combo:checked arrow {
  -gtk-icon-source: none; background: none; border: none; box-shadow: none;
  min-width: 0; min-height: 0; margin: 0; padding: 0; }

/* Interruptor */
"""
    def fondo(img, tam):
        return f'-gtk-scaled(url("catalina/{img}.png"), url("catalina/{img}@2.png")) center / {tam} no-repeat'
    c += ("switch { border: none; border-radius: 0; box-shadow: none; animation: none;\n"
          f"  min-width: 42px; min-height: 24px; background: {fondo('sw-apagado', '42px 24px')}; }}\n")
    for estado, img in ((":checked", "sw-encendido"), (":backdrop", "sw-apagado-sin-foco"),
                        (":checked:backdrop", "sw-encendido-sin-foco"), (":disabled", "sw-apagado-desactivado"),
                        (":checked:disabled", "sw-encendido-desactivado")):
        c += f"switch{estado} {{ background: {fondo(img, '42px 24px')}; }}\n"
    c += ("switch slider, switch:checked slider, switch:hover slider {\n"
          "  min-width: 21px; min-height: 24px; margin: 0; border: none; border-radius: 0; box-shadow: none;\n"
          f"  background: {fondo('sw-perilla', '25px 24px')}; }}\n"
          f"switch:disabled slider {{ background: {fondo('sw-perilla-desactivada', '25px 24px')}; }}\n\n/* Slider */\n")
    c += tres("scale.horizontal trough", "pista", 3, extra=" min-height: 5px; padding: 0;")
    c += tres("scale.horizontal highlight, scale.horizontal fill", "pista-llena", 3, extra=" min-height: 5px; margin: 0 -3px;")
    c += ("scale slider, scale slider:hover, scale slider:active {\n"
          "  min-width: 21px; min-height: 21px; margin: -9px; border: none; border-radius: 0; box-shadow: none;\n"
          f"  background: {fondo('perilla', '21px 21px')}; }}\n"
          f"scale slider:active {{ background: {fondo('perilla-apretada', '21px 21px')}; }}\n"
          f"scale slider:disabled {{ background: {fondo('perilla-desactivada', '21px 21px')}; }}\n\n/* Barra de desplazamiento */\n")
    c += tres("scrollbar.vertical slider, scrollbar.overlay-indicator:not(.dragging):not(.hovering).vertical slider",
              "barra-v", 8, vertical=True, extra=" margin: 0; min-width: 12px; min-height: 24px;")
    c += tres("scrollbar.horizontal slider, scrollbar.overlay-indicator:not(.dragging):not(.hovering).horizontal slider",
              "barra-h", 8, extra=" margin: 0; min-height: 12px; min-width: 24px;")
    c += COLORES_CLARO if claro else COLORES
    return c


# Los colores de Catalina oscuro, medidos en las capturas de la Mac de José
# (Desktop/SS, 10-10-2026): la barra de título y la de herramientas son un
# solo degradado de #38393c a #2d2e30, con una línea de luz arriba y una
# negra abajo; el contenido #1b1d1f; el lateral #27282a; el fondo de las
# ventanas #303031.
COLORES = """
/* Colores de Catalina oscuro */
/* Muffin pinta la barra de las ventanas sin barra propia con el
   metacity-theme, que toma estos colores del tema GTK. */
@define-color titlebar_gradient_a #38393c;
@define-color titlebar_gradient_b #333437;
@define-color wm_bg #333437;
@define-color wm_bg_unfocused #29292b;
@define-color wm_highlight #4a4b4e;
/* El borde de 1 px de la ventana: en Catalina es gris claro (#535355), con
   la sombra negra por fuera. */
@define-color wm_border_focused #535355;
@define-color wm_border_unfocused #48484a;
.background { background-color: #303031; }
.view, iconview, treeview.view, textview text,
.nemo-window .view, .nemo-window iconview, .nemo-window treeview.view { background-color: #1b1d1f; }
.sidebar, .nemo-window .sidebar, placessidebar, placessidebar list,
.nemo-window .places-treeview, .nemo-window treeview.places-treeview { background-color: #27282a; }

headerbar, .csd headerbar, headerbar.default-decoration, .titlebar:not(headerbar),
.maximized headerbar, .tiled headerbar {
  background-color: #333437;
  background-image: linear-gradient(to bottom, #38393c, #2d2e30);
  box-shadow: inset 0 1px rgba(255, 255, 255, 0.18);
  border-bottom: 1px solid #000000; }
headerbar:backdrop, .csd headerbar:backdrop, headerbar.default-decoration:backdrop,
.titlebar:not(headerbar):backdrop, .maximized headerbar:backdrop {
  background-color: #29292b; background-image: none;
  box-shadow: inset 0 1px rgba(255, 255, 255, 0.10);
  border-bottom-color: #000000; }

/* Los menús de las apps a 14 px (10.5 pt), como en Catalina; el resto del
   texto queda a 13 px. */
menu menuitem, .menu menuitem, .context-menu menuitem, popover.menu modelbutton { font-size: 10.5pt; }

/* La barra que pinta Muffin (ventanas sin barra propia) va sin línea abajo:
   en el Finder, la barra de título y la de herramientas son un solo
   degradado, y la línea va debajo de la de herramientas (la pone Fynder). */
headerbar.default-decoration, .titlebar:not(headerbar), headerbar.default-decoration:backdrop,
.titlebar:not(headerbar):backdrop { border-bottom: none; }

/* El marco de Muffin lo pinta GTK (headerbar.default-decoration), no el
   metacity-theme: la geometría va aquí. Como en las capturas del Finder:
   barra de 22 px, semáforos de 12 px cada 20 px (16 de botón y 4 de
   separación: GTK pone 6, se le quita 1 por lado) con el primero a 8 px del
   borde, y esquinas de 4 px (Mojave usa 8). */
headerbar.default-decoration, .csd headerbar.default-decoration { min-height: 22px; padding: 0 6px; }
headerbar.default-decoration button.titlebutton { margin: 0 -1px; }
.ssd decoration { border-radius: 4px 4px 0 0; }
separator:first-child + headerbar, headerbar:first-child,
separator:first-child + headerbar:backdrop, headerbar:first-child:backdrop { border-top-left-radius: 4px; }
headerbar:last-child, headerbar:last-child:backdrop { border-top-right-radius: 4px; }
.maximized headerbar:first-child, .tiled headerbar:first-child,
.maximized headerbar:last-child, .tiled headerbar:last-child { border-radius: 0; }

/* Fynder y Nemo: la barra de título y la de herramientas, un solo degradado
   como en el Finder; la línea negra va debajo de la de herramientas. */
.nemo-window headerbar, .nemo-window .titlebar:not(headerbar) {
  background-image: linear-gradient(to bottom, #38393c, #333437);
  border-bottom: none; }
.nemo-window .primary-toolbar:not(.libreoffice-toolbar) {
  background-color: #303134;
  background-image: linear-gradient(to bottom, #333437, #2d2e30);
  border-image: none; border-style: solid; border-width: 0 0 1px 0; border-color: #000000; }
.nemo-window:backdrop headerbar, .nemo-window:backdrop .titlebar:not(headerbar),
.nemo-window:backdrop .primary-toolbar:not(.libreoffice-toolbar) {
  background-color: #29292b; background-image: none; }
"""


# Los colores de Catalina claro. Los de sistema, medidos en la Monterey de Vega Real (extraer-mac,
# medidas.json: windowBackgroundColor #ECECEC, controlBackground #FFFFFF, separador 10 % negro);
# la barra de título, aproximada hasta tener la captura clara de Catalina.
COLORES_CLARO = """
/* Colores de Catalina claro */
@define-color titlebar_gradient_a #e8e6e8;
@define-color titlebar_gradient_b #d3d1d3;
@define-color wm_bg #dcdadc;
@define-color wm_bg_unfocused #f6f6f6;
@define-color wm_highlight #ffffff;
@define-color wm_border_focused #b3b3b3;
@define-color wm_border_unfocused #c6c6c6;
.background { background-color: #ececec; }
.view, iconview, treeview.view, textview text,
.nemo-window .view, .nemo-window iconview, .nemo-window treeview.view { background-color: #ffffff; }
.sidebar, .nemo-window .sidebar, placessidebar, placessidebar list,
.nemo-window .places-treeview, .nemo-window treeview.places-treeview { background-color: #e6e6e6; }

headerbar, .csd headerbar, headerbar.default-decoration, .titlebar:not(headerbar),
.maximized headerbar, .tiled headerbar {
  background-color: #dcdadc;
  background-image: linear-gradient(to bottom, #e8e6e8, #d3d1d3);
  box-shadow: inset 0 1px rgba(255, 255, 255, 0.6);
  border-bottom: 1px solid #b3b3b3; }
headerbar:backdrop, .csd headerbar:backdrop, headerbar.default-decoration:backdrop,
.titlebar:not(headerbar):backdrop, .maximized headerbar:backdrop {
  background-color: #f6f6f6; background-image: none; box-shadow: none;
  border-bottom-color: #d1d1d1; }

menu menuitem, .menu menuitem, .context-menu menuitem, popover.menu modelbutton { font-size: 10.5pt; }
headerbar.default-decoration, .titlebar:not(headerbar), headerbar.default-decoration:backdrop,
.titlebar:not(headerbar):backdrop { border-bottom: none; }
headerbar.default-decoration, .csd headerbar.default-decoration { min-height: 22px; padding: 0 6px; }
headerbar.default-decoration button.titlebutton { margin: 0 -1px; }
.ssd decoration { border-radius: 4px 4px 0 0; }
separator:first-child + headerbar, headerbar:first-child,
separator:first-child + headerbar:backdrop, headerbar:first-child:backdrop { border-top-left-radius: 4px; }
headerbar:last-child, headerbar:last-child:backdrop { border-top-right-radius: 4px; }
.maximized headerbar:first-child, .tiled headerbar:first-child,
.maximized headerbar:last-child, .tiled headerbar:last-child { border-radius: 0; }

.nemo-window headerbar, .nemo-window .titlebar:not(headerbar) {
  background-image: linear-gradient(to bottom, #e8e6e8, #dcdadc);
  border-bottom: none; }
.nemo-window .primary-toolbar:not(.libreoffice-toolbar) {
  background-color: #d6d4d6;
  background-image: linear-gradient(to bottom, #dcdadc, #d3d1d3);
  border-image: none; border-style: solid; border-width: 0 0 1px 0; border-color: #b3b3b3; }
.nemo-window:backdrop headerbar, .nemo-window:backdrop .titlebar:not(headerbar),
.nemo-window:backdrop .primary-toolbar:not(.libreoffice-toolbar) {
  background-color: #f6f6f6; background-image: none; }
"""

# Los colores de acento de Catalina (los de sistema, medidos en Monterey: medidas.json).
ACENTOS = {'Blue': '#007AFF', 'Purple': '#AF52DE', 'Pink': '#FF2D55', 'Red': '#FF3B30',
           'Orange': '#FF9500', 'Yellow': '#FFCC00', 'Green': '#28CD41', 'Graphite': '#8E8E93'}
# Las piezas que en Catalina van del color de acento.
DE_ACENTO = ('popup', 'popup-apretado', 'pista-llena', 'sw-encendido', 'sw-encendido-desactivado')


def tenir(img, acento):
    """Pasa los píxeles azules (los del acento) al color dado, con su misma luz: el tono y la
    saturación del acento, la luminosidad de cada píxel. Graphite queda en gris."""
    import colorsys
    h = ACENTOS[acento].lstrip('#')
    r0, g0, b0 = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    ht, lt, st = colorsys.rgb_to_hls(r0, g0, b0)
    _hb, lb, _sb = colorsys.rgb_to_hls(0, 0.478, 1)
    px = img.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            hh, ll, ss = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
            if ss > 0.35 and 0.52 < hh < 0.72:  # azul
                # La luz relativa al azul de referencia, llevada a la del acento.
                l2 = min(1, max(0, ll * (lt / lb)))
                nr, ng, nb = colorsys.hls_to_rgb(ht, l2, st * min(1, ss / 0.9))
                px[x, y] = (int(nr * 255), int(ng * 255), int(nb * 255), a)
    return img


def css(tema, oscuros, claro=False, acento=None):
    """Escribe gtk-3.0/catalina/*.png y catalina.css, y lo importa."""
    p = piezas(oscuros)
    if not p:
        return 0
    carpeta = os.path.join(tema, "gtk-3.0", "catalina")
    os.makedirs(carpeta, exist_ok=True)
    hechos = 0
    for esc in (1, 2):
        sufijo = "@2" if esc == 2 else ""
        imagenes = {
            "popup": p.get(("popup", esc, 0, 0, 0, 0, 0)),
            "popup-apretado": p.get(("popup", esc, 0, 2, 0, 0, 0)),
            "popup-desactivado": p.get(("popup", esc, 0, 4, 0, 0, 0)),
            "popup-sin-foco": p.get(("popup", esc, 1, 0, 0, 0, 0)),
            "pista": p.get(("pista", esc, 0, 0, 0, 0, 0)),
            "pista-llena": p.get(("pista", esc, 0, 0, 0, 7, 0)),
            "perilla": p.get(("perilla", esc, 0, 0, 0, 0, 0)),
            "perilla-apretada": p.get(("perilla", esc, 0, 2, 0, 0, 0)),
            "perilla-desactivada": p.get(("perilla", esc, 0, 4, 0, 0, 0)),
            "barra-v": p.get(("barra-v", esc, 0, 0, 0, 0, 0)),
            "barra-h": p.get(("barra-h", esc, 0, 0, 0, 0, 0)),
            "sw-perilla": p.get(("sw-perilla", esc, 0, 0, 0, 0, 0)),
            "sw-perilla-desactivada": p.get(("sw-perilla", esc, 0, 4, 0, 0, 0)),
            "sw-apagado": interruptor(p, esc, 0, 0, 0),
            "sw-encendido": interruptor(p, esc, 0, 0, 1),
            "sw-apagado-sin-foco": interruptor(p, esc, 1, 0, 0),
            "sw-encendido-sin-foco": interruptor(p, esc, 1, 0, 1),
            "sw-apagado-desactivado": interruptor(p, esc, 0, 4, 0),
            "sw-encendido-desactivado": interruptor(p, esc, 0, 4, 1),
        }
        # Las de tres partes: (puntas en px a 1x, vertical). El centro va
        # aparte, de fondo (ver tres()).
        tres_partes = {"popup": (7, 23, False), "popup-apretado": (7, 23, False),
                       "popup-desactivado": (7, 23, False), "popup-sin-foco": (7, 23, False),
                       "pista": (3, 3, False), "pista-llena": (3, 3, False),
                       "barra-v": (8, 8, True), "barra-h": (8, 8, False)}
        for nombre, img in imagenes.items():
            if img is None:
                continue
            if acento and acento != 'Blue' and nombre in DE_ACENTO:
                img = tenir(img.copy(), acento)
            img.save(os.path.join(carpeta, nombre + sufijo + ".png"))
            hechos += 1
            if nombre in tres_partes:
                a, b, vertical = tres_partes[nombre]
                a, b = a * esc, b * esc
                caja = (0, a, img.width, img.height - b) if vertical else (a, 0, img.width - b, img.height)
                img.crop(caja).save(os.path.join(carpeta, nombre + "-centro" + sufijo + ".png"))
    with open(os.path.join(tema, "gtk-3.0", "catalina.css"), "w") as f:
        f.write(hoja_css(claro))
    for hoja in ("gtk.css", "gtk-dark.css"):
        ruta = os.path.join(tema, "gtk-3.0", hoja)
        texto = open(ruta).read()
        if 'url("catalina.css")' not in texto:
            with open(ruta, "a") as f:
                f.write('@import url("catalina.css");\n')
    return hechos


def marco(tema):
    """La geometría del marco de Muffin como la de Catalina, medida en las
    capturas de José: semáforos de 12 px cada 20 px (16 de imagen + 2 y 2 de
    borde), el primero a 8 px del borde (4 + 2 + 2 de la imagen) y 2 px más
    arriba que en Mojave (6 px desde el borde de arriba); esquinas de 5 px."""
    ruta = os.path.join(tema, "metacity-1", "metacity-theme-3.xml")
    if not os.path.isfile(ruta):
        return False
    texto = open(ruta).read()
    m = re.search(r'<frame_geometry name="normal" [^>]*>.*?</frame_geometry>', texto, re.S)
    if not m:
        return False
    bloque = m.group(0)
    nuevo = re.sub(r'<border name="button_border"[^>]*/>',
                   '<border name="button_border" left="2" right="2" top="2" bottom="6" />', bloque)
    texto = texto.replace(bloque, nuevo)
    texto = re.sub(r'rounded_top_(left|right)="4"', r'rounded_top_\1="5"', texto)
    # Los arcos y las líneas del borde redondeado, de 4 a 5 px de radio.
    def cinco(m):
        b = m.group(0)
        for a, z in (('width="9" height="9"', 'width="11" height="11"'),
                     ('width="8" height="8"', 'width="10" height="10"'),
                     ('x="width-10"', 'x="width-12"'), ('x="width-11"', 'x="width-13"'),
                     ('x1="4" y1="0" x2="width-5"', 'x1="5" y1="0" x2="width-6"'),
                     ('x1="5" y1="1" x2="width - 5"', 'x1="6" y1="1" x2="width - 6"'),
                     ('y1="4" x2="0"', 'y1="5" x2="0"'), ('y1="4" x2="width-1"', 'y1="5" x2="width-1"')):
            b = b.replace(a, z)
        return b
    texto = re.sub(r'<draw_ops name="rounded_border_(?:un)?focused">.*?</draw_ops>', cinco, texto, flags=re.S)
    open(ruta, "w").write(texto)
    return True


def main():
    claro = '--claro' in sys.argv
    acento = sys.argv[sys.argv.index('--acento') + 1] if '--acento' in sys.argv else None
    sys.argv = [a for i, a in enumerate(sys.argv)
                if a != '--claro' and a != '--acento' and not (i > 0 and sys.argv[i - 1] == '--acento')]
    if len(sys.argv) != 4 or (acento and acento not in ACENTOS):
        sys.exit(__doc__)
    claros, oscuros = semaforos(sys.argv[1]), semaforos(sys.argv[2])
    if not oscuros:
        sys.exit("  ✗ no salieron los semáforos del catálogo (¿falta liblzfse?)")
    m = metacity(sys.argv[3], oscuros)
    claras, oscuras = marcas(sys.argv[1]), marcas(sys.argv[2])
    g = gresource(sys.argv[3], claros or oscuros, oscuros, claras or oscuras, oscuras)
    marco(sys.argv[3])
    # Las piezas de la apariencia de la variante: la clara para Constanza-Claro.
    c = css(sys.argv[3], sys.argv[1] if claro else sys.argv[2], claro, acento)
    print(f"  controles de Catalina: {m} semáforos en metacity-1, {g} imágenes en gtk.gresource"
          f" y {c} piezas en catalina/")


if __name__ == "__main__":
    main()
