#!/usr/bin/env python3
# El nombre que sale debajo del ícono en el Startup Manager de la Mac (⌥ al
# encender): .disk_label (pantallas normales, la MacBook de 2008) y
# .disk_label_2x (Retina), sin bless. Van en la carpeta del cargador
# (EFI/BOOT de la partición EFI).
#
#   python3 etiqueta-disco.py "sapOS" [carpeta]
#
# El formato (el de bless, BLGenerateLabelData): un byte de versión (1), el
# ancho y el alto en big-endian de 16 bits, y un byte por píxel. El byte NO es
# el gris: es un índice de la paleta de 8 bits de la Mac, y solo se usan 16
# tonos. Escribir el gris tal cual (0-255) pinta colores sueltos de la paleta.
# Comprobado contra las etiquetas que hizo bless (10-11-2026): usan exactamente
# estos 16 valores.
import os
import struct
import sys

from PIL import Image, ImageDraw, ImageFont

# Del más claro (fondo, transparente) al texto lleno, de 16 en 16 niveles de gris.
PALETA = bytes((0x00, 0xF6, 0xF7, 0x2A, 0xF8, 0xF9, 0x55, 0xFA,
                0xFB, 0x80, 0xFC, 0xFD, 0xAB, 0xFE, 0xFF, 0xD6))

# La fuente de la Mac si desde-mac.sh la dejó; si no, la de Mint. Con sudo, el
# HOME es el de root: icono-disco.sh pasa el del usuario en ETIQUETA_HOME.
_HOME = os.environ.get("ETIQUETA_HOME") or os.path.expanduser("~")
FUENTES = (os.path.join(_HOME, ".local/share/fonts/san-francisco/SFNS.ttf"),
           "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf")

# El alto del texto en píxeles: el de las etiquetas de bless (12 y 24 con margen).
ALTO = {1: 11, 2: 22}


def fuente(px):
    for ruta in FUENTES:
        if os.path.exists(ruta):
            return ImageFont.truetype(ruta, px)
    sys.exit("✗ no encuentro ninguna fuente: " + ", ".join(FUENTES))


def etiqueta(texto, escala):
    f = fuente(ALTO[escala])
    medir = ImageDraw.Draw(Image.new("L", (1, 1)))
    x0, y0, x1, y1 = medir.textbbox((0, 0), texto, font=f)
    margen = escala
    img = Image.new("L", (x1 - x0 + 2 * margen, y1 - y0 + 2 * margen), 0)
    ImageDraw.Draw(img).text((margen - x0, margen - y0), texto, font=f, fill=255)
    pixeles = bytes(PALETA[g >> 4] for g in img.tobytes())
    return struct.pack(">BHH", 1, img.width, img.height) + pixeles, img.size


def main():
    if len(sys.argv) < 2:
        sys.exit('uso: etiqueta-disco.py "Texto" [carpeta]')
    texto, carpeta = sys.argv[1], (sys.argv[2] if len(sys.argv) > 2 else ".")
    for escala, nombre in ((1, ".disk_label"), (2, ".disk_label_2x")):
        datos, (w, h) = etiqueta(texto, escala)
        with open(os.path.join(carpeta, nombre), "wb") as out:
            out.write(datos)
        print(f"  {nombre}: «{texto}», {w}×{h}")


if __name__ == "__main__":
    main()
