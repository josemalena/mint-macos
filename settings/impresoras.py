"""Printers & Scanners: el panel de Catalina (Screen Shot 2026-10-14 at 1.22.47 PM).

La lista, el estado, Location, Kind y la impresora predeterminada salen de CUPS (lpstat, lpoptions);
«Share this printer on the network» es printer-is-shared (lpadmin, el usuario está en el grupo lpadmin);
Open Print Queue… y Options & Supplies… abren system-config-printer en esa impresora; el «+» abre
system-config-printer para añadir una. Sin equivalente (en gris): Default paper size, y la lista de
escáneres (no hay captura de la lista con escáneres).
La ventana de añadir impresora, la cola y las hojas de opciones de Catalina no tienen captura.
"""
import os
import re
import subprocess

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk  # noqa: E402

import paneles  # noqa: E402


def _salida(*cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=10,
                              env=dict(os.environ, LC_ALL="C")).stdout
    except (OSError, subprocess.SubprocessError):
        return ""


def impresoras():
    """[{nombre, estado, descripcion, lugar, conexion, compartida}] de `lpstat -l -p`."""
    salida = _salida("lpstat", "-l", "-p")
    lista, actual = [], None
    for linea in salida.splitlines():
        m = re.match(r"^printer (\S+) (.*)$", linea)
        if m:
            texto = m.group(2)
            fuera = "disabled" in texto or "not accepting" in texto
            actual = {"nombre": m.group(1), "estado": "Offline" if fuera else ("Printing" if "now printing" in texto
                                                                                 else "Idle"),
                      "descripcion": "", "lugar": "", "conexion": ""}
            lista.append(actual)
        elif actual is not None:
            k, _, v = linea.strip().partition(":")
            if k == "Description":
                actual["descripcion"] = v.strip()
            elif k == "Location":
                actual["lugar"] = v.strip()
            elif k == "Connection":
                actual["conexion"] = v.strip()
    return lista


def predeterminada():
    m = re.search(r"destination: (\S+)", _salida("lpstat", "-d"))
    return m.group(1) if m else ""


def compartida(nombre):
    """printer-is-shared de CUPS (pycups); False si no se puede saber."""
    try:
        import cups
        return bool(cups.Connection().getPrinters().get(nombre, {}).get("printer-is-shared"))
    except Exception:  # noqa: BLE001 — sin pycups o sin servidor CUPS
        return False


def modelo(nombre):
    """printer-make-and-model de CUPS: lo que Catalina llama «Kind»."""
    try:
        import cups
        return cups.Connection().getPrinters().get(nombre, {}).get("printer-make-and-model", "")
    except Exception:  # noqa: BLE001
        return ""


def _gris(widget, motivo="Not available on this computer."):
    widget.set_sensitive(False)
    widget.set_tooltip_text(motivo)
    return widget


def _marco():
    m = Gtk.Frame()
    m.get_style_context().add_class("mp-sd-lista")
    return m


class PanelPrinters:
    id = "com.apple.preference.printfax"
    nombre = "Printers & Scanners"
    claves = []
    externo = False
    propio = True
    celda = None
    PRUEBA = bool(os.environ.get("MINT_IMPRESORAS_PRUEBA"))     # solo lee: no cambia nada en CUPS

    def __init__(self):
        self.panel = paneles.Panel(self.id, self.nombre, [],
                                   palabras="printers, scanners, print, printer, default printer, queue, sharing")
        self.ventana = None
        self._cargando = False

    def coincide(self, texto):
        t = texto.lower().strip()
        return bool(t) and any(t in c.lower() for c in (self.nombre, self.panel.palabras, self.id))

    def construir(self):
        from propios import imagen_icono_panel
        self._imagen = imagen_icono_panel
        self._cargando = True
        caja = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        caja.get_style_context().add_class("mp-propio")
        for lado in ("top", "bottom", "start", "end"):
            getattr(caja, "set_margin_" + lado)(16)
        cuerpo = Gtk.Box(spacing=12)
        izq = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        marco = _marco()
        self._lista = Gtk.ListBox()
        self._lista.set_size_request(200, 240)
        self._lista.connect("row-selected", lambda _l, f: self._detalle(f))
        marco.add(self._lista)
        izq.pack_start(marco, True, True, 0)
        botones = Gtk.Box()
        botones.get_style_context().add_class("linked")
        mas = Gtk.Button(label="+")
        mas.connect("clicked", lambda _b: self._lanzar([]))
        menos = _gris(Gtk.Button(label="−"), "Use system-config-printer to remove a printer.")
        botones.pack_start(mas, False, False, 0)
        botones.pack_start(menos, False, False, 0)
        izq.pack_start(botones, False, False, 4)
        cuerpo.pack_start(izq, False, False, 0)
        self._der = _marco()
        cuerpo.pack_start(self._der, True, True, 0)
        caja.pack_start(cuerpo, True, True, 0)

        g = Gtk.Grid(column_spacing=10, row_spacing=8)
        g.set_halign(Gtk.Align.CENTER)
        e1 = Gtk.Label(label="Default printer:", xalign=1.0)
        e1.get_style_context().add_class("mp-fila-etiqueta")
        g.attach(e1, 0, 0, 1, 1)
        self._pred = Gtk.ComboBoxText()
        self._pred.connect("changed", lambda c: self._poner_predeterminada(c.get_active_id()))
        g.attach(self._pred, 1, 0, 1, 1)
        e2 = Gtk.Label(label="Default paper size:", xalign=1.0)
        e2.get_style_context().add_class("mp-fila-etiqueta")
        g.attach(e2, 0, 1, 1, 1)
        papel = Gtk.ComboBoxText()
        papel.append("a4", "A4")
        papel.set_active(0)
        g.attach(_gris(papel, "The paper size is set by each printer on this computer."), 1, 1, 1, 1)
        caja.pack_start(g, False, False, 0)

        self._impresoras = impresoras()
        pred = predeterminada()
        for p in self._impresoras:
            fila = Gtk.ListBoxRow()
            fila.p = p
            h = Gtk.Box(spacing=8, margin=6)
            h.pack_start(Gtk.Image.new_from_icon_name("printer", Gtk.IconSize.LARGE_TOOLBAR), False, False, 0)
            v = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
            v.pack_start(Gtk.Label(label=p["descripcion"] or p["nombre"], xalign=0), False, False, 0)
            s = Gtk.Label(label="%s%s" % (p["estado"], ", Default" if p["nombre"] == pred else ""), xalign=0)
            s.get_style_context().add_class("mp-sd-detalle")
            v.pack_start(s, False, False, 0)
            h.pack_start(v, True, True, 0)
            fila.add(h)
            self._lista.add(fila)
            self._pred.append(p["nombre"], p["descripcion"] or p["nombre"])
        if pred:
            self._pred.set_active_id(pred)
        caja.show_all()
        if self._impresoras:
            self._lista.select_row(self._lista.get_row_at_index(0))
        self._cargando = False
        return caja

    def _detalle(self, fila):
        for h in self._der.get_children():
            self._der.remove(h)
        if fila is None:
            return
        p = fila.p
        caja = Gtk.Box(spacing=18, margin=16)
        caja.pack_start(self._imagen(self.id, 96), False, False, 0)
        c = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        t = Gtk.Label(label=p["descripcion"] or p["nombre"], xalign=0)
        t.get_style_context().add_class("mp-titulo-negrita")
        c.pack_start(t, False, False, 0)
        cola = Gtk.Button(label="Open Print Queue…")
        cola.connect("clicked", lambda _b: self._lanzar(["--show-jobs", p["nombre"]]))
        opciones = Gtk.Button(label="Options & Supplies…")
        opciones.connect("clicked", lambda _b: self._lanzar([]))
        c.pack_start(cola, False, False, 0)
        c.pack_start(opciones, False, False, 0)
        g = Gtk.Grid(column_spacing=10, row_spacing=4)
        for i, (k, v) in enumerate((("Location:", p["lugar"]), ("Kind:", modelo(p["nombre"])), ("Status:", p["estado"]))):
            e = Gtk.Label(label=k, xalign=1.0)
            e.get_style_context().add_class("mp-sd-detalle")
            g.attach(e, 0, i, 1, 1)
            g.attach(Gtk.Label(label=v, xalign=0), 1, i, 1, 1)
        c.pack_start(g, False, False, 12)
        compartir = Gtk.CheckButton(label="Share this printer on the network")
        compartir.set_active(compartida(p["nombre"]))
        compartir.connect("toggled", lambda b: self._compartir(p["nombre"], b.get_active()))
        c.pack_start(compartir, False, False, 0)
        caja.pack_start(c, True, True, 0)
        self._der.add(caja)
        self._der.show_all()

    # ── acciones ─────────────────────────────────────────────────────────
    def _lanzar(self, args):
        if self.PRUEBA:
            return
        try:
            subprocess.Popen(["system-config-printer", *args], start_new_session=True,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except OSError:
            pass

    def _poner_predeterminada(self, nombre):
        if self._cargando or self.PRUEBA or not nombre:
            return
        subprocess.run(["lpadmin", "-d", nombre], capture_output=True, timeout=15)

    def _compartir(self, nombre, si):
        if self._cargando or self.PRUEBA:
            return
        subprocess.run(["lpadmin", "-p", nombre, "-o", "printer-is-shared=%s" % ("true" if si else "false")],
                       capture_output=True, timeout=15)
