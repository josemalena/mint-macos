"""Paneles de System Preferences que escriben directo en la configuración del
programa, en vez de traer la interfaz de ese programa.

Cada uno es una clase con `id`, `nombre`, `panel` (para el buscador y el ícono) y
`construir()`, que devuelve el widget de la página. El diseño es el de la captura
de Catalina (Screen Shot 2026-10-14 at 12.12.52 AM, panel Dock).

Los controles que de verdad hacen algo aquí van conectados. Los de Catalina que Linux o
nuestro Plank no tienen (Prefer tabs when opening documents) no se inventan: donde la
captura los muestra se dibujan en gris, como en una Mac sin esa función (ver teclado.py).
"""
import json
import os
import re
import subprocess
import sys

import gi
gi.require_version("Gtk", "3.0")
gi.require_version("GdkPixbuf", "2.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, Gio, GLib, GdkPixbuf, Gtk  # noqa: E402

import apple_id  # noqa: E402
import paneles  # noqa: E402

MAGIC_LAMP = "CinnamonMagicLamp@klangman"


def _plank():
    """El dock1 de Plank (nuestro fork): dconf, ruta relocatable."""
    return Gio.Settings.new_with_path("net.launchpad.plank.dock.settings", "/net/launchpad/plank/docks/dock1/")


# El tema de Plank se edita en su archivo: Plank lo vigila y recarga solo. Lo que
# había se guarda al apagar un control, para devolverlo igual al encenderlo.
_TEMA_DEFECTO = {"IndicatorSize": "0.75", "LaunchBounceHeight": "0.625"}
_RESPALDO = os.path.expanduser("~/.local/share/mint-macos/settings/dock-tema-original.json")


def _archivo_tema(plank):
    nombre = plank.get_string("theme")
    for base in (os.path.expanduser("~/.local/share/plank/themes"), "/usr/local/share/plank/themes",
                 "/usr/share/plank/themes"):
        ruta = os.path.join(base, nombre, "dock.theme")
        if os.path.exists(ruta):
            return ruta
    return None


def _leer_tema(ruta, clave):
    m = re.search(r"^%s=(.*)$" % re.escape(clave), open(ruta, encoding="utf-8").read(), re.M)
    return m.group(1).strip() if m else None


def _poner_tema(ruta, clave, valor):
    texto = open(ruta, encoding="utf-8").read()
    if re.search(r"^%s=" % re.escape(clave), texto, re.M):
        texto = re.sub(r"^%s=.*$" % re.escape(clave), "%s=%s" % (clave, valor), texto, flags=re.M)
    else:
        texto += "\n%s=%s\n" % (clave, valor)
    with open(ruta, "w", encoding="utf-8") as f:
        f.write(texto)


def _encender_tema(plank, clave, encendido):
    """Encendido: el valor de antes (o el de la casa). Apagado: 0, guardando el de antes."""
    ruta = _archivo_tema(plank)
    if ruta is None:
        return
    import json
    try:
        guardado = json.load(open(_RESPALDO, encoding="utf-8"))
    except (OSError, ValueError):
        guardado = {}
    actual = _leer_tema(ruta, clave)
    if encendido:
        _poner_tema(ruta, clave, guardado.get(clave) or _TEMA_DEFECTO[clave])
    else:
        if actual not in (None, "0", "0.0"):
            guardado[clave] = actual
            os.makedirs(os.path.dirname(_RESPALDO), exist_ok=True)
            json.dump(guardado, open(_RESPALDO, "w", encoding="utf-8"))
        _poner_tema(ruta, clave, "0")


def _tema_encendido(plank, clave):
    ruta = _archivo_tema(plank)
    if ruta is None:
        return True
    v = _leer_tema(ruta, clave)
    try:
        return v is not None and float(v) > 0
    except ValueError:
        return True


def imagen_icono_panel(ident, lado):
    """El ícono de Apple del panel (settings/desde-mac.sh), o el genérico del tema."""
    ruta = os.path.expanduser(f"~/.local/share/mint-macos/settings/iconos/{ident}.png")
    img = Gtk.Image()
    try:
        img.set_from_pixbuf(GdkPixbuf.Pixbuf.new_from_file_at_size(ruta, lado, lado))
    except GLib.Error:
        img.set_from_icon_name("preferences-system", Gtk.IconSize.DIALOG)
    return img


def _etiqueta(texto):
    l = Gtk.Label(label=texto, xalign=1.0)
    l.get_style_context().add_class("mp-fila-etiqueta")
    return l


def _escala(minimo, maximo, valor, pie_izq, pie_der, al_cambiar):
    """Un slider como el de Catalina: sin número, con marcas «Small … Large» debajo."""
    esc = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, minimo, maximo, 1)
    esc.set_draw_value(False)
    esc.set_value(valor)
    esc.set_size_request(200, -1)
    esc.add_mark(minimo, Gtk.PositionType.BOTTOM, pie_izq)
    esc.add_mark(maximo, Gtk.PositionType.BOTTOM, pie_der)
    esc.connect("value-changed", lambda s: al_cambiar(int(s.get_value())))
    return esc


class PanelDock:
    """Dock: Plank por dconf, el efecto genio por la extensión Magic Lamp y el
    doble clic de la barra de título por el gsettings del gestor de ventanas."""
    id = "com.apple.preference.dock"
    nombre = "Dock"
    claves = []
    externo = False
    propio = True
    celda = None

    def __init__(self):
        self.panel = paneles.Panel(self.id, self.nombre, [],
                                   palabras="dock, size, magnification, position, minimize, genie, hide, zoom, title bar")
        self.plank = None

    def coincide(self, texto):
        t = texto.lower().strip()
        return bool(t) and any(t in c.lower() for c in (self.nombre, self.panel.palabras, self.id))

    # ── la página ────────────────────────────────────────────────────────
    def construir(self):
        try:
            self.plank = _plank()
        except Exception:  # noqa: BLE001 — sin el esquema de Plank
            l = Gtk.Label(label="Plank is not installed.")
            l.show()
            return l
        p = self.plank
        cuadro = Gtk.Grid(column_spacing=14, row_spacing=14)
        cuadro.get_style_context().add_class("mp-propio")
        cuadro.set_halign(Gtk.Align.CENTER)
        cuadro.set_margin_top(22)
        cuadro.set_margin_bottom(22)
        cuadro.set_margin_start(30)
        cuadro.set_margin_end(30)
        fila = 0

        # Size
        cuadro.attach(_etiqueta("Size:"), 0, fila, 1, 1)
        cuadro.attach(_escala(16, 128, p.get_int("icon-size"), "Small", "Large",
                              lambda v: p.set_int("icon-size", v)), 1, fila, 2, 1)
        fila += 1

        # Magnification
        mag = Gtk.CheckButton(label="Magnification:")
        mag.set_active(p.get_boolean("zoom-enabled"))
        cuadro.attach(mag, 0, fila, 1, 1)
        zoom = _escala(100, 300, min(300, max(100, p.get_int("zoom-percent"))), "Min", "Max",
                       lambda v: p.set_int("zoom-percent", v))
        zoom.set_sensitive(mag.get_active())
        cuadro.attach(zoom, 1, fila, 2, 1)

        def al_magnificar(b):
            p.set_boolean("zoom-enabled", b.get_active())
            zoom.set_sensitive(b.get_active())
        mag.connect("toggled", al_magnificar)
        fila += 1

        # Position on screen
        cuadro.attach(_etiqueta("Position on screen:"), 0, fila, 1, 1)
        pos = Gtk.Box(spacing=18)
        grupo = None
        for clave, texto in (("left", "Left"), ("bottom", "Bottom"), ("right", "Right")):
            caja = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
            r = Gtk.RadioButton.new_from_widget(grupo)
            grupo = grupo or r
            r.set_active(p.get_string("position") == clave)
            r.connect("toggled", lambda b, c=clave: b.get_active() and p.set_string("position", c))
            caja.pack_start(r, False, False, 0)
            caja.pack_start(Gtk.Label(label=texto), False, False, 0)
            pos.pack_start(caja, False, False, 0)
        cuadro.attach(pos, 1, fila, 2, 1)
        fila += 1

        # Minimize windows using
        cuadro.attach(_etiqueta("Minimize windows using:"), 0, fila, 1, 1)
        efecto = Gtk.ComboBoxText()
        efecto.append("genie", "Genie effect")
        efecto.append("scale", "Scale effect")
        efecto.set_active_id("genie" if self._genio_activo() else "scale")
        efecto.connect("changed", lambda c: self._poner_genio(c.get_active_id() == "genie"))
        efecto.set_halign(Gtk.Align.START)
        cuadro.attach(efecto, 1, fila, 2, 1)
        fila += 1

        # Prefer tabs when opening documents: lo decide cada app, no el sistema; como en una Mac
        # que no tuviera la función, se dibuja en gris (captura 12.12.52 AM).
        cuadro.attach(_etiqueta("Prefer tabs when opening documents:"), 0, fila, 1, 1)
        pestanas = Gtk.ComboBoxText()
        pestanas.append("full", "In Full Screen Only")
        pestanas.set_active(0)
        pestanas.set_sensitive(False)
        pestanas.set_tooltip_text("Each app decides this on its own on this computer.")
        pestanas.set_halign(Gtk.Align.START)
        cuadro.attach(pestanas, 1, fila, 2, 1)
        fila += 1

        # Minimize windows into application icon (el Plank de mint-macos; con un Plank
        # sin esa clave el control no sale: no hay nada que escribir).
        if p.props.settings_schema.has_key("minimize-into-icon"):
            en_icono = Gtk.CheckButton(label="Minimize windows into application icon")
            en_icono.set_active(p.get_boolean("minimize-into-icon"))
            en_icono.connect("toggled", lambda b: p.set_boolean("minimize-into-icon", b.get_active()))
            cuadro.attach(en_icono, 1, fila, 2, 1)
            fila += 1

        # Double-click a window's title bar to
        wm = Gio.Settings.new("org.cinnamon.desktop.wm.preferences")
        dc = Gtk.CheckButton(label="Double-click a window’s title bar to")
        valor = wm.get_string("action-double-click-titlebar")
        dc.set_active(valor in ("toggle-maximize", "minimize"))
        combo = Gtk.ComboBoxText()
        combo.append("toggle-maximize", "zoom")
        combo.append("minimize", "minimize")
        combo.set_active_id(valor if valor in ("toggle-maximize", "minimize") else "toggle-maximize")
        combo.set_sensitive(dc.get_active())

        def doble_clic(*_):
            combo.set_sensitive(dc.get_active())
            wm.set_string("action-double-click-titlebar", combo.get_active_id() if dc.get_active() else "none")
        dc.connect("toggled", doble_clic)
        combo.connect("changed", doble_clic)
        caja_dc = Gtk.Box(spacing=8)
        caja_dc.pack_start(dc, False, False, 0)
        caja_dc.pack_start(combo, False, False, 0)
        cuadro.attach(caja_dc, 1, fila, 2, 1)
        fila += 1

        # Animate opening applications: el rebote al abrir (LaunchBounceHeight del tema)
        animar = Gtk.CheckButton(label="Animate opening applications")
        animar.set_active(_tema_encendido(p, "LaunchBounceHeight"))
        animar.connect("toggled", lambda b: _encender_tema(p, "LaunchBounceHeight", b.get_active()))
        cuadro.attach(animar, 1, fila, 2, 1)
        fila += 1

        # Automatically hide and show the Dock
        ocultar = Gtk.CheckButton(label="Automatically hide and show the Dock")
        ocultar.set_active(p.get_string("hide-mode") != "none")
        ocultar.connect("toggled", lambda b: p.set_string("hide-mode", "auto" if b.get_active() else "none"))
        cuadro.attach(ocultar, 1, fila, 2, 1)
        fila += 1

        # Show indicators for open applications: el punto bajo el ícono (IndicatorSize del tema)
        indic = Gtk.CheckButton(label="Show indicators for open applications")
        indic.set_active(_tema_encendido(p, "IndicatorSize"))
        indic.connect("toggled", lambda b: _encender_tema(p, "IndicatorSize", b.get_active()))
        cuadro.attach(indic, 1, fila, 2, 1)
        fila += 1

        # Show recent applications in Dock: las últimas tres apps cerradas se quedan
        # (clave show-recent-apps del Plank de mint-macos).
        if p.props.settings_schema.has_key("show-recent-apps"):
            recientes = Gtk.CheckButton(label="Show recent applications in Dock")
            recientes.set_active(p.get_boolean("show-recent-apps"))
            recientes.connect("toggled", lambda b: p.set_boolean("show-recent-apps", b.get_active()))
            cuadro.attach(recientes, 1, fila, 2, 1)

        cuadro.show_all()
        return cuadro

    # ── el efecto genio: encender o apagar la extensión Magic Lamp ──────
    @staticmethod
    def _genio_activo():
        return MAGIC_LAMP in Gio.Settings.new("org.cinnamon").get_strv("enabled-extensions")

    @staticmethod
    def _poner_genio(si):
        cfg = Gio.Settings.new("org.cinnamon")
        lista = [e for e in cfg.get_strv("enabled-extensions") if e != MAGIC_LAMP]
        if si:
            lista.append(MAGIC_LAMP)
        cfg.set_strv("enabled-extensions", lista)


class PanelAppleID:
    """Apple ID: el estado de iCloud Drive y de Mail y Calendar, con lo que hace
    falta para completarlos. No sale en la cuadrícula: se abre desde la franja de
    arriba, como en Catalina."""
    id = "com.apple.preferences.AppleIDPrefPane"
    nombre = "Apple ID"
    claves = []
    externo = False
    propio = True
    celda = None
    oculto = True          # fuera de la cuadrícula
    ventana = None         # la pone la ventana al abrirlo

    def __init__(self):
        self.panel = paneles.Panel(self.id, self.nombre, [], palabras="apple id, icloud, mail, calendar, sign in")

    def coincide(self, texto):
        t = texto.lower().strip()
        return bool(t) and any(t in c.lower() for c in (self.nombre, self.panel.palabras, self.id))

    def construir(self):
        cuadro = Gtk.Grid(column_spacing=14, row_spacing=14)
        cuadro.get_style_context().add_class("mp-propio")
        cuadro.set_halign(Gtk.Align.CENTER)
        cuadro.set_margin_top(22)
        cuadro.set_margin_bottom(22)
        cuadro.set_margin_start(30)
        cuadro.set_margin_end(30)
        cuenta = self.ventana._apple_id_conocido if self.ventana else None
        tiene_mail = apple_id.mail_configurado()

        def fila(n, etiqueta, estado, boton=None):
            cuadro.attach(_etiqueta(etiqueta), 0, n, 1, 1)
            e = Gtk.Label(label=estado, xalign=0, wrap=True, max_width_chars=34)
            cuadro.attach(e, 1, n, 1, 1)
            if boton:
                cuadro.attach(boton, 2, n, 1, 1)

        def boton(texto, accion):
            b = Gtk.Button(label=texto)
            b.set_valign(Gtk.Align.CENTER)
            b.connect("clicked", lambda *_: accion())
            return b

        v = self.ventana
        if cuenta:
            fila(0, "Apple ID:", cuenta, boton("Sign Out…", v._cerrar_sesion_apple_id))
            fila(1, "iCloud Drive:", "On — appears in your home folder as iCloud Drive")
            fila(2, "Mail & Calendar:",
                 "Set up in Thunderbird" if tiene_mail else "Not set up yet. It needs an app-specific password.",
                 boton("Update…" if tiene_mail else "Set Up…", lambda: v._hoja_apple_id("mail")))
        else:
            fila(0, "Apple ID:", "Not signed in", boton("Sign In…", lambda: v._hoja_apple_id()))
            fila(1, "iCloud Drive:", "Off. Sign in to use your iCloud files.")
            fila(2, "Mail & Calendar:", "Sign in first.")
        cuadro.show_all()
        return cuadro


class PanelSpotlight:
    """Spotlyte (el «Spotlight» de este Linux, con el ícono de Spotlight de Catalina): los ajustes de Spotlyte (el fork de Ulauncher), en su settings.json.
    Solo lleva los controles que Spotlyte tiene de verdad; las categorías de resultados
    y Privacy de Catalina no existen allí. Spotlyte lee su configuración al arrancar, así
    que cada cambio lo reinicia (con los mismos argumentos con que estaba corriendo)."""
    id = "com.apple.preference.spotlight"
    nombre = "Spotlyte"
    claves = []
    externo = False
    propio = True
    celda = None
    ARCHIVO = os.environ.get("MINT_SPOTLIGHT_ARCHIVO") or os.path.expanduser("~/.config/ulauncher/settings.json")
    SIN_REINICIO = bool(os.environ.get("MINT_SPOTLIGHT_SIN_REINICIO"))
    ATAJOS = [("<Super>space", "⌘Space"), ("<Control>space", "⌃Space"), ("<Alt>space", "⌥Space"),
              ("<Alt><Super>space", "⌥⌘Space")]
    PANTALLAS = [("mouse-pointer-monitor", "Display with the mouse pointer"), ("default-monitor", "Main display")]
    RECIENTES = [("0", "None"), ("3", "3"), ("5", "5"), ("8", "8")]

    def __init__(self):
        self.panel = paneles.Panel(self.id, self.nombre, [],
                                   palabras="spotlyte, spotlight, search, ulauncher, shortcut, menu bar, recent apps")
        self.ventana = None
        self._cargando = False

    def coincide(self, texto):
        t = texto.lower().strip()
        return bool(t) and any(t in c.lower() for c in (self.nombre, self.panel.palabras, self.id))

    def _leer(self):
        try:
            with open(self.ARCHIVO, encoding="utf-8") as f:
                datos = json.load(f)
            return datos if isinstance(datos, dict) else {}
        except (OSError, ValueError):
            return {}

    def _escribir(self, clave, valor):
        """Cambia una clave sin tocar las demás y reinicia Spotlyte para que la lea."""
        if self._cargando:
            return
        datos = self._leer()
        datos[clave] = valor
        os.makedirs(os.path.dirname(self.ARCHIVO), exist_ok=True)
        with open(self.ARCHIVO + ".tmp", "w", encoding="utf-8") as f:
            json.dump(datos, f, indent=4, sort_keys=True)
        os.replace(self.ARCHIVO + ".tmp", self.ARCHIVO)
        GLib.idle_add(self._reiniciar)

    @staticmethod
    def _procesos():
        """[(pid, argv)] de Spotlyte en marcha (su programa lleva «spotlyte» y «ulauncher» en la ruta)."""
        out = []
        for d in os.listdir("/proc"):
            if not d.isdigit() or int(d) == os.getpid():
                continue
            try:
                with open(f"/proc/{d}/cmdline", "rb") as f:
                    argv = f.read().decode("utf-8", "replace").split("\0")[:-1]
            except OSError:
                continue
            if len(argv) >= 2 and "python" in os.path.basename(argv[0]) and "spotlyte" in argv[1] \
                    and argv[1].endswith("/ulauncher"):
                out.append((int(d), argv))
        return out

    def _reiniciar(self):
        if self.SIN_REINICIO:
            print("[prueba] reiniciaría Spotlyte", file=sys.stderr)
            return False
        import signal
        import time
        procesos = self._procesos()
        if not procesos:
            return False
        argv = procesos[0][1]
        for pid, _a in procesos:
            try:
                os.kill(pid, signal.SIGTERM)
            except OSError:
                pass
        for _ in range(20):
            if not self._procesos():
                break
            time.sleep(0.1)
        subprocess.Popen(argv, start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return False

    # ── la página ────────────────────────────────────────────────────────
    def construir(self):
        datos = self._leer()
        self._cargando = True
        caja = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
        caja.get_style_context().add_class("mp-propio")

        cab = Gtk.Box(spacing=14)
        cab.pack_start(imagen_icono_panel(self.id, 48), False, False, 0)
        t = Gtk.Label(label="Spotlyte helps you quickly find apps and files on your computer.", xalign=0)
        t.set_line_wrap(True)
        t.set_max_width_chars(70)
        cab.pack_start(t, True, True, 0)
        caja.pack_start(cab, False, False, 0)

        marco = Gtk.Frame()
        marco.get_style_context().add_class("mp-sd-lista")
        cuadro = Gtk.Grid(column_spacing=14, row_spacing=14)
        cuadro.set_margin_top(20)
        cuadro.set_margin_bottom(20)
        cuadro.set_margin_start(24)
        cuadro.set_margin_end(24)
        cuadro.set_halign(Gtk.Align.START)
        marco.add(cuadro)
        fila = 0

        def combo(opciones, clave, defecto):
            c = Gtk.ComboBoxText()
            for k, n in opciones:
                c.append(k, n)
            actual = str(datos.get(clave, defecto))
            if not c.set_active_id(actual):
                c.append(actual, actual)
                c.set_active_id(actual)
            c.connect("changed", lambda w: self._escribir(clave, w.get_active_id()))
            return c

        # Spotlight shortcut
        cuadro.attach(_etiqueta("Spotlyte shortcut:"), 0, fila, 1, 1)
        cuadro.attach(combo(self.ATAJOS, "hotkey-show-app", "<Super>space"), 1, fila, 1, 1)
        fila += 1
        # Show on
        cuadro.attach(_etiqueta("Show Spotlyte on:"), 0, fila, 1, 1)
        cuadro.attach(combo(self.PANTALLAS, "render-on-screen", "mouse-pointer-monitor"), 1, fila, 1, 1)
        fila += 1
        # Recent apps
        cuadro.attach(_etiqueta("Recent apps:"), 0, fila, 1, 1)
        cuadro.attach(combo(self.RECIENTES, "show-recent-apps", "0"), 1, fila, 1, 1)
        fila += 1

        for clave, texto, defecto in (("show-menu-icon", "Show Spotlyte in the menu bar", False),
                                      ("clear-previous-query", "Clear the search when Spotlyte loses focus", True)):
            c = Gtk.CheckButton(label=texto)
            c.set_active(bool(datos.get(clave, defecto)))
            c.connect("toggled", lambda w, k=clave: self._escribir(k, w.get_active()))
            cuadro.attach(c, 0, fila, 2, 1)
            fila += 1
        caja.pack_start(marco, False, False, 0)

        nota = Gtk.Label(label="Spotlyte restarts when you change a setting.", xalign=0)
        nota.get_style_context().add_class("mp-sd-detalle")
        caja.pack_start(nota, False, False, 0)
        caja.show_all()
        self._cargando = False
        return caja


class PanelStartupDisk:
    """Startup Disk: elige con qué sistema arranca la computadora. La lista sale de
    las entradas de arranque EFI (efibootmgr, que cualquiera puede leer: Ubuntu/GRUB,
    Mac OS X…) y escribe el BootOrder; aparte, la entrada por defecto del propio GRUB.
    Todo cambio lo hace el ayudante de root (settings/startup-disk) por pkexec: el
    candado pide la clave de administrador una vez, como en Catalina.
    MINT_STARTUPDISK_PRUEBA=1 usa datos falsos y no toca nada."""
    id = "com.apple.preference.startupdisk"
    nombre = "Startup Disk"
    claves = []
    externo = False
    propio = True
    celda = None
    AYUDANTE = "/usr/libexec/mint-macos/startup-disk"
    PRUEBA = bool(os.environ.get("MINT_STARTUPDISK_PRUEBA"))

    def __init__(self):
        self.panel = paneles.Panel(self.id, self.nombre, [],
                                   palabras="startup disk, boot, grub, efi, restart, default os, macos")
        self.ventana = None
        self.desbloqueado = False
        self.entradas, self.actual, self.orden = [], None, []
        self.elegida = None

    def coincide(self, texto):
        t = texto.lower().strip()
        return bool(t) and any(t in c.lower() for c in (self.nombre, self.panel.palabras, self.id))

    # ── los datos ────────────────────────────────────────────────────────
    def _leer_efi(self):
        """[(id, nombre, detalle)], BootCurrent y BootOrder, de `efibootmgr -v`."""
        if self.PRUEBA:
            texto = ("BootCurrent: 0000\nBootOrder: 0000,0080\n"
                     "Boot0000* Ubuntu\tHD(1,GPT,x)/File(\\EFI\\GRUB\\shimx64.efi)\n"
                     "Boot0080* Mac OS X\tPciRoot(0x0)/File(\\System\\Library\\CoreServices\\boot.efi)\n"
                     "Boot0082* \tPciRoot(0x0)/File(\\x\\boot.efi)\n")
        else:
            try:
                texto = subprocess.run(["efibootmgr", "-v"], capture_output=True, text=True, timeout=10).stdout
            except (OSError, subprocess.SubprocessError):
                texto = ""
        entradas, actual, orden = [], None, []
        for linea in texto.splitlines():
            if linea.startswith("BootCurrent:"):
                actual = linea.split(":", 1)[1].strip().upper()
            elif linea.startswith("BootOrder:"):
                orden = [x.strip().upper() for x in linea.split(":", 1)[1].split(",") if x.strip()]
            else:
                m = re.match(r"^Boot([0-9A-Fa-f]{4})\*? ?(.*)$", linea)
                if m:
                    nombre, _, ruta = m.group(2).partition("\t")
                    if nombre.strip():
                        entradas.append((m.group(1).upper(), nombre.strip(), ruta))
        return entradas, actual, orden

    @staticmethod
    def _describir(nombre, ruta):
        r = ruta.lower()
        if "coreservices" in r or "boot.efi" in r:
            return "macOS", "drive-harddisk-system"
        if "grub" in r or "shim" in r:
            return "Linux, GRUB", "distributor-logo"
        return "EFI", "drive-harddisk"

    # ── la página ────────────────────────────────────────────────────────
    def construir(self):
        self.entradas, self.actual, self.orden = self._leer_efi()
        self.elegida = (self.orden[0] if self.orden else None)
        caja = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        caja.get_style_context().add_class("mp-propio")
        titulo = Gtk.Label(label="Select the system you want to use to start up your computer", xalign=0)
        titulo.get_style_context().add_class("mp-sd-titulo")
        caja.pack_start(titulo, False, False, 0)

        # La lista: cuadros de 118×98 con el ícono y dos líneas, sobre fondo oscuro.
        marco = Gtk.Frame()
        marco.get_style_context().add_class("mp-sd-lista")
        marco.set_size_request(-1, 98)
        self.fila = Gtk.FlowBox()
        self.fila.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self.fila.set_min_children_per_line(4)
        self.fila.set_max_children_per_line(8)
        self.fila.set_homogeneous(False)
        self.fila.set_halign(Gtk.Align.START)
        self.fila.set_valign(Gtk.Align.START)
        self.fila.get_style_context().add_class("mp-sd-fila")
        self.fila.connect("child-activated", lambda _f, hijo: self._elegir(hijo.entrada_id))
        self.fila.connect("selected-children-changed", self._cambio_seleccion)
        for ident, nombre, ruta in self.entradas:
            detalle, icono = self._describir(nombre, ruta)
            celda = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
            celda.set_size_request(110, -1)
            celda.pack_start(Gtk.Image.new_from_icon_name(icono, Gtk.IconSize.DIALOG), False, False, 0)
            n = Gtk.Label(label=nombre)
            n.get_style_context().add_class("mp-sd-nombre")
            celda.pack_start(n, False, False, 0)
            d = Gtk.Label(label=detalle + (", running" if ident == self.actual else ""))
            d.get_style_context().add_class("mp-sd-detalle")
            celda.pack_start(d, False, False, 0)
            hijo = Gtk.FlowBoxChild()
            hijo.entrada_id = ident
            hijo.add(celda)
            self.fila.add(hijo)
        marco.add(self.fila)
        caja.pack_start(marco, False, False, 0)

        self.seleccion_txt = Gtk.Label(label="", xalign=0)
        self.seleccion_txt.get_style_context().add_class("mp-sd-detalle")
        self.seleccion_txt.set_line_wrap(True)
        self.b_reiniciar = Gtk.Button(label="Restart…")
        self.b_reiniciar.set_size_request(151, -1)
        self.b_reiniciar.connect("clicked", lambda *_: self._reiniciar())
        fila_r = Gtk.Box(spacing=12)
        fila_r.pack_start(self.seleccion_txt, True, True, 0)
        fila_r.pack_end(self.b_reiniciar, False, False, 0)
        fila_r.set_margin_top(6)
        caja.pack_start(fila_r, False, False, 0)

        # GRUB: la entrada que arranca sola (lo que en Catalina es el modo de disco de destino).
        sec = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        sec.set_margin_top(22)
        t2 = Gtk.Label(label="Choose the entry GRUB starts by default", xalign=0)
        t2.get_style_context().add_class("mp-sd-titulo")
        sec.pack_start(t2, False, False, 0)
        d2 = Gtk.Label(label="When nothing is chosen at startup, GRUB starts this entry. Unlock the pane to see "
                             "the list.", xalign=0)
        d2.set_line_wrap(True)
        d2.set_max_width_chars(70)
        d2.get_style_context().add_class("mp-sd-detalle")
        sec.pack_start(d2, False, False, 0)
        self.combo_grub = Gtk.ComboBoxText()
        self.combo_grub.set_sensitive(False)
        self.combo_grub.connect("changed", self._grub_cambio)
        self.b_saved = Gtk.Button(label="Enable…")
        self.b_saved.set_no_show_all(True)
        self.b_saved.connect("clicked", lambda *_: self._activar_saved())
        self.grub_txt = Gtk.Label(label="", xalign=0)
        self.grub_txt.get_style_context().add_class("mp-sd-detalle")
        self.grub_txt.set_line_wrap(True)
        fila_g = Gtk.Box(spacing=12)
        fila_g.pack_start(self.combo_grub, True, True, 0)
        fila_g.pack_start(self.b_saved, False, False, 0)
        sec.pack_start(fila_g, False, False, 6)
        sec.pack_start(self.grub_txt, False, False, 0)
        caja.pack_start(sec, False, False, 0)

        # El candado.
        pie = Gtk.Box(spacing=8)
        pie.set_margin_top(26)
        self.b_candado = Gtk.Button()
        self.b_candado.set_relief(Gtk.ReliefStyle.NONE)
        self.b_candado.get_style_context().add_class("mp-sd-candado")
        self.b_candado.connect("clicked", lambda *_: self._candado())
        self.candado_img = Gtk.Image()
        self.b_candado.add(self.candado_img)
        self.candado_txt = Gtk.Label(label="", xalign=0)
        self.candado_txt.get_style_context().add_class("mp-sd-detalle")
        pie.pack_start(self.b_candado, False, False, 0)
        pie.pack_start(self.candado_txt, False, False, 0)
        caja.pack_start(pie, False, False, 0)

        self._pintar_candado()
        self._pintar_seleccion()
        # el nombre del que arranca hoy queda marcado
        for h in self.fila.get_children():
            if h.entrada_id == self.elegida:
                self.fila.select_child(h)
        caja.show_all()
        if os.environ.get("MINT_STARTUPDISK_PRUEBA") == "2":       # prueba: ya desbloqueado
            GLib.timeout_add(500, lambda: self._candado() and False)
        return caja

    # ── estado ───────────────────────────────────────────────────────────
    def _nombre_de(self, ident):
        for i, n, _r in self.entradas:
            if i == ident:
                return n
        return ident or ""

    def _pintar_candado(self):
        glifo_ = "LockUnlocked" if self.desbloqueado else "LockLocked"
        ruta = os.path.join(os.path.expanduser("~/.local/share/mint-macos/settings/glifos"), glifo_ + "@1x.png")
        try:
            self.candado_img.set_from_pixbuf(GdkPixbuf.Pixbuf.new_from_file(ruta))
        except GLib.Error:
            self.candado_img.set_from_icon_name("changes-allow" if self.desbloqueado else "changes-prevent", Gtk.IconSize.LARGE_TOOLBAR)
        self.candado_txt.set_text("Click the lock to prevent further changes." if self.desbloqueado
                                  else "Click the lock to make changes.")
        self.fila.set_sensitive(self.desbloqueado)
        self.combo_grub.set_sensitive(self.desbloqueado and self.combo_grub.get_model() is not None
                                      and len(self.combo_grub.get_model()) > 0)
        self.b_reiniciar.set_sensitive(self.desbloqueado and self.elegida is not None)
        self.b_saved.set_visible(False)

    def _pintar_seleccion(self):
        if self.elegida:
            self.seleccion_txt.set_text(f"You have selected {self._nombre_de(self.elegida)}.")
        else:
            self.seleccion_txt.set_text("")

    def _cambio_seleccion(self, _f):
        pass

    # ── el ayudante de root ──────────────────────────────────────────────
    def _ayudante(self, args, listo):
        """Corre el ayudante con pkexec sin bloquear la ventana; listo(ok, salida, error)."""
        if self.PRUEBA:
            print("[prueba] ayudante:", " ".join(args), file=sys.stderr)
            fake = {"grub-list": json.dumps({"entries": [{"id": "0", "title": "Linux Mint 22.2 Cinnamon"},
                                                         {"id": "1>0", "title": "Advanced options > Linux 6.8"},
                                                         {"id": "2", "title": "UEFI Firmware Settings"}],
                                             "default": "saved", "saved_entry": "0"})}
            GLib.idle_add(lambda: listo(True, fake.get(args[0], ""), "") and False)
            return
        if not os.path.exists(self.AYUDANTE):
            GLib.idle_add(lambda: listo(False, "", "missing") and False)
            return
        try:
            proc = Gio.Subprocess.new(["pkexec", self.AYUDANTE] + args,
                                      Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE)
        except GLib.Error as e:
            GLib.idle_add(lambda: listo(False, "", str(e)) and False)
            return

        def fin(p, res):
            try:
                _ok, out, err = p.communicate_utf8_finish(res)
            except GLib.Error as e:
                listo(False, "", str(e))
                return
            listo(p.get_exit_status() == 0, out or "", (err or "").strip())
        proc.communicate_utf8_async(None, None, fin)

    def _sin_ayudante(self):
        d = Gtk.MessageDialog(transient_for=self.ventana, modal=True, message_type=Gtk.MessageType.INFO,
                              buttons=Gtk.ButtonsType.OK, text="Startup Disk needs its helper installed.")
        d.format_secondary_text("Run this once in a terminal, then try again:\n\nsudo "
                                + os.path.join(os.path.dirname(os.path.abspath(__file__)), "startup-disk",
                                               "instalar-root.sh"))
        d.run()
        d.destroy()

    def _error(self, titulo, detalle):
        d = Gtk.MessageDialog(transient_for=self.ventana, modal=True, message_type=Gtk.MessageType.ERROR,
                              buttons=Gtk.ButtonsType.OK, text=titulo)
        d.format_secondary_text(detalle)
        d.run()
        d.destroy()

    # ── acciones ─────────────────────────────────────────────────────────
    def _candado(self):
        if self.desbloqueado:
            self.desbloqueado = False
            self._pintar_candado()
            return

        def listo(ok, _o, err):
            if not ok:
                if err == "missing":
                    self._sin_ayudante()
                return False
            self.desbloqueado = True
            self._pintar_candado()
            self._cargar_grub()
            return False
        self._ayudante(["auth"], listo)

    def _elegir(self, ident):
        if not self.desbloqueado or ident == self.elegida:
            return
        previo = self.elegida

        def listo(ok, _o, err):
            if ok:
                self.elegida = ident
            else:
                self.elegida = previo
                self._error("The startup disk was not changed.", err or "The helper failed.")
                for h in self.fila.get_children():
                    if h.entrada_id == previo:
                        self.fila.select_child(h)
            self._pintar_seleccion()
            self.b_reiniciar.set_sensitive(self.elegida is not None)
            return False
        self._ayudante(["efi-order", ident], listo)

    def _reiniciar(self):
        if not self.elegida:
            return
        d = Gtk.MessageDialog(transient_for=self.ventana, modal=True, message_type=Gtk.MessageType.QUESTION,
                              buttons=Gtk.ButtonsType.NONE, text="Are you sure you want to restart?")
        d.format_secondary_text(f"Your computer will start up using {self._nombre_de(self.elegida)}.")
        d.add_button("Cancel", Gtk.ResponseType.CANCEL)
        d.add_button("Restart", Gtk.ResponseType.OK)
        d.set_default_response(Gtk.ResponseType.OK)
        r = d.run()
        d.destroy()
        if r != Gtk.ResponseType.OK:
            return

        def listo(ok, _o, err):
            if not ok:
                self._error("The computer could not be restarted.", err or "The helper failed.")
                return False
            if self.PRUEBA:
                print("[prueba] systemctl reboot", file=sys.stderr)
            else:
                subprocess.Popen(["systemctl", "reboot"])
            return False
        self._ayudante(["efi-next", self.elegida], listo)

    def _cargar_grub(self):
        def listo(ok, out, err):
            if not ok:
                self.grub_txt.set_text("The GRUB menu could not be read." if err != "missing" else "")
                return False
            try:
                datos = json.loads(out)
            except ValueError:
                return False
            self._grub = datos
            self.combo_grub.handler_block_by_func(self._grub_cambio)
            self.combo_grub.remove_all()
            for e in datos["entries"]:
                self.combo_grub.append(e["id"], e["title"])
            salvado = datos.get("default") == "saved"
            if salvado:
                self.combo_grub.set_active_id(datos.get("saved_entry") or "0")
            self.combo_grub.handler_unblock_by_func(self._grub_cambio)
            self.b_saved.set_visible(not salvado)
            self.grub_txt.set_text("" if salvado else
                                   "GRUB is not set to remember a default. Enable it to choose one here.")
            self.combo_grub.set_sensitive(salvado)
            return False
        self._ayudante(["grub-list"], listo)

    def _activar_saved(self):
        def listo(ok, _o, err):
            if not ok:
                self._error("GRUB could not be changed.", err or "The helper failed.")
                return False
            self._cargar_grub()
            return False
        self._ayudante(["grub-enable-saved"], listo)

    def _grub_cambio(self, combo):
        ident = combo.get_active_id()
        if not ident or not self.desbloqueado:
            return

        def listo(ok, _o, err):
            if not ok:
                self._error("The default entry was not changed.", err or "The helper failed.")
            return False
        self._ayudante(["grub-default", ident], listo)


class PanelMissionControl:
    """Mission Control: la mitad que Cinnamon sabe hacer (Displays have separate Spaces,
    los atajos de la extensión misioncontrol@macos) y la hoja de Hot Corners, que
    escribe `hotcorner-layout` de org.cinnamon. Una esquina de Cinnamon corre
    `expo`, `scale`, `desktop` o un comando; las acciones de Catalina que no son
    de esas tres van como comando (las que viven dentro de Cinnamon, por Eval)."""
    id = "com.apple.preference.expose"
    nombre = "Mission Control"
    claves = []
    externo = False
    propio = True
    celda = None
    EVAL = "gdbus call --session --dest org.Cinnamon --object-path /org/Cinnamon --method org.Cinnamon.Eval "
    # (comando de la esquina, nombre en Catalina); el primero es «-», apagada.
    ACCIONES = [
        ("", "\u2013"),
        ("scale", "Mission Control"),
        (EVAL + "global.mintMacosAppWindows()", "Application Windows"),
        ("desktop", "Desktop"),
        ("~/.local/bin/mac-launchpad", "Launchpad"),
        (EVAL + "global.mintMacosNotificationCenter()", "Notification Center"),
        ("cinnamon-screensaver-command -a", "Start Screen Saver"),
        ("xset dpms force off", "Put Display to Sleep"),
        ("cinnamon-screensaver-command -l", "Lock Screen"),
    ]
    # 0 arriba izquierda, 1 arriba derecha, 2 abajo izquierda, 3 abajo derecha (el orden de Cinnamon).
    ESQUINAS = ("tl", "tr", "bl", "br")
    VACIA = "expo:false:0"

    def __init__(self):
        self.panel = paneles.Panel(self.id, self.nombre, [],
                                   palabras="spaces, desktops, workspaces, hot corners, windows, mission control, expose")
        self.ventana = None
        self._cargando = False

    def coincide(self, texto):
        t = texto.lower().strip()
        return bool(t) and any(t in c.lower() for c in (self.nombre, self.panel.palabras, self.id))

    @staticmethod
    def _cinnamon():
        return Gio.Settings.new("org.cinnamon")

    @classmethod
    def _expandir(cls, cmd):
        return os.path.expanduser(cmd) if cmd.startswith("~") else cmd

    @classmethod
    def leer_esquinas(cls, ajustes=None):
        """[comando|""] por esquina: lo que hoy hace cada una ("" si está apagada)."""
        capas = list((ajustes or cls._cinnamon()).get_strv("hotcorner-layout"))
        capas += [cls.VACIA] * (4 - len(capas))
        salida = []
        for item in capas[:4]:
            partes = item.rsplit(":", 2)             # el comando puede llevar «:» (la última es el retraso)
            salida.append(partes[0] if len(partes) == 3 and partes[1] == "true" else "")
        return salida

    @classmethod
    def escribir_esquina(cls, indice, comando, ajustes=None):
        """Cambia una esquina y deja las otras (con su retraso) como estaban."""
        aj = ajustes or cls._cinnamon()
        capas = list(aj.get_strv("hotcorner-layout"))
        capas += [cls.VACIA] * (4 - len(capas))
        retraso = "0"
        partes = capas[indice].rsplit(":", 2)
        if len(partes) == 3:
            retraso = partes[2]
        capas[indice] = f"{cls._expandir(comando)}:true:{retraso}" if comando else cls.VACIA
        aj.set_strv("hotcorner-layout", capas)

    # ── la página ────────────────────────────────────────────────────────
    def construir(self):
        aj = self._cinnamon()
        mut = Gio.Settings.new("org.cinnamon.muffin")
        self._cargando = True
        caja = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
        caja.get_style_context().add_class("mp-propio")

        cab = Gtk.Box(spacing=14)
        cab.pack_start(imagen_icono_panel(self.id, 48), False, False, 0)
        t = Gtk.Label(label="Mission Control gives you an overview of all your open windows, "
                            "all arranged in a unified view.", xalign=0)
        t.set_line_wrap(True)
        t.set_max_width_chars(70)
        cab.pack_start(t, True, True, 0)
        caja.pack_start(cab, False, False, 0)

        marco = Gtk.Frame()
        marco.get_style_context().add_class("mp-sd-lista")
        cuadro = Gtk.Grid(column_spacing=14, row_spacing=10)
        for lado in ("top", "bottom", "start", "end"):
            getattr(cuadro, "set_margin_" + lado)(16 if lado in ("top", "bottom") else 20)
        cuadro.set_halign(Gtk.Align.START)
        marco.add(cuadro)
        # Displays have separate Spaces = los escritorios no se reparten entre pantallas.
        c = Gtk.CheckButton(label="Displays have separate Spaces")
        c.set_active(not mut.get_boolean("workspaces-only-on-primary"))
        c.connect("toggled", lambda w: mut.set_boolean("workspaces-only-on-primary", not w.get_active()))
        cuadro.attach(c, 0, 0, 2, 1)
        caja.pack_start(marco, False, False, 0)

        tit = Gtk.Label(label="Keyboard and Mouse Shortcuts", xalign=0)
        tit.get_style_context().add_class("mp-sd-detalle")
        caja.pack_start(tit, False, False, 0)
        atajos = Gtk.Frame()
        atajos.get_style_context().add_class("mp-sd-lista")
        g = Gtk.Grid(column_spacing=14, row_spacing=10)
        for lado in ("top", "bottom", "start", "end"):
            getattr(g, "set_margin_" + lado)(16 if lado in ("top", "bottom") else 20)
        g.set_halign(Gtk.Align.START)
        for i, (n, a) in enumerate((("Mission Control:", "\u2303\u2191"), ("Application windows:", "\u2303\u2193"),
                                    ("Spaces left and right:", "\u2303\u2190  \u2303\u2192"))):
            g.attach(_etiqueta(n), 0, i, 1, 1)
            v = Gtk.Label(label=a, xalign=0)
            g.attach(v, 1, i, 1, 1)
        atajos.add(g)
        caja.pack_start(atajos, False, False, 0)

        pie = Gtk.Box()
        b = Gtk.Button(label="Hot Corners\u2026")
        b.connect("clicked", lambda _b: self._hoja())
        pie.pack_start(b, False, False, 0)
        caja.pack_start(pie, False, False, 0)
        caja.show_all()
        self._cargando = False
        return caja

    # ── la hoja de las cuatro esquinas ───────────────────────────────────
    def _fondo(self, w, h):
        """El escritorio actual en miniatura (o un gris si no se puede leer)."""
        try:
            uri = Gio.Settings.new("org.cinnamon.desktop.background").get_string("picture-uri")
            ruta = Gio.File.new_for_uri(uri).get_path()
            pb = GdkPixbuf.Pixbuf.new_from_file(ruta)
            esc = max(w / pb.get_width(), h / pb.get_height())
            pb = pb.scale_simple(int(pb.get_width() * esc) + 1, int(pb.get_height() * esc) + 1,
                                 GdkPixbuf.InterpType.BILINEAR)
            return pb.new_subpixbuf((pb.get_width() - w) // 2, (pb.get_height() - h) // 2, w, h)
        except (GLib.Error, TypeError, AttributeError):
            return None

    def _hoja(self):
        d = Gtk.Dialog(transient_for=self.ventana, modal=True)
        d.set_decorated(False)
        d.get_style_context().add_class("mp-hoja")
        caja = d.get_content_area()
        caja.set_spacing(10)
        for lado in ("top", "bottom", "start", "end"):
            getattr(caja, "set_margin_" + lado)(20 if lado in ("start", "end") else 16)
        t = Gtk.Label(label="Active Screen Corners", xalign=0)
        t.get_style_context().add_class("mp-sd-detalle")
        caja.pack_start(t, False, False, 0)
        marco = Gtk.Frame()
        marco.get_style_context().add_class("mp-sd-lista")
        g = Gtk.Grid(column_spacing=30, row_spacing=22)
        for lado in ("top", "bottom", "start", "end"):
            getattr(g, "set_margin_" + lado)(16 if lado in ("top", "bottom") else 36)
        marco.add(g)

        actuales = self.leer_esquinas()
        combos = []
        for i in range(4):
            c = Gtk.ComboBoxText()
            for n, (cmd, nombre) in enumerate(self.ACCIONES):
                c.append(str(n), nombre)
            ids = [self._expandir(a[0]) for a in self.ACCIONES]
            if actuales[i] in ids:
                c.set_active(ids.index(actuales[i]))
            else:                                  # un comando ajeno: se muestra tal cual
                c.append("x", actuales[i])
                c.set_active_id("x")
            c.set_size_request(212, -1)
            c.connect("changed", lambda w, k=i: self._elegida(k, w))
            combos.append(c)
        miniatura = Gtk.DrawingArea()
        miniatura.set_size_request(100, 70)
        fondo = self._fondo(100, 70)

        def pintar(_w, cr):
            if fondo is not None:
                Gdk.cairo_set_source_pixbuf(cr, fondo, 0, 0)
            else:
                cr.set_source_rgb(0.15, 0.2, 0.3)
            cr.paint()
            cr.set_source_rgb(1, 1, 1)
            for x, y, dx, dy in ((0, 0, 1, 1), (100, 0, -1, 1), (0, 70, 1, -1), (100, 70, -1, -1)):
                cr.move_to(x, y)
                cr.line_to(x + 9 * dx, y)
                cr.line_to(x, y + 9 * dy)
                cr.close_path()
                cr.fill()
            return False
        miniatura.connect("draw", pintar)
        g.attach(combos[0], 0, 0, 1, 1)
        g.attach(combos[1], 2, 0, 1, 1)
        g.attach(combos[2], 0, 1, 1, 1)
        g.attach(combos[3], 2, 1, 1, 1)
        g.attach(miniatura, 1, 0, 1, 2)
        caja.pack_start(marco, False, False, 0)
        ok = d.add_button("OK", Gtk.ResponseType.OK)
        ok.get_style_context().add_class("suggested-action")
        d.set_default_response(Gtk.ResponseType.OK)
        d.show_all()
        d.run()
        d.destroy()

    def _elegida(self, indice, combo):
        n = combo.get_active_id()
        if n is None or n == "x":
            return
        self.escribir_esquina(indice, self.ACCIONES[int(n)][0])


import general  # noqa: E402  (teclado, raton y general usan cosas de este módulo, por eso van al final)
import raton  # noqa: E402
import teclado  # noqa: E402

PROPIOS = {p.id: p for p in (PanelDock(), PanelAppleID(), PanelSpotlight(), PanelStartupDisk(),
                                     PanelMissionControl(), teclado.PanelKeyboard(), raton.PanelMouse(),
                                     general.PanelGeneral())}
# Sin touchpad, Trackpad es la pantalla «No trackpad found» de Catalina; con uno, lo sirve el módulo de Cinnamon.
if not raton.hay_touchpad():
    PROPIOS[raton.PanelTrackpad.id] = raton.PanelTrackpad()
