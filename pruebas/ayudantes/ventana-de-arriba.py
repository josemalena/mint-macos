#!/usr/bin/env python3
"""ventana-de-arriba.py: imprime el pid (_NET_WM_PID) de la ventana más alta de la pila de la raíz (la que está encima de todo)."""
from Xlib import display, Xatom

d = display.Display()
hijos = d.screen().root.query_tree().children
pid_atom = d.intern_atom("_NET_WM_PID")
for w in reversed(hijos):
    try:
        a = w.get_attributes()
        if a.map_state != 2:      # solo las visibles
            continue
        p = w.get_full_property(pid_atom, Xatom.CARDINAL)
        print(p.value[0] if p else 0)
        break
    except Exception:
        continue
