#!/usr/bin/env python3
"""⌥⇧⌘⎋: fuerza la salida de la app del frente, como en la Mac.

Es lo mismo que «Force Quit <app>» del menú Apple con Shift apretado. Nunca
toca el escritorio ni el panel: si al frente está uno de esos, no hace nada.
"""
import subprocess
import sys

NO_SE_TOCAN = ("_NET_WM_WINDOW_TYPE_DESKTOP", "_NET_WM_WINDOW_TYPE_DOCK")


def salida(*cmd):
    return subprocess.run(cmd, capture_output=True, text=True, check=False).stdout.strip()


def main():
    ventana = salida("xdotool", "getactivewindow")
    if not ventana:
        return 0
    tipo = salida("xprop", "-id", ventana, "_NET_WM_WINDOW_TYPE")
    if any(t in tipo for t in NO_SE_TOCAN):
        return 0
    pid = salida("xdotool", "getwindowpid", ventana)
    if not pid.isdigit() or int(pid) <= 1:
        return 0
    subprocess.run(["kill", "-KILL", pid], check=False)
    return 0


if __name__ == "__main__":
    sys.exit(main())
