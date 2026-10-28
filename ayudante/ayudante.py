#!/usr/bin/python3
"""mint-macos-ayudante: un solo proceso residente para las ventanas pequeñas que se piden con un atajo.

Arranca oculto con la sesión (`ayudante.py --residente`), con GTK ya cargado, y enseña al instante:

    forcequit   la ventana «Force Quit Applications» (⌥⌘⎋ y Apple ▸ Force Quit…)
    captura     la barra de capturas y grabación de ⇧⌘5

Se le pide por D-Bus (la acción de GApplication del mismo nombre), sin arrancar Python:

    gdbus call --session --dest io.github.josemalena.MintMacosAyudante \\
      --object-path /io/github/josemalena/MintMacosAyudante \\
      --method org.gtk.Actions.Activate forcequit '[]' '{}'

Si el proceso no existe (se cayó o la sesión aún no lo arrancó), `ayudante.py --accion NOMBRE` lo
levanta y hace esa acción. Las ventanas son las de forcekill.py (applet applemenu@macos) y
herramienta.py (capturas/), que se cargan desde donde las instala cada uno, así no hay dos copias.
"""
import importlib.machinery
import importlib.util
import os
import shutil
import sys
import traceback

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gio, GLib, Gtk  # noqa: E402

APP_ID = "io.github.josemalena.MintMacosAyudante"
HOME = os.path.expanduser("~")

def primera(*rutas):
    """La primera que exista: lo del usuario gana a lo del sistema (la imagen instala en /usr)."""
    for r in rutas:
        if r and os.path.exists(r):
            return r
    return rutas[-1] if rutas else None


# AYUDANTE_FORCEKILL y AYUDANTE_HERRAMIENTA cambian la ruta (para probar sin instalar).
FUENTES = {
    "forcekill": os.environ.get("AYUDANTE_FORCEKILL")
    or primera(os.path.join(HOME, ".local/share/cinnamon/applets/applemenu@macos/forcekill.py"),
               "/usr/share/cinnamon/applets/applemenu@macos/forcekill.py"),
    "herramienta": os.environ.get("AYUDANTE_HERRAMIENTA")
    or primera(os.path.join(HOME, ".local/bin/mac-captura-herramienta"),
               shutil.which("mac-captura-herramienta") or "/usr/local/bin/mac-captura-herramienta"),
}


def cargar(nombre):
    """Importa uno de los programas por su ruta (el de la barra no lleva .py)."""
    ruta = FUENTES[nombre]
    cargador = importlib.machinery.SourceFileLoader("ayudante_" + nombre, ruta)
    spec = importlib.util.spec_from_loader(cargador.name, cargador)
    mod = importlib.util.module_from_spec(spec)
    cargador.exec_module(mod)
    return mod


class Ayudante(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.FLAGS_NONE)
        self.accion_inicial = None       # --accion: lo que se pidió al levantarlo a mano
        self.ventanas = {}               # acción → ventana abierta
        self.modulos = {}

    def do_startup(self):
        Gtk.Application.do_startup(self)
        self.hold()                      # residente: sigue vivo sin ventanas
        for nombre in ("forcequit", "captura"):
            accion = Gio.SimpleAction.new(nombre, None)
            accion.connect("activate", lambda _a, _p, n=nombre: self.pedir(n))
            self.add_action(accion)
        # Se cargan ahora, con la sesión, para que el primer atajo no pague la importación.
        for n in ("forcekill", "herramienta"):
            try:
                self.modulos[n] = cargar(n)
            except Exception:  # noqa: BLE001
                print(f"No se pudo cargar {n}:", file=sys.stderr)
                traceback.print_exc()
        if "herramienta" in self.modulos:
            self.modulos["herramienta"].SALIR = lambda: None    # la barra al terminar solo se cierra
        GLib.idle_add(self._calentar)

    def _calentar(self):
        """Arma una ventana de Force Quit sin enseñarla: deja listas las fuentes, los íconos y el CSS."""
        try:
            self.modulos["forcekill"].ForceQuitWindow().destroy()
        except Exception:  # noqa: BLE001
            pass
        return False

    def do_activate(self):
        if self.accion_inicial:
            accion, self.accion_inicial = self.accion_inicial, None
            self.pedir(accion)

    def pedir(self, nombre):
        """Enseña la ventana de esa acción; si ya está abierta, la trae al frente."""
        ventana = self.ventanas.get(nombre)
        if ventana is not None:
            ventana.present()
            return
        try:
            if nombre == "forcequit":
                ventana = self.modulos["forcekill"].ForceQuitWindow()
                ventana.show_all()
            else:
                ventana = self.modulos["herramienta"].Barra()     # se enseña sola
        except Exception:  # noqa: BLE001
            traceback.print_exc()
            return
        self.ventanas[nombre] = ventana
        ventana.connect("destroy", lambda *_: self.ventanas.pop(nombre, None))
        ventana.present()


def main():
    GLib.set_prgname("mint-macos-ayudante")
    app = Ayudante()
    args = sys.argv[1:]
    if "--accion" in args:
        i = args.index("--accion")
        app.accion_inicial = args[i + 1] if i + 1 < len(args) else None
    return app.run([sys.argv[0]])


if __name__ == "__main__":
    sys.exit(main())
