"""Regla 2: el tamaño de la ventana y el orden de arriba abajo de los controles.

mac / nuestro: {"ventana": {"ancho": 668, "alto": 589}, "controles": [{"texto": "Appearance:", "y": 20, "x": 50, "ancho": 80, "alto": 17}, …]}
(y desde arriba; para los nuestros, relativas a la ventana, de AT-SPI).
Gravedades: tamaño (la ventana difiere más de TOLERANCIA), orden (dos controles que están en los dos lados cambiaron de lugar vertical).
"""
from . import fila, norm

REGLA = "geometría"
TOLERANCIA = 0.08


def revisar(mac, nuestro):
    filas = []
    vm, vn = mac.get("ventana") or {}, nuestro.get("ventana") or {}
    for eje in ("ancho", "alto"):
        a, b = vm.get(eje), vn.get(eje)
        if a and b and abs(a - b) / a > TOLERANCIA:
            filas.append(fila(REGLA, f"ventana: {eje}", str(a), str(b), "tamaño", f"{(b - a) / a:+.0%}"))
    suyos = {norm(c["texto"]): c for c in nuestro.get("controles", []) if c.get("texto")}
    comunes = [(c, suyos[norm(c["texto"])]) for c in mac.get("controles", []) if c.get("texto") and norm(c["texto"]) in suyos]
    por_mac = [c["texto"] for c, _ in sorted(comunes, key=lambda p: (p[0]["y"], p[0].get("x", 0)))]
    por_suyo = [c["texto"] for c, _ in sorted(comunes, key=lambda p: (p[1]["y"], p[1].get("x", 0)))]
    if por_mac != por_suyo:
        for i, (a, b) in enumerate(zip(por_mac, por_suyo)):
            if norm(a) != norm(b):
                filas.append(fila(REGLA, f"control #{i + 1} de arriba abajo", a, b, "orden"))
                break
    return filas
