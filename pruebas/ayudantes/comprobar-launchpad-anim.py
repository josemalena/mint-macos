#!/usr/bin/env python3
"""comprobar-launchpad-anim.py LOG abrir|cerrar MS CURVA ESCALA — el registro de LAUNCHPAD_DEBUG contra la curva del perfil (caso 114).

Cada cuadro pintado durante la animación anota «abrir t=… alfa=… escala=…» (o «cerrar …»); aquí la curva se calcula de nuevo, aparte del código
(cubic-bezier de las curvas por omisión del motor de la Mac), y se compara: alfa y escala por cuadro, que ningún cuadro pase de la duración y, al cerrar, que la ventana se esconda al cumplirse la duración. Sale 0 si todo cuadra."""
import re, sys

log, fase, ms, curva, escala = sys.argv[1], sys.argv[2], float(sys.argv[3]) / 1000, sys.argv[4], float(sys.argv[5])
P = {'easeIn': (0.42, 0, 1, 1), 'easeOut': (0, 0, 0.58, 1), 'easeInEaseOut': (0.42, 0, 0.58, 1)}[curva]

def bezier(x):
    x1, y1, x2, y2 = P
    t = x
    for _ in range(60):   # Newton
        u = 1 - t
        fx = 3 * u * u * t * x1 + 3 * u * t * t * x2 + t ** 3 - x
        dfx = 3 * u * u * x1 + 6 * u * t * (x2 - x1) + 3 * t * t * (1 - x2)
        if abs(fx) < 1e-9 or abs(dfx) < 1e-9:
            break
        t -= fx / dfx
    u = 1 - t
    return 3 * u * u * t * y1 + 3 * u * t * t * y2 + t ** 3

texto = open(log).read()
cuadros = [(float(a), float(b), float(c)) for a, b, c in re.findall(fase + r' t=([0-9.]+) alfa=([0-9.]+) escala=([0-9.]+)', texto)]
# (el servidor de la prueba pinta a pocos cuadros por segundo —cada uno pasa de 50 ms con la máquina cargada—: basta con uno o dos; cada uno
# trae su tiempo, así que la curva y la duración se comprueban igual)
if len(cuadros) < 1:
    print('ningún cuadro de %s' % fase); sys.exit(1)
peor = 0.0
for t, alfa, e in cuadros:
    f = bezier(min(1.0, t / ms))
    esp_alfa = f if fase == 'abrir' else 1 - f
    esp_esc = 1 + (escala - 1) * ((1 - f) if fase == 'abrir' else f)
    peor = max(peor, abs(alfa - esp_alfa), abs(e - esp_esc) / max(escala - 1, 1e-9) * 0.5)
ultimo = max(t for t, _, _ in cuadros)
print('%s: %d cuadros, el último a %.0f ms de %.0f, peor diferencia %.3f' % (fase, len(cuadros), ultimo * 1000, ms * 1000, peor))
if peor > 0.03 or ultimo > ms:
    sys.exit(1)
if fase == 'cerrar':
    m = re.search(r'cerrar fin t=([0-9.]+)', texto)
    if not m or not (ms <= float(m.group(1)) <= ms + 0.6):
        print('la ventana no se escondió al cumplirse los %.0f ms: %s' % (ms * 1000, m and m.group(1))); sys.exit(1)
