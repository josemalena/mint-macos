#!/usr/bin/env python3
"""Pruebas de las reglas con datos inventados (nada de Apple). Uso: python3 -I prueba.py  (desde herramientas/visor-nib)."""
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from auditar import texto, menus, geometria, a_markdown  # noqa: E402


def comprobar(nombre, cond):
    print(("✓ " if cond else "✗ ") + nombre)
    if not cond:
        sys.exit(1)


# Regla de texto: igual, parecido, falta, sobra
mac = {"textos": [{"texto": "Show scroll bars:"}, {"texto": "Click in the scroll bar to:"}, {"texto": "Highlight color:"}, {"texto": "Recent items"}]}
nuestro = {"textos": ["Show scroll bars", "Click in the scroll bar", "Recent Items:", "Our own thing"], "revisar_sobra": True}
filas = texto.revisar(mac, nuestro)
grav = {(f["mac"], f["gravedad"]) for f in filas}
comprobar("el texto igual (sin dos puntos) no da fila", ("Show scroll bars:", "texto") not in grav and ("Show scroll bars:", "falta") not in grav)
comprobar("«Highlight color:» falta", ("Highlight color:", "falta") in grav)
comprobar("«Our own thing» sobra", any(f["gravedad"] == "sobra" and f["nuestro"] == "Our own thing" for f in filas))

# Regla de menús: atajo, falta, orden, sobra
mac_m = {"menus": [{"texto": "File", "items": [
    {"texto": "New", "atajo": "⌘N"}, {"texto": "Open…", "atajo": "⌘O"}, {"separador": True}, {"texto": "Close", "atajo": "⌘W"}, {"texto": "Print…", "atajo": "⌘P"}]}]}
nu_m = {"menus": [{"texto": "File", "items": [
    {"texto": "Open", "atajo": "⌘O"}, {"texto": "New", "atajo": "⇧⌘N"}, {"texto": "Close", "atajo": "⌘W"}, {"texto": "Extra", "atajo": ""}]}]}
filas = menus.revisar(mac_m, nu_m)
por = {(f["que"], f["gravedad"]) for f in filas}
comprobar("«New» con atajo distinto", ("File ▸ New", "atajo") in por)
comprobar("«Print…» falta", ("File ▸ Print…", "falta") in por)
comprobar("«Extra» sobra", ("File ▸ Extra", "sobra") in por)
comprobar("cambió el orden de New y Open", any(f["gravedad"] == "orden" for f in filas))
comprobar("«Open…» y «Open» solo difieren en los puntos suspensivos (no hay fila de texto)", not any(f["gravedad"] == "texto" and "Open" in f["que"] for f in filas))

# Regla de geometría
mac_g = {"ventana": {"ancho": 668, "alto": 589}, "controles": [{"texto": "Appearance:", "y": 20}, {"texto": "Accent color:", "y": 80}, {"texto": "Highlight color:", "y": 110}]}
nu_g = {"ventana": {"ancho": 700, "alto": 480}, "controles": [{"texto": "Appearance:", "y": 20}, {"texto": "Highlight color:", "y": 70}, {"texto": "Accent color:", "y": 100}]}
filas = geometria.revisar(mac_g, nu_g)
comprobar("el alto de la ventana difiere", any(f["que"] == "ventana: alto" and f["gravedad"] == "tamaño" for f in filas))
comprobar("el ancho (+4.8 %) cae en la tolerancia", not any(f["que"] == "ventana: ancho" for f in filas))
comprobar("el orden vertical cambió", any(f["gravedad"] == "orden" for f in filas))
print(a_markdown(filas, "Ejemplo"))
