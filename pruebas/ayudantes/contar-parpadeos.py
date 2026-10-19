#!/usr/bin/env python3
"""contar-parpadeos.py CARPETA X0,Y0,X1,Y1,R,G,B: cuántas veces el rectángulo (del color R,G,B) se apaga y vuelve a encender en los cuadros PNG."""
import glob
import sys
from PIL import Image

carpeta, caja = sys.argv[1], sys.argv[2].split(",")
x0, y0, x1, y1 = [int(v) for v in caja[:4]]
objetivo = tuple(int(v) for v in caja[4:7])
estado = []
for f in sorted(glob.glob(carpeta + "/*.png")):
    im = Image.open(f).convert("RGB").crop((x0, y0, x1, y1))
    cerca = sum(1 for p in im.getdata() if all(abs(p[i] - objetivo[i]) < 12 for i in range(3)))
    estado.append(cerca > 0.5 * (x1 - x0) * (y1 - y0))
print(sum(1 for a, b in zip(estado, estado[1:]) if (not a) and b))   # apagado y de vuelta encendido; cerrarse el menú no vuelve
