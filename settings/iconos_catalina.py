"""Íconos de Apple sacados del disco de la Mac, solo en local (nunca al repo).

Los dejan tema/iconos/car.py (hojas deepmap2 de los Assets.car, sesión de Infra: ~/.local/share/mint-macos/iconos-catalina-deepmap2/)
y desde-mac.sh/Pillow (los .icns de las apps, en ~/.local/share/mint-macos/settings/privacidad/). Si falta alguno, la fila
va sin ícono: nunca se pone otro en su lugar.
"""
import glob
import os

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import GdkPixbuf, Gtk  # noqa: E402

HOME = os.path.expanduser("~/.local/share/mint-macos")
PROFUNDO = os.path.join(HOME, "iconos-catalina-deepmap2")
PRIVACIDAD = os.path.join(HOME, "settings", "privacidad")

# Banderas de Input Sources: el archivo de Apple trae 173 en orden y sin nombres. Solo van las que se compararon con la
# captura (U.S. = la bandera sola; Spanish - ISO = España con «ISO» debajo); las demás distribuciones salen sin bandera.
BANDERAS = {"us": 58, "es": 51}


def _buscar(patron):
    hallados = sorted(glob.glob(patron))
    return hallados[0] if hallados else None


def imagen(ruta, tam):
    """Gtk.Image del archivo a ese tamaño (en píxeles lógicos), o None si no existe."""
    if not ruta or not os.path.exists(ruta):
        return None
    try:
        pb = GdkPixbuf.Pixbuf.new_from_file_at_size(ruta, tam * 2, tam * 2)
    except Exception:  # noqa: BLE001
        return None
    i = Gtk.Image.new_from_pixbuf(pb.scale_simple(tam, tam, GdkPixbuf.InterpType.HYPER))
    return i


def de_screentime(nombre, tam=24):
    return imagen(_buscar(os.path.join(PROFUNDO, "ScreenTime", nombre + "-*@2x.png")), tam)


def de_atajos(categoria, tam=16):
    return imagen(_buscar(os.path.join(PROFUNDO, "shortcuts", "category_%s-32x32@2x.png" % categoria)), tam)


def de_privacidad(nombre, tam=24):
    """«locationservices», «camera»… (Security.prefPane) o «contacts», «calendars», «reminders», «photos» (de sus apps)."""
    ruta = _buscar(os.path.join(PROFUNDO, "Security", "privacy-%s-*@2x.png" % nombre)) or \
        _buscar(os.path.join(PRIVACIDAD, nombre + ".png"))
    return imagen(ruta, tam)


def bandera(capa, tam=18):
    n = BANDERAS.get(capa)
    if n is None:
        return None
    return imagen(_buscar(os.path.join(PROFUNDO, "banderas", "bandera-%03d-*.png" % n)), tam)
