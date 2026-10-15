#!/usr/bin/env python3
"""Los fondos de escritorio de Apple, sacados del disco de la Mac (solo lectura) a un tamaño razonable.

    fondos.py <raíz del volumen de sistema de la Mac> [destino]

De «System/Library/Desktop Pictures» saca cada imagen (los .heic, solo la imagen principal) a un JPG de
hasta 2880×1800 en <destino>/fotos/, su miniatura de 192×120 en <destino>/miniaturas/ y los colores
sólidos (Solid Colors/*.png) en <destino>/colores/. El orden de Catalina sale de «.orderedPictures.plist»
y queda en <destino>/orden.json. Por defecto el destino es ~/.local/share/mint-macos/fondos.
Todo es de Apple: nunca va al repo. Los que ImageMagick no pueda abrir se saltan con un aviso.
"""
import base64
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys

CARPETA = "System/Library/Desktop Pictures"


def convertir(origen, destino, *args, espera=240):
    cmd = ["convert", "-limit", "memory", "1GiB", "-limit", "map", "2GiB", origen, *args, destino]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=espera)
    except subprocess.TimeoutExpired:
        return False
    return r.returncode == 0 and os.path.exists(destino)


def cuadros_claro_oscuro(ruta):
    """(cuadro claro, cuadro oscuro) de un .heic dinámico, de su XMP apple_desktop:solar; None si no está."""
    with open(ruta, "rb") as f:
        datos = f.read(60_000_000)
    m = re.search(rb'apple_desktop:solar="([^"]+)"', datos)
    if not m:
        return None
    try:
        ap = plistlib.loads(base64.b64decode(m.group(1)))["ap"]
        return int(ap["l"]), int(ap["d"])
    except (ValueError, KeyError, plistlib.InvalidFileException):
        return None


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    raiz = sys.argv[1]
    base = sys.argv[2] if len(sys.argv) > 2 else os.path.expanduser("~/.local/share/mint-macos/fondos")
    origen = os.path.join(raiz, CARPETA)
    if not os.path.isdir(origen):
        sys.exit(f"✗ No encuentro {origen}")
    for sub in ("fotos", "miniaturas", "colores"):
        os.makedirs(os.path.join(base, sub), exist_ok=True)
    try:
        orden = plistlib.load(open(os.path.join(origen, ".orderedPictures.plist"), "rb"))
    except (OSError, ValueError):
        orden = sorted(f for f in os.listdir(origen) if f.lower().endswith((".jpg", ".heic")))
    hechos = []
    for nombre in orden:
        ruta = os.path.join(origen, nombre)
        if not os.path.isfile(ruta):
            continue
        stem = os.path.splitext(nombre)[0]
        foto = os.path.join(base, "fotos", stem + ".jpg")
        mini = os.path.join(base, "miniaturas", stem + ".jpg")
        if not os.path.exists(foto):
            fuente = ruta + ("[0]" if nombre.lower().endswith(".heic") else "")
            if not convertir(fuente, foto, "-resize", "2880x1800>", "-quality", "88"):
                print(f"  ⚠ no pude abrir {nombre}")
                continue
        if not os.path.exists(mini):
            convertir(foto, mini, "-resize", "192x120^", "-gravity", "center", "-extent", "192x120", "-quality", "85")
        hechos.append(stem)
        print(f"  ✓ {stem}", flush=True)
    # Los fondos dinámicos (Catalina, Mojave) traen varios cuadros del día, y su metadato XMP
    # (apple_desktop:solar) dice cuál es el «Light (Still)» y cuál el «Dark (Still)» (ap.l y ap.d).
    # Se sacan como «<nombre> Light» y «<nombre> Dark».
    for stem in ("Catalina", "Mojave"):
        ruta = os.path.join(origen, stem + ".heic")
        if not os.path.isfile(ruta):
            continue
        indices = cuadros_claro_oscuro(ruta)
        if indices is None:
            print(f"  ⚠ no encuentro los cuadros claro y oscuro de {stem}")
            continue
        for etiqueta, i in zip(("Light", "Dark"), indices):
            nombre = f"{stem} {etiqueta}"
            foto = os.path.join(base, "fotos", nombre + ".jpg")
            mini = os.path.join(base, "miniaturas", nombre + ".jpg")
            if not os.path.exists(foto):
                convertir(f"{ruta}[{i}]", foto, "-resize", "2880x1800>", "-quality", "88")
            if os.path.exists(foto) and not os.path.exists(mini):
                convertir(foto, mini, "-resize", "192x120^", "-gravity", "center", "-extent", "192x120",
                          "-quality", "85")
            if os.path.exists(foto):
                hechos.append(nombre)
                print(f"  ✓ {nombre} (cuadro {i})", flush=True)
    colores = os.path.join(origen, "Solid Colors")
    nombres = []
    if os.path.isdir(colores):
        for f in sorted(os.listdir(colores)):
            if f.lower().endswith(".png"):
                shutil.copy2(os.path.join(colores, f), os.path.join(base, "colores", f))
                nombres.append(os.path.splitext(f)[0])
    json.dump({"fotos": hechos, "colores": nombres}, open(os.path.join(base, "orden.json"), "w"), indent=1)
    print(f"{len(hechos)} fotos y {len(nombres)} colores en {base}")


if __name__ == "__main__":
    main()
