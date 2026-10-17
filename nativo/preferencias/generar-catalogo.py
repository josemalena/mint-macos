#!/usr/bin/env python3
"""Genera catalogo-datos.vala: el orden y los datos de cada panel (id, nombre, palabras del buscador, ícono del tema), tal como
los arma settings/paneles.py + settings/propios.py. Es el catálogo de los paneles que todavía no están en Vala (se abren con el
System Preferences de Python); cada panel que se porta lleva sus propios datos y la fila de aquí deja de usarse.

    python3 nativo/preferencias/generar-catalogo.py > nativo/preferencias/catalogo-datos.vala
"""
import os
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
SETTINGS = os.path.join(AQUI, "..", "..", "settings")
sys.path.insert(0, SETTINGS)
sys.path.insert(0, "/usr/share/cinnamon/cinnamon-settings")

import paneles  # noqa: E402
import propios  # noqa: E402

# Los paneles que sirve un módulo de Cinnamon (no propios): quedan en Python. «requiere» es el programa que debe existir.
REQUIERE = {"com.apple.preferences.internetaccounts": "gnome-online-accounts-gtk"}


def v(texto):
    return '"' + texto.replace("\\", "\\\\").replace('"', '\\"') + '"'


print("// GENERADO por generar-catalogo.py de settings/paneles.py y settings/propios.py: no se edita a mano.")
print("namespace Preferencias {")
print("    public struct DatosPanel {")
print("        public string grupo;")
print("        public string id;")
print("        public string nombre;")
print("        public string palabras;")
print("        public string icono_tema;")
print("        public string requiere;")
print("    }")
print()
print("    public DatosPanel[] catalogo () {")
print("        DatosPanel[] a = {};")
for gid, orden in paneles.GRUPOS:
    for p in orden:
        pr = propios.PROPIOS.get(p.id)
        src = pr.panel if pr is not None else p
        print("        a += DatosPanel () { grupo = %s, id = %s, nombre = %s, palabras = %s, icono_tema = %s, requiere = %s };" % (
            v(gid), v(src.id), v(src.nombre), v(src.palabras), v(src.icono_tema), v(REQUIERE.get(src.id, ""))))
ap = propios.PROPIOS[propios.PanelAppleID.id]
print("        return a;")
print("    }")
print()
print("    // Apple ID no sale en la cuadrícula: se abre desde la franja de arriba.")
print("    public DatosPanel datos_apple_id () {")
print("        return DatosPanel () { grupo = \"oculto\", id = %s, nombre = %s, palabras = %s, icono_tema = %s, requiere = \"\" };" % (
    v(ap.panel.id), v(ap.panel.nombre), v(ap.panel.palabras), v(ap.panel.icono_tema)))
print("    }")
print("}")
