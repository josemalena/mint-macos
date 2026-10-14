#!/usr/bin/env python3
"""Los controles de Catalina en el tema GTK: los semáforos de las ventanas,
las casillas y los radios, sacados de los catálogos de apariencia del disco
de la Mac.

    controles.py <SystemAppearance.car> <DarkAquaAppearance.car> <tema>

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


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    claros, oscuros = semaforos(sys.argv[1]), semaforos(sys.argv[2])
    if not oscuros:
        sys.exit("  ✗ no salieron los semáforos del catálogo (¿falta liblzfse?)")
    m = metacity(sys.argv[3], oscuros)
    claras, oscuras = marcas(sys.argv[1]), marcas(sys.argv[2])
    g = gresource(sys.argv[3], claros or oscuros, oscuros, claras or oscuras, oscuras)
    print(f"  controles de Catalina: {m} semáforos en metacity-1 y {g} imágenes en gtk.gresource")


if __name__ == "__main__":
    main()
