"""Users & Groups: el panel de Catalina (Screen Shot 2026-10-14 at 12.15.36 AM Password, 12.15.40 AM Login Items,
12.15.45 AM Login Options).

Password: la foto (~/.face), el nombre completo (GECOS de /etc/passwd) y Change Password…, que abre el
módulo de usuario de Cinnamon (la clave se cambia con polkit allí). Login Items: las apps de
~/.config/autostart (menos las de mint-macos, que son piezas del propio sistema); + añade una app y − quita
la entrada (la aparta a ~/.local/share/mint-macos/respaldos/autostart-quitados, no la borra). Guest User, Groups, Login Options (todas las opciones), el candado y la casilla Hide no
tienen equivalente de usuario aquí: se dibujan como en las capturas, en gris.
No hay captura con el candado abierto ni de Change Password…, la hoja + o los grupos.
"""
import configparser
import glob
import grp
import os
import pwd
import shutil
import subprocess

import gi
gi.require_version("Gtk", "3.0")
gi.require_version("GdkPixbuf", "2.0")
from gi.repository import Gio, GdkPixbuf, GLib, Gtk  # noqa: E402

import paneles  # noqa: E402

AUTOARRANQUE = os.path.expanduser("~/.config/autostart")


def _gris(widget, motivo="Not available on this computer."):
    widget.set_sensitive(False)
    widget.set_tooltip_text(motivo)
    return widget


def _marco():
    m = Gtk.Frame()
    m.get_style_context().add_class("mp-sd-lista")
    return m


def _usuario():
    p = pwd.getpwuid(os.getuid())
    nombre = p.pw_gecos.split(",")[0] or p.pw_name
    try:
        admin = p.pw_name in grp.getgrnam("sudo").gr_mem or p.pw_name in grp.getgrnam("admin").gr_mem
    except KeyError:
        admin = False
    return nombre, admin


def _foto(lado):
    for ruta in (os.path.expanduser("~/.face"), os.path.expanduser("~/.face.icon")):
        try:
            return GdkPixbuf.Pixbuf.new_from_file_at_size(ruta, lado, lado)
        except GLib.Error:
            continue
    return None


def entradas_de_inicio():
    """[(nombre, ruta, tipo)] de las apps de ~/.config/autostart que se abren al entrar (sin las de mint-macos)."""
    salida = []
    for ruta in sorted(glob.glob(os.path.join(AUTOARRANQUE, "*.desktop"))):
        if os.path.basename(ruta).startswith("mint-macos"):
            continue
        c = configparser.ConfigParser(interpolation=None, strict=False)
        try:
            c.read(ruta, encoding="utf-8")
            e = c["Desktop Entry"]
        except (configparser.Error, KeyError, OSError):
            continue
        if e.get("Hidden", "false").lower() == "true" or e.get("X-GNOME-Autostart-enabled", "true").lower() == "false":
            continue
        salida.append((e.get("Name", os.path.basename(ruta)), ruta, "Application"))
    return salida


class PanelUsers:
    id = "com.apple.preferences.users"
    nombre = "Users & Groups"
    claves = []
    externo = False
    propio = True
    celda = None
    PRUEBA = bool(os.environ.get("MINT_USUARIOS_PRUEBA"))     # no abre ni cambia nada

    def __init__(self):
        self.panel = paneles.Panel(self.id, self.nombre, [],
                                   palabras="users, groups, account, password, login items, startup, "
                                            "login options, guest")
        self.ventana = None

    def coincide(self, texto):
        t = texto.lower().strip()
        return bool(t) and any(t in c.lower() for c in (self.nombre, self.panel.palabras, self.id))

    def construir(self):
        caja = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        caja.get_style_context().add_class("mp-propio")
        for lado in ("top", "bottom", "start", "end"):
            getattr(caja, "set_margin_" + lado)(14)
        cuerpo = Gtk.Box(spacing=12)
        izq = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        marco = _marco()
        col = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        col.set_size_request(190, 300)
        nombre, admin = _usuario()
        enc = Gtk.Label(label="Current User", xalign=0, margin=6)
        enc.get_style_context().add_class("mp-sd-detalle")
        col.pack_start(enc, False, False, 0)
        actual = Gtk.Box(spacing=8, margin=6)
        pb = _foto(32)
        actual.pack_start(Gtk.Image.new_from_pixbuf(pb) if pb else Gtk.Image.new_from_icon_name(
            "avatar-default", Gtk.IconSize.DND), False, False, 0)
        v = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        v.pack_start(Gtk.Label(label=nombre, xalign=0), False, False, 0)
        r = Gtk.Label(label="Admin" if admin else "Standard", xalign=0)
        r.get_style_context().add_class("mp-sd-detalle")
        v.pack_start(r, False, False, 0)
        actual.pack_start(v, True, True, 0)
        col.pack_start(actual, False, False, 0)
        otros = Gtk.Label(label="Other Users", xalign=0, margin=6)
        otros.get_style_context().add_class("mp-sd-detalle")
        col.pack_start(otros, False, False, 0)
        invitado = Gtk.Box(spacing=8, margin=6)
        invitado.pack_start(Gtk.Image.new_from_icon_name("avatar-default", Gtk.IconSize.LARGE_TOOLBAR),
                            False, False, 0)
        iv = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        iv.pack_start(Gtk.Label(label="Guest User", xalign=0), False, False, 0)
        iv.pack_start(Gtk.Label(label="Off", xalign=0), False, False, 0)
        invitado.pack_start(iv, True, True, 0)
        col.pack_start(_gris(invitado, "The guest session is set in the login window settings."), False, False, 0)
        col.pack_start(_gris(Gtk.Label(label="Groups", xalign=0, margin=6)), False, False, 0)
        col.pack_start(Gtk.Box(), True, True, 0)
        col.pack_start(Gtk.Separator(), False, False, 0)
        opciones = Gtk.Box(spacing=8, margin=8)
        opciones.pack_start(Gtk.Image.new_from_icon_name("go-home-symbolic", Gtk.IconSize.LARGE_TOOLBAR),
                            False, False, 0)
        opciones.pack_start(Gtk.Label(label="Login Options"), False, False, 0)
        col.pack_start(_gris(opciones, "The login window options are set by the system administrator."),
                       False, False, 0)
        marco.add(col)
        izq.pack_start(marco, True, True, 0)
        botones = Gtk.Box()
        botones.get_style_context().add_class("linked")
        botones.pack_start(_gris(Gtk.Button(label="+")), False, False, 0)
        botones.pack_start(_gris(Gtk.Button(label="−")), False, False, 0)
        izq.pack_start(botones, False, False, 4)
        cuerpo.pack_start(izq, False, False, 0)

        stack = Gtk.Stack()
        stack.add_titled(self._pagina_clave(nombre), "password", "Password")
        stack.add_titled(self._pagina_inicio(), "items", "Login Items")
        pestanas = Gtk.StackSwitcher()
        pestanas.set_stack(stack)
        pestanas.set_halign(Gtk.Align.CENTER)
        pestanas.get_style_context().add_class("mp-pestanas")
        der = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        der.pack_start(pestanas, False, False, 0)
        m2 = _marco()
        m2.add(stack)
        der.pack_start(m2, True, True, 0)
        cuerpo.pack_start(der, True, True, 0)
        caja.pack_start(cuerpo, True, True, 0)
        pie = Gtk.Box(spacing=8)
        pie.pack_start(_gris(Gtk.Image.new_from_icon_name("changes-prevent-symbolic", Gtk.IconSize.LARGE_TOOLBAR),
                             "Changes to other users need the administrator password."), False, False, 0)
        pie.pack_start(Gtk.Label(label="Click the lock to make changes."), False, False, 0)
        caja.pack_start(pie, False, False, 0)
        caja.show_all()
        pedida = os.environ.get("MINT_USUARIOS_PESTANA")        # solo para las pruebas visuales
        if pedida:
            stack.set_visible_child_name(pedida)
        return caja

    # ── Password ─────────────────────────────────────────────────────────
    def _pagina_clave(self, nombre):
        pagina = Gtk.Box(spacing=14, margin=18)
        pagina.set_valign(Gtk.Align.START)
        pb = _foto(64)
        pagina.pack_start(Gtk.Image.new_from_pixbuf(pb) if pb else Gtk.Image.new_from_icon_name(
            "avatar-default", Gtk.IconSize.DIALOG), False, False, 0)
        t = Gtk.Label(label=nombre, xalign=0)
        t.get_style_context().add_class("mp-titulo-negrita")
        pagina.pack_start(t, True, True, 0)
        b = Gtk.Button(label="Change Password…")
        b.connect("clicked", lambda _b: self._cambiar_clave())
        pagina.pack_start(b, False, False, 0)
        return pagina

    def _cambiar_clave(self):
        if self.PRUEBA:
            return
        try:
            subprocess.Popen(["cinnamon-settings", "user"], start_new_session=True,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except OSError:
            pass

    # ── Login Items ──────────────────────────────────────────────────────
    def _pagina_inicio(self):
        pagina = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8, margin=16)
        pagina.pack_start(Gtk.Label(label="These items will open automatically when you log in:", xalign=0),
                          False, False, 0)
        self._items = Gtk.ListStore(str, str, str, bool)
        arbol = Gtk.TreeView(model=self._items)
        arbol.append_column(Gtk.TreeViewColumn("Item", Gtk.CellRendererText(), text=0))
        arbol.append_column(Gtk.TreeViewColumn("Kind", Gtk.CellRendererText(), text=2))
        hide = Gtk.CellRendererToggle()
        hide.set_property("activatable", False)
        arbol.append_column(Gtk.TreeViewColumn("Hide", hide, active=3))
        self._arbol = arbol
        pant = Gtk.ScrolledWindow()
        pant.set_size_request(-1, 190)
        pant.add(arbol)
        m = _marco()
        m.add(pant)
        pagina.pack_start(m, True, True, 0)
        n = Gtk.Label(label="To hide an application when you log in, select the checkbox in the Hide column "
                            "next to the application.", xalign=0)
        n.set_line_wrap(True)
        n.set_max_width_chars(60)
        n.get_style_context().add_class("mp-sd-detalle")
        pagina.pack_start(n, False, False, 0)
        botones = Gtk.Box()
        botones.get_style_context().add_class("linked")
        mas = Gtk.Button(label="+")
        mas.connect("clicked", lambda _b: self._agregar())
        menos = Gtk.Button(label="−")
        menos.connect("clicked", lambda _b: self._quitar())
        botones.pack_start(mas, False, False, 0)
        botones.pack_start(menos, False, False, 0)
        pagina.pack_start(botones, False, False, 0)
        self._recargar()
        return pagina

    def _recargar(self):
        self._items.clear()
        for nombre, ruta, tipo in entradas_de_inicio():
            self._items.append([nombre, ruta, tipo, False])

    def _agregar(self):
        d = Gtk.AppChooserDialog(transient_for=self.ventana, modal=True)
        if d.run() == Gtk.ResponseType.OK and not self.PRUEBA:
            info = d.get_app_info()
            origen = info.get_filename() if hasattr(info, "get_filename") else None
            if origen and os.path.isfile(origen):
                os.makedirs(AUTOARRANQUE, exist_ok=True)
                destino = os.path.join(AUTOARRANQUE, os.path.basename(origen))
                if not os.path.exists(destino):
                    with open(origen, encoding="utf-8") as f, open(destino, "w", encoding="utf-8") as g:
                        g.write(f.read())
        d.destroy()
        self._recargar()

    def _quitar(self):
        modelo, it = self._arbol.get_selection().get_selected()
        if it is None or self.PRUEBA:
            return
        ruta = modelo[it][1]
        if os.path.dirname(ruta) == AUTOARRANQUE:
            # No se borra: se aparta a un respaldo, para poder devolverla (Plank, Solaar y Spotlyte son de aquí).
            respaldo = os.path.expanduser("~/.local/share/mint-macos/respaldos/autostart-quitados")
            try:
                os.makedirs(respaldo, exist_ok=True)
                shutil.move(ruta, os.path.join(respaldo, os.path.basename(ruta)))
            except OSError:
                pass
        self._recargar()
