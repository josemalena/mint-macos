#!/usr/bin/env python3
"""agarrar-teclado.py SEGUNDOS: abre una ventana y agarra el teclado y el ratón (como un programa ajeno con su grab) durante SEGUNDOS."""
import sys
import time
from Xlib import X, display

d = display.Display()
raiz = d.screen().root
ventana = raiz.create_window(0, 0, 10, 10, 0, d.screen().root_depth, X.InputOutput, X.CopyFromParent)
ventana.map()
d.sync()
time.sleep(0.7)   # que esté visible: con la ventana sin mapear el grab da GrabNotViewable (3)
ok_t = ventana.grab_keyboard(True, X.GrabModeAsync, X.GrabModeAsync, X.CurrentTime)
ok_p = ventana.grab_pointer(True, X.ButtonPressMask, X.GrabModeAsync, X.GrabModeAsync, X.NONE, X.NONE, X.CurrentTime)
print("grab teclado:", ok_t, "ratón:", ok_p, "(0 = lo tiene)", flush=True)
time.sleep(float(sys.argv[1]))
