"""Desktop & Screen Saver: el panel de Catalina con sus dos pestañas.

Capturas: Screen Shot 2026-10-14 at 12.12.20 AM (Desktop), 12.12.26 AM (Screen Saver),
12.12.31 AM (Screen Saver Options) y 12.12.36 AM (Hot Corners).

Desktop: la vista previa, la lista Apple ▸ Desktop Pictures / Colors y Folders, y la cuadrícula de
miniaturas. Escoger una foto escribe picture-uri de org.cinnamon.desktop.background. Las fotos y los
colores de Apple salen del disco de la Mac con `fondos.py` a ~/.local/share/mint-macos/fondos (arte de
Apple: nunca va al repo). Change picture y Random order son el slideshow de Cinnamon con la carpeta
que se escogió. El popup de Dynamic Desktop (Light / Dark / Dynamic) va en gris: Cinnamon no cambia
el fondo por la hora.
Screen Saver: Start after es idle-delay de org.cinnamon.desktop.session, Show with clock es
org.cinnamon.desktop.screensaver show-clock y Hot Corners… abre la hoja del panel Mission Control.
Los protectores de Apple (Classic, Drift, Flurry…) y Screen Saver Options… no existen aquí: se dibujan
como en la captura, en gris.
Las opciones de los popups Start after y Change picture, salvo «20 Minutes» y «Every 30 minutes», no
tienen captura.
"""
import json
import os

import gi
gi.require_version("Gtk", "3.0")
gi.require_version("GdkPixbuf", "2.0")
from gi.repository import Gio, GdkPixbuf, GLib, Gtk  # noqa: E402

import paneles  # noqa: E402

FONDOS = os.path.expanduser("~/.local/share/mint-macos/fondos")
CARPETAS = os.path.expanduser("~/.config/mint-macos/fondos-carpetas.json")
BG = "org.cinnamon.desktop.background"
INTERVALOS = [(1, "Every minute"), (5, "Every 5 minutes"), (15, "Every 15 minutes"),
              (30, "Every 30 minutes"), (60, "Every hour")]
INACTIVIDAD = [(60, "1 Minute"), (120, "2 Minutes"), (300, "5 Minutes"), (600, "10 Minutes"),
               (1200, "20 Minutes"), (1800, "30 Minutes"), (3600, "1 Hour"), (0, "Never")]
PROTECTORES = ["Classic", "Drift", "Flurry", "Arabesque", "Shell"]      # los que se ven en la captura


def _gris(widget, motivo="Not available on this computer."):
    widget.set_sensitive(False)
    widget.set_tooltip_text(motivo)
    return widget


def _marco():
    m = Gtk.Frame()
    m.get_style_context().add_class("mp-sd-lista")
    return m


def _carpetas():
    try:
        return [c for c in json.load(open(CARPETAS, encoding="utf-8")) if isinstance(c, str)]
    except (OSError, ValueError):
        return []


class PanelDesktopScreenSaver:
    id = "com.apple.preference.desktopscreeneffect"
    nombre = "Desktop & Screen Saver"
    claves = []
    externo = False
    propio = True
    celda = None
    PRUEBA = bool(os.environ.get("MINT_ESCRITORIO_PRUEBA"))     # no cambia el fondo ni la configuración

    def __init__(self):
        self.panel = paneles.Panel(self.id, self.nombre, [],
                                   palabras="desktop, wallpaper, background, screen saver, screensaver, picture, "
                                            "start after, clock, hot corners")
        self.ventana = None
        self._cargando = False

    def coincide(self, texto):
        t = texto.lower().strip()
        return bool(t) and any(t in c.lower() for c in (self.nombre, self.panel.palabras, self.id))

    # ── la página ────────────────────────────────────────────────────────
    def construir(self):
        self._cargando = True
        self._bg = Gio.Settings.new(BG)
        self._cfg_dia = Gio.Settings.new("org.cinnamon.desktop.background.slideshow")
        caja = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        caja.get_style_context().add_class("mp-propio")
        caja.set_margin_top(12)
        stack = Gtk.Stack()
        stack.add_titled(self._pagina_escritorio(), "desktop", "Desktop")
        stack.add_titled(self._pagina_protector(), "screensaver", "Screen Saver")
        pestanas = Gtk.StackSwitcher()
        pestanas.set_stack(stack)
        pestanas.set_halign(Gtk.Align.CENTER)
        pestanas.get_style_context().add_class("mp-pestanas")
        caja.pack_start(pestanas, False, False, 0)
        marco = _marco()
        marco.add(stack)
        caja.pack_start(marco, True, True, 0)
        caja.show_all()
        pedida = os.environ.get("MINT_ESCRITORIO_PESTANA")        # solo para las pruebas visuales
        if pedida:
            stack.set_visible_child_name(pedida)
        self._cargando = False
        return caja

    # ── Desktop ──────────────────────────────────────────────────────────
    def _pagina_escritorio(self):
        pagina = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        pagina.set_margin_top(14)
        pagina.set_margin_start(18)
        pagina.set_margin_end(18)
        pagina.set_margin_bottom(14)

        arriba = Gtk.Box(spacing=18)
        self._vista = Gtk.Image()
        marco_v = _marco()
        marco_v.add(self._vista)
        arriba.pack_start(marco_v, False, False, 0)
        der = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        self._nombre = Gtk.Label(xalign=0)
        der.pack_start(self._nombre, False, False, 4)
        din = Gtk.ComboBoxText()
        din.append("d", "Dark (Still)")
        din.set_active(0)
        der.pack_start(_gris(din, "The desktop does not change with the time of day on this computer."),
                       False, False, 0)
        arriba.pack_start(der, False, False, 0)
        pagina.pack_start(arriba, False, False, 0)

        medio = Gtk.Box(spacing=0)
        self._arbol = Gtk.TreeStore(str, str, str)       # texto, tipo, dato
        apple = self._arbol.append(None, ["Apple", "grupo", ""])
        self._arbol.append(apple, ["Desktop Pictures", "fotos", ""])
        self._arbol.append(apple, ["Colors", "colores", ""])
        carpetas = self._arbol.append(None, ["Folders", "grupo", ""])
        pics = os.path.expanduser("~/Pictures")
        self._arbol.append(carpetas, ["Pictures", "carpeta", pics])
        for c in _carpetas():
            self._arbol.append(carpetas, [os.path.basename(c.rstrip("/")) or c, "carpeta", c])
        self._lateral = Gtk.TreeView(model=self._arbol)
        self._lateral.set_headers_visible(False)
        self._lateral.append_column(Gtk.TreeViewColumn("", Gtk.CellRendererText(), text=0))
        self._lateral.expand_all()
        self._lateral.get_selection().connect("changed", lambda s: self._fuente(s))
        pl = Gtk.ScrolledWindow()
        pl.set_size_request(170, 230)
        pl.add(self._lateral)
        ml = _marco()
        ml.add(pl)
        medio.pack_start(ml, False, False, 0)
        self._rejilla = Gtk.FlowBox()
        self._rejilla.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self._rejilla.set_max_children_per_line(4)
        self._rejilla.set_homogeneous(True)
        self._rejilla.connect("child-activated", lambda _r, h: self._escoger(h))
        pr = Gtk.ScrolledWindow()
        pr.add(self._rejilla)
        mr = _marco()
        mr.add(pr)
        medio.pack_start(mr, True, True, 0)
        pagina.pack_start(medio, True, True, 0)

        pie = Gtk.Grid(column_spacing=10, row_spacing=6)
        botones = Gtk.Box()
        botones.get_style_context().add_class("linked")
        mas = Gtk.Button(label="+")
        mas.connect("clicked", lambda _b: self._agregar_carpeta())
        menos = Gtk.Button(label="−")
        menos.connect("clicked", lambda _b: self._quitar_carpeta())
        botones.pack_start(mas, False, False, 0)
        botones.pack_start(menos, False, False, 0)
        pie.attach(botones, 0, 0, 1, 2)
        self._cambiar = Gtk.CheckButton(label="Change picture:")
        self._intervalo = Gtk.ComboBoxText()
        for m, n in INTERVALOS:
            self._intervalo.append(str(m), n)
        self._intervalo.set_active_id(str(self._cfg_dia.get_int("delay")) if str(self._cfg_dia.get_int("delay"))
                                      in [str(m) for m, _n in INTERVALOS] else "30")
        self._azar = Gtk.CheckButton(label="Random order")
        self._cambiar.set_active(self._cfg_dia.get_boolean("slideshow-enabled"))
        self._azar.set_active(self._cfg_dia.get_boolean("random-order"))
        pie.attach(self._cambiar, 1, 0, 1, 1)
        pie.attach(self._intervalo, 2, 0, 1, 1)
        pie.attach(self._azar, 1, 1, 2, 1)
        for w in (self._cambiar, self._azar):
            w.connect("toggled", lambda _w: self._slideshow())
        self._intervalo.connect("changed", lambda _c: self._slideshow())
        pagina.pack_start(pie, False, False, 0)

        self._fuente_actual = None
        self._mostrar_actual()
        self._lateral.get_selection().select_path(Gtk.TreePath("0:0"))
        return pagina

    def _mostrar_actual(self):
        uri = self._bg.get_string("picture-uri")
        ruta = Gio.File.new_for_uri(uri).get_path() if uri else None
        try:
            self._vista.set_from_pixbuf(GdkPixbuf.Pixbuf.new_from_file_at_scale(ruta, 118, 74, False))
        except (GLib.Error, TypeError):
            self._vista.clear()
        nombre = os.path.splitext(os.path.basename(ruta))[0] if ruta else ""
        self._nombre.set_text(nombre.replace("-", " ").title())

    def _fuente(self, sel):
        modelo, it = sel.get_selected()
        if it is None or modelo[it][1] == "grupo":
            return
        for h in self._rejilla.get_children():
            self._rejilla.remove(h)
        tipo, dato = modelo[it][1], modelo[it][2]
        self._fuente_actual = (tipo, dato)
        elementos = []                       # [(rótulo, ruta de la imagen, ruta de la miniatura)]
        if tipo == "fotos":
            try:
                orden = json.load(open(os.path.join(FONDOS, "orden.json"), encoding="utf-8"))["fotos"]
            except (OSError, ValueError, KeyError):
                orden = []
            for n in orden:
                elementos.append((n, os.path.join(FONDOS, "fotos", n + ".jpg"),
                                  os.path.join(FONDOS, "miniaturas", n + ".jpg")))
        elif tipo == "colores":
            colores = os.path.join(FONDOS, "colores")
            for f in sorted(os.listdir(colores)) if os.path.isdir(colores) else []:
                elementos.append((os.path.splitext(f)[0], os.path.join(colores, f), os.path.join(colores, f)))
        else:
            try:
                archivos = sorted(f for f in os.listdir(dato) if f.lower().endswith((".jpg", ".jpeg", ".png")))
            except OSError:
                archivos = []
            for f in archivos[:80]:
                elementos.append((f, os.path.join(dato, f), os.path.join(dato, f)))
        for rotulo, ruta, mini in elementos:
            try:
                pb = GdkPixbuf.Pixbuf.new_from_file_at_scale(mini, 96, 60, True)
            except GLib.Error:
                continue
            h = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2, margin=4)
            h.pack_start(Gtk.Image.new_from_pixbuf(pb), False, False, 0)
            hijo = Gtk.FlowBoxChild()
            hijo.add(h)
            hijo.ruta = ruta
            hijo.set_tooltip_text(rotulo)
            self._rejilla.add(hijo)
        self._rejilla.show_all()

    def _escoger(self, hijo):
        if self._cargando or self.PRUEBA:
            return
        self._bg.set_string("picture-uri", Gio.File.new_for_path(hijo.ruta).get_uri())
        self._bg.set_string("picture-options", "zoom")
        self._mostrar_actual()

    def _slideshow(self):
        """Change picture / Random order: el slideshow de Cinnamon sobre la carpeta escogida."""
        if self._cargando or self.PRUEBA:
            return
        fuente = self._fuente_actual
        if self._cambiar.get_active() and fuente:
            tipo, dato = fuente
            carpeta = os.path.join(FONDOS, "fotos") if tipo == "fotos" else (dato if tipo == "carpeta" else None)
            if carpeta and os.path.isdir(carpeta):
                self._cfg_dia.set_string("image-source", Gio.File.new_for_path(carpeta).get_uri()
                                         .replace("file://", "directory://", 1))
        self._cfg_dia.set_int("delay", int(self._intervalo.get_active_id() or 30))
        self._cfg_dia.set_boolean("random-order", self._azar.get_active())
        self._cfg_dia.set_boolean("slideshow-enabled", self._cambiar.get_active())

    def _agregar_carpeta(self):
        d = Gtk.FileChooserDialog(title="Choose a folder", transient_for=self.ventana,
                                  action=Gtk.FileChooserAction.SELECT_FOLDER)
        d.add_button("Cancel", Gtk.ResponseType.CANCEL)
        d.add_button("Choose", Gtk.ResponseType.OK)
        if d.run() == Gtk.ResponseType.OK:
            ruta = d.get_filename()
            lista = _carpetas()
            if ruta not in lista and not self.PRUEBA:
                lista.append(ruta)
                os.makedirs(os.path.dirname(CARPETAS), exist_ok=True)
                json.dump(lista, open(CARPETAS, "w", encoding="utf-8"))
                it = self._arbol.get_iter(Gtk.TreePath("1"))
                self._arbol.append(it, [os.path.basename(ruta.rstrip("/")) or ruta, "carpeta", ruta])
                self._lateral.expand_all()
        d.destroy()

    def _quitar_carpeta(self):
        modelo, it = self._lateral.get_selection().get_selected()
        if it is None or modelo[it][1] != "carpeta" or modelo[it][2] == os.path.expanduser("~/Pictures"):
            return
        ruta = modelo[it][2]
        if not self.PRUEBA:
            json.dump([c for c in _carpetas() if c != ruta], open(CARPETAS, "w", encoding="utf-8"))
        modelo.remove(it)

    # ── Screen Saver ─────────────────────────────────────────────────────
    def _pagina_protector(self):
        pagina = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        pagina.set_margin_top(14)
        pagina.set_margin_start(18)
        pagina.set_margin_end(18)
        pagina.set_margin_bottom(14)
        cuerpo = Gtk.Box(spacing=0)
        lista = Gtk.ListBox()
        lista.set_size_request(200, 230)
        for n in PROTECTORES:
            fila = Gtk.ListBoxRow()
            fila.add(Gtk.Label(label=n, margin=14))
            lista.add(fila)
        ml = _marco()
        ml.add(_gris(lista, "Apple’s screen savers are not available on this computer."))
        cuerpo.pack_start(ml, False, False, 0)
        vista = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
        vista.set_halign(Gtk.Align.CENTER)
        vista.set_valign(Gtk.Align.CENTER)
        vista.pack_start(_gris(Gtk.Button(label="Screen Saver Options…")), False, False, 0)
        mv = _marco()
        mv.add(vista)
        cuerpo.pack_start(mv, True, True, 8)
        pagina.pack_start(cuerpo, True, True, 0)

        pie = Gtk.Grid(column_spacing=10, row_spacing=6)
        pie.attach(Gtk.Label(label="Start after:", xalign=1.0), 0, 0, 1, 1)
        sesion = Gio.Settings.new("org.cinnamon.desktop.session")
        self._inactividad = Gtk.ComboBoxText()
        for s, n in INACTIVIDAD:
            self._inactividad.append(str(s), n)
        actual = sesion.get_uint("idle-delay") if "idle-delay" in sesion.list_keys() else 0
        if not self._inactividad.set_active_id(str(actual)):
            self._inactividad.append(str(actual), "%d Minutes" % (actual // 60))
            self._inactividad.set_active_id(str(actual))
        self._inactividad.connect("changed", lambda c: (not self._cargando and not self.PRUEBA)
                                  and sesion.set_uint("idle-delay", int(c.get_active_id())))
        pie.attach(self._inactividad, 1, 0, 1, 1)
        salvapantallas = Gio.Settings.new("org.cinnamon.desktop.screensaver")
        reloj = Gtk.CheckButton(label="Show with clock")
        reloj.set_active(salvapantallas.get_boolean("show-clock"))
        reloj.connect("toggled", lambda b: (not self._cargando and not self.PRUEBA)
                      and salvapantallas.set_boolean("show-clock", b.get_active()))
        pie.attach(reloj, 2, 0, 1, 1)
        pie.attach(_gris(Gtk.CheckButton(label="Use random screen saver")), 2, 1, 1, 1)
        esquinas = Gtk.Button(label="Hot Corners…")
        esquinas.connect("clicked", lambda _b: self._esquinas())
        pie.attach(esquinas, 3, 0, 1, 1)
        pagina.pack_start(pie, False, False, 0)
        return pagina

    def _esquinas(self):
        import propios
        mc = propios.PROPIOS.get("com.apple.preference.expose")
        if mc is not None:
            mc.ventana = self.ventana
            mc._hoja()
