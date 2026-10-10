#!/usr/bin/env python3
"""La manzana del menú Apple, sacada de la fuente del sistema de la Mac.

En macOS la manzana de la barra es el carácter U+F8FF de San Francisco, así
que sale vectorial de SFNS.ttf (la que copia fuentes/desde-mac.sh). Deja en
~/.local/share/constanza/manzana/:
  apple-menu.svg        blanca, recortada justo al contorno de la manzana
  apple-menu.png        a 1x, de ALTO px de alto (16 por defecto)
  apple-menu@2x.png     a 2x
Uso local: la fuente y lo que sale de ella no van al repo.
Sale con 3 si no está SFNS.ttf o no trae la manzana.

Uso: desde-fuente.py [alto en px a 1x]
"""
import os, sys
from PIL import Image, ImageDraw, ImageFont
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.boundsPen import BoundsPen

FUENTE = os.path.expanduser('~/.local/share/fonts/san-francisco/SFNS.ttf')
DEST = os.path.expanduser('~/.local/share/constanza/manzana')
ALTO = int(sys.argv[1]) if len(sys.argv) > 1 else 16

if not os.path.exists(FUENTE):
    print('  manzana: falta SFNS.ttf (corre fuentes/desde-mac.sh con el disco de la Mac)'); sys.exit(3)
f = TTFont(FUENTE)
nombre = f.getBestCmap().get(0xF8FF)
if not nombre:
    print('  manzana: SFNS.ttf no trae U+F8FF'); sys.exit(3)
glifos = f.getGlyphSet()
bp = BoundsPen(glifos); glifos[nombre].draw(bp)
x0, y0, x1, y1 = bp.bounds
pp = SVGPathPen(glifos); glifos[nombre].draw(pp)
ancho, alto = x1 - x0, y1 - y0
# Las fuentes tienen la y hacia arriba; el SVG, hacia abajo.
svg = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {ancho:g} {alto:g}" '
       f'width="{ancho / alto * ALTO:.2f}" height="{ALTO}">'
       f'<path fill="#ffffff" transform="matrix(1 0 0 -1 {-x0:g} {y1:g})" d="{pp.getCommands()}"/></svg>\n')
os.makedirs(DEST, exist_ok=True)
ruta = os.path.join(DEST, 'apple-menu.svg')
with open(ruta, 'w') as s:
    s.write(svg)
# Los PNG salen de la fuente con FreeType, dibujados grandes y reducidos:
# así no hace falta un rasterizador de SVG.
GRANDE = 512
letra = ImageFont.truetype(FUENTE, GRANDE)
lienzo = Image.new('L', (GRANDE * 2, GRANDE * 2), 0)
ImageDraw.Draw(lienzo).text((GRANDE // 2, GRANDE // 2), '\uf8ff', font=letra, fill=255)
mascara = lienzo.crop(lienzo.getbbox())
for esc, sufijo in ((1, ''), (2, '@2x')):
    h = ALTO * esc
    w = round(mascara.width * h / mascara.height)
    a = mascara.resize((w, h), Image.LANCZOS)
    im = Image.new('RGBA', (w, h), (255, 255, 255, 0)); im.putalpha(a)
    im.save(os.path.join(DEST, f'apple-menu{sufijo}.png'))
print(f'  manzana: {ruta} ({ancho / alto * ALTO:.1f}×{ALTO} px a 1x, y sus PNG)')
