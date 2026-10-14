#!/usr/bin/python3
"""System Preferences para Cinnamon, con el diseño de macOS Catalina.

Una ventana nueva: barra de herramientas (atrás, adelante, Show All y búsqueda),
la cuadrícula de paneles por grupos y, al abrir uno, su página con pestañas.
Por dentro no reescribe nada de Cinnamon: carga los módulos de
cinnamon-settings (los cs_*.py de /usr/share/cinnamon/cinnamon-settings) y los
muestra en su propia ventana. Lo que cambia es el aspecto y cómo se agrupan.

    mac-settings                 la cuadrícula
    mac-settings sound           un panel: por el nombre de Cinnamon…
    mac-settings Displays        …o el de Catalina (sin importar mayúsculas)
    mac-settings --lista         los paneles que hay

Los íconos de Apple (settings/desde-mac.sh) se leen de
~/.local/share/mint-macos/settings; sin ellos se usan los del tema.
"""

import argparse
import time
import importlib
import importlib.util
import json
import os
import subprocess
import sys
import traceback

CS = "/usr/share/cinnamon/cinnamon-settings"
AQUI = os.path.dirname(os.path.abspath(__file__))
APPS = os.path.expanduser("~/.local/share/mint-macos/settings")

sys.path.insert(0, CS)
sys.path.append(CS + "/modules")
sys.path.append(CS + "/bin")
sys.path.insert(0, AQUI)

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
gi.require_version("GdkPixbuf", "2.0")
from gi.repository import Gdk, GdkPixbuf, Gio, GLib, Gtk  # noqa: E402

import cairo  # noqa: E402

import paneles  # noqa: E402
import apple_id  # noqa: E402

_T0 = time.time()


def traza(texto):
    """MP_DEBUG=1 imprime cuánto tarda cada fase del arranque."""
    if os.environ.get("MP_DEBUG"):
        print(f"[{time.time() - _T0:6.2f}s] {texto}", file=sys.stderr, flush=True)


APP_ID = "io.github.josemalena.MintMacosSettings"
TITULO = "System Preferences"
ICONO = 40            # el ícono de cada panel en la cuadrícula
COLUMNAS = 8          # paneles por fila, como en Catalina
ANCHO = 668           # el ancho de la ventana de Catalina
MIN_ALTO = 380
MIN_PAGINA = 520      # una página de módulo no baja de esto: sus listas se estiran


class Motor:
    """Carga los módulos de cinnamon-settings y los deja en un diccionario."""

    def __init__(self, content_box):
        spec = importlib.util.spec_from_file_location("cs_main", CS + "/cinnamon-settings.py")
        self.cs = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.cs)
        self.cs.config.PARSED_ARGS = argparse.Namespace(module=None, tab=None, sort=None, panel=None)
        self.SW = self.cs.SettingsWidgets
        self.content_box = content_box
        content_box.c_manager = self.cs.capi.CManager()
        self.paginas = {}       # clave → SidePage
        self.modulos = {}       # clave → instancia del módulo de python (si lo hay)
        self.cargar()

    def cargar(self):
        cs, SW = self.cs, self.SW
        for nombre in cs.PYTHON_CS_MODULES:
            try:
                mod = importlib.import_module(nombre).Module(self.content_box)
                try:
                    if not mod._loadCheck():
                        continue
                except AttributeError:
                    pass
                self.paginas[mod.name] = mod.sidePage
                self.modulos[mod.name] = mod
            except Exception:
                print(f"no cargó {nombre}", file=sys.stderr)
                traceback.print_exc()
        for item in cs.CONTROL_CENTER_MODULES:
            cc = SW.CCModule(item[0], item[1], item[2], item[3], item[4], self.content_box)
            if cc.process(self.content_box.c_manager):
                self.paginas[item[1]] = cc.sidePage
        tiene_sources = False
        for item in cs.STANDALONE_MODULES:
            sa = SW.SAModule(item[0], item[1], item[2], item[3], item[4], self.content_box)
            if sa.process():
                self.paginas[item[1]] = sa.sidePage
                tiene_sources = tiene_sources or "mintsources" in item[1]
        if not tiene_sources:
            for item in cs.ALTERNATE_MODULES:
                sa = SW.SAModule(item[0], item[1], item[2], item[3], item[4], self.content_box)
                if sa.process():
                    self.paginas[item[1]] = sa.sidePage
        for clave, (etiqueta, icono, palabras) in paneles.EXTERNOS.items():
            sa = SW.SAModule(etiqueta, clave, icono, "prefs", palabras, self.content_box)
            if sa.process():
                self.paginas[clave] = sa.sidePage

    def poner_padre(self, ventana):
        for mod in self.modulos.values():
            try:
                mod._setParentRef(ventana)
            except AttributeError:
                pass


def armar_paneles(motor):
    """[(grupo, [PanelVivo])]: los paneles de Catalina que tienen con qué
    servirse, y al final los módulos de Cinnamon que ningún panel recogió."""
    usados = set()
    grupos = []
    for gid, lista in paneles.GRUPOS:
        vivos = []
        for p in lista:
            claves = [k for k in p.modulos if k in motor.paginas]
            # Alternativas externas (blueman o blueberry): con la primera basta.
            externas = [k for k in claves if motor.paginas[k].is_standalone]
            internas = [k for k in claves if not motor.paginas[k].is_standalone]
            if internas:
                claves = internas
            elif externas:
                claves = externas[:1]
            if not claves:
                continue
            usados.update(claves)
            vivos.append(PanelVivo(p, claves, motor))
        if vivos:
            grupos.append((gid, vivos))
    # Solo los paneles de Catalina. Lo demás de Mint (Disks, Firewall, Fingerprints…)
    # queda detrás de un solo botón, «Advanced», que abre el cinnamon-settings de
    # siempre.
    grupos.append(("advanced", [PanelAvanzado()]))
    return grupos


class PanelAvanzado:
    """«Advanced»: el cinnamon-settings de Mint entero, para lo que Catalina no tiene."""
    id = "mint.advanced"
    nombre = "Advanced"
    claves = []
    externo = True
    celda = None

    def __init__(self):
        self.panel = paneles.Panel(self.id, self.nombre, [], palabras="advanced, mint, cinnamon, all settings",
                                   icono_tema="cs-general")

    def lanzar(self):
        subprocess.Popen(["cinnamon-settings"], start_new_session=True)

    def coincide(self, texto):
        t = texto.lower().strip()
        return bool(t) and any(t in c.lower() for c in (self.nombre, self.panel.palabras, self.id))


class PanelVivo:
    """Un panel con los módulos que de verdad están en esta máquina."""

    def __init__(self, panel, claves, motor):
        self.panel = panel
        self.claves = claves
        self.motor = motor

    @property
    def id(self):
        return self.panel.id

    @property
    def nombre(self):
        return self.panel.nombre

    @property
    def externo(self):
        return all(self.motor.paginas[k].is_standalone for k in self.claves)

    def nombre_pestana(self, clave):
        return self.panel.pestanas.get(clave) or self.motor.paginas[clave].name

    def coincide(self, texto):
        t = texto.lower().strip()
        if not t:
            return False
        campos = [self.nombre, self.panel.palabras, self.id]
        for k in self.claves:
            sp = self.motor.paginas[k]
            campos += [sp.name, sp.keywords or "", k]
        return any(t in c.lower() for c in campos)


def pixbuf_icono(ident, icono_tema, lado):
    ruta = os.path.join(APPS, "iconos", ident + ".png")
    try:
        if os.path.exists(ruta):
            return GdkPixbuf.Pixbuf.new_from_file_at_size(ruta, lado, lado)
    except GLib.Error:
        pass
    tema = Gtk.IconTheme.get_default()
    for nombre in (icono_tema, "preferences-system"):
        try:
            # FORCE_SIZE: que todos midan lo mismo, aunque el tema no tenga ese tamaño.
            return tema.load_icon(nombre, lado, Gtk.IconLookupFlags.FORCE_SIZE)
        except GLib.Error:
            continue
    return None


def imagen_icono(ident, icono_tema, lado):
    img = Gtk.Image()
    pb = pixbuf_icono(ident, icono_tema, lado)
    if pb is not None:
        img.set_from_pixbuf(pb)
    img.set_size_request(lado, lado)
    return img


def glifo(nombre, respaldo, color=(1.0, 1.0, 1.0, 0.85)):
    """Un glifo de la barra de herramientas de Apple, pintado del color dado.
    Salen en negro de la Mac (settings/desde-mac.sh): aquí se usan como máscara.
    Sin ellos se usa el ícono simbólico del tema."""
    escala = Gdk.Screen.get_default().get_monitor_scale_factor(0) if hasattr(
        Gdk.Screen.get_default(), "get_monitor_scale_factor") else 1
    escala = 2 if escala >= 2 else 1
    ruta = os.path.join(APPS, "glifos", f"{nombre}@{escala}x.png")
    try:
        pb = GdkPixbuf.Pixbuf.new_from_file(ruta)
    except GLib.Error:
        return Gtk.Image.new_from_icon_name(respaldo, Gtk.IconSize.MENU)
    ancho, alto = pb.get_width(), pb.get_height()
    mascara = cairo.ImageSurface(cairo.FORMAT_ARGB32, ancho, alto)
    cr = cairo.Context(mascara)
    Gdk.cairo_set_source_pixbuf(cr, pb, 0, 0)
    cr.paint()
    pintado = cairo.ImageSurface(cairo.FORMAT_ARGB32, ancho, alto)
    cr = cairo.Context(pintado)
    cr.set_source_rgba(*color)
    cr.mask_surface(mascara, 0, 0)
    pintado.set_device_scale(escala, escala)
    return Gtk.Image.new_from_surface(pintado)


class Ventana(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title=TITULO)
        self.set_default_size(ANCHO, 540)
        self.set_icon_name("preferences-system")
        self.get_style_context().add_class("mp-ventana")
        self.historial, self.pos = [], -1
        self.actual = None            # PanelVivo abierto, o None en la cuadrícula
        self.claves_pestana = {}
        self.modulo_actual = None

        proveedor = Gtk.CssProvider()
        proveedor.load_from_path(os.path.join(AQUI, "estilo", "catalina.css"))
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(), proveedor, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

        raiz = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.add(raiz)
        raiz.pack_start(self._barra(), False, False, 0)

        self.pila = Gtk.Stack()
        self.pila.set_transition_type(Gtk.StackTransitionType.CROSSFADE)
        self.pila.set_transition_duration(120)
        raiz.pack_start(self.pila, True, True, 0)

        # La caja donde los módulos de Cinnamon ponen su página.
        self.content_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.content_box.get_style_context().add_class("mp-contenido")
        traza("ventana lista, cargando módulos")
        self.motor = Motor(self.content_box)
        self.motor.poner_padre(self)
        traza("módulos cargados")
        self.grupos = armar_paneles(self.motor)
        self.todos = [p for _, ps in self.grupos for p in ps]
        traza("paneles armados")

        self.pila.add_named(self._cuadricula(), "cuadricula")
        traza("cuadrícula armada")
        self.pila.add_named(self._pagina(), "pagina")
        self.connect("key-press-event", self._tecla)
        self.connect("button-press-event", self._boton)
        self.show_all()
        traza("show_all")
        self.mostrar_todo(registrar=False)
        traza("lista")

    # ── barra de herramientas ────────────────────────────────────────────
    def _barra(self):
        barra = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        barra.get_style_context().add_class("mp-barra")

        flechas = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        flechas.get_style_context().add_class("linked")
        self.b_atras, self.b_adelante, self.b_todo = Gtk.Button(), Gtk.Button(), Gtk.Button()
        self.i_atras = glifo("GoBack", "go-previous-symbolic")
        self.i_adelante = glifo("GoForward", "go-next-symbolic")
        self.b_atras.add(self.i_atras)
        self.b_adelante.add(self.i_adelante)
        self.b_atras.set_tooltip_text("Back")
        self.b_adelante.set_tooltip_text("Forward")
        self.b_atras.connect("clicked", lambda *_: self.ir(-1))
        self.b_adelante.connect("clicked", lambda *_: self.ir(1))
        flechas.pack_start(self.b_atras, False, False, 0)
        flechas.pack_start(self.b_adelante, False, False, 0)
        barra.pack_start(flechas, False, False, 0)

        self.b_todo.add(glifo("ToolbarTopSites", "view-grid-symbolic"))
        self.b_todo.set_tooltip_text("Show All")
        self.b_todo.connect("clicked", lambda *_: self.mostrar_todo())
        barra.pack_start(self.b_todo, False, False, 0)

        barra.pack_start(Gtk.Box(), True, True, 0)   # el título va en el marco de la ventana

        self.buscar = Gtk.SearchEntry()
        self.buscar.set_placeholder_text("Search")
        self.buscar.set_width_chars(22)
        self.buscar.connect("search-changed", self._buscando)
        self.buscar.connect("activate", self._buscar_enter)
        barra.pack_end(self.buscar, False, False, 0)

        self.resultados = Gtk.Popover.new(self.buscar)
        self.resultados.set_modal(False)
        self.resultados.set_position(Gtk.PositionType.BOTTOM)
        self.lista = Gtk.ListBox()
        self.lista.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self.lista.connect("row-activated", lambda lb, fila: self._abrir_desde_busqueda(fila))
        self.resultados.add(self.lista)
        self._actualizar_flechas()
        return barra

    # ── la cuadrícula ────────────────────────────────────────────────────
    def _cuadricula(self):
        caja = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        caja.get_style_context().add_class("mp-cuadricula")
        caja.pack_start(self._banner(), False, False, 0)
        for _gid, lista in self.grupos:
            raya = Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL)
            raya.get_style_context().add_class("mp-raya")
            caja.pack_start(raya, False, False, 0)
            fila = Gtk.Grid()
            fila.set_column_homogeneous(True)
            fila.set_halign(Gtk.Align.START)
            fila.get_style_context().add_class("mp-grupo")
            for i, pv in enumerate(lista):
                fila.attach(self._celda(pv), i % COLUMNAS, i // COLUMNAS, 1, 1)
            # Las columnas que sobran se rellenan para que las filas cortas queden
            # a la izquierda, con las celdas del mismo ancho que las de arriba.
            for i in range(len(lista), COLUMNAS if len(lista) < COLUMNAS else len(lista)):
                hueco = Gtk.Box()
                hueco.set_size_request(80, 1)
                fila.attach(hueco, i % COLUMNAS, i // COLUMNAS, 1, 1)
            caja.pack_start(fila, False, False, 0)
        sw = Gtk.ScrolledWindow()
        sw.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        sw.set_shadow_type(Gtk.ShadowType.NONE)
        sw.add(caja)
        self.cuadricula = caja
        return sw

    def _banner(self):
        """La franja de arriba: el Apple ID, como en Catalina. Sin sesión, «Sign in
        to your Apple ID» con su botón; con sesión, el nombre, el Apple ID y los
        botones de Mail & Calendar y Sign Out."""
        self.banner = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        self.banner.get_style_context().add_class("mp-banner")
        self._pintar_banner(None)
        GLib.idle_add(self._leer_apple_id)
        return self.banner

    def _leer_apple_id(self):
        """rclone tarda en contestar: se pregunta aparte y la franja se rehace."""
        import threading

        def corre():
            try:
                actual = apple_id.apple_id_actual()
            except Exception:  # noqa: BLE001
                actual = None
            GLib.idle_add(self._pintar_banner, actual)
        threading.Thread(target=corre, daemon=True).start()
        return False

    def _pintar_banner(self, actual):
        self._apple_id_conocido = actual
        for c in self.banner.get_children():
            self.banner.remove(c)
        self.banner.pack_start(self._avatar(48), False, False, 0)
        textos = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        if actual:
            t1, t2 = GLib.get_real_name() or GLib.get_user_name(), actual
        else:
            t1, t2 = "Sign in to your Apple ID", "Set up iCloud, the App Store, and more."
        nombre = Gtk.Label(label=t1, xalign=0)
        nombre.get_style_context().add_class("mp-nombre")
        sub = Gtk.Label(label=t2, xalign=0)
        sub.get_style_context().add_class("mp-subtitulo")
        textos.pack_start(nombre, False, False, 0)
        textos.pack_start(sub, False, False, 0)
        self.banner.pack_start(textos, True, True, 0)
        if actual:
            for etiqueta, accion in (("Mail & Calendar…", lambda *_: self._hoja_apple_id("mail")),
                                     ("Sign Out", lambda *_: self._cerrar_sesion_apple_id())):
                b = Gtk.Button(label=etiqueta)
                b.set_valign(Gtk.Align.CENTER)
                b.connect("clicked", accion)
                self.banner.pack_start(b, False, False, 0)
        else:
            b = Gtk.Button(label="Sign In")
            b.set_valign(Gtk.Align.CENTER)
            b.connect("clicked", lambda *_: self._hoja_apple_id())
            self.banner.pack_start(b, False, False, 0)
        self.banner.show_all()
        return False

    def _hoja_apple_id(self, paso=None):
        hoja = apple_id.HojaAppleID(self, al_terminar=self._leer_apple_id)
        if paso == "mail":
            hoja.apple_id = self._apple_id_conocido or ""
            hoja._paso_mail()
        hoja.show_all()

    def _cerrar_sesion_apple_id(self):
        d = Gtk.MessageDialog(transient_for=self, modal=True, message_type=Gtk.MessageType.QUESTION,
                              buttons=Gtk.ButtonsType.NONE, text="Sign out of your Apple ID?")
        d.format_secondary_text("iCloud Drive is unmounted and its session removed. Mail and Calendar settings "
                                "added to Thunderbird are removed too. Your files in iCloud are not touched.")
        d.add_button("Cancel", Gtk.ResponseType.CANCEL)
        d.add_button("Sign Out", Gtk.ResponseType.OK)
        if d.run() == Gtk.ResponseType.OK:
            apple_id.cerrar_sesion()
            self._leer_apple_id()
        d.destroy()

    def _avatar(self, lado):
        area = Gtk.DrawingArea()
        area.set_size_request(lado, lado)
        pb = None
        for ruta in (os.path.expanduser("~/.face"),
                     f"/var/lib/AccountsService/icons/{GLib.get_user_name()}"):
            try:
                if os.path.exists(ruta):
                    pb = GdkPixbuf.Pixbuf.new_from_file_at_scale(ruta, lado, lado, False)
                    break
            except GLib.Error:
                continue
        if pb is None:
            pb = pixbuf_icono("", "avatar-default", lado)

        def pintar(w, cr):
            import math
            cr.arc(lado / 2, lado / 2, lado / 2, 0, 2 * math.pi)
            cr.clip()
            if pb is not None:
                Gdk.cairo_set_source_pixbuf(cr, pb, 0, 0)
                cr.paint()
            else:
                cr.set_source_rgb(0.5, 0.5, 0.52)
                cr.paint()
            return False

        area.connect("draw", pintar)
        return area

    def _celda(self, pv):
        boton = Gtk.Button()
        boton.set_relief(Gtk.ReliefStyle.NONE)
        boton.get_style_context().add_class("mp-celda")
        caja = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        caja.pack_start(imagen_icono(pv.id, pv.panel.icono_tema, ICONO), False, False, 0)
        et = Gtk.Label(label=pv.nombre)
        et.set_line_wrap(True)
        et.set_justify(Gtk.Justification.CENTER)
        et.set_max_width_chars(10)
        et.set_lines(3)
        caja.pack_start(et, False, False, 0)
        boton.add(caja)
        boton.set_size_request(80, -1)
        boton.connect("clicked", lambda *_: self.abrir(pv))
        pv.celda = boton
        return boton

    # ── la página de un panel ────────────────────────────────────────────
    def _pagina(self):
        caja = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.fila_pestanas = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        self.fila_pestanas.set_halign(Gtk.Align.CENTER)
        self.fila_pestanas.get_style_context().add_class("mp-fila-pestanas")
        caja.pack_start(self.fila_pestanas, False, False, 0)
        self.sub_pestanas = Gtk.StackSwitcher()
        self.sub_pestanas.set_halign(Gtk.Align.CENTER)
        self.sub_pestanas.get_style_context().add_class("mp-pestanas")
        caja.pack_start(self.sub_pestanas, False, False, 0)
        sw = Gtk.ScrolledWindow()
        sw.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        sw.add(self.content_box)
        sw.set_vexpand(True)
        self.sw_contenido = sw
        caja.pack_start(sw, True, True, 0)
        return caja

    def _pestanas_modulos(self, pv):
        for hijo in self.fila_pestanas.get_children():
            self.fila_pestanas.remove(hijo)
        if len(pv.claves) < 2:
            self.fila_pestanas.hide()
            return
        self.fila_pestanas.get_style_context().add_class("linked")
        self.fila_pestanas.show()
        grupo = None
        self.botones_pestana = {}
        for clave in pv.claves:
            b = Gtk.RadioButton.new_with_label_from_widget(grupo, pv.nombre_pestana(clave))
            b.set_mode(False)
            b.get_style_context().add_class("mp-pestana")
            grupo = grupo or b
            b.connect("toggled", self._pestana_activada, pv, clave)
            self.botones_pestana[clave] = b
            self.fila_pestanas.pack_start(b, False, False, 0)
        self.fila_pestanas.show_all()

    def _pestana_activada(self, boton, pv, clave):
        if boton.get_active() and self.actual is pv:
            self._mostrar_modulo(pv, clave)

    def _salir_modulo(self):
        """Los módulos de Cinnamon limpian lo suyo al salir (restauran las
        pestañas, paran lo que escuchaban…), como hace cinnamon-settings."""
        sp = self.modulo_actual
        self.modulo_actual = None
        modulo = getattr(sp, "module", None) if sp is not None else None
        if modulo is not None and hasattr(modulo, "on_navigate_out_of_module"):
            try:
                modulo.on_navigate_out_of_module()
            except Exception:
                traceback.print_exc()

    def _mostrar_modulo(self, pv, clave):
        self._salir_modulo()
        sp = self.motor.paginas[clave]
        self.modulo_actual = sp
        sp.build()
        stack = sp.stack
        if stack is not None and len(stack.get_children()) > 1:
            self.sub_pestanas.set_stack(stack)
            self.sub_pestanas.show()
            interna = pv.panel.abre.get(clave)
            tabs = self.motor.cs.TABS.get(clave, {})
            hijos = stack.get_children()
            if interna in tabs and tabs[interna] < len(hijos):
                stack.set_visible_child(hijos[tabs[interna]])
        else:
            self.sub_pestanas.set_stack(None)
            self.sub_pestanas.hide()
        self.content_box.show_all()
        GLib.idle_add(self._ajustar_alto)

    def _ajustar_alto(self):
        _min, nat = self.content_box.get_preferred_height()
        barra = self.fila_pestanas.get_preferred_height()[1] + self.sub_pestanas.get_preferred_height()[1]
        pantalla = Gdk.Screen.get_default().get_height()
        alto = max(MIN_PAGINA, min(nat + barra + 90, int(pantalla * 0.85)))
        ancho = max(ANCHO, min(self.content_box.get_preferred_width()[1] + 40, 1000))
        self.resize(ancho, alto)
        return False

    # ── navegación ───────────────────────────────────────────────────────
    def abrir(self, pv, registrar=True):
        if isinstance(pv, PanelAvanzado):
            pv.lanzar()
            return
        if pv.externo:
            # Un programa externo: se lanza y la ventana se queda donde estaba.
            self.motor.paginas[pv.claves[0]].build()
            return
        self.actual = pv
        self.set_title(pv.nombre)
        self.pila.set_visible_child_name("pagina")
        self._pestanas_modulos(pv)
        self._mostrar_modulo(pv, pv.claves[0])
        if registrar:
            self._registrar(pv.id)

    def abrir_id(self, ident):
        for pv in self.todos:
            if pv.id == ident:
                self.abrir(pv)
                return True
        return False

    def abrir_por_nombre(self, texto):
        """Un panel por su nombre de Catalina, su identificador o el de Cinnamon."""
        t = texto.lower().strip()
        for pv in self.todos:
            if t in (pv.id.lower(), pv.nombre.lower(), pv.id.split(".")[-1].lower()) or t in pv.claves:
                self.abrir(pv)
                return True
        destino = paneles.ALIAS.get(t)
        if destino:
            for pv in self.todos:
                if pv.id.split(".")[-1].lower() == destino:
                    self.abrir(pv)
                    return True
        return False

    def mostrar_todo(self, registrar=True):
        self._salir_modulo()
        self.actual = None
        self.set_title(TITULO)
        self.pila.set_visible_child_name("cuadricula")
        for hijo in self.content_box.get_children():
            hijo.hide()
        self.buscar.set_text("")
        _min, nat = self.cuadricula.get_preferred_height()
        tope = int(Gdk.Screen.get_default().get_height() * 0.85)
        self.resize(ANCHO, max(MIN_ALTO, min(nat + 60, tope)))
        if registrar:
            self._registrar(None)

    def _registrar(self, ident):
        del self.historial[self.pos + 1:]
        if not self.historial or self.historial[-1] != ident:
            self.historial.append(ident)
        self.pos = len(self.historial) - 1
        self._actualizar_flechas()

    def ir(self, paso):
        nuevo = self.pos + paso
        if not 0 <= nuevo < len(self.historial):
            return
        self.pos = nuevo
        ident = self.historial[nuevo]
        if ident is None:
            self.mostrar_todo(registrar=False)
        else:
            for pv in self.todos:
                if pv.id == ident:
                    self.abrir(pv, registrar=False)
        self._actualizar_flechas()

    def _actualizar_flechas(self):
        hay_atras = self.pos > 0
        hay_adelante = self.pos < len(self.historial) - 1
        self.b_atras.set_sensitive(hay_atras)
        self.b_adelante.set_sensitive(hay_adelante)
        # Un glifo pintado no se atenúa solo cuando el botón se desactiva.
        self.i_atras.set_opacity(1.0 if hay_atras else 0.35)
        self.i_adelante.set_opacity(1.0 if hay_adelante else 0.35)

    # ── búsqueda ─────────────────────────────────────────────────────────
    def _buscando(self, entrada):
        texto = entrada.get_text()
        for fila in self.lista.get_children():
            self.lista.remove(fila)
        if not texto.strip():
            self.resultados.popdown()
            return
        hallados = [pv for pv in self.todos if pv.coincide(texto)]
        for pv in hallados[:12]:
            fila = Gtk.ListBoxRow()
            fila.pv = pv
            caja = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
            caja.pack_start(imagen_icono(pv.id, pv.panel.icono_tema, 20), False, False, 0)
            caja.pack_start(Gtk.Label(label=pv.nombre, xalign=0), False, False, 0)
            caja.set_border_width(4)
            fila.add(caja)
            self.lista.add(fila)
        if hallados:
            self.lista.show_all()
            self.lista.select_row(self.lista.get_row_at_index(0))
            self.resultados.popup()
            self.buscar.grab_focus()
        else:
            fila = Gtk.ListBoxRow()
            fila.pv = None
            etiqueta = Gtk.Label(label="No results")
            etiqueta.set_border_width(8)
            fila.add(etiqueta)
            self.lista.add(fila)
            self.lista.show_all()
            self.resultados.popup()

    def _buscar_enter(self, *_):
        fila = self.lista.get_selected_row()
        if fila is not None:
            self._abrir_desde_busqueda(fila)

    def _abrir_desde_busqueda(self, fila):
        pv = getattr(fila, "pv", None)
        self.resultados.popdown()
        if pv is not None:
            self.abrir(pv)
            self.buscar.set_text("")

    # ── teclas y ratón ───────────────────────────────────────────────────
    def _tecla(self, _w, ev):
        ctrl = ev.state & Gdk.ModifierType.CONTROL_MASK
        alt = ev.state & Gdk.ModifierType.MOD1_MASK
        if ev.keyval == Gdk.KEY_Escape and self.resultados.get_visible():
            self.resultados.popdown()
            self.buscar.set_text("")
            return True
        if ctrl and ev.keyval in (Gdk.KEY_f, Gdk.KEY_F):
            self.buscar.grab_focus()
            return True
        if ctrl and ev.keyval in (Gdk.KEY_l, Gdk.KEY_L):
            self.mostrar_todo()
            return True
        if ctrl and ev.keyval in (Gdk.KEY_w, Gdk.KEY_W, Gdk.KEY_q, Gdk.KEY_Q):
            self.close()
            return True
        if alt and ev.keyval == Gdk.KEY_Left:
            self.ir(-1)
            return True
        if alt and ev.keyval == Gdk.KEY_Right:
            self.ir(1)
            return True
        if self.resultados.get_visible() and ev.keyval in (Gdk.KEY_Down, Gdk.KEY_Up):
            fila = self.lista.get_selected_row()
            i = fila.get_index() if fila else -1
            i = max(0, i + (1 if ev.keyval == Gdk.KEY_Down else -1))
            nueva = self.lista.get_row_at_index(i)
            if nueva:
                self.lista.select_row(nueva)
            return True
        return False

    def _boton(self, _w, ev):
        if ev.button == 8:       # el botón «atrás» del ratón
            self.ir(-1)
            return True
        if ev.button == 9:
            self.ir(1)
            return True
        return False


class Aplicacion(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID,
                         flags=Gio.ApplicationFlags.HANDLES_COMMAND_LINE)
        self.ventana = None

    def do_startup(self):
        Gtk.Application.do_startup(self)
        # app.abrir("sound") desde otro proceso o desde un menú.
        accion = Gio.SimpleAction.new("abrir", GLib.VariantType.new("s"))
        accion.connect("activate", lambda _a, v: self._abrir_accion(v.get_string()))
        self.add_action(accion)
        todo = Gio.SimpleAction.new("todo", None)
        todo.connect("activate", lambda *_: self.ventana and self.ventana.mostrar_todo())
        self.add_action(todo)

    def _abrir_accion(self, nombre):
        if self.ventana is None:
            return
        if nombre:
            self.ventana.abrir_por_nombre(nombre)
        self.ventana.present()

    def do_command_line(self, cl):
        traza("do_command_line")
        args = cl.get_arguments()[1:]
        if self.ventana is None:
            try:
                self.ventana = Ventana(self)
                # cs_themes y cs_gestures lo buscan en la aplicación para esconder
                # o mostrar las pestañas.
                self.stack_switcher = self.ventana.sub_pestanas
            except Exception:
                traceback.print_exc()
                # Si algo cambió en Cinnamon y el motor no carga, que el usuario
                # no se quede sin ajustes: se abre el original.
                subprocess.Popen(["cinnamon-settings"] + args)
                return 1
        if args and args[0] == "--lista":
            for pv in self.ventana.todos:
                print(f"{pv.id:46} {pv.nombre:24} {','.join(pv.claves)}")
            self.ventana.destroy()
            return 0
        if args:
            if not self.ventana.abrir_por_nombre(args[0]):
                print(f"No hay un panel «{args[0]}». Mira mac-settings --lista.", file=sys.stderr)
        self.ventana.present()
        return 0


def main():
    traza("main")
    # El WM_CLASS sale del nombre del programa: con él el Dock y el menú de la
    # barra agrupan la ventana bajo el lanzador mint-macos-settings.desktop.
    GLib.set_prgname("mac-settings")
    GLib.set_application_name(TITULO)
    return Aplicacion().run(sys.argv)


if __name__ == "__main__":
    sys.exit(main())
