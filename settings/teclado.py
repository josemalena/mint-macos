"""Keyboard: el panel de Catalina con sus cinco pestañas (Keyboard, Text, Shortcuts,
Input Sources, Dictation) y la hoja de Modifier Keys.

El diseño sale de las capturas de Catalina: Screen Shot 2026-10-14 at 12.13.25 AM
(Shortcuts), 12.13.29 (Keyboard), 12.13.34 (Text), 12.13.39 (Input Sources),
12.13.42 (Dictation) y 1.14.37 PM (Modifier Keys).

Lo que Linux sabe hacer se conecta de verdad: Key Repeat y Delay Until Repeat
(org.cinnamon.desktop.peripherals.keyboard), el atajo de Spotlyte, las distribuciones
(org.gnome.libgnomekbd.keyboard) y Modifier Keys (keyd, por un ayudante de root con
polkit, como Startup Disk). Lo que no tiene equivalente (Text, Dictation, el visor de
emojis) se dibuja como en la captura pero en gris, como en una Mac sin esa función.
"""
import json
import os
import subprocess
import sys

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gio, GLib, Gtk  # noqa: E402

import paneles  # noqa: E402

# Los pasos de los dos sliders son los de Catalina, en milisegundos
# (KeyRepeat 120, 90, 60, 30, 12, 6, 2 y InitialKeyRepeat 120, 94, 68, 35, 25, 15, por 15 ms).
INTERVALOS = [1800, 1350, 900, 450, 180, 90, 30]        # Key Repeat: de «Slow» a «Fast»
RETARDOS = [1800, 1410, 1020, 525, 375, 225]            # Delay Until Repeat: de «Long» a «Short»

# Modifier Keys: las teclas que se pueden reasignar y lo que puede hacer cada una.
TECLAS = [("capslock", "Caps Lock (⇪) Key:"), ("control", "Control (^) Key:"),
          ("option", "Option (⌥) Key:"), ("command", "Command (⌘) Key:")]
ACCIONES = [("capslock", "⇪ Caps Lock"), ("control", "^ Control"), ("option", "⌥ Option"),
            ("command", "⌘ Command"), ("escape", "⎋ Escape"), ("none", "No Action")]
AYUDANTE = "/usr/libexec/mint-macos/modifier-keys"
CONF_KEYD = "/etc/keyd/default.conf"
BLOQUE_INICIO = "# >>> mint-macos modifier-keys (lo escribe System Preferences; no lo edites a mano)"
BLOQUE_FIN = "# <<< mint-macos modifier-keys"


def _etiqueta(texto):
    l = Gtk.Label(label=texto, xalign=1.0)
    l.get_style_context().add_class("mp-fila-etiqueta")
    return l


def _escala(pasos, indice, pie_izq, pie_der, al_cambiar, con_apagado=False, pie_segundo=None):
    """Un slider de Catalina: una marca por paso y, debajo, los extremos («Slow … Fast»)."""
    n = len(pasos) + (1 if con_apagado else 0)
    esc = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0, n - 1, 1)
    esc.set_draw_value(False)
    esc.set_round_digits(0)
    esc.set_value(indice)
    esc.set_size_request(150, -1)
    for i in range(n):
        esc.add_mark(i, Gtk.PositionType.BOTTOM, None)
    if pie_segundo:
        esc.add_mark(1, Gtk.PositionType.BOTTOM, pie_segundo)
    esc.add_mark(0, Gtk.PositionType.BOTTOM, pie_izq)
    esc.add_mark(n - 1, Gtk.PositionType.BOTTOM, pie_der)
    esc.connect("value-changed", lambda s: al_cambiar(int(round(s.get_value()))))
    return esc


def _marco():
    m = Gtk.Frame()
    m.get_style_context().add_class("mp-sd-lista")
    return m


def _gris(widget, motivo=None):
    """Un control de una función que esta computadora no tiene: se dibuja, en gris."""
    widget.set_sensitive(False)
    if motivo:
        widget.set_tooltip_text(motivo)
    return widget


class PanelKeyboard:
    id = "com.apple.preference.keyboard"
    nombre = "Keyboard"
    claves = []
    externo = False
    propio = True
    celda = None
    # Para probar sin tocar el sistema: MINT_TECLADO_PRUEBA=1 no escribe en keyd ni en gsettings.
    PRUEBA = bool(os.environ.get("MINT_TECLADO_PRUEBA"))

    def __init__(self):
        self.panel = paneles.Panel(self.id, self.nombre, [],
                                   palabras="keyboard, key repeat, delay, shortcuts, modifier keys, caps lock, "
                                            "input sources, layout, text, dictation")
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
        stack = Gtk.Stack()
        paginas = (("keyboard", "Keyboard", self._pagina_teclado), ("text", "Text", self._pagina_texto),
                   ("shortcuts", "Shortcuts", self._pagina_atajos),
                   ("sources", "Input Sources", self._pagina_fuentes),
                   ("dictation", "Dictation", self._pagina_dictado))
        for clave, titulo, hacer in paginas:
            stack.add_titled(hacer(), clave, titulo)
        pestanas = Gtk.StackSwitcher()
        pestanas.set_stack(stack)
        pestanas.set_halign(Gtk.Align.CENTER)
        pestanas.get_style_context().add_class("mp-pestanas")
        caja.pack_start(pestanas, False, False, 0)
        marco = _marco()
        marco.add(stack)
        caja.pack_start(marco, True, True, 0)

        pie = Gtk.Box()
        bt = Gtk.Button(label="Set Up Bluetooth Keyboard…")
        bt.connect("clicked", lambda _b: self._bluetooth())
        pie.pack_end(bt, False, False, 0)
        caja.pack_start(pie, False, False, 0)
        caja.show_all()
        pedida = os.environ.get("MINT_TECLADO_PESTANA")      # solo para las pruebas visuales
        if pedida:
            stack.set_visible_child_name(pedida)
        if os.environ.get("MINT_TECLADO_HOJA"):               # idem: abre la hoja de Modifier Keys
            GLib.timeout_add(4000, lambda: self._hoja_modificadoras() and False)
        self._cargando = False
        return caja

    def _bluetooth(self):
        """Emparejar un teclado: la ventana de Bluetooth (blueman), que busca dispositivos nuevos."""
        for prog in ("blueman-manager", "blueberry"):
            try:
                subprocess.Popen([prog], start_new_session=True,
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                return
            except OSError:
                continue

    # ── Keyboard ─────────────────────────────────────────────────────────
    @staticmethod
    def _teclado():
        return Gio.Settings.new("org.cinnamon.desktop.peripherals.keyboard")

    @staticmethod
    def _mas_cercano(pasos, valor):
        return min(range(len(pasos)), key=lambda i: abs(pasos[i] - valor))

    def _pagina_teclado(self):
        cfg = self._teclado()
        pagina = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        pagina.set_margin_top(22)
        pagina.set_margin_start(24)
        pagina.set_margin_end(24)

        sliders = Gtk.Grid(column_spacing=40, row_spacing=4)
        sliders.set_halign(Gtk.Align.CENTER)
        # Key Repeat: 0 es «Off» y de 1 a 7 los intervalos de más lento a más rápido.
        repite = cfg.get_boolean("repeat")
        pos_repeticion = 0 if not repite else 1 + self._mas_cercano(INTERVALOS, cfg.get_uint("repeat-interval"))

        def al_repetir(i):
            if self._cargando or self.PRUEBA:
                return
            cfg.set_boolean("repeat", i > 0)
            if i > 0:
                cfg.set_uint("repeat-interval", INTERVALOS[i - 1])
        pos_retardo = len(RETARDOS) - 1 - self._mas_cercano(RETARDOS, cfg.get_uint("delay"))

        def al_retardar(i):
            if self._cargando or self.PRUEBA:
                return
            cfg.set_uint("delay", RETARDOS[len(RETARDOS) - 1 - i])
        for col, (titulo, esc) in enumerate((
                ("Key Repeat", _escala(INTERVALOS, pos_repeticion, "Off", "Fast", al_repetir, con_apagado=True,
                         pie_segundo="Slow")),
                ("Delay Until Repeat", _escala(RETARDOS, pos_retardo, "Long", "Short", al_retardar)))):
            t = Gtk.Label(label=titulo)
            sliders.attach(t, col, 0, 1, 1)
            sliders.attach(esc, col, 1, 1, 1)
        pagina.pack_start(sliders, False, False, 0)

        visores = Gtk.CheckButton(label="Show keyboard and emoji viewers in menu bar")
        _gris(visores, "There is no keyboard or emoji viewer to show on this computer.")
        pagina.pack_start(visores, False, False, 6)

        relleno = Gtk.Box()
        pagina.pack_start(relleno, True, True, 0)
        mod = Gtk.Button(label="Modifier Keys…")
        mod.connect("clicked", lambda _b: self._hoja_modificadoras())
        fila = Gtk.Box()
        fila.pack_end(mod, False, False, 0)
        pagina.pack_start(fila, False, False, 14)
        return pagina

    # ── Text: sin equivalente en Linux, en gris ──────────────────────────
    def _pagina_texto(self):
        pagina = Gtk.Box(spacing=18)
        pagina.set_margin_top(22)
        pagina.set_margin_start(24)
        pagina.set_margin_end(24)
        izq = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        lista = Gtk.ListStore(str, str)
        arbol = Gtk.TreeView(model=lista)
        for i, titulo in enumerate(("Replace", "With")):
            col = Gtk.TreeViewColumn(titulo, Gtk.CellRendererText(), text=i)
            col.set_expand(True)
            arbol.append_column(col)
        marco = _marco()
        marco.add(arbol)
        marco.set_size_request(360, 320)
        izq.pack_start(_gris(marco, "Text replacement is not available on this computer."), True, True, 0)
        botones = Gtk.Box()
        botones.get_style_context().add_class("linked")
        for t in ("+", "−"):
            botones.pack_start(_gris(Gtk.Button(label=t)), False, False, 0)
        izq.pack_start(botones, False, False, 0)
        pagina.pack_start(izq, False, False, 0)

        der = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        for texto, activo in (("Correct spelling automatically", False), ("Capitalize words automatically", True),
                              ("Add period with double-space", True)):
            c = Gtk.CheckButton(label=texto)
            c.set_active(activo)
            der.pack_start(_gris(c), False, False, 0)
        der.pack_start(Gtk.Label(label="Spelling:", xalign=0), False, False, 8)
        ortografia = Gtk.ComboBoxText()
        ortografia.append("auto", "Automatic by Language")
        ortografia.set_active(0)
        der.pack_start(_gris(ortografia), False, False, 0)
        inteligentes = Gtk.CheckButton(label="Use smart quotes and dashes")
        inteligentes.set_active(True)
        der.pack_start(_gris(inteligentes), False, False, 8)
        for texto, valor in (("for Double Quotes", "“abc”"), ("for Single Quotes", "‘abc’")):
            f = Gtk.Box(spacing=8)
            f.pack_start(Gtk.Label(label=texto, xalign=0), False, False, 0)
            c = Gtk.ComboBoxText()
            c.append("v", valor)
            c.set_active(0)
            f.pack_end(_gris(c), False, False, 0)
            der.pack_start(f, False, False, 0)
        pagina.pack_start(der, False, False, 0)
        return pagina

    # ── Shortcuts ────────────────────────────────────────────────────────
    CATEGORIAS = ["Launchpad & Dock", "Display", "Mission Control", "Keyboard", "Screenshots", "Services",
                  "Spotlight", "Accessibility", "App Shortcuts"]

    def _pagina_atajos(self):
        pagina = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        pagina.set_margin_top(14)
        pagina.set_margin_start(20)
        pagina.set_margin_end(20)
        pagina.pack_start(Gtk.Label(label="To change a shortcut, select it, click the key combination, "
                                          "and then type the new keys.", xalign=0), False, False, 0)
        cuerpo = Gtk.Box(spacing=0)
        categorias = Gtk.ListBox()
        categorias.set_size_request(170, 240)
        derecha = Gtk.Stack()
        for nombre in self.CATEGORIAS:
            fila = Gtk.ListBoxRow()
            fila.add(Gtk.Label(label=nombre, xalign=0, margin=4))
            fila.nombre = nombre
            categorias.add(fila)
            derecha.add_named(self._atajos_de(nombre), nombre)
        categorias.connect("row-selected", lambda _l, f: f and derecha.set_visible_child_name(f.nombre))
        m1, m2 = _marco(), _marco()
        m1.add(categorias)
        m2.add(derecha)
        cuerpo.pack_start(m1, False, False, 0)
        cuerpo.pack_start(m2, True, True, 6)
        pagina.pack_start(cuerpo, True, True, 0)
        derecha.show_all()      # Gtk.Stack solo cambia a una página que ya es visible
        categorias.select_row(categorias.get_row_at_index(self.CATEGORIAS.index("Spotlight")))
        derecha.set_visible_child_name("Spotlight")

        pie = Gtk.Box()
        pie.pack_end(_gris(Gtk.Button(label="Restore Defaults")), False, False, 0)
        pagina.pack_start(pie, False, False, 4)
        nav = Gtk.CheckButton(label="Use keyboard navigation to move focus between controls")
        _gris(nav, "Tab and Shift Tab already move the focus between controls.")
        pagina.pack_start(nav, False, False, 0)
        pagina.pack_start(Gtk.Label(label="Press the Tab key to move focus forward and Shift Tab to move focus backward.",
                                    xalign=0), False, False, 0)
        return pagina

    def _atajos_de(self, categoria):
        lista = Gtk.ListBox()
        lista.set_selection_mode(Gtk.SelectionMode.NONE)
        if categoria == "Spotlight":
            from propios import PanelSpotlight  # el atajo de Spotlyte es el de ese panel
            ajuste = PanelSpotlight()
            datos = ajuste._leer()
            actual = datos.get("hotkey-show-app", "<Super>space")
            fila = Gtk.Box(spacing=10, margin=6)
            marca = Gtk.CheckButton()
            marca.set_active(True)
            _gris(marca)
            fila.pack_start(marca, False, False, 0)
            fila.pack_start(Gtk.Label(label="Show Spotlight search", xalign=0), True, True, 0)
            combo = Gtk.ComboBoxText()
            for k, n in PanelSpotlight.ATAJOS:
                combo.append(k, n)
            if not combo.set_active_id(actual):
                combo.append(actual, actual)
                combo.set_active_id(actual)
            combo.connect("changed", lambda w: self._cargando or self.PRUEBA
                          or ajuste._escribir("hotkey-show-app", w.get_active_id()))
            fila.pack_end(combo, False, False, 0)
            lista.add(fila)
            # Show Finder search window: Fynder no tiene esa ventana; se dibuja como en la captura, en gris.
            fila2 = Gtk.Box(spacing=10, margin=6)
            marca2 = Gtk.CheckButton()
            marca2.set_active(True)
            fila2.pack_start(_gris(marca2), False, False, 0)
            fila2.pack_start(Gtk.Label(label="Show Finder search window", xalign=0), True, True, 0)
            fila2.pack_end(Gtk.Label(label="\u2325\u2318Space"), False, False, 6)
            _gris(fila2, "Fynder has no search window yet.")
            lista.add(fila2)
        return lista

    # ── Input Sources ────────────────────────────────────────────────────
    def _pagina_fuentes(self):
        pagina = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        pagina.set_margin_top(14)
        pagina.set_margin_start(20)
        pagina.set_margin_end(20)
        try:
            capas = Gio.Settings.new("org.gnome.libgnomekbd.keyboard").get_strv("layouts")
        except Exception:  # noqa: BLE001
            capas = []
        lista = Gtk.ListBox()
        lista.set_size_request(-1, 280)
        for capa in capas:
            lista.add(Gtk.Label(label=self._nombre_capa(capa), xalign=0, margin=6))
        marco = _marco()
        marco.add(lista)
        pagina.pack_start(marco, True, True, 0)
        menu = Gtk.CheckButton(label="Show Input menu in menu bar")
        _gris(menu, "The keyboard layout menu lives in the Cinnamon panel.")
        pagina.pack_start(menu, False, False, 0)
        return pagina

    @staticmethod
    def _nombre_capa(capa):
        """«us» → «U.S.»; «us\\tintl» y los demás se muestran como los define xkb."""
        nombres = {"us": "U.S.", "es": "Spanish", "latam": "Latin American", "us\tintl": "U.S. International"}
        return nombres.get(capa, capa.replace("\t", " ("))

    # ── Dictation: sin equivalente en Linux, en gris ─────────────────────
    def _pagina_dictado(self):
        pagina = Gtk.Box(spacing=24)
        pagina.set_margin_top(30)
        pagina.set_margin_start(30)
        der = Gtk.Grid(column_spacing=10, row_spacing=10)
        t = Gtk.Label(label="Use Dictation wherever you can type text. To start dictating, use the shortcut "
                            "or select Start Dictation from the Edit menu.", xalign=0)
        t.set_line_wrap(True)
        t.set_max_width_chars(52)
        der.attach(t, 0, 0, 2, 1)
        der.attach(_etiqueta("Dictation:"), 0, 1, 1, 1)
        onoff = Gtk.Box(spacing=10)
        r_on = Gtk.RadioButton.new_with_label_from_widget(None, "On")
        r_off = Gtk.RadioButton.new_with_label_from_widget(r_on, "Off")
        r_off.set_active(True)
        onoff.pack_start(r_on, False, False, 0)
        onoff.pack_start(r_off, False, False, 0)
        der.attach(_gris(onoff, "Dictation is not available on this computer."), 1, 1, 1, 1)
        for i, (texto, valor) in enumerate((("Language:", "English (United States)"), ("Shortcut:", "Off"))):
            der.attach(_etiqueta(texto), 0, 2 + i, 1, 1)
            c = Gtk.ComboBoxText()
            c.append("v", valor)
            c.set_active(0)
            der.attach(_gris(c), 1, 2 + i, 1, 1)
        pagina.pack_start(der, False, False, 0)
        return pagina

    # ── Modifier Keys ────────────────────────────────────────────────────
    @staticmethod
    def leer_modificadoras():
        """{tecla: acción} del bloque que escribe el ayudante en keyd; lo no listado va por defecto."""
        actual = {t: t for t, _n in TECLAS}
        try:
            texto = open(CONF_KEYD, encoding="utf-8").read()
        except OSError:
            return actual
        dentro = False
        for linea in texto.splitlines():
            if linea.strip() == BLOQUE_INICIO:
                dentro = True
            elif linea.strip() == BLOQUE_FIN:
                dentro = False
            elif dentro and linea.startswith("# "):
                partes = linea[2:].split("=")
                if len(partes) == 2 and partes[0].strip() in actual:
                    actual[partes[0].strip()] = partes[1].strip()
        return actual

    def _hoja_modificadoras(self):
        d = Gtk.Dialog(transient_for=self.ventana, modal=True)
        d.set_decorated(False)
        d.get_style_context().add_class("mp-hoja")
        caja = d.get_content_area()
        caja.set_spacing(12)
        for lado in ("top", "bottom", "start", "end"):
            getattr(caja, "set_margin_" + lado)(20)
        t = Gtk.Label(label="For each modifier key listed below, choose the action you want it to perform "
                            "from the pop-up menu.", xalign=0)
        t.set_line_wrap(True)
        t.set_max_width_chars(46)
        caja.pack_start(t, False, False, 0)
        g = Gtk.Grid(column_spacing=10, row_spacing=10)
        g.set_halign(Gtk.Align.CENTER)
        actuales = self.leer_modificadoras()
        combos = {}
        for i, (tecla, etiqueta) in enumerate(TECLAS):
            g.attach(_etiqueta(etiqueta), 0, i, 1, 1)
            c = Gtk.ComboBoxText()
            for k, n in ACCIONES:
                c.append(k, n)
            c.set_active_id(actuales[tecla])
            combos[tecla] = c
            g.attach(c, 1, i, 1, 1)
        caja.pack_start(g, False, False, 0)
        restaurar = d.add_button("Restore Defaults", Gtk.ResponseType.REJECT)
        d.add_button("Cancel", Gtk.ResponseType.CANCEL)
        ok = d.add_button("OK", Gtk.ResponseType.OK)
        ok.get_style_context().add_class("suggested-action")
        d.set_default_response(Gtk.ResponseType.OK)
        restaurar.connect("clicked", lambda _b: [combos[t].set_active_id(t) for t, _n in TECLAS])
        d.show_all()
        while True:
            r = d.run()
            if r == Gtk.ResponseType.REJECT:
                continue        # «Restore Defaults» solo vuelve a poner los menús; se aplica con OK
            break
        elegido = {t: combos[t].get_active_id() for t, _n in TECLAS}
        d.destroy()
        if r == Gtk.ResponseType.OK and elegido != actuales:
            self.aplicar_modificadoras(elegido)

    def aplicar_modificadoras(self, elegido):
        """Se lo pide al ayudante de root por pkexec (pide la clave una vez); keyd recarga solo."""
        if self.PRUEBA:
            print("[prueba] modifier-keys", json.dumps(elegido), file=sys.stderr)
            return True
        args = ["pkexec", AYUDANTE] + [f"{t}={elegido[t]}" for t, _n in TECLAS]
        try:
            r = subprocess.run(args, capture_output=True, text=True, timeout=120)
        except (OSError, subprocess.SubprocessError) as e:
            self._aviso("Modifier Keys", f"Could not change the modifier keys: {e}")
            return False
        if r.returncode != 0:
            if r.returncode not in (126, 127):   # 126/127: se canceló la clave; no es un error que contar
                self._aviso("Modifier Keys", (r.stderr or r.stdout or "The change was not applied.").strip())
            return False
        return True

    def _aviso(self, titulo, texto):
        d = Gtk.MessageDialog(transient_for=self.ventana, modal=True, message_type=Gtk.MessageType.WARNING,
                              buttons=Gtk.ButtonsType.OK, text=titulo)
        d.format_secondary_text(texto)
        d.run()
        d.destroy()
