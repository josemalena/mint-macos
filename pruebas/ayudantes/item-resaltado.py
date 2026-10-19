#!/usr/bin/env python3
"""item-resaltado.py ANTES.png DESPUES.png: la caja y el color del ítem que se resaltó entre las dos capturas: X0,Y0,X1,Y1,R,G,B."""
import sys
from PIL import Image, ImageChops

a = Image.open(sys.argv[1]).convert("RGB")
b = Image.open(sys.argv[2]).convert("RGB")
caja = ImageChops.difference(a, b).getbbox()
if not caja:
    print("0,0,1,1,0,0,0")
else:
    x0, y0, x1, y1 = caja
    c = b.getpixel(((x0 + x1) // 2, y0 + 4))
    print("%d,%d,%d,%d,%d,%d,%d" % (x0 + 6, y0 + 3, x1 - 6, y1 - 3, c[0], c[1], c[2]))
