#!/usr/bin/env python3
"""cerrar-ventana.py ID: pide al gestor cerrar la ventana como el botón de cerrar (_NET_CLOSE_WINDOW con la hora del servidor).
wmctrl -c manda la hora 0 y Muffin avisa «without a timestamp»; el aviso de «no responde» sale de este camino."""
import sys
from Xlib import X, display, protocol, Xatom

d = display.Display()
raiz = d.screen().root
ventana = raiz.create_window(-10, -10, 1, 1, 0, d.screen().root_depth, X.InputOutput, X.CopyFromParent, event_mask=X.PropertyChangeMask)
ventana.change_property(Xatom.WM_NAME, Xatom.STRING, 8, b"hora")
while True:
    e = d.next_event()
    if e.type == X.PropertyNotify:
        hora = e.time
        break
ev = protocol.event.ClientMessage(
    window=int(sys.argv[1], 0), client_type=d.intern_atom("_NET_CLOSE_WINDOW"), data=(32, [hora, 1, 0, 0, 0]))
raiz.send_event(ev, event_mask=X.SubstructureRedirectMask | X.SubstructureNotifyMask)
d.sync()
