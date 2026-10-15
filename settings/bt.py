"""Bluetooth: el panel de Catalina (Screen Shot 2026-10-14 at 1.22.35 PM y 1.22.39 PM, la hoja Advanced…).

Habla con BlueZ por D-Bus (org.bluez, bus del sistema): el estado del adaptador, Turn Bluetooth On/Off,
la lista de dispositivos con «Connected» / «Not Connected» y Connect / Disconnect del dispositivo
escogido. La lista se refresca cada 3 segundos mientras el panel está abierto.
Sin equivalente (en gris): Show Bluetooth in menu bar y las tres casillas de Advanced… (el asistente de
arranque y despertar la computadora con un dispositivo).
El contextual de un dispositivo y el emparejamiento de dispositivos nuevos no tienen captura: la lista
solo enseña los dispositivos ya emparejados.
"""
import os

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gio, GLib, Gtk  # noqa: E402

import paneles  # noqa: E402

BLUEZ = "org.bluez"


def _llamar(objeto, interfaz, metodo, args=None, sinc=True):
    bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
    return bus.call_sync(BLUEZ, objeto, interfaz, metodo, args, None, Gio.DBusCallFlags.NONE, 15000, None)


def estado():
    """(adaptador {ruta, props}, [dispositivos {ruta, props}]) de GetManagedObjects, o (None, [])."""
    try:
        r = Gio.bus_get_sync(Gio.BusType.SYSTEM, None).call_sync(
            BLUEZ, "/", "org.freedesktop.DBus.ObjectManager", "GetManagedObjects", None, None,
            Gio.DBusCallFlags.NONE, 5000, None).unpack()[0]
    except GLib.Error:
        return None, []
    adaptador, dispositivos = None, []
    for ruta, ifaces in sorted(r.items()):
        if "org.bluez.Adapter1" in ifaces and adaptador is None:
            adaptador = {"ruta": ruta, "props": ifaces["org.bluez.Adapter1"]}
        if "org.bluez.Device1" in ifaces:
            dispositivos.append({"ruta": ruta, "props": ifaces["org.bluez.Device1"]})
    return adaptador, dispositivos


def _poner_propiedad(ruta, interfaz, nombre, valor):
    _llamar(ruta, "org.freedesktop.DBus.Properties", "Set", GLib.Variant("(ssv)", (interfaz, nombre, valor)))


class PanelBluetooth:
    id = "com.apple.preferences.Bluetooth"
    nombre = "Bluetooth"
    claves = []
    externo = False
    propio = True
    celda = None
    PRUEBA = bool(os.environ.get("MINT_BT_PRUEBA"))     # solo lee: no enciende, apaga ni conecta

    def __init__(self):
        self.panel = paneles.Panel(self.id, self.nombre, [],
                                   palabras="bluetooth, devices, pair, connect, discoverable, keyboard, mouse, "
                                            "headphones, speaker")
        self.ventana = None
        self._adaptador = None
        self._temporizador = None

    def coincide(self, texto):
        t = texto.lower().strip()
        return bool(t) and any(t in c.lower() for c in (self.nombre, self.panel.palabras, self.id))

    def construir(self):
        from propios import imagen_icono_panel
        caja = Gtk.Box(spacing=24)
        caja.get_style_context().add_class("mp-propio")
        for lado in ("top", "bottom", "start", "end"):
            getattr(caja, "set_margin_" + lado)(20)
        izq = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        izq.set_size_request(210, -1)
        izq.pack_start(imagen_icono_panel(self.id, 130), False, False, 12)
        self._estado = Gtk.Label()
        self._estado.get_style_context().add_class("mp-titulo-negrita")
        izq.pack_start(self._estado, False, False, 0)
        self._boton = Gtk.Button()
        self._boton.connect("clicked", lambda _b: self._alternar())
        izq.pack_start(self._boton, False, False, 0)
        self._visible = Gtk.Label()
        self._visible.set_line_wrap(True)
        self._visible.set_justify(Gtk.Justification.CENTER)
        izq.pack_start(self._visible, False, False, 6)
        caja.pack_start(izq, False, False, 0)

        der = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        marco = Gtk.Frame()
        marco.get_style_context().add_class("mp-sd-lista")
        cab = Gtk.Label(label="Devices", xalign=0, margin=6)
        cab.get_style_context().add_class("mp-titulo-negrita")
        interior = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        interior.pack_start(cab, False, False, 0)
        self._lista = Gtk.ListBox()
        self._lista.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self._lista.connect("row-selected", lambda _l, _f: self._botones())
        pant = Gtk.ScrolledWindow()
        pant.set_size_request(-1, 240)
        pant.add(self._lista)
        interior.pack_start(pant, True, True, 0)
        marco.add(interior)
        der.pack_start(marco, True, True, 0)

        accion = Gtk.Box(spacing=8)
        self._conectar = Gtk.Button(label="Connect")
        self._conectar.connect("clicked", lambda _b: self._conmutar())
        accion.pack_start(self._conectar, False, False, 0)
        der.pack_start(accion, False, False, 0)
        pie = Gtk.Box(spacing=8)
        menu = Gtk.CheckButton(label="Show Bluetooth in menu bar")
        menu.set_active(True)
        menu.set_sensitive(False)
        menu.set_tooltip_text("The Bluetooth menu lives in the Cinnamon panel.")
        pie.pack_start(menu, False, False, 0)
        av = Gtk.Button(label="Advanced…")
        av.connect("clicked", lambda _b: self._hoja())
        pie.pack_end(av, False, False, 0)
        der.pack_start(pie, False, False, 0)
        caja.pack_start(der, True, True, 0)

        caja.show_all()
        self._refrescar()
        self._visible_para_otros(True)         # como Catalina: visible mientras el panel está abierto
        self._temporizador = GLib.timeout_add_seconds(3, self._refrescar)

        def al_cerrar(_w):
            if self._temporizador:
                GLib.source_remove(self._temporizador)
            self._visible_para_otros(False)
        caja.connect("destroy", al_cerrar)
        return caja

    def _visible_para_otros(self, si):
        """Discoverable del adaptador (BlueZ lo apaga solo a los 180 s si el panel no lo hace antes)."""
        if self.PRUEBA or self._adaptador is None or not self._adaptador["props"].get("Powered"):
            return
        try:
            _poner_propiedad(self._adaptador["ruta"], "org.bluez.Adapter1", "Discoverable", GLib.Variant("b", si))
        except GLib.Error:
            pass

    # ── el estado ────────────────────────────────────────────────────────
    def _refrescar(self):
        adaptador, dispositivos = estado()
        self._adaptador = adaptador
        if adaptador is None:
            self._estado.set_text("Bluetooth: Not Available")
            self._boton.hide()
            self._visible.set_text("")
        else:
            p = adaptador["props"]
            enc = bool(p.get("Powered"))
            self._estado.set_text("Bluetooth: %s" % ("On" if enc else "Off"))
            self._boton.set_label("Turn Bluetooth %s" % ("Off" if enc else "On"))
            self._boton.show()
            self._visible.set_text("Now discoverable as\n“%s”" % p.get("Alias", "") if enc else "")
        ruta_elegida = self._ruta_elegida()
        for f in self._lista.get_children():
            self._lista.remove(f)
        for d in dispositivos:
            p = d["props"]
            if not p.get("Paired"):
                continue
            fila = Gtk.ListBoxRow()
            fila.ruta, fila.conectado = d["ruta"], bool(p.get("Connected"))
            h = Gtk.Box(spacing=10, margin=6)
            h.pack_start(Gtk.Image.new_from_icon_name(p.get("Icon", "bluetooth") + "-symbolic", Gtk.IconSize.LARGE_TOOLBAR),
                         False, False, 0)
            v = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
            v.pack_start(Gtk.Label(label=p.get("Alias") or p.get("Name") or p.get("Address", ""), xalign=0),
                         False, False, 0)
            s = Gtk.Label(label="Connected" if fila.conectado else "Not Connected", xalign=0)
            s.get_style_context().add_class("mp-sd-detalle")
            v.pack_start(s, False, False, 0)
            h.pack_start(v, True, True, 0)
            fila.add(h)
            self._lista.add(fila)
            if d["ruta"] == ruta_elegida:
                self._lista.select_row(fila)
        self._lista.show_all()
        self._botones()
        return True

    def _ruta_elegida(self):
        f = self._lista.get_selected_row()
        return getattr(f, "ruta", None) if f else None

    def _botones(self):
        f = self._lista.get_selected_row()
        self._conectar.set_visible(f is not None)
        if f is not None:
            self._conectar.set_label("Disconnect" if f.conectado else "Connect")

    # ── acciones ─────────────────────────────────────────────────────────
    def _alternar(self):
        if self._adaptador is None or self.PRUEBA:
            return
        enc = bool(self._adaptador["props"].get("Powered"))
        try:
            _poner_propiedad(self._adaptador["ruta"], "org.bluez.Adapter1", "Powered", GLib.Variant("b", not enc))
        except GLib.Error:
            pass
        self._refrescar()

    def _conmutar(self):
        f = self._lista.get_selected_row()
        if f is None or self.PRUEBA:
            return
        metodo = "Disconnect" if f.conectado else "Connect"
        bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
        bus.call(BLUEZ, f.ruta, "org.bluez.Device1", metodo, None, None, Gio.DBusCallFlags.NONE, 30000, None,
                 lambda _o, _r: self._refrescar())

    def _hoja(self):
        d = Gtk.Dialog(transient_for=self.ventana, modal=True)
        d.set_decorated(False)
        d.get_style_context().add_class("mp-hoja")
        c = d.get_content_area()
        c.set_spacing(8)
        for lado in ("top", "bottom", "start", "end"):
            getattr(c, "set_margin_" + lado)(20)
        for titulo, detalle in (
                ("Open Bluetooth Setup Assistant at startup if no keyboard is detected",
                 "If you use a keyboard and your computer doesn’t detect one when you start your computer, "
                 "the Bluetooth Setup Assistant will open to connect the Bluetooth keyboard."),
                ("Open Bluetooth Setup Assistant at startup if no mouse or trackpad is detected",
                 "If you use a mouse or trackpad and your computer doesn’t detect one when you start your "
                 "computer, the Bluetooth Setup Assistant will open to connect the Bluetooth mouse or trackpad."),
                ("Allow Bluetooth devices to wake this computer",
                 "If you use a Bluetooth keyboard or mouse or trackpad, and your computer goes to sleep, you can "
                 "press a key on your keyboard or click your mouse or trackpad to wake your computer.")):
            b = Gtk.CheckButton(label=titulo)
            b.set_active(True)
            b.set_sensitive(False)
            b.set_tooltip_text("Not available on this computer.")
            c.pack_start(b, False, False, 0)
            t = Gtk.Label(label=detalle, xalign=0)
            t.set_line_wrap(True)
            t.set_max_width_chars(70)
            t.set_margin_start(24)
            t.get_style_context().add_class("mp-sd-detalle")
            c.pack_start(t, False, False, 4)
        ok = d.add_button("OK", Gtk.ResponseType.OK)
        ok.get_style_context().add_class("suggested-action")
        d.set_default_response(Gtk.ResponseType.OK)
        d.show_all()
        d.run()
        d.destroy()
