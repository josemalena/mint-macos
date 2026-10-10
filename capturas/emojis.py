#!/usr/bin/python3
"""Selector de emojis para ⌃⌘Espacio, como el de macOS Catalina.

Abre el selector de emojis de GTK (categorías, búsqueda y recientes) junto al
puntero. El emoji elegido se copia al portapapeles y se escribe en la ventana
que estaba al frente (xdotool type). Si esa app no lo acepta escrito, queda en
el portapapeles para pegarlo con ⌘V.

Esc o hacer clic afuera lo cierra sin hacer nada.
"""

import subprocess
import sys

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, GLib, Gtk  # noqa: E402


def ventana_activa():
    try:
        return subprocess.run(["xdotool", "getactivewindow"], capture_output=True,
                              text=True, timeout=2).stdout.strip()
    except Exception:
        return ""


ANCHO, ALTO = 460, 440


class Selector(Gtk.Window):
    def __init__(self, destino):
        super().__init__(type=Gtk.WindowType.TOPLEVEL)
        self.destino = destino
        self.elegido = None
        self.abierto = False
        self.set_decorated(False)
        self.set_skip_taskbar_hint(True)
        self.set_skip_pager_hint(True)
        self.set_keep_above(True)
        self.set_type_hint(Gdk.WindowTypeHint.UTILITY)
        self.set_default_size(ANCHO, ALTO)
        # En X11 el selector de GTK se dibuja DENTRO de la ventana que lo abre:
        # la ventana es del tamaño del selector y transparente.
        visual = self.get_screen().get_rgba_visual()
        if visual is not None:
            self.set_visual(visual)
        css = Gtk.CssProvider()
        css.load_from_data(b"window.selector-emojis { background: transparent; }")
        self.get_style_context().add_provider(css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        self.get_style_context().add_class("selector-emojis")

        # El selector cuelga de un GtkEntry invisible, arriba de todo.
        caja = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.entrada = Gtk.Entry()
        self.entrada.set_opacity(0.0)
        self.entrada.set_size_request(ANCHO, 1)
        self.entrada.connect("changed", self.al_elegir)
        caja.pack_start(self.entrada, False, False, 0)
        self.add(caja)

        # Junto al puntero, sin salirse de la pantalla.
        pantalla = Gdk.Display.get_default()
        _, x, y = pantalla.get_default_seat().get_pointer().get_position()
        mon = pantalla.get_monitor_at_point(x, y).get_geometry()
        x = min(max(mon.x, x - ANCHO // 2), mon.x + mon.width - ANCHO)
        y = min(max(mon.y, y), mon.y + mon.height - ALTO)
        self.move(x, y)
        self.connect("key-press-event", self.al_tecla)
        self.connect("focus-out-event", lambda *a: self.cerrar_si_nada())
        self.show_all()
        GLib.timeout_add(60, self.abrir)

    def abrir(self):
        self.present_with_time(Gdk.CURRENT_TIME)
        self.entrada.grab_focus()
        self.entrada.emit("insert-emoji")
        GLib.timeout_add(150, self.vigilar)
        # Red de seguridad: si en 2 s el selector nunca tomó el foco, salir.
        GLib.timeout_add(2000, lambda: (self.abierto or self.elegido is not None or Gtk.main_quit()) and False)
        return False

    # Mientras el selector está abierto, el foco de la ventana está en su
    # buscador; cuando se cierra (Esc o clic afuera), el foco vuelve a la
    # entrada. Se vigila eso cada 150 ms: los eventos de foco no siempre
    # llegan con el selector dentro de la ventana.
    def vigilar(self):
        if self.elegido is not None:
            return False
        foco = self.get_focus()
        if foco is not None and foco is not self.entrada:
            self.abierto = True
        elif self.abierto:
            Gtk.main_quit()
            return False
        return True

    def cerrar_si_nada(self):
        if self.elegido is None:
            Gtk.main_quit()
        return False

    def al_tecla(self, w, ev):
        if ev.keyval == Gdk.KEY_Escape:
            Gtk.main_quit()
        return False

    def al_elegir(self, entrada):
        texto = entrada.get_text()
        if not texto or self.elegido is not None:
            return
        self.elegido = texto
        portapapeles = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD)
        portapapeles.set_text(texto, -1)
        portapapeles.store()
        self.hide()
        GLib.timeout_add(120, self.escribir)

    def escribir(self):
        if self.destino:
            subprocess.run(["xdotool", "windowactivate", "--sync", self.destino],
                           timeout=3, check=False)
            subprocess.run(["xdotool", "type", "--clearmodifiers", "--delay", "0",
                            self.elegido], timeout=3, check=False)
        # Que el portapapeles sobreviva un momento a la salida.
        GLib.timeout_add(400, Gtk.main_quit)
        return False


def main():
    Selector(ventana_activa())
    Gtk.main()
    return 0


if __name__ == "__main__":
    sys.exit(main())
