#!/usr/bin/env python3
"""Cursores de Catalina para el tema Constanza, sacados del disco de la Mac.

    cursores.py <carpeta cursors de HIServices> <tema> [tema base]

<carpeta cursors> es System/Library/Frameworks/ApplicationServices.framework/
Versions/A/Frameworks/HIServices.framework/Versions/A/Resources/cursors: una
carpeta por cursor, con cursor.pdf (vector) e info.plist (punto activo,
sombra y, si es animado, cuadros y demora).

Escribe <tema>/cursors/ en formato Xcursor (xcursorgen), a 24, 32, 48 y 64:
primero copia el tema base (McMojave-cursors), que trae todos los nombres de
X11, CSS y los hash de Qt; encima pone los de Catalina con todos sus nombres.
La flecha, la I de texto y la espera de Catalina no están aquí (van
compiladas en SkyLight): quedan las del tema base.

Nada de esto va al repo: se genera en local desde el disco de la Mac.
"""
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile

from PIL import Image, ImageFilter

TAMANOS = (24, 32, 48, 64)   # nominales de Xcursor; 24 = 1x de macOS
BASE = "/usr/share/icons/McMojave-cursors"

# Cursor de macOS → nombres de X11/CSS (el primero es el archivo; los demás,
# enlaces). Los hash son los que piden Qt y las apps viejas.
NOMBRES = {
    "pointinghand": ["pointer", "hand2", "hand1", "pointing_hand",
                     "e29285e634086352946a0e7090d73106", "9d800788f1b08800ae810202380a0822"],
    "openhand": ["grab", "openhand", "hand", "5aca4d189052212118709018842178c0"],
    "closedhand": ["grabbing", "closedhand", "208530c400c041818281048008011002"],
    "move": ["move", "fleur", "all-scroll", "size_all",
             "4498f0e0c1937ffe01fd06f973665830", "9081237383d90e509aa00f00170e968f"],
    "notallowed": ["not-allowed", "no-drop", "crossed_circle", "forbidden", "circle",
                   "dnd-no-drop", "03b6e0fcb3499374a867c041f52298f0"],
    "help": ["help", "question_arrow", "whats_this", "left_ptr_help",
             "5c6cd98b3f3ebcb1f9c7f1c204630408", "d9ce0ab605698f320427677b458ad60b"],
    "contextualmenu": ["context-menu"],
    "copy": ["copy", "dnd-copy", "1081e37283d90000800003c07f3ef6bf",
             "6407b0e94181790501fd1e167b474872", "08ffe1cb5fe6fc01f906f1c063814ccf"],
    "makealias": ["alias", "link", "dnd-link", "3085a0e285430894940527032f8b26df",
                  "640fb0e74195791501fd1ed57b41487f", "a2a266d0498c3104214a47bd64ab0fc8"],
    "cross": ["crosshair", "cross", "tcross", "cross_reverse", "diamond_cross"],
    "cell": ["cell", "plus"],
    "zoomin": ["zoom-in"],
    "zoomout": ["zoom-out"],
    "ibeamvertical": ["vertical-text"],
    "busybutclickable": ["progress", "left_ptr_watch", "half-busy",
                         "00000000000000020006000e7e9ffc3f", "08e8e1c95fe2fc01f976f1e063a24ccd",
                         "3ecb610c1bf2410f44200f48c40d3599"],
    "resizeeastwest": ["ew-resize", "h_double_arrow", "sb_h_double_arrow", "size_hor",
                       "028006030e0e7ebffc7f7070c0600140", "14fef782d02440884392942c11205230"],
    "resizeleftright": ["col-resize", "split_h"],
    "resizenorthsouth": ["ns-resize", "v_double_arrow", "sb_v_double_arrow", "size_ver",
                         "00008160000006810000408080010102", "2870a09082c103050810ffdffffe0204"],
    "resizeupdown": ["row-resize", "split_v"],
    "resizenorth": ["n-resize", "top_side"],
    "resizesouth": ["s-resize", "bottom_side"],
    "resizeeast": ["e-resize", "right_side"],
    "resizewest": ["w-resize", "left_side"],
    "resizenortheast": ["ne-resize", "top_right_corner"],
    "resizenorthwest": ["nw-resize", "top_left_corner"],
    "resizesoutheast": ["se-resize", "bottom_right_corner"],
    "resizesouthwest": ["sw-resize", "bottom_left_corner"],
    "resizenortheastsouthwest": ["nesw-resize", "size_bdiag", "fd_double_arrow",
                                 "fcf1c3c7cd4491d801f1e1c78f100000"],
    "resizenorthwestsoutheast": ["nwse-resize", "size_fdiag", "bd_double_arrow",
                                 "c7088f0f3e6c8088236ef8e1e3e70000"],
}


def pagina(pdf):
    """Ancho y alto de la página del PDF, en puntos."""
    salida = subprocess.run(["pdfinfo", pdf], capture_output=True, text=True, check=True).stdout
    for linea in salida.splitlines():
        if linea.startswith("Page size:"):
            partes = linea.split()
            return float(partes[2]), float(partes[4])
    raise ValueError(f"sin tamaño de página: {pdf}")


def dibujar(pdf, escala, tmp):
    """El PDF dibujado a escala (1 = 1 px por punto), con transparencia."""
    base = os.path.join(tmp, "p")
    subprocess.run(["pdftocairo", "-png", "-singlefile", "-transp", "-r", str(72 * escala), pdf, base],
                   check=True)
    return Image.open(base + ".png").convert("RGBA")


def con_sombra(img, info, escala):
    """La sombra que macOS le pone al cursor (color, desenfoque y corrimiento
    del info.plist). El corrimiento de macOS va con la Y hacia arriba."""
    color = info.get("shadowcolor")
    if not color:
        return img
    r, g, b, a = color
    blur = float(info.get("blur", 0)) * escala
    dx = round(float(info.get("shadowoffsetx", 0)) * escala)
    dy = round(-float(info.get("shadowoffsety", 0)) * escala)
    margen = int(blur * 2) + abs(dx) + abs(dy) + 1
    lienzo = Image.new("RGBA", (img.width + 2 * margen, img.height + 2 * margen), (0, 0, 0, 0))
    alfa = Image.new("L", lienzo.size, 0)
    alfa.paste(img.getchannel("A"), (margen + dx, margen + dy))
    if blur:
        alfa = alfa.filter(ImageFilter.GaussianBlur(blur / 2))
    alfa = alfa.point(lambda v: int(v * a))
    sombra = Image.new("RGBA", lienzo.size, (int(r * 255), int(g * 255), int(b * 255), 0))
    sombra.putalpha(alfa)
    lienzo.alpha_composite(sombra)
    lienzo.alpha_composite(img, (margen, margen))
    return lienzo, margen


def cursor(carpeta, destino, tmp):
    """Un cursor de macOS a archivo Xcursor. Devuelve True si salió."""
    pdf = os.path.join(carpeta, "cursor.pdf")
    plist = os.path.join(carpeta, "info.plist")
    if not (os.path.isfile(pdf) and os.path.isfile(plist)):
        return False
    with open(plist, "rb") as f:
        info = plistlib.load(f)
    cuadros = int(info.get("frames", 1))
    demora = max(1, round(float(info.get("delay", 0.05)) * 1000))
    ancho_pt, alto_pt = pagina(pdf)
    alto_cuadro = alto_pt / cuadros
    lineas = []
    for nominal in TAMANOS:
        escala = nominal / 24
        hoja = dibujar(pdf, escala, tmp)
        h = round(alto_cuadro * escala)
        for i in range(cuadros):
            img = hoja.crop((0, i * h, hoja.width, (i + 1) * h))
            res = con_sombra(img, info, escala)
            img, margen = res if isinstance(res, tuple) else (res, 0)
            x = round(float(info.get("hotx", 0)) * escala) + margen
            y = round(float(info.get("hoty", 0)) * escala) + margen
            png = os.path.join(tmp, f"{os.path.basename(carpeta)}-{nominal}-{i}.png")
            img.save(png)
            lineas.append(f"{nominal} {x} {y} {png}" + (f" {demora}" if cuadros > 1 else ""))
    conf = os.path.join(tmp, "cursor.conf")
    with open(conf, "w") as f:
        f.write("\n".join(lineas) + "\n")
    subprocess.run(["xcursorgen", conf, destino], check=True)
    return True


def main():
    if len(sys.argv) not in (3, 4):
        sys.exit(__doc__)
    mac, tema = sys.argv[1], sys.argv[2]
    base = sys.argv[3] if len(sys.argv) == 4 else BASE
    cursores = os.path.join(tema, "cursors")
    if os.path.isdir(cursores):
        shutil.rmtree(cursores)
    if os.path.isdir(os.path.join(base, "cursors")):
        shutil.copytree(os.path.join(base, "cursors"), cursores, symlinks=True)
    else:
        os.makedirs(cursores)
    hechos = []
    with tempfile.TemporaryDirectory() as tmp:
        for origen, nombres in NOMBRES.items():
            # Primero se genera; solo si sale se reemplazan los del tema base.
            nuevo = os.path.join(tmp, "nuevo.xcursor")
            if not cursor(os.path.join(mac, origen), nuevo, tmp):
                continue
            for n in nombres:
                p = os.path.join(cursores, n)
                if os.path.lexists(p):
                    os.remove(p)
            shutil.move(nuevo, os.path.join(cursores, nombres[0]))
            for n in nombres[1:]:
                os.symlink(nombres[0], os.path.join(cursores, n))
            hechos.append(origen)
    faltan = [o for o in NOMBRES if o not in hechos]
    print(f"  cursores de Catalina: {len(hechos)}" + (f" (faltan: {' '.join(faltan)})" if faltan else "")
          + f"; el resto, de {os.path.basename(base)}")


if __name__ == "__main__":
    main()
