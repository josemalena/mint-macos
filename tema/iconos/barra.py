#!/usr/bin/env python3
"""Los glifos de la barra de menú de la Mac para los símbolos de Linux que los piden.

    barra.py <raíz del volumen de sistema de la Mac> <carpeta destino>

Sale de los Menu Extras de la Mac (System/Library/CoreServices/Menu Extras/*.menu): cada
glifo viene en PDF vectorial; pdftocairo lo pasa a SVG y aquí se pinta del color simbólico
(#bebebe) en un cuadro de 16×16, para que GTK y xapp-status lo recoloreen como cualquier
símbolo. Lo que la Mac no tenga se salta con un aviso: no se sustituye.

Bluetooth (Bluetooth.menu): conectado/inactivo y apagado. Escribe en <destino> (la carpeta
escalables/status de Constanza). Nada de esto va al repo: se genera aquí.
"""
import os
import re
import subprocess
import sys
import tempfile

EXTRAS = "System/Library/CoreServices/Menu Extras"
# PDF en la Mac → nombres de símbolo que lo piden en Linux.
GLIFOS = {
    "Bluetooth.menu/Contents/Resources/Bluetooth_Idle.pdf": [
        "bluetooth-active-symbolic", "bluetooth-symbolic", "bluetooth-disconnected-symbolic",
        "blueman-tray-symbolic", "blueman-symbolic", "blueman-active-symbolic",
    ],
    "Bluetooth.menu/Contents/Resources/Bluetooth_Off.pdf": [
        "bluetooth-disabled-symbolic", "bluetooth-hardware-disabled-symbolic",
        "blueman-disabled-symbolic", "blueman-tray-disabled-symbolic",
    ],
}
COLOR = "#bebebe"
LADO = 16


def a_simbolico(pdf):
    """El PDF como SVG de 16×16 con un solo color, centrado."""
    with tempfile.TemporaryDirectory() as tmp:
        svg = os.path.join(tmp, "g.svg")
        subprocess.run(["pdftocairo", "-svg", pdf, svg], check=True)
        texto = open(svg, encoding="utf-8").read()
    ancho, alto = (float(v) for v in re.search(r'width="([\d.]+)" height="([\d.]+)"', texto).groups())
    esc = min((LADO - 2) / ancho, (LADO - 2) / alto)            # 1 px de margen
    dx, dy = (LADO - ancho * esc) / 2, (LADO - alto * esc) / 2
    cuerpo = re.search(r"<svg[^>]*>(.*)</svg>", texto, re.S).group(1)
    cuerpo = re.sub(r'fill="rgb\([^"]*\)"', f'fill="{COLOR}"', cuerpo)
    cuerpo = re.sub(r'stroke="rgb\([^"]*\)"', f'stroke="{COLOR}"', cuerpo)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" '
            f'width="{LADO}" height="{LADO}" viewBox="0 0 {LADO} {LADO}">'
            f'<g transform="translate({dx:.3f} {dy:.3f}) scale({esc:.4f})">{cuerpo}</g></svg>\n')


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    raiz, destino = sys.argv[1], sys.argv[2]
    os.makedirs(destino, exist_ok=True)
    hechos = 0
    for rel, nombres in GLIFOS.items():
        pdf = os.path.join(raiz, EXTRAS, rel)
        if not os.path.isfile(pdf):
            print(f"  ⚠ sin glifo en la Mac: {rel}")
            continue
        svg = a_simbolico(pdf)
        for n in nombres:
            with open(os.path.join(destino, n + ".svg"), "w", encoding="utf-8") as f:
                f.write(svg)
        hechos += 1
    print(f"  barra: {hechos} glifos de la Mac")


if __name__ == "__main__":
    main()
