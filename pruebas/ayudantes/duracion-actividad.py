#!/usr/bin/env python3
"""duracion-actividad.py VIDEO [x0,y0,x1,y1] — los tramos en que cambia la pantalla grabada (x11grab, pts reales), con su duración.

Por cuadro se mira qué fracción de píxeles cambió respecto al anterior (gris, a 1/4 de tamaño); los cuadros con cambio separados por menos de
100 ms son un mismo tramo. Imprime una línea JSON por tramo: inicio_ms (desde el primer cuadro), ms (del cuadro anterior al primer cambio, hasta
el último cambio: la misma regla que las medidas de la Mac, un cuadro de precisión) y cuadros. Lo usan los casos que comparan una animación con el perfil."""
import json, re, subprocess, sys
import numpy as np

video = sys.argv[1]
reg = [int(v) for v in sys.argv[2].split(',')] if len(sys.argv) > 2 else None
d = subprocess.run(['ffprobe', '-v', 'error', '-select_streams', 'v:0', '-show_entries', 'stream=width,height', '-of', 'csv=p=0', video],
                   capture_output=True, text=True).stdout.strip().split(',')
W, H = int(d[0]), int(d[1])
filtro = 'format=gray'
if reg:
    x0, y0, x1, y1 = reg
    filtro = 'crop=%d:%d:%d:%d,format=gray' % (x1 - x0, y1 - y0, x0, y0)
    W, H = x1 - x0, y1 - y0
w, h = max(W // 4, 1), max(H // 4, 1)
p = subprocess.run(['ffmpeg', '-loglevel', 'info', '-i', video, '-fps_mode', 'passthrough', '-vf', filtro + ',scale=%d:%d:flags=area,showinfo' % (w, h),
                    '-f', 'rawvideo', '-'], capture_output=True)
pts = [float(m) for m in re.findall(r'pts_time:([0-9.]+)', p.stderr.decode())]
c = np.frombuffer(p.stdout, np.uint8).reshape(-1, h, w).astype(int)
cambio = [0.0] + [float((np.abs(c[i] - c[i - 1]) > 12).mean()) for i in range(1, len(c))]
tramos, ini, fin = [], None, None
for i, f in enumerate(cambio):
    if f > 0.0004:
        if ini is not None and pts[i] - pts[fin] > 0.1:
            tramos.append((ini, fin)); ini = None
        if ini is None:
            ini = i
        fin = i
if ini is not None:
    tramos.append((ini, fin))
for a, b in tramos:
    print(json.dumps({'inicio_ms': round(pts[a] * 1000), 'ms': round((pts[b] - pts[a - 1]) * 1000), 'cuadros': b - a + 1}))
