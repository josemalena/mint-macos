#!/usr/bin/env python3
"""Los controles de Catalina en el tema GTK: los semáforos de las ventanas,
las casillas y los radios, sacados de los catálogos de apariencia del disco
de la Mac.

    controles.py <SystemAppearance.car> <DarkAquaAppearance.car> <tema> [--claro] [--acento ACENTO]

--claro: las piezas de la apariencia clara (SystemAppearance) y los colores de Catalina claro.
--medidas: el medidas.json de la versión (extraer-mac): sus colores de sistema reemplazan los fijos
que tienen equivalente en la Mac (fondo de ventana, de las vistas, del texto). Sin él, o sin el color,
quedan los medidos en capturas (Catalina) y se anota.
--metacity-claro: solo lo de metacity-1 (en Constanza-Claro: los semáforos inactivos salían de la apariencia oscura).
--version-propia: la versión no es Catalina (Samaná = Monterey): los semáforos de metacity-1 salen de la
apariencia de la variante (clara u oscura) y la geometría del marco sale de las medidas (--medidas).
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
import json
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
        if atr.get("capa", 0):
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
        # capa: desde Monterey hay renditions extra de capa 2 (una máscara roja lisa); la imagen es la de capa 0.
        if not tipo or atr.get("presentación", 0) or atr.get("capa", 0):
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


def con_medidas(css, medidas, claro):
    """Cambia en la hoja los colores fijos por los de medidas.json de la versión, por su papel:
    windowBackgroundColor (.background), controlBackgroundColor (las vistas) y labelColor (el texto
    de los controles)."""
    if not medidas:
        return css, []
    import json
    try:
        c = json.load(open(medidas))['colores']['claro' if claro else 'oscuro']
    except (OSError, ValueError, KeyError):
        return css, ['medidas sin leer']
    def hexa(k):
        v = c.get(k) or {}
        h, a = v.get('hex'), v.get('alfa', 1)
        if not h:
            return None
        return h if a >= 0.999 else 'rgba(%d, %d, %d, %.2f)' % (int(h[1:3], 16), int(h[3:5], 16), int(h[5:7], 16), a)
    hechos = []
    fondo, vista, texto = hexa('windowBackgroundColor'), hexa('controlBackgroundColor'), hexa('labelColor')
    viejo_fondo, viejo_vista, viejo_texto = ('#ececec', '#ffffff', '#262626') if claro else ('#303031', '#1b1d1f', '#e5e5e5')
    for viejo, nuevo, k in ((viejo_fondo, fondo, 'windowBackgroundColor'), (viejo_vista, vista, 'controlBackgroundColor')):
        if nuevo:
            css = css.replace('background-color: %s;' % viejo, 'background-color: %s;' % nuevo)
            hechos.append(k)
    if texto:
        css = css.replace('@define-color catalina_texto %s;' % viejo_texto, '@define-color catalina_texto %s;' % texto)
        hechos.append('labelColor')
    return css, hechos


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
        def con_capa(pieza, pres, estado):
            """El cuerpo de una pieza y, encima, su capa 7 (desde Monterey el bloque de acento con las flechas ▲▼ va en una imagen aparte del
            mismo lienzo: referencias/.../trabajo-samana-20261026/piezas/INFORME.md). Catálogos sin esa capa (Catalina): el cuerpo solo."""
            cuerpo = p.get((pieza, esc, pres, estado, 0, 0, 0))
            capa = p.get((pieza, esc, pres, estado, 0, 7, 0))
            if cuerpo is None or capa is None or capa.size != cuerpo.size:
                return cuerpo
            lienzo = cuerpo.copy()
            lienzo.alpha_composite(capa)
            return lienzo

        imagenes = {
            "popup": con_capa("popup", 0, 0),
            "popup-apretado": con_capa("popup", 0, 2),
            "popup-desactivado": con_capa("popup", 0, 4),
            "popup-sin-foco": con_capa("popup", 1, 0),
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
    hoja, hechos = con_medidas(hoja_css(claro), MEDIDAS, claro)
    with open(os.path.join(tema, "gtk-3.0", "catalina.css"), "w") as f:
        f.write(hoja)
        f.write('\n/* Colores de la versión (medidas.json): %s */\n' % (', '.join(hechos) or
                                                                     'ninguno: los de las capturas de Catalina'))
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


def marco_medidas(tema, medidas):
    """La geometría del marco que pinta Muffin (headerbar.default-decoration, en catalina.css) con las medidas de la
    versión (medidas.json, ventana): alto de la barra de título, y el padding izquierdo que deja el centro del primer
    semáforo a (x + ancho/2) del borde. El botón de 16 px va centrado en la barra (a la mitad del fotograma que
    mide la versión) y el paso entre centros ya es de 20 (16 de botón + 6 de GTK - 2 de margen): se comprueba contra
    la medida. Calibrado en el Muffin de esta máquina: con padding 6 el centro del primer semáforo cae a 13 px del
    borde de la ventana, o sea centro = padding + 7."""
    v = json.load(open(medidas)).get("ventana") or {}
    sem, alto = v.get("semaforos"), v.get("alto_barra_titulo_pt")
    if not (sem and alto):
        return False
    c, mi = sem["cerrar"], sem["minimizar"]
    if mi["x_pt"] - c["x_pt"] != 20:
        print(f"  ⚠ el paso de los semáforos es {mi['x_pt'] - c['x_pt']}, no 20: el marco queda con el de Catalina")
    centro_x = c["x_pt"] + c["ancho_pt"] / 2
    pad = round(centro_x - 7)
    with open(os.path.join(tema, "gtk-3.0", "catalina.css"), "a") as f:
        f.write(f"\n/* Marco de Muffin, medidas de la versión (ventana.alto_barra_titulo_pt={alto}, semáforos desde {centro_x:g} px) */\n"
                f"headerbar.default-decoration, .csd headerbar.default-decoration {{ min-height: {alto}px; padding: 0 {pad}px; }}\n")
    return True


# Alto de un botón de empuje de Monterey a 1x, medido en 08-pref-com.apple.preference.displays-claro.png
# («Night Shift…»: borde de arriba en y=261, de abajo en y=282 → 22 px). El de Mojave suma 6 px de padding y
# borde a su min-height (20 → 26 px, medido en el Muffin de esta máquina), así que el min-height es 22 - 6.
BOTON_ALTO = 22
BOTON_ALTO_EXTRA = 2


def botones_medidas(tema):
    with open(os.path.join(tema, "gtk-3.0", "catalina.css"), "a") as f:
        f.write(f"\n/* Botón de empuje de Monterey: {BOTON_ALTO} px (captura 08-pref-…displays-claro: Night Shift…) */\n"
                f"button, button.text-button {{ min-height: {BOTON_ALTO - BOTON_ALTO_EXTRA}px; }}\n")


# El slider de Monterey. El .car (Aqua.car) solo trae la máscara de la perilla (Slider_KnobMask_Regular_Horizontal, 21×21 a 1x);
# la pista, el relleno y la perilla los dibuja AppKit, así que los valores salen de la captura
# 08-pref-com.apple.preference.displays-{claro,oscuro}.png (slider «Brightness», 1x): pista de 4 px (y=128..131) con el relleno
# #1B85FB (27,133,251) y el resto #E0DEE0 (224,222,224) en claro; #206DE2 y #3E3A47 en oscuro; perilla blanca de 21 px (x=484..504,
# con borde de 1 px) y sombra de 1 px debajo (y=140, 183 sobre 236). En oscuro la perilla es gris (148,146,153) con el relleno azul (ventana activa): no es
# el aspecto inactivo, que en 06-finder-iconos-activa-oscuro (ventana sin foco) es relleno gris y perilla de contorno oscuro. En
# 03-control-center-oscuro la perilla es blanca, pero es el panel de Control Center, no un NSSlider de ventana.
SLIDER = {
    False: dict(relleno="#206DE2", pista="#3E3A47", perilla="#949299", borde="rgba(0, 0, 0, 0.35)"),
    True: dict(relleno="#1B85FB", pista="#E0DEE0", perilla="#FFFFFF", borde="rgba(0, 0, 0, 0.22)"),
}


def slider_medidas(tema, claro):
    v = SLIDER[claro]
    with open(os.path.join(tema, "gtk-3.0", "catalina.css"), "a") as f:
        f.write(f"""
/* Slider de Monterey (captura 08-pref-…displays: Brightness) */
scale.horizontal trough {{ min-height: 4px; padding: 0; border: none; border-radius: 2px; background: {v['pista']}; }}
scale.horizontal highlight, scale.horizontal fill {{ min-height: 4px; margin: 0; border: none; border-radius: 2px; background: {v['relleno']}; }}
scale slider, scale slider:hover, scale slider:active {{ min-width: 21px; min-height: 21px; margin: -9px; border: 1px solid {v['borde']};
  border-radius: 11px; background: {v['perilla']}; background-image: none; box-shadow: 0 1px 1px rgba(0, 0, 0, 0.18); }}
""")


MEDIDAS = None


# Efectos de ventana y barras de Monterey, de referencias/.../trabajo-samana-20261026/efectos/INFORME.md (capturas 15-force-quit-* y los .car):
#  - esquinas de ventana: 10.33 px medidos con alfa (toolbar, solo título, panel, diálogo, hoja); WindowShapeEdges da 9.5-9.75 pt.
#  - sombra de ventana: NO está en los .car (los CTFX no traen offset ni blur); medida con un ajuste gaussiano en la captura 15-force-quit:
#    activa en claro σ≈17 px, amplitud 0.32, ≈10 px de desplazamiento hacia abajo; inactiva σ≈12, amplitud 0.24. El CSS (blur = 2σ) es hipótesis.
#    En oscuro la amplitud sale de 0.5-0.65 con ruido: hipótesis.
#  - barra de título y de herramientas: color plano, sin degradado (no hay GRAD de toolbar): claro (250,245,249), oscuro (56,52,60).
#  - barra lateral: color plano en la captura: claro (231,226,230), oscuro (70,67,73). Los .car la dan como capa Mica (blur 30), así que llevan el
#    tinte del fondo de pantalla de la Mac de referencia: hipótesis de que valgan para otro fondo.
EFECTOS = {
    True:  {"titulo": "#faf5f9", "lateral": "#e7e2e6", "sombra": "0 10px 34px 5px rgba(0, 0, 0, 0.32)", "sombra_inactiva": "0 8px 24px 3px rgba(0, 0, 0, 0.24)"},
    False: {"titulo": "#38343c", "lateral": "#464349", "sombra": "0 10px 34px 5px rgba(0, 0, 0, 0.55)", "sombra_inactiva": "0 8px 24px 3px rgba(0, 0, 0, 0.40)"},
}
VENTANA_RADIO = 10


# Menús de GTK (menús contextuales y de los programas GTK) con los mismos números que los de Cinnamon (menus/INFORME.md, cambios 2-4, 6, 8, 13):
# caja de 6 px de radio con 4 px de relleno, fila de 22, resaltado de radio 4 con el azul medido (H, varía con el fondo), separador de 1 px, atenuado a 0.25.
MENUS = {
    True:  {"fondo": "#ececec", "borde": "rgba(0, 0, 0, 0.23)", "texto": "#262626", "resalte": "#207ce0", "sep": "rgba(0, 0, 0, 0.10)"},
    False: {"fondo": "#323232", "borde": "rgba(0, 0, 0, 0.85)", "texto": "#e5e5e5", "resalte": "#1c5bb9", "sep": "rgba(255, 255, 255, 0.14)"},
}


def menus_gtk(tema, claro):
    m = MENUS[claro]
    with open(os.path.join(tema, "gtk-3.0", "catalina.css"), "a") as f:
        f.write(f"""
/* Menús de GTK de Monterey (controles.py, MENUS) */
menu, .menu, .context-menu, .popup menu {{
  background-color: {m['fondo']}; color: {m['texto']}; border: 1px solid {m['borde']}; border-radius: 6px; padding: 4px;
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.26); }}
menu menuitem, .menu menuitem, .context-menu menuitem {{
  min-height: 22px; padding: 0 10px 0 9px; border-radius: 4px; color: {m['texto']}; background-image: none; }}
menu menuitem:hover, .menu menuitem:hover, .context-menu menuitem:hover {{ background-color: {m['resalte']}; color: #ffffff; }}
menu menuitem:disabled, .menu menuitem:disabled, .context-menu menuitem:disabled {{ color: alpha({m['texto']}, 0.25); }}
menu separator, .menu separator, .context-menu separator {{ min-height: 1px; margin: 5px 10px; background-color: {m['sep']}; border: none; }}
""")


def efectos_medidos(tema, claro):
    e = EFECTOS[claro]
    r = VENTANA_RADIO
    with open(os.path.join(tema, "gtk-3.0", "catalina.css"), "a") as f:
        f.write(f"""
/* Efectos de Monterey (controles.py, EFECTOS): esquinas de {r} px, barras planas y barra lateral. La sombra NO va aquí: una box-shadow en `.ssd decoration` hace que Muffin la sume al borde invisible
   y el cliente se corre 30 px (probado en Xvfb); la sombra de Muffin se ajusta con su ShadowFactory (extensión), ver EFECTOS */
.ssd decoration {{ border-radius: {r}px {r}px 0 0; }}
headerbar.default-decoration, .csd headerbar.default-decoration {{ border-top-left-radius: {r}px; border-top-right-radius: {r}px; }}
headerbar, .csd headerbar, headerbar.default-decoration, .titlebar:not(headerbar), .maximized headerbar, .tiled headerbar,
headerbar:backdrop, .csd headerbar:backdrop, headerbar.default-decoration:backdrop, .titlebar:not(headerbar):backdrop, .maximized headerbar:backdrop {{
  background-color: {e['titulo']}; background-image: none; }}
.maximized headerbar, .tiled headerbar, .maximized decoration, .tiled decoration {{ border-radius: 0; }}
.sidebar, .nemo-window .sidebar, placessidebar, placessidebar list,
.nemo-window .places-treeview, .nemo-window treeview.places-treeview {{ background-color: {e['lateral']}; }}
""")


# Piezas que solo trae Monterey (o que Mojave pinta con colores planos y aquí se toman del catálogo): el botón default azul y el botón redondo
# de ayuda «?». Fuente de los nombres y los atributos: referencias/.../trabajo-samana-20261026/piezas/INFORME.md (puntos 3 y 5).
#   boton:  PushButton_PushButton_Regular, lienzo 38x32 con el cuerpo en x5..33, y3..27; valor1 = default (azul), presentación1 = ventana sin foco
#           (gris), estado2 = pulsado, estado4 = deshabilitado.
#   ayuda:  RoundHelpButton_Regular, 25x25, el «?» ya va dentro; estado2 pulsado, estado4 deshabilitado.
PIEZAS_MONTEREY = {
    "boton": "PushButton_PushButton_Regular",
    "ayuda": "RoundHelpButton_Regular",
    "pulldown": "PullDownButton_PullDownButton_Regular",
    "disclosure": "DisclosureButton_Regular",
    "seg-pista": "SegmentedControlSlider_SegmentedControl_Regular",
    "seg-pastilla": "SegmentedControlSlider_RoundedSegmentBezel_Regular",
}
def CENTRO(izq, der, solape=None):
    """Las líneas de background del centro de una pieza de tres partes (puntas de izq y der px): el centro se pinta `solape` px bajo cada punta
    (no más: con imágenes translúcidas lo que queda doble se ve más claro u oscuro), para que entre el centro y las puntas no quede la raya clara de
    1 px que dejaba el padding-box."""
    if solape is None:   # piezas opacas: el centro entero bajo las puntas, 2 px menos de cada lado (así se probó que no queda raya)
        return "center / calc(100% - 4px) 100% no-repeat;"
    return f"{izq - solape}px 0 / calc(100% - {izq + der - 2 * solape}px) 100% no-repeat;"


PUNTA_BOTON = 6   # px a 1x de cada punta (el radio ~5 más el borde); el resto es el centro


def recortar(img):
    """El lienzo de Apple sin el margen transparente (el cuerpo solo)."""
    caja = img.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
    return img.crop(caja) if caja else img


def segmentos_pestanas(carpeta, p):
    """Las pestañas de Monterey («Keyboard | Text | Shortcuts» de System Preferences; GtkStackSwitcher): una pista gris translúcida con el
    segmento activo como pastilla blanca (gris claro en oscuro), NO azul (confirmado en las capturas 08-pref-...keyboard--keyboardTab-claro y
    --shortcutsTab-oscuro). Piezas: SegmentedControlSlider_SegmentedControl_Regular (34x24; valor1 sin separador; el separador de 1x12 está en
    valor0, columna central) y SegmentedControlSlider_RoundedSegmentBezel_Regular (30x24). Las puntas de 8 px y el resto son hipótesis de corte.
    Devuelve el CSS (vacío si el catálogo no trae las piezas)."""
    PUNTA = 8
    hechas = {}
    for esc in (1, 2):
        sufijo = "@2" if esc == 2 else ""
        pista = p.get(("seg-pista", esc, 0, 0, 1, 0, 0))
        con_sep = p.get(("seg-pista", esc, 0, 0, 0, 0, 0))
        pastillas = {"seg-pastilla": p.get(("seg-pastilla", esc, 0, 0, 0, 0, 0)),
                     "seg-pastilla-apretada": p.get(("seg-pastilla", esc, 0, 2, 0, 0, 0)),
                     "seg-pastilla-desactivada": p.get(("seg-pastilla", esc, 0, 4, 0, 0, 0)),
                     "seg-pastilla-sin-foco": p.get(("seg-pastilla", esc, 1, 0, 0, 0, 0))}
        if pista is None or con_sep is None or pastillas["seg-pastilla"] is None:
            return ""
        pista = recortar(pista)
        todo = [("seg-pista", pista)] + [(n, recortar(i)) for n, i in pastillas.items() if i is not None]
        for nombre, img in todo:
            img.save(os.path.join(carpeta, nombre + sufijo + ".png"))
            a = PUNTA * esc
            img.crop((a, 0, img.width - a, img.height)).save(os.path.join(carpeta, nombre + "-centro" + sufijo + ".png"))
            hechas[nombre] = img.height // esc
        # el separador: la columna central de la pista con separador, solo las filas que lo traen
        ancho = con_sep.width
        col = con_sep.crop((ancho // 2 - esc // 2 if esc == 1 else ancho // 2 - 1, 0, ancho // 2 + (1 if esc == 1 else 1), con_sep.height))
        caja = col.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
        if caja:
            col.crop((0, caja[1], esc, caja[3])).save(os.path.join(carpeta, "seg-sep" + sufijo + ".png"))
            hechas["seg-sep"] = (caja[3] - caja[1]) // esc
    alto_pista, alto_pastilla = hechas["seg-pista"], hechas["seg-pastilla"]

    def tres_(img, extra=""):
        return (f"  border-style: solid; border-width: 0 {PUNTA}px; border-radius: 0; box-shadow: none;\n"
                f'  border-image: -gtk-scaled(url("catalina/{img}.png"), url("catalina/{img}@2.png")) 0 {PUNTA} 0 {PUNTA} stretch;\n'
                f'  background: -gtk-scaled(url("catalina/{img}-centro.png"), url("catalina/{img}-centro@2.png")) {CENTRO(PUNTA, PUNTA, 2)}\n'
                f"  background-clip: border-box; background-origin: border-box;{extra}")
    # Especificidad alta (.linked, .toggle, :not(...)): el tema de base pinta .linked > button:checked:not(:last-child) con sus propios bordes
    B = "stackswitcher.linked > button:not(.mp-ninguno):not(.mp-ninguna)"
    c = ("\n/* Pestañas de Monterey (controles.py, segmentos_pestanas): pista gris con la pastilla blanca en la activa */\n"
         f"stackswitcher.linked {{\n  min-height: {alto_pista}px; padding: 0; margin: 0;\n{tres_('seg-pista')} }}\n"
         f"{B} {{\n  min-height: {alto_pastilla}px; margin: {(alto_pista - alto_pastilla) // 2}px 0; padding: 0 12px; border: none; border-radius: 0;\n"
         "  box-shadow: none; background: none; text-shadow: none; }\n")
    if "seg-sep" in hechas:
        c += (f"{B}:not(:first-child) {{\n"
              '  background: -gtk-scaled(url("catalina/seg-sep.png"), url("catalina/seg-sep@2.png")) left center no-repeat; }\n'
              f"{B}:checked, {B}:checked + button {{ background-image: none; }}\n")
    # La pastilla va plana (color + radio + sombra leída de la imagen), no en tres partes: es un relleno uniforme translúcido y el corte en tres dejaba
    # una raya clara u oscura en cada punta (en oscuro, blanco con alfa 64: el solape se ve doble y la costura, un hueco).
    def pastilla(nombre):
        from PIL import Image as _I
        img = _I.open(os.path.join(carpeta, nombre + ".png")).convert("RGBA")
        r, g, b_, a = img.getpixel((img.width // 2, img.height // 2))
        sombra = img.getpixel((img.width // 2, img.height - 1))
        sombra_css = f"0 1px 1px rgba(0, 0, 0, {sombra[3] / 255:.2f})" if sombra[3] > 6 and sombra[:3] == (0, 0, 0) else "none"
        return (f"  border: none; border-radius: 6px; background-image: none; background-color: rgba({r}, {g}, {b_}, {a / 255:.3f});\n"
                f"  box-shadow: {sombra_css}; color: @catalina_texto;")
    c += (f"{B}:checked, {B}:active {{\n{pastilla('seg-pastilla')} }}\n"
          f"{B}:checked:active {{\n{pastilla('seg-pastilla-apretada') if 'seg-pastilla-apretada' in hechas else pastilla('seg-pastilla')} }}\n"
          f"{B}:disabled {{ opacity: 0.5; }}\n"
          f"{B}:checked:backdrop {{\n{pastilla('seg-pastilla-sin-foco') if 'seg-pastilla-sin-foco' in hechas else pastilla('seg-pastilla')} }}\n")
    return c


def pulldown(carpeta, p):
    """El botón desplegable con texto de Monterey (PullDownButton, 47x25: cuerpo y, en la capa 7, el bloque con el chevron ⌄), como el popup. Se aplica
    a `menubutton.pulldown > button` (la app lo pide con esa clase: un MenuButton con solo ícono no lleva este cuerpo). Las puntas de 7 y 23 px son
    las del popup (hipótesis para este)."""
    imgs = {}
    for esc in (1, 2):
        sufijo = "@2" if esc == 2 else ""
        for nombre, pres, estado in (("pulldown", 0, 0), ("pulldown-apretado", 0, 2), ("pulldown-desactivado", 0, 4), ("pulldown-sin-foco", 1, 0)):
            cuerpo = p.get(("pulldown", esc, pres, estado, 0, 0, 0))
            capa = p.get(("pulldown", esc, pres, estado, 0, 7, 0))
            if cuerpo is None:
                continue
            img = cuerpo.copy()
            if capa is not None and capa.size == cuerpo.size:
                img.alpha_composite(capa)
            img.save(os.path.join(carpeta, nombre + sufijo + ".png"))
            img.crop((7 * esc, 0, img.width - 23 * esc, img.height)).save(os.path.join(carpeta, nombre + "-centro" + sufijo + ".png"))
            imgs[nombre] = img.height // esc
    if "pulldown" not in imgs:
        return ""

    def tres_(img):
        return ("  border-style: solid; border-width: 0 23px 0 7px; border-radius: 0; box-shadow: none; text-shadow: none;\n"
                f'  border-image: -gtk-scaled(url("catalina/{img}.png"), url("catalina/{img}@2.png")) 0 23 0 7 stretch;\n'
                f'  background: -gtk-scaled(url("catalina/{img}-centro.png"), url("catalina/{img}-centro@2.png")) center / calc(100% - 4px) 100% no-repeat;\n'
                "  background-clip: border-box; background-origin: border-box;")
    # GtkMenuButton es un ToggleButton: el nodo es button.toggle con la clase en él mismo (3.24); `menubutton.pulldown > button` por si el nodo es otro
    def sel(estado=""):
        return f"button.pulldown:not(.mp-ninguno){estado}, menubutton.pulldown > button:not(.mp-ninguno){estado}"
    c = ("\n/* Pull-down de Monterey (controles.py, pulldown): MenuButton con la clase «pulldown» */\n"
         f"{sel()} {{\n  min-height: {imgs['pulldown']}px; padding: 0 4px 1px 2px; color: @catalina_texto;\n{tres_('pulldown')} }}\n")
    for estado, img in ((":checked", "pulldown-apretado"), (":active", "pulldown-apretado"), (":disabled", "pulldown-desactivado"), (":backdrop", "pulldown-sin-foco")):
        if img in imgs:
            c += f"{sel(estado)} {{\n{tres_(img)} }}\n"
    c += "button.pulldown arrow, menubutton.pulldown > button arrow { -gtk-icon-source: none; min-width: 0; min-height: 0; margin: 0; padding: 0; }\n"
    return c


def disclosure(carpeta, p):
    """El botón de acción de Monterey: un chevron ⌄ (⌃ al estar abierto) sin cuerpo (DisclosureButton_Regular, 28x26, imagen fija; el menú de
    acción de la barra del Finder). Clase «accion-disclosure» en un MenuButton (o Button) con solo ícono: la app la pone; aquí solo se dibuja.
    Estados: apretado, deshabilitado y sin foco. El ícono de GTK se oculta (la imagen ya trae el chevron)."""
    hechas = []
    variantes = {"disclosure": (0, 0, 0), "disclosure-abierto": (0, 0, 1), "disclosure-apretado": (0, 2, 0), "disclosure-desactivado": (0, 4, 0),
                 "disclosure-sin-foco": (1, 0, 0)}
    for esc in (1, 2):
        sufijo = "@2" if esc == 2 else ""
        for nombre, (pres, estado, valor) in variantes.items():
            img = p.get(("disclosure", esc, pres, estado, valor, 0, 0))
            if img is None:
                continue
            img.save(os.path.join(carpeta, nombre + sufijo + ".png"))
            if esc == 1:
                hechas.append(nombre)
    if "disclosure" not in hechas:
        return ""

    def fondo(img):
        return (f"  min-width: 22px; min-height: 22px; padding: 0; border: none; border-radius: 0; box-shadow: none; background-color: transparent;\n"
                f'  background-image: -gtk-scaled(url("catalina/{img}.png"), url("catalina/{img}@2.png")); background-position: center; background-size: 28px 26px;\n'
                "  background-repeat: no-repeat;")
    c = "\n/* Botón de acción de Monterey (controles.py, disclosure): clase «accion-disclosure» */\n"
    base = "button.accion-disclosure, menubutton.accion-disclosure > button"
    c += f"{base}, {base}:hover {{\n{fondo('disclosure')} }}\n"
    for estado, img in ((":checked", "disclosure-abierto"), (":active", "disclosure-apretado"), (":disabled", "disclosure-desactivado"),
                        (":backdrop", "disclosure-sin-foco")):
        if img in hechas:
            c += ",\n".join(f"{b}{estado}" for b in base.split(", ")) + f" {{\n{fondo(img)} }}\n"
    c += ("button.accion-disclosure image, button.accion-disclosure arrow, menubutton.accion-disclosure > button image, "
          "menubutton.accion-disclosure > button arrow { -gtk-icon-source: none; min-width: 0; min-height: 0; margin: 0; padding: 0; opacity: 0; }\n")
    return c


def monterey_botones(tema, oscuros, claro, acento=None):
    """Escribe el botón default y el botón de ayuda de Monterey en gtk-3.0/catalina/ y su CSS al final de catalina.css."""
    tabla = {k: v for k, v in PIEZAS.items()}
    PIEZAS.update(PIEZAS_MONTEREY)
    try:
        p = piezas(oscuros)
    finally:
        for k in PIEZAS_MONTEREY:
            if k not in tabla:
                PIEZAS.pop(k, None)
    carpeta = os.path.join(tema, "gtk-3.0", "catalina")
    os.makedirs(carpeta, exist_ok=True)
    hechos = []
    variantes = {  # nombre: (pieza, presentación, estado, valor)
        "boton-default": ("boton", 0, 0, 1), "boton-default-apretado": ("boton", 0, 2, 1),
        "boton-default-desactivado": ("boton", 0, 4, 1), "boton-default-sin-foco": ("boton", 1, 0, 1),
        "ayuda": ("ayuda", 0, 0, 0), "ayuda-apretado": ("ayuda", 0, 2, 0),
        "ayuda-desactivado": ("ayuda", 0, 4, 0), "ayuda-sin-foco": ("ayuda", 1, 0, 0),
    }
    for esc in (1, 2):
        sufijo = "@2" if esc == 2 else ""
        for nombre, (pieza, pres, estado, valor) in variantes.items():
            img = p.get((pieza, esc, pres, estado, valor, 0, 0))
            if img is None:
                continue
            img = recortar(img)
            if acento and acento != 'Blue' and nombre.startswith("boton-default") and not nombre.endswith("sin-foco"):
                img = tenir(img.copy(), acento)
            img.save(os.path.join(carpeta, nombre + sufijo + ".png"))
            if nombre.startswith("boton-"):
                a = PUNTA_BOTON * esc
                img.crop((a, 0, img.width - a, img.height)).save(os.path.join(carpeta, nombre + "-centro" + sufijo + ".png"))
            if esc == 1 and nombre not in hechos:
                hechos.append(nombre)
    if not hechos:
        return False

    def borde(img):
        # min-height = el alto de la imagen (23 px a 1x): sin escala vertical no se mezcla el borde de las puntas con lo transparente de afuera
        # (se veía una raya clara a 6 px del borde en el botón azul)
        return (f"  min-height: {alto1x}px; padding-top: 0; padding-bottom: 0;\n"
                f"  border-style: solid; border-width: 0 {PUNTA_BOTON}px; border-radius: 0; box-shadow: none;\n"
                f'  border-image: -gtk-scaled(url("catalina/{img}.png"), url("catalina/{img}@2.png")) 0 {PUNTA_BOTON} 0 {PUNTA_BOTON} stretch;\n'
                f'  background: -gtk-scaled(url("catalina/{img}-centro.png"), url("catalina/{img}-centro@2.png")) {CENTRO(PUNTA_BOTON, PUNTA_BOTON)}\n'
                "  background-clip: border-box; background-origin: border-box; text-shadow: none; color: #ffffff;")
    alto1x = Image.open(os.path.join(carpeta, "boton-default.png")).height if "boton-default" in hechos else 23
    css_ = "\n/* Botón default y botón de ayuda de Monterey (controles.py, monterey_botones) */\n"
    # El centro se pinta 2 px por debajo de cada punta (calc(100% - 4px), centrado): con el centro solo dentro del padding-box, entre el centro y las
    # puntas quedaba una raya clara de 1 px (probado en Xvfb). También en el popup, que tiene la misma costura.
    css_ += ("combobox button.combo, .background combobox button.combo, combobox button.combo:hover, combobox button.combo:active,\n"
             "combobox button.combo:checked, combobox button.combo:backdrop, combobox button.combo:disabled {\n"
             "  background-clip: border-box; background-origin: border-box; background-size: calc(100% - 4px) 100%; background-position: center; }\n")
    if "boton-default" in hechos:
        sel = "button.suggested-action, .background button.suggested-action, button.default, .background button.default"
        css_ += f"{sel}, {sel.replace('button.suggested-action', 'button.suggested-action:hover').replace('button.default', 'button.default:hover')} {{\n{borde('boton-default')} }}\n"
        for estado, img in ((":active", "boton-default-apretado"), (":checked", "boton-default-apretado"),
                            (":disabled", "boton-default-desactivado"), (":backdrop", "boton-default-sin-foco")):
            if img in hechos:
                css_ += f"button.suggested-action{estado}, button.default{estado} {{\n{borde(img)} }}\n"
        css_ += "button.suggested-action:backdrop, button.default:backdrop { color: #262626; }\n"
    css_ += segmentos_pestanas(carpeta, p)
    css_ += pulldown(carpeta, p)
    css_ += disclosure(carpeta, p)
    if "ayuda" in hechos:
        def redondo(img):
            return ("  min-width: 22px; min-height: 22px; padding: 0; border: none; border-radius: 0; box-shadow: none; text-shadow: none;\n"
                    f'  background: -gtk-scaled(url("catalina/{img}.png"), url("catalina/{img}@2.png")) center / 25px 25px no-repeat;')
        css_ += f"button.circular, button.circular:hover {{\n{redondo('ayuda')} }}\n"
        for estado, img in ((":active", "ayuda-apretado"), (":disabled", "ayuda-desactivado"), (":backdrop", "ayuda-sin-foco")):
            if img in hechos:
                css_ += f"button.circular{estado} {{\n{redondo(img)} }}\n"
    with open(os.path.join(tema, "gtk-3.0", "catalina.css"), "a") as f:
        f.write(css_)
    return True


def main():
    global MEDIDAS
    if '--medidas' in sys.argv:
        i = sys.argv.index('--medidas')
        MEDIDAS = sys.argv[i + 1]
        del sys.argv[i:i + 2]
    claro = '--claro' in sys.argv
    por_apariencia = '--metacity-claro' in sys.argv  # los semáforos de metacity-1 de la variante clara salen de la apariencia clara
    por_version = '--version-propia' in sys.argv      # no es Catalina: sus medidas y su apariencia clara
    acento = sys.argv[sys.argv.index('--acento') + 1] if '--acento' in sys.argv else None
    sys.argv = [a for i, a in enumerate(sys.argv)
                if a not in ('--claro', '--version-propia', '--metacity-claro') and a != '--acento' and not (i > 0 and sys.argv[i - 1] == '--acento')]
    if len(sys.argv) != 4 or (acento and acento not in ACENTOS):
        sys.exit(__doc__)
    claros, oscuros = semaforos(sys.argv[1]), semaforos(sys.argv[2])
    if not oscuros:
        sys.exit("  ✗ no salieron los semáforos del catálogo (¿falta liblzfse?)")
    m = metacity(sys.argv[3], (claros or oscuros) if ((por_version or por_apariencia) and claro) else oscuros)
    claras, oscuras = marcas(sys.argv[1]), marcas(sys.argv[2])
    g = gresource(sys.argv[3], claros or oscuros, oscuros, claras or oscuras, oscuras)
    marco(sys.argv[3])
    # Las piezas de la apariencia de la variante: la clara para Constanza-Claro.
    c = css(sys.argv[3], sys.argv[1] if claro else sys.argv[2], claro, acento)
    if por_version and MEDIDAS:
        marco_medidas(sys.argv[3], MEDIDAS)
        botones_medidas(sys.argv[3])
        slider_medidas(sys.argv[3], claro)
        monterey_botones(sys.argv[3], sys.argv[1] if claro else sys.argv[2], claro, acento)
        efectos_medidos(sys.argv[3], claro)
        menus_gtk(sys.argv[3], claro)
    print(f"  controles de Catalina: {m} semáforos en metacity-1, {g} imágenes en gtk.gresource"
          f" y {c} piezas en catalina/")


if __name__ == "__main__":
    main()
