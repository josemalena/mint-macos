#!/usr/bin/python3
"""Arma /Applications como la de macOS.

En la Mac, /Applications es una carpeta con una entrada por aplicación y una
subcarpeta, Utilities, con las herramientas del sistema. Aquí se genera lo mismo
a partir de los lanzadores (.desktop) que Linux ya tiene instalados:

  /Applications/Firefox.app            (un lanzador ejecutable, con su ícono)
  /Applications/Utilities/Terminal…    (las herramientas del sistema)

Cada entrada es una COPIA del .desktop, no un enlace: Fynder solo muestra el
nombre y el ícono de un lanzador si el archivo es ejecutable o está en una
carpeta del sistema, y un enlace a /usr/share/applications sale como un archivo
cualquiera con candado. Lo único que cambia en la copia es Name=, que lleva el
nombre corto y el sufijo «.app» (la Mac de José muestra todas las extensiones).

Lo que no es una aplicación de escritorio no entra: los paneles de configuración
de Cinnamon (Fynder tendrá un solo «System Preferences»), los programas de
terminal y las piezas internas (Plank, Rofi).

Solo se toca lo que este programa creó: la lista va en .mint-macos-aplicaciones
dentro de la carpeta. Un archivo del usuario nunca se pisa ni se borra.

Ajustes en ~/.config/mint-macos/aplicaciones.conf, una orden por línea:
    ocultar   algo.desktop          no entra
    mostrar   algo.desktop          entra aunque la regla lo deje fuera
    arriba    algo.desktop          va en /Applications, no en Utilities
    utilities algo.desktop          va en Utilities
    nombre    algo.desktop  Nombre  el nombre que se ve (sin el .app)

Uso:
    aplicaciones.py                  sincroniza /Applications
    aplicaciones.py --destino DIR    otra carpeta (para probar)
    aplicaciones.py --simular        dice qué haría, sin escribir nada
    aplicaciones.py --quitar         borra lo generado y deja la carpeta como estaba
    aplicaciones.py --sin-sufijo     sin «.app» en los nombres
"""

import argparse
import json
import os
import re
import shutil
import sys

# Cinnamon es el escritorio; sin esto, un servicio de systemd (sin sesión
# gráfica en el entorno) vería otras OnlyShowIn y descartaría apps de más.
os.environ.setdefault("XDG_CURRENT_DESKTOP", "X-Cinnamon")


def _dirs_de_datos():
    """XDG_DATA_DIRS completo: un servicio de systemd no siempre trae las de
    Flatpak y Snap, y sin ellas sus apps desaparecerían de /Applications."""
    actuales = [d for d in os.environ.get("XDG_DATA_DIRS", "").split(":") if d]
    for d in ("/usr/local/share", "/usr/share",
              "/var/lib/flatpak/exports/share",
              os.path.expanduser("~/.local/share/flatpak/exports/share"),
              "/var/lib/snapd/desktop"):
        if d not in actuales and os.path.isdir(d):
            actuales.append(d)
    return ":".join(actuales)


os.environ["XDG_DATA_DIRS"] = _dirs_de_datos()

import gi  # noqa: E402

gi.require_version("Gio", "2.0")
from gi.repository import Gio  # noqa: E402

DESTINO = "/Applications"
UTILITIES = "Utilities"
LISTA = ".mint-macos-aplicaciones"
CONFIG = os.path.expanduser("~/.config/mint-macos/aplicaciones.conf")

# Piezas internas del escritorio y duplicados de «el Finder»: no son apps que
# José abra a mano. Se pueden volver a mostrar con «mostrar» en la configuración.
OCULTAR = {
    "fynder.desktop", "nemo.desktop", "nemo-mac.desktop", "org.gnome.Nautilus.desktop",
    "plank.desktop", "net.launchpad.plank.desktop",
    "rofi.desktop", "rofi-theme-selector.desktop",
}

# Van en /Applications aunque su categoría diga «sistema»: son lo que la Mac
# pone ahí (System Preferences y la App Store).
ARRIBA = {"cinnamon-settings.desktop", "mintinstall.desktop", "mint-macos-settings.desktop"}

# Con System Preferences de mint-macos instalada, «System Settings» (la misma cosa
# con otro diseño) no sale: en la Mac solo hay una.
PREFERENCIAS = "mint-macos-settings.desktop"
AJUSTES_CINNAMON = "cinnamon-settings.desktop"

# Nombres que el lanzador trae mal escritos o que la Mac llama distinto.
NOMBRES = {"launchpad.desktop": "Launchpad"}

# Categorías de Utilities: lo que en Catalina vive en /Applications/Utilities
# (Activity Monitor, Terminal, Disk Utility, Keychain Access, Console…).
CATEGORIAS_UTILITIES = {
    "System", "Monitor", "TerminalEmulator", "Security", "Filesystem",
    "X-GNOME-Utilities", "Settings", "DesktopSettings", "HardwareSettings",
    "Archiving",
}

# Los paneles de Cinnamon salen de «System Settings», que es una sola app.
RE_PANEL = re.compile(r"^(cinnamon-settings-.+|cinnamon-.+-panel)\.desktop$")

GENERICOS = re.compile(r"\s+(web browser|browser|mail|email|e-mail|client)$", re.I)


def nombre_corto(app):
    """«Firefox Web Browser» → «Firefox» (como en la barra del menú)."""
    n = (app.get_display_name() or "").strip()
    g = (app.get_generic_name() or "").strip()
    corto = n
    if g and corto.lower().endswith(" " + g.lower()):
        corto = corto[: -(len(g) + 1)]
    corto = GENERICOS.sub("", corto).strip()
    return corto or n


def leer_config():
    cfg = {"ocultar": set(OCULTAR), "mostrar": set(), "arriba": set(ARRIBA),
           "utilities": set(), "nombre": dict(NOMBRES)}
    if not os.path.exists(CONFIG):
        return cfg
    with open(CONFIG, encoding="utf-8") as f:
        for linea in f:
            linea = linea.split("#", 1)[0].strip()
            if not linea:
                continue
            partes = linea.split(None, 2)
            if len(partes) < 2:
                continue
            orden, id_ = partes[0], partes[1]
            if orden == "nombre" and len(partes) == 3:
                cfg["nombre"][id_] = partes[2].strip()
            elif orden in ("ocultar", "mostrar", "arriba", "utilities"):
                cfg[orden].add(id_)
                if orden == "mostrar":
                    cfg["ocultar"].discard(id_)
                if orden == "ocultar":
                    cfg["mostrar"].discard(id_)
    return cfg


def aplicaciones(cfg):
    """Las apps que entran: [(id, app, nombre_visible, subcarpeta)], sin repetir."""
    vistas = {}
    todas = Gio.AppInfo.get_all()
    hay_preferencias = any(os.path.basename(a.get_filename() or "") == PREFERENCIAS
                           for a in todas if a.should_show())
    for app in todas:
        if not app.should_show():
            continue
        ruta = app.get_filename() or ""
        id_ = os.path.basename(ruta)
        if not ruta or not id_.endswith(".desktop"):
            continue
        if id_ in cfg["ocultar"] and id_ not in cfg["mostrar"]:
            continue
        if id_ == AJUSTES_CINNAMON and hay_preferencias and id_ not in cfg["mostrar"]:
            continue
        if RE_PANEL.match(id_) and id_ not in cfg["mostrar"]:
            continue
        if app.get_boolean("Terminal"):        # programas de terminal
            continue
        if "ConsoleOnly" in (app.get_categories() or ""):
            continue
        nombre = cfg["nombre"].get(id_) or nombre_corto(app)
        # Dos lanzadores con el mismo nombre (VS Code instalado dos veces): el
        # primero que devuelve GIO, que es el de más prioridad, y el otro no.
        if nombre.lower() in vistas:
            continue
        cats = set((app.get_categories() or "").split(";"))
        if id_ in cfg["arriba"]:
            sub = ""
        elif id_ in cfg["utilities"] or (cats & CATEGORIAS_UTILITIES):
            sub = UTILITIES
        else:
            sub = ""
        vistas[nombre.lower()] = (id_, app, nombre, sub)
    return sorted(vistas.values(), key=lambda t: (t[3] != "", t[2].lower()))


def contenido(ruta_origen, nombre_visible):
    """El .desktop con Name= cambiado (y sin los Name[xx]=, que lo taparían)."""
    with open(ruta_origen, encoding="utf-8", errors="replace") as f:
        lineas = f.read().split("\n")
    salida, en_entrada, puesto = [], False, False
    for l in lineas:
        if l.startswith("["):
            if en_entrada and not puesto:
                salida.append(f"Name={nombre_visible}")
                puesto = True
            en_entrada = l.strip() == "[Desktop Entry]"
            salida.append(l)
            if en_entrada:
                salida.append(f"Name={nombre_visible}")
                salida.append(f"X-MintMacos-Origen={ruta_origen}")
                puesto = True
            continue
        if en_entrada and re.match(r"^(Name(\[[^\]]*\])?|X-MintMacos-Origen)=", l):
            continue
        salida.append(l)
    return "\n".join(salida)


def deseado(destino, cfg, sufijo):
    """{ruta_relativa: (contenido, mtime_origen)} de todo lo que debe existir."""
    out = {}
    for id_, app, nombre, sub in aplicaciones(cfg):
        visible = nombre + sufijo
        rel = os.path.join(sub, id_) if sub else id_
        ruta = app.get_filename()
        out[rel] = (contenido(ruta, visible), os.stat(ruta).st_mtime)
    return out


def sincronizar(destino, cfg, sufijo, simular):
    lista_ruta = os.path.join(destino, LISTA)
    previo = set()
    if os.path.exists(lista_ruta):
        with open(lista_ruta, encoding="utf-8") as f:
            previo = set(json.load(f))
    quiero = deseado(destino, cfg, sufijo)
    escritos = borrados = 0

    for rel, (texto, mtime) in sorted(quiero.items()):
        ruta = os.path.join(destino, rel)
        # Si existe y no es nuestro, no se pisa.
        if os.path.exists(ruta) and rel not in previo:
            print(f"respeto {rel}: ya existe y no es mío", file=sys.stderr)
            continue
        igual = False
        if os.path.exists(ruta):
            with open(ruta, encoding="utf-8", errors="replace") as f:
                igual = f.read() == texto
        if igual and os.access(ruta, os.X_OK):
            continue
        escritos += 1
        if simular:
            print(f"+ {rel}")
            continue
        os.makedirs(os.path.dirname(ruta), exist_ok=True)
        with open(ruta, "w", encoding="utf-8") as f:
            f.write(texto)
        os.chmod(ruta, 0o755)
        os.utime(ruta, (mtime, mtime))

    for rel in sorted(previo - set(quiero)):
        ruta = os.path.join(destino, rel)
        if os.path.isfile(ruta):
            borrados += 1
            if simular:
                print(f"- {rel}")
            else:
                os.remove(ruta)
        sub = os.path.dirname(ruta)
        if not simular and sub != destino and os.path.isdir(sub) and not os.listdir(sub):
            os.rmdir(sub)

    if not simular:
        with open(lista_ruta, "w", encoding="utf-8") as f:
            json.dump(sorted(quiero), f, indent=0)
    print(f"{len(quiero)} apps en {destino}: {escritos} escritas, {borrados} quitadas.")


def quitar(destino, simular):
    lista_ruta = os.path.join(destino, LISTA)
    if not os.path.exists(lista_ruta):
        print("No hay nada generado aquí.")
        return
    with open(lista_ruta, encoding="utf-8") as f:
        previo = json.load(f)
    for rel in previo:
        ruta = os.path.join(destino, rel)
        if os.path.isfile(ruta):
            print(("- " if simular else "borro ") + rel)
            if not simular:
                os.remove(ruta)
    if not simular:
        for sub in {os.path.dirname(os.path.join(destino, r)) for r in previo}:
            if sub != destino and os.path.isdir(sub) and not os.listdir(sub):
                os.rmdir(sub)
        os.remove(lista_ruta)
    print("Listo: la carpeta quedó como estaba (la carpeta en sí no se borra).")


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawTextHelpFormatter)
    p.add_argument("--destino", default=DESTINO)
    p.add_argument("--simular", action="store_true")
    p.add_argument("--quitar", action="store_true")
    p.add_argument("--sin-sufijo", action="store_true")
    a = p.parse_args()

    if not os.path.isdir(a.destino):
        print(f"No existe {a.destino}. Para /Applications hace falta crearla una vez, "
              f"con tu usuario como dueño:\n  sudo install -d -o $USER -g $(id -gn) {a.destino}",
              file=sys.stderr)
        return 1
    if not os.access(a.destino, os.W_OK):
        print(f"{a.destino} no es tuya. Una vez:\n  sudo chown $USER:$(id -gn) {a.destino}",
              file=sys.stderr)
        return 1

    if a.quitar:
        quitar(a.destino, a.simular)
    else:
        sincronizar(a.destino, leer_config(), "" if a.sin_sufijo else ".app", a.simular)
    return 0


if __name__ == "__main__":
    sys.exit(main())
