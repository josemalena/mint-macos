"""Sound: el panel de Catalina con sus tres pestañas (Sound Effects, Output, Input).

Capturas: Screen Shot 2026-10-14 at 1.20.39 PM (Sound Effects), 1.20.52 PM (Output), 1.20.55 PM (Input).

Conectado de verdad (PipeWire/PulseAudio con pactl): los dispositivos de salida y de entrada y cuál es
el predeterminado, Balance, Output volume, Mute e Input volume. En Sound Effects, «Play user interface
sound effects» y «Play feedback when volume is changed» son claves de org.cinnamon.desktop.sound.
Sin equivalente aquí (en gris, como en una Mac sin esa función): Alert volume, Play sound effects
through, Show volume in menu bar y el medidor Input level.

La lista de alertas (Basso, Blow, Bottle…) son sonidos de Apple: salen del disco de la Mac a
`~/.local/share/mint-macos/settings/sonidos/` y nunca van al repo. Sin ellos la lista queda vacía.
"""
import glob
import json
import os
import subprocess

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gio, GLib, Gtk  # noqa: E402

import paneles  # noqa: E402

SONIDOS = os.path.expanduser("~/.local/share/mint-macos/settings/sonidos")


def _pactl(*args):
    try:
        r = subprocess.run(["pactl", *args], capture_output=True, text=True, timeout=10)
        return r.stdout if r.returncode == 0 else ""
    except (OSError, subprocess.SubprocessError):
        return ""


def _json(que):
    try:
        return json.loads(_pactl("-f", "json", "list", que) or "[]")
    except ValueError:
        return []


def _tipo(d, es_salida):
    """El texto de la columna Type, como los pone Catalina (USB, HDMI, Bluetooth, Headphone port…)."""
    p = d.get("properties", {})
    bus, nombre = p.get("device.bus", ""), d.get("name", "").lower()
    puerto = (d.get("active_port") or "").lower()
    if bus == "usb":
        return "USB"
    if bus == "bluetooth" or "bluez" in nombre:
        return "Bluetooth"
    if "hdmi" in nombre or "hdmi" in puerto:
        return "HDMI"
    if "headphone" in puerto:
        return "Headphone port"
    if "line" in puerto:
        return "Audio line-in port"
    return "Built-in"


def _etiqueta(texto):
    l = Gtk.Label(label=texto, xalign=1.0)
    l.get_style_context().add_class("mp-fila-etiqueta")
    return l


def _gris(widget, motivo=None):
    widget.set_sensitive(False)
    if motivo:
        widget.set_tooltip_text(motivo)
    return widget


def _marco():
    m = Gtk.Frame()
    m.get_style_context().add_class("mp-sd-lista")
    return m


def _deslizador(valor, minimo, maximo, pie_izq, pie_der, al_cambiar, marcas=11):
    esc = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, minimo, maximo, (maximo - minimo) / 100.0)
    esc.set_draw_value(False)
    esc.set_value(valor)
    esc.set_size_request(190, -1)
    esc.set_margin_start(14)
    for i in range(marcas):
        esc.add_mark(minimo + (maximo - minimo) * i / (marcas - 1), Gtk.PositionType.BOTTOM, None)
    if pie_izq:
        esc.add_mark(minimo, Gtk.PositionType.BOTTOM, pie_izq)
        esc.add_mark(maximo, Gtk.PositionType.BOTTOM, pie_der)
    esc.connect("value-changed", lambda s: al_cambiar(s.get_value()))
    return esc


class PanelSound:
    id = "com.apple.preference.sound"
    nombre = "Sound"
    claves = []
    externo = False
    propio = True
    celda = None
    PRUEBA = bool(os.environ.get("MINT_SONIDO_PRUEBA"))     # no escribe en PipeWire ni en gsettings

    def __init__(self):
        self.panel = paneles.Panel(self.id, self.nombre, [],
                                   palabras="sound, volume, output, input, microphone, speakers, balance, "
                                            "mute, alert, sound effects")
        self.ventana = None
        self._cargando = False

    def coincide(self, texto):
        t = texto.lower().strip()
        return bool(t) and any(t in c.lower() for c in (self.nombre, self.panel.palabras, self.id))

    # ── la página ────────────────────────────────────────────────────────
    def construir(self):
        self._cargando = True
        caja = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        caja.get_style_context().add_class("mp-propio")
        caja.set_margin_top(12)
        stack = Gtk.Stack()
        stack.add_titled(self._pagina_efectos(), "efectos", "Sound Effects")
        stack.add_titled(self._pagina_dispositivos(True), "salida", "Output")
        stack.add_titled(self._pagina_dispositivos(False), "entrada", "Input")
        pestanas = Gtk.StackSwitcher()
        pestanas.set_stack(stack)
        pestanas.set_halign(Gtk.Align.CENTER)
        pestanas.get_style_context().add_class("mp-pestanas")
        caja.pack_start(pestanas, False, False, 0)
        marco = _marco()
        marco.add(stack)
        caja.pack_start(marco, True, True, 0)
        caja.pack_start(self._pie(), False, False, 6)
        caja.show_all()
        pedida = os.environ.get("MINT_SONIDO_PESTANA")        # solo para las pruebas visuales
        if pedida:
            stack.set_visible_child_name(pedida)
        self._cargando = False
        return caja

    # ── Output volume y Mute (abajo, en las tres pestañas) ───────────────
    def _pie(self):
        g = Gtk.Grid(column_spacing=10, row_spacing=6)
        g.set_halign(Gtk.Align.CENTER)
        g.attach(_etiqueta("Output volume:"), 0, 0, 1, 1)
        sal = self._predeterminado("sinks", "get-default-sink")
        vol = self._volumen(sal) if sal else 0
        self._vol_salida = _deslizador(vol, 0, 100, None, None, self._poner_volumen_salida)
        g.attach(self._vol_salida, 1, 0, 1, 1)
        self._mudo = Gtk.CheckButton(label="Mute")
        self._mudo.set_active(bool(sal and sal.get("mute")))
        self._mudo.connect("toggled", lambda b: self._poner_mudo(b.get_active()))
        g.attach(self._mudo, 2, 0, 1, 1)
        menu = Gtk.CheckButton(label="Show volume in menu bar")
        menu.set_active(True)
        g.attach(_gris(menu, "The volume control lives in the Cinnamon panel."), 1, 1, 2, 1)
        return g

    @staticmethod
    def _volumen(d):
        """El volumen más alto de los canales, de 0 a 100."""
        v = [c.get("value_percent", "0%").rstrip("%") for c in d.get("volume", {}).values()]
        try:
            return max(float(x) for x in v)
        except ValueError:
            return 0.0

    @staticmethod
    def _predeterminado(que, orden):
        nombre = _pactl(orden).strip()
        for d in _json(que):
            if d.get("name") == nombre:
                return d
        return None

    def _poner_volumen_salida(self, v):
        if self._cargando or self.PRUEBA:
            return
        _pactl("set-sink-volume", "@DEFAULT_SINK@", "%d%%" % round(v))

    def _poner_mudo(self, si):
        if self._cargando or self.PRUEBA:
            return
        _pactl("set-sink-mute", "@DEFAULT_SINK@", "1" if si else "0")

    # ── Sound Effects ────────────────────────────────────────────────────
    def _pagina_efectos(self):
        pagina = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        pagina.set_margin_top(14)
        pagina.set_margin_start(20)
        pagina.set_margin_end(20)
        pagina.set_margin_bottom(14)
        t = Gtk.Label(label="Select an alert sound:", xalign=0)
        t.get_style_context().add_class("mp-titulo-negrita")
        pagina.pack_start(t, False, False, 0)
        lista = Gtk.ListStore(str, str, str)
        for ruta in sorted(glob.glob(os.path.join(SONIDOS, "*"))):
            lista.append([os.path.splitext(os.path.basename(ruta))[0], "Built-in", ruta])
        arbol = Gtk.TreeView(model=lista)
        for i, titulo in enumerate(("Name", "Type")):
            col = Gtk.TreeViewColumn(titulo, Gtk.CellRendererText(), text=i)
            col.set_expand(True)
            arbol.append_column(col)
        sel = arbol.get_selection()
        sel.connect("changed", self._alerta_elegida)
        marco = _marco()
        marco.set_size_request(-1, 130)
        pantalla = Gtk.ScrolledWindow()
        pantalla.add(arbol)
        marco.add(pantalla)
        pagina.pack_start(marco, False, False, 0)

        g = Gtk.Grid(column_spacing=10, row_spacing=10)
        g.set_halign(Gtk.Align.CENTER)
        g.attach(_etiqueta("Play sound effects through:"), 0, 0, 1, 1)
        por = Gtk.ComboBoxText()
        por.append("sel", "Selected sound output device")
        por.set_active(0)
        g.attach(_gris(por, "Effects always use the selected output device here."), 1, 0, 2, 1)
        g.attach(_etiqueta("Alert volume:"), 0, 1, 1, 1)
        g.attach(_gris(_deslizador(100, 0, 100, None, None, lambda v: None, 8),
                       "Alerts follow the output volume on this computer."), 1, 1, 2, 1)
        cfg = Gio.Settings.new("org.cinnamon.desktop.sound")
        for i, (clave, texto) in enumerate((("event-sounds", "Play user interface sound effects"),
                                            ("volume-sound-enabled", "Play feedback when volume is changed"))):
            c = Gtk.CheckButton(label=texto)
            c.set_active(cfg.get_boolean(clave))
            c.connect("toggled", lambda b, k=clave: (not self._cargando and not self.PRUEBA)
                      and cfg.set_boolean(k, b.get_active()))
            g.attach(c, 1, 2 + i, 2, 1)
        pagina.pack_start(g, False, False, 0)
        return pagina

    def _alerta_elegida(self, seleccion):
        modelo, it = seleccion.get_selected()
        if it is None or self._cargando or self.PRUEBA:
            return
        ruta = modelo[it][2]
        # La alerta de Sound Effects es el aviso del sistema, no el sonido de las notificaciones (en la Mac estas no la usan): aquí ya no se
        # toca org.cinnamon.sounds notification-*. La versión en Vala (paneles/sonido.vala) la vuelve el evento bell-window-system de un tema propio;
        # esta, la de respaldo, solo la reproduce.
        try:
            subprocess.Popen(["paplay", ruta], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except OSError:
            pass

    # ── Output e Input ───────────────────────────────────────────────────
    def _pagina_dispositivos(self, salida):
        que = "sinks" if salida else "sources"
        pagina = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        pagina.set_margin_top(14)
        pagina.set_margin_start(20)
        pagina.set_margin_end(20)
        pagina.set_margin_bottom(14)
        t = Gtk.Label(label="Select a device for sound %s:" % ("output" if salida else "input"), xalign=0)
        t.get_style_context().add_class("mp-titulo-negrita")
        pagina.pack_start(t, False, False, 0)

        lista = Gtk.ListStore(str, str, str)       # nombre, tipo, id de PipeWire
        predeterminado = _pactl("get-default-" + ("sink" if salida else "source")).strip()
        elegido = None
        for d in _json(que):
            if not salida and d.get("name", "").endswith(".monitor"):
                continue                           # los «monitor» son la salida escuchada, no un micrófono
            it = lista.append([d.get("description", d["name"]), _tipo(d, salida), d["name"]])
            if d["name"] == predeterminado:
                elegido = it
        arbol = Gtk.TreeView(model=lista)
        for i, titulo in enumerate(("Name", "Type")):
            col = Gtk.TreeViewColumn(titulo, Gtk.CellRendererText(), text=i)
            col.set_expand(True)
            arbol.append_column(col)
        marco = _marco()
        marco.set_size_request(-1, 140)
        pantalla = Gtk.ScrolledWindow()
        pantalla.add(arbol)
        marco.add(pantalla)
        pagina.pack_start(marco, False, False, 0)

        sub = Gtk.Label(label="Settings for the selected device:", xalign=0)
        pagina.pack_start(sub, False, False, 0)
        g = Gtk.Grid(column_spacing=10, row_spacing=10)
        g.set_halign(Gtk.Align.CENTER)
        if salida:
            g.attach(_etiqueta("Balance:"), 0, 0, 1, 1)
            self._balance = _deslizador(0, -100, 100, "left", "right", self._poner_balance, 5)
            g.attach(self._balance, 1, 0, 1, 1)
        else:
            g.attach(_etiqueta("Input volume:"), 0, 0, 1, 1)
            self._vol_entrada = _deslizador(0, 0, 100, None, None, self._poner_volumen_entrada)
            g.attach(self._vol_entrada, 1, 0, 1, 1)
            g.attach(_etiqueta("Input level:"), 0, 1, 1, 1)
            nivel = Gtk.Box(spacing=6)
            for _ in range(15):
                nivel.pack_start(Gtk.Separator(orientation=Gtk.Orientation.VERTICAL), False, False, 0)
            g.attach(_gris(nivel, "The input level meter is not available on this computer."), 1, 1, 1, 1)
        pagina.pack_start(g, False, False, 0)

        arbol.get_selection().connect("changed", self._dispositivo_elegido, salida)
        if elegido is not None:
            arbol.get_selection().select_iter(elegido)
        return pagina

    def _dispositivo_elegido(self, seleccion, salida):
        modelo, it = seleccion.get_selected()
        if it is None:
            return
        nombre = modelo[it][2]
        d = next((x for x in _json("sinks" if salida else "sources") if x["name"] == nombre), None)
        previo, self._cargando = self._cargando, True
        if d is not None:
            if salida:
                self._balance.set_value(float(d.get("balance", 0.0)) * 100)
            else:
                self._vol_entrada.set_value(self._volumen(d))
        self._cargando = previo
        if not previo and not self.PRUEBA:
            _pactl("set-default-" + ("sink" if salida else "source"), nombre)
            if salida:        # el volumen y el mute de abajo son los del dispositivo recién elegido
                self._cargando = True
                self._vol_salida.set_value(self._volumen(d or {}))
                self._mudo.set_active(bool(d and d.get("mute")))
                self._cargando = False

    def _poner_balance(self, b):
        """b de -100 (todo a la izquierda) a 100 (todo a la derecha): baja el canal contrario."""
        if self._cargando or self.PRUEBA:
            return
        d = self._predeterminado("sinks", "get-default-sink")
        if not d:
            return
        v = self._volumen(d)
        izq = v * (1 - max(0.0, b) / 100.0)
        der = v * (1 + min(0.0, b) / 100.0)
        _pactl("set-sink-volume", "@DEFAULT_SINK@", "%d%%" % round(izq), "%d%%" % round(der))

    def _poner_volumen_entrada(self, v):
        if self._cargando or self.PRUEBA:
            return
        _pactl("set-source-volume", "@DEFAULT_SOURCE@", "%d%%" % round(v))
