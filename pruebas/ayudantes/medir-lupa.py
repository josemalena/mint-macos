#!/usr/bin/env python3
"""medir-lupa.py VIDEO CX [ANCHO_BANDA] — cuánto tarda en crecer el ícono bajo el puntero (caso 110).

VIDEO es la franja de abajo de la pantalla grabada a 60 cuadros por segundo (x11grab, pts reales); CX, la x del puntero. Por cuadro se
busca la fila más alta que cambió respecto al primero dentro de una banda angosta alrededor del puntero: el ícono crece hacia arriba.
Imprime en JSON: ms (de 10 % a 90 % del crecimiento), el máximo en px, y el error máximo contra la recta y contra la curva easeOutCubic
(la de antes), para saber cuál de las dos se parece más. Precisión: un cuadro (16.7 ms)."""
import json, re, subprocess, sys
import numpy as np

video, cx = sys.argv[1], int(sys.argv[2])
banda = int(sys.argv[3]) if len(sys.argv) > 3 else 30
dims = subprocess.run(['ffprobe', '-v', 'error', '-select_streams', 'v:0', '-show_entries', 'stream=width,height', '-of', 'csv=p=0', video],
                      capture_output=True, text=True).stdout.strip().split(',')
W, H = int(dims[0]), int(dims[1])
p = subprocess.run(['ffmpeg', '-loglevel', 'info', '-i', video, '-fps_mode', 'passthrough', '-vf', 'format=gray,showinfo', '-f', 'rawvideo', '-'], capture_output=True)
pts = [float(m) for m in re.findall(r'pts_time:([0-9.]+)', p.stderr.decode())]
cuadros = np.frombuffer(p.stdout, np.uint8).reshape(-1, H, W)[:, :, max(0, cx - banda):cx + banda].astype(int)
def altura(c):
    """El alto del ícono bajo el puntero: la tira seguida de abajo hacia arriba en la banda (la etiqueta que sale arriba va separada
    por un hueco y no cuenta), sobre el fondo blanco de la prueba."""
    mejor = 0
    for x in range(c.shape[1]):
        hay = c[:-12][::-1, x] < 235
        ini = next((i for i in range(25) if hay[i]), None)
        if ini is None:
            continue
        n = ini
        while n < len(hay) and hay[n]:
            n += 1
        mejor = max(mejor, n - ini)
    return mejor

altos = np.array([altura(c) for c in cuadros], float)
reposo = altos[0]
altos = altos - reposo   # lo que crece
# el crecimiento empieza en el primer cuadro con 8 px o más (menos es el ruido del puntero al llegar) y se mide en los 800 ms que siguen
ini = int(np.argmax(altos >= 8))
if altos[ini] < 8:
    print(json.dumps({'error': 'el ícono no creció'})); sys.exit(1)
ventana = [i for i in range(ini, len(altos)) if pts[i] - pts[ini] <= 0.8]
maximo = altos[ventana].max()
prog = altos / maximo
t0 = pts[ini - 1]   # el cuadro anterior: el crecimiento empezó entre ese y este
fin = next(i for i in ventana if prog[i] >= 0.98)
print(json.dumps({'ms_hasta_98': round((pts[fin] - t0) * 1000), 'ms_cota_baja': round((pts[fin] - pts[ini]) * 1000),
                  'alto_max_px': int(maximo), 'cuadros_en_el_tramo': fin - ini + 1,
                  'nota': 'Xvfb pinta pocos cuadros por segundo: la duración vale, la forma de la curva no'}))
