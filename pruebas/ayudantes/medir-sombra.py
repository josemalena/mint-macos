#!/usr/bin/env python3
"""medir-sombra.py CAPTURA X_BORDE Y — la sombra a la izquierda de una ventana, sobre fondo blanco (caso 117).

CAPTURA es la pantalla (fondo blanco, una ventana); X_BORDE, la x del borde izquierdo de la ventana y Y, una fila a media altura (lejos de las
esquinas y del desplazamiento vertical). La sombra gaussiana de un borde recto vale A/2 en el borde y A·(1-Φ(d/σ)) a d píxeles: se imprime
«oscuridad_en_el_borde sigma_px» con la oscuridad de 0 a 1 y σ como la distancia en que cae a 0.317 de la del borde."""
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert('L')
xb, y = int(sys.argv[2]), int(sys.argv[3])
# el borde de verdad: el salto más grande de brillo cerca de la x dada (el marco de la ventana no empieza en la x que da el gestor)
xb = max(range(xb - 20, xb + 20), key=lambda x: abs(im.getpixel((x, y)) - im.getpixel((x - 1, y))))
osc = [(255 - im.getpixel((xb - 2 - d, y))) / 255.0 for d in range(0, min(xb, 80))]
borde = osc[0]
if borde <= 0.01:
    print('0 0'); sys.exit(0)
sigma = next((d for d, v in enumerate(osc) if v <= borde * 0.317), len(osc))
print('%.3f %d' % (borde, sigma))
