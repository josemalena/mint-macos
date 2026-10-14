#!/usr/bin/env python3
"""Pone en <carpeta> el logo propio de cada app (el que instala en hicolor:
el paquete, Flatpak o snap), para que gane al que pone Os-Catalina.

    originales.py <carpeta> <nombre-de-ícono>...

El SVG se enlaza tal cual; un PNG se copia a 256 px. Lo que no tenga ícono
propio se salta.
"""
import os
import sys

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gtk  # noqa: E402
from PIL import Image  # noqa: E402


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    carpeta, nombres = sys.argv[1], sys.argv[2:]
    os.makedirs(carpeta, exist_ok=True)
    hicolor = Gtk.IconTheme()
    hicolor.set_custom_theme("hicolor")
    hechos, sin = 0, []
    for n in nombres:
        info = hicolor.lookup_icon(n, 256, 0)
        origen = info.get_filename() if info else None
        # Los que GTK trae dentro de la librería (/org/gtk/…) no son archivos.
        if not origen or not os.path.isfile(origen):
            sin.append(n)
            continue
        for ext in (".svg", ".png"):
            p = os.path.join(carpeta, n + ext)
            if os.path.lexists(p):
                os.remove(p)
        if origen.endswith(".svg"):
            os.symlink(origen, os.path.join(carpeta, n + ".svg"))
        else:
            img = Image.open(origen).convert("RGBA")
            img.resize((256, 256), Image.LANCZOS).save(os.path.join(carpeta, n + ".png"))
        hechos += 1
    print(f"  {hechos} logos propios" + (f" (sin ícono propio: {' '.join(sin)})" if sin else ""))


if __name__ == "__main__":
    main()
