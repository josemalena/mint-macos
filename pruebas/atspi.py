#!/usr/bin/python3
"""Busca un texto en lo que muestra una app, por accesibilidad (AT-SPI): sin
teclas ni clics, lee el árbol de la app como lo leería un lector de pantalla.

    atspi.py --pid PID --texto TEXTO [--segundos N] [--rol ROL]

Sale con 0 en cuanto un elemento de la app tiene ese nombre (exacto), con 1 si
no aparece en N segundos (por defecto 15). Con --volcar imprime el árbol.
"""
import argparse
import sys
import time

import gi
gi.require_version("Atspi", "2.0")
from gi.repository import Atspi  # noqa: E402


def app_de(pid):
    escritorio = Atspi.get_desktop(0)
    for i in range(escritorio.get_child_count()):
        a = escritorio.get_child_at_index(i)
        try:
            if a is not None and a.get_process_id() == pid:
                return a
        except gi.repository.GLib.Error:
            continue
    return None


def recorrer(nodo, nivel=0, tope=4000):
    """(nivel, nodo) de todo el árbol, a lo ancho, con un tope de nodos."""
    pila = [(nivel, nodo)]
    vistos = 0
    while pila and vistos < tope:
        n, x = pila.pop(0)
        vistos += 1
        yield n, x
        try:
            hijos = x.get_child_count()
        except gi.repository.GLib.Error:
            continue
        for i in range(min(hijos, 500)):
            try:
                h = x.get_child_at_index(i)
            except gi.repository.GLib.Error:
                continue
            if h is not None:
                pila.append((n + 1, h))


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--pid", type=int, required=True)
    p.add_argument("--texto")
    p.add_argument("--rol")
    p.add_argument("--segundos", type=float, default=15)
    p.add_argument("--volcar", action="store_true")
    a = p.parse_args()
    fin = time.time() + a.segundos
    while True:
        app = app_de(a.pid)
        if app is not None:
            for n, x in recorrer(app):
                try:
                    nombre, rol = x.get_name() or "", x.get_role_name()
                except gi.repository.GLib.Error:
                    continue
                if a.volcar:
                    print("  " * n + f"[{rol}] {nombre}")
                elif nombre == a.texto and (not a.rol or rol == a.rol):
                    print(f"[{rol}] {nombre}")
                    return 0
            if a.volcar:
                return 0
        if time.time() > fin:
            print(f"no aparece «{a.texto}» en la app del pid {a.pid}"
                  + ("" if app else " (la app no está en el bus de accesibilidad)"), file=sys.stderr)
            return 1
        time.sleep(0.5)


if __name__ == "__main__":
    sys.exit(main())
