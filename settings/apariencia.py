#!/usr/bin/env python3
"""Las miniaturas Light, Dark y Auto de General (Appearance), armadas con el fondo de Catalina.

    apariencia.py [carpeta de fondos] [destino]

Light usa «Catalina Light» y Dark «Catalina Dark» (el cuadro más claro y el más oscuro de Catalina.heic) (de ~/.local/share/mint-macos/fondos, que saca
fondos.py del disco de la Mac); Auto es la mitad de cada una. Sobre el fondo van una barra de menús con
un título resaltado en azul y su menú desplegado, y una ventana con los tres botones de color y su barra
lateral, en claro o en oscuro, a 134×88 (la miniatura de 67×44 de Catalina a 2x), con las esquinas
redondeadas. Es una composición propia (las miniaturas de Apple están en un catálogo que no se abre):
la forma, el tamaño y la disposición salen de la captura 12.11.59 AM. Nada de esto va al repo: el
destino por defecto es ~/.local/share/mint-macos/settings/apariencia.
"""
import os
import sys

from PIL import Image, ImageDraw

ANCHO, ALTO, ESC = 134, 88, 4          # se dibuja a 4x y se baja con LANCZOS


def fondo(ruta):
    im = Image.open(ruta).convert("RGB")
    r = max(ANCHO * ESC / im.width, ALTO * ESC / im.height)
    im = im.resize((int(im.width * r) + 1, int(im.height * r) + 1), Image.LANCZOS)
    x, y = (im.width - ANCHO * ESC) // 2, (im.height - ALTO * ESC) // 2
    return im.crop((x, y, x + ANCHO * ESC, y + ALTO * ESC)).convert("RGBA")


def capa(im, forma, color, radio=0):
    """Dibuja un rectángulo (x0, y0, x1, y1 a 1x) translúcido encima."""
    tapa = Image.new("RGBA", im.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(tapa)
    caja = [v * ESC for v in forma]
    (d.rounded_rectangle(caja, radius=radio * ESC, fill=color) if radio else d.rectangle(caja, fill=color))
    return Image.alpha_composite(im, tapa)


def escena(ruta, oscuro, x0=0, x1=ANCHO):
    """El fondo con la barra de menús, el menú abierto y la ventana, solo entre x0 y x1 (a 1x)."""
    im = fondo(ruta)
    barra = (28, 34, 52, 215) if oscuro else (236, 236, 240, 225)
    menu = (26, 32, 46, 230) if oscuro else (232, 232, 238, 235)
    ventana = (46, 46, 48, 255) if oscuro else (236, 236, 236, 255)
    lateral = (38, 41, 44, 255) if oscuro else (214, 214, 216, 255)
    cuerpo = (28, 28, 30, 255) if oscuro else (255, 255, 255, 255)
    im = capa(im, (0, 0, ANCHO, 9), barra)
    im = capa(im, (14, 0, 56, 9), (0, 122, 255, 255))
    im = capa(im, (14, 9, 56, 19), menu)
    im = capa(im, (22, 43, ANCHO, ALTO), ventana)
    im = capa(im, (22, 61, 70, ALTO), lateral)
    im = capa(im, (70, 61, ANCHO, ALTO), cuerpo)
    d = ImageDraw.Draw(im)
    for i, c in enumerate(((255, 95, 87), (255, 189, 46), (39, 201, 63))):
        cx, cy, r = (30 + i * 11) * ESC, 52 * ESC, 4 * ESC
        d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=c + (255,))
    # Solo se queda la franja pedida (para Auto: la mitad de cada una).
    mascara = Image.new("L", im.size, 0)
    ImageDraw.Draw(mascara).rectangle((x0 * ESC, 0, x1 * ESC, ALTO * ESC), fill=255)
    vacia = Image.new("RGBA", im.size, (0, 0, 0, 0))
    return Image.composite(im, vacia, mascara)


def redondear(im):
    m = Image.new("L", im.size, 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, im.width - 1, im.height - 1), radius=9 * ESC, fill=255)
    salida = Image.new("RGBA", im.size, (0, 0, 0, 0))
    salida.paste(im, (0, 0), m)
    return salida.resize((ANCHO, ALTO), Image.LANCZOS)


def main():
    fondos = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/.local/share/mint-macos/fondos")
    destino = sys.argv[2] if len(sys.argv) > 2 else os.path.expanduser("~/.local/share/mint-macos/settings/apariencia")
    dia = os.path.join(fondos, "fotos", "Catalina Light.jpg")
    noche = os.path.join(fondos, "fotos", "Catalina Dark.jpg")
    for r in (dia, noche):
        if not os.path.exists(r):
            sys.exit(f"✗ Falta {r}: corre fondos.py primero.")
    os.makedirs(destino, exist_ok=True)
    mitad = ANCHO // 2
    claro = escena(dia, False)
    oscuro = escena(noche, True)
    auto = Image.alpha_composite(escena(dia, False, 0, mitad), escena(noche, True, mitad, ANCHO))
    for nombre, im in (("light", claro), ("dark", oscuro), ("auto", auto)):
        redondear(im).save(os.path.join(destino, nombre + ".png"))
        print("  ✓", nombre)


if __name__ == "__main__":
    main()
