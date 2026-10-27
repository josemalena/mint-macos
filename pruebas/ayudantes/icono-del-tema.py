#!/usr/bin/env python3
"""icono-del-tema.py TEMA NOMBRE… — de qué tema sale cada ícono simbólico y si se pinta (caso 115). Imprime «nombre ruta tinta» por línea;
tinta = píxeles no transparentes al cargarlo en rojo (load_symbolic): el glifo tiene que existir y recolorearse."""
import sys
import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, Gdk

tema = Gtk.IconTheme.new()
tema.set_custom_theme(sys.argv[1])
for nombre in sys.argv[2:]:
    info = tema.lookup_icon(nombre, 16, 0)
    if info is None:
        print(nombre, 'NINGUNO', 0); continue
    pb, _ = info.load_symbolic(Gdk.RGBA(1, 0, 0, 1), None, None, None)
    px = pb.get_pixels(); n = pb.get_n_channels()
    tinta = sum(1 for i in range(0, len(px), n) if px[i + n - 1] > 30 and px[i] > 150 and px[i + 1] < 80)
    print(nombre, info.get_filename(), tinta)
