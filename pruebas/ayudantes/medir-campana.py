#!/usr/bin/env python3
"""medir-campana.py CAPTURA CX — la forma de la lupa del Muelle con el puntero en CX (caso 110).

CAPTURA es la pantalla con la lupa completa. Del borde de arriba de lo dibujado se saca la altura de cada columna: el centro debe ser ~2.0× la de
las puntas (en reposo), bajar sin saltos hacia los lados y quedar a 1.7–1.8× a unos 3 anchos (lo medido en la Mac, dock-lupa/INDICE.md).
El ancho de un ícono se saca de la propia captura (distancia entre las puntas de los íconos en reposo)."""
import sys
import numpy as np
from PIL import Image

im = np.array(Image.open(sys.argv[1]).convert('L')).astype(int)
cx = int(sys.argv[2])
H, W = im.shape
franja = im[H - 200:H - 12]
def altura(x):
    """La tira seguida de abajo hacia arriba (la etiqueta que sale sobre el ícono queda separada por un hueco y no cuenta)."""
    hay = franja[::-1, x] < 235
    ini = next((i for i in range(25) if hay[i]), None)
    if ini is None:
        return 0
    n = ini
    while n < len(hay) and hay[n]:
        n += 1
    return n - ini

alto = np.array([altura(x) for x in range(W)])
activas = np.where(alto > 0)[0]
izq, der = activas.min(), activas.max()
reposo = float(np.median(np.concatenate([alto[izq:izq + 25], alto[der - 25:der]])))
centro = float(alto[cx - 20:cx + 20].max())
# ancho de un paso: el ícono a d pasos del puntero (en reposo) queda corrido (f-1)·d·(1-p²/3) pasos (lo que
# ocupan al crecer los de antes) y debe medir 1+(f-1)(1-p²) con p = d/6 (la campana medida)
arranques = [x for x in range(izq, izq + 200) if alto[x] > 0 and alto[x - 1] == 0]
paso = float(arranques[1] - arranques[0])   # lo que hay entre centros de dos íconos en reposo (los de la punta)
f = 2.0
peor = 0.0
for d in range(1, 7):   # (a 0 pasos el puntero no cae en el centro de un ícono)
    p = d / 6.0
    x = cx + (d + (f - 1) * d * (1 - p * p / 3)) * paso * (1 if d else 0)
    esperado = 1 + (f - 1) * (1 - p * p)
    medido = float(alto[int(x) - 14:int(x) + 14].max()) / reposo
    peor = max(peor, abs(medido - esperado))
    print('  a %d pasos: %.2f× (esperado %.2f)' % (d, medido, esperado), file=sys.stderr)
print('reposo %.0f px, peor diferencia %.2f' % (reposo, peor), file=sys.stderr)
sys.exit(0 if peor <= 0.12 else 1)
