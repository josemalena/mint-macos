#!/usr/bin/env python3
"""Visor de nib: pinta en GTK3 las ventanas, las vistas y los menús de un nib de
macOS a su tamaño en puntos, con el árbol de objetos y sus propiedades al lado.
Sirve para comparar mint-macos con la Mac sin depender de capturas.

    herramientas/visor-nib/visor.py RUTA.app                 una app entera: sus nib en una lista,
                                                             con el principal (NSMainNibFile) abierto
    herramientas/visor-nib/visor.py RUTA.nib                 la ventana del visor
    herramientas/visor-nib/visor.py RUTA.nib --json SALIDA   el árbol en JSON (para Dev-Dock)
    herramientas/visor-nib/visor.py RUTA.nib --png CARPETA   cada ventana a un PNG (sin pantalla:
                                                             para Xvfb y las pruebas)

Límites: los controles salen con el tema de aquí (Constanza), no con AppKit; lo que
la app llena al correr no está; las ventanas con constraints salen con su marco
inicial. Solo lee recursos (nib, .strings, Assets.car); los PNG y los JSON van a
~/.local/share/mint-macos/visor-nib, nunca al repo: tienen contenido de Apple.
"""
import glob
import json
import os
import subprocess
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
import nib  # noqa: E402

import gi  # noqa: E402
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, Gdk, GdkPixbuf  # noqa: E402

SALIDA = os.path.join(os.path.expanduser('~/.local/share/mint-macos'), 'visor-nib')
CAR = os.path.join(os.path.dirname(os.path.dirname(AQUI)), 'tema', 'iconos', 'car.py')


# --- una app entera --------------------------------------------------------------

def ruta_nib(p):
    """Un nib puede ser un archivo o una carpeta (keyedobjects.nib dentro)."""
    if os.path.isdir(p):
        for n in sorted(os.listdir(p)):
            if n.startswith('keyedobjects') and n.endswith('.nib'):
                return os.path.join(p, n)
        return None
    return p


def nibs_del_bundle(app):
    """(nombre, ruta) de los nib de una .app: Base.lproj, en.lproj, los sueltos y los de los
    storyboards; el principal (NSMainNibFile o NSMainStoryboardFile) primero."""
    recursos = os.path.join(app, 'Contents', 'Resources')
    principal = None
    try:
        import plistlib  # pylint: disable=import-outside-toplevel
        info = plistlib.load(open(os.path.join(app, 'Contents', 'Info.plist'), 'rb'))
        principal = info.get('NSMainNibFile') or info.get('NSMainStoryboardFile')
    except (OSError, ValueError):
        pass
    vistos, out = set(), []
    for carpeta in ('Base.lproj', 'en.lproj', 'English.lproj', ''):
        d = os.path.join(recursos, carpeta)
        for n in sorted(os.listdir(d)) if os.path.isdir(d) else []:
            rutas = []
            if n.endswith('.nib'):
                rutas.append((n[:-4], os.path.join(d, n)))
            elif n.endswith('.storyboardc'):
                for m in sorted(os.listdir(os.path.join(d, n))):
                    if m.endswith('.nib'):
                        rutas.append(('%s ▸ %s' % (n[:-12], m[:-4]), os.path.join(d, n, m)))
            for nombre, r in rutas:
                r = ruta_nib(r)
                if r and nombre not in vistos:
                    vistos.add(nombre)
                    out.append((nombre, r))
    out.sort(key=lambda x: (x[0] != principal and not x[0].startswith(str(principal) + ' ▸'), x[0].lower()))
    return out


# --- las imágenes del bundle y de AppKit ---------------------------------------

class Imagenes:
    """Saca una vez los Assets.car de la app y de AppKit a una carpeta y busca por nombre."""

    def __init__(self, ruta_nib):
        recursos = os.path.dirname(os.path.dirname(ruta_nib))
        self.app = os.path.basename(os.path.dirname(os.path.dirname(recursos))) or 'app'
        self.carpeta = os.path.join(SALIDA, self.app, 'imagenes')
        self.cars = [os.path.join(recursos, 'Assets.car')]
        # El disco de la Mac: las imágenes del sistema (NSActionTemplate…) están en AppKit.
        i = ruta_nib.find('/System/')
        if i > 0:
            raiz = ruta_nib[:i]
            self.cars.append(os.path.join(raiz, 'System/Library/Frameworks/AppKit.framework/Versions/C/Resources/Assets.car'))
        self.recursos = recursos
        self._listo = False

    def _sacar(self):
        if self._listo:
            return
        self._listo = True
        if os.path.isdir(self.carpeta) and os.listdir(self.carpeta):
            return
        os.makedirs(self.carpeta, exist_ok=True)
        for car in self.cars:
            if os.path.exists(car):
                for modo in ('sacar', 'glifos'):
                    subprocess.run(['nice', '-n', '19', sys.executable, '-I', CAR, modo, car, self.carpeta],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def ruta(self, nombre):
        if not nombre:
            return None
        # Primero un png suelto del bundle; después lo sacado de los .car.
        for p in (os.path.join(self.recursos, nombre + '.png'), os.path.join(self.recursos, nombre)):
            if os.path.isfile(p):
                return p
        self._sacar()
        candidatos = [p for p in glob.glob(os.path.join(glob.escape(self.carpeta), glob.escape(nombre)) + '*.png')
                      if os.path.basename(p)[len(nombre)] in '-@.' and 'oscuro' not in p]
        # La de escala 1 primero (a tamaño en puntos), después la más chica.
        candidatos.sort(key=lambda p: ('@2x' in p or '@3x' in p, os.path.getsize(p)))
        return candidatos[0] if candidatos else None


# --- pintar ---------------------------------------------------------------------

def imagen(imgs, nombre, tam=None):
    r = imgs.ruta(nombre)
    if not r:
        return None
    try:
        if tam:
            pb = GdkPixbuf.Pixbuf.new_from_file_at_size(r, int(tam[0]), int(tam[1]))
        else:
            pb = GdkPixbuf.Pixbuf.new_from_file(r)
        return Gtk.Image.new_from_pixbuf(pb)
    except Exception:  # pylint: disable=broad-except
        return None


def widget(n, imgs):
    """Un control de AppKit con su equivalente de GTK, o un recuadro con el nombre de la clase."""
    c, p = n['clase'], n['props']
    w = None
    texto = p.get('texto') or p.get('titulo')
    if c == 'NSTextField':
        w = Gtk.Label(label=texto or '')
        w.set_xalign(0)
    elif c in ('NSButton',):
        im = imagen(imgs, p.get('imagen'), (16, 16))
        w = Gtk.Button(label=texto) if texto else Gtk.Button()
        if im:
            w.set_image(im)
            w.set_always_show_image(True)
    elif c == 'NSPopUpButton':
        w = Gtk.ComboBoxText()
        for h in n['hijos']:
            for it in h['hijos']:
                if it['props'].get('titulo'):
                    w.append_text(it['props']['titulo'])
        w.set_active(0)
    elif c == 'NSSegmentedControl':
        w = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        w.get_style_context().add_class('linked')
        for s in p.get('segmentos', []):
            b = Gtk.ToggleButton(label=s.get('titulo') or '')
            b.set_active(s.get('elegido', False))
            w.pack_start(b, True, True, 0)
    elif c in ('NSTableView', 'NSOutlineView'):
        cols = [k for k in p.get('columnas', []) if not k.get('oculta')]
        modelo = Gtk.ListStore(*([str] * max(1, len(cols))))
        w = Gtk.TreeView(model=modelo)
        for i, k in enumerate(cols):
            col = Gtk.TreeViewColumn(k.get('titulo') or k.get('identificador') or '', Gtk.CellRendererText(), text=i)
            col.set_fixed_width(int(k.get('ancho') or 80))
            col.set_sizing(Gtk.TreeViewColumnSizing.FIXED)
            w.append_column(col)
    elif c == 'NSImageView':
        w = imagen(imgs, p.get('imagen'), (p['marco'][2], p['marco'][3]) if p.get('marco') else None)
    elif c == 'NSProgressIndicator':
        w = Gtk.ProgressBar()
    elif c in ('NSSearchField',):
        w = Gtk.SearchEntry()
    return w


def pintar(n, imgs, fijo, x0=0.0, y0=0.0, marcar=None):
    """Pone cada vista en su marco dentro de un Gtk.Fixed (todo en coordenadas de la ventana)."""
    m = n['props'].get('marco')
    if m:
        x, y = x0 + m[0], y0 + m[1]
        w = widget(n, imgs)
        ancho, alto = max(1, int(m[2])), max(1, int(m[3]))
        if w is None and n['clase'] not in ('NSView', 'NSClipView', 'NSScrollView', 'NSTabView'):
            w = Gtk.Frame(label=n['props'].get('clase_propia') or n['clase'])
            w.get_style_context().add_class('visor-nib-recuadro')
        if w is not None:
            w.set_size_request(ancho, alto)
            fijo.put(w, int(x), int(y))
            if marcar is not None:
                marcar[id(n)] = w
            if n['clase'] in ('NSTableView', 'NSOutlineView', 'NSPopUpButton', 'NSSegmentedControl'):
                return
    else:
        x, y = x0, y0
    if n['clase'] == 'NSTabView':
        # Solo la primera pestaña: las otras están detrás.
        tabs = [h for h in n['hijos'] if h['clase'] == 'NSTabViewItem']
        for h in tabs[:1]:
            for v in h['hijos']:
                pintar(v, imgs, fijo, x, y, marcar)
        return
    for h in n['hijos']:
        if h['clase'] not in ('NSMenu', 'NSToolbar'):
            pintar(h, imgs, fijo, x, y, marcar)


def barra_de_herramientas(tb, imgs):
    caja = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
    caja.set_border_width(6)
    for it in tb['hijos']:
        p = it['props']
        ident = p.get('identificador') or ''
        if ident == 'NSToolbarFlexibleSpaceItem':
            caja.pack_start(Gtk.Box(), True, True, 0)
            continue
        if ident in ('NSToolbarSpaceItem', 'NSToolbarSeparatorItem'):
            caja.pack_start(Gtk.Separator(orientation=Gtk.Orientation.VERTICAL), False, False, 0)
            continue
        vista = it['hijos'][0] if it['hijos'] else None
        w = widget(vista, imgs) if vista else None
        if w is None:
            w = Gtk.Button()
            im = imagen(imgs, p.get('imagen'), (16, 16))
            if im:
                w.set_image(im)
            else:
                w.set_label(p.get('titulo') or ident)
        if vista and vista['props'].get('marco'):
            w.set_size_request(int(vista['props']['marco'][2]), int(vista['props']['marco'][3]))
        w.set_tooltip_text(p.get('ayuda') or p.get('titulo') or '')
        caja.pack_start(w, False, False, 0)
    return caja


def lienzo(raiz, imgs, marcar=None):
    """Una ventana del nib como widget: toolbar arriba y su vista de contenido a tamaño."""
    caja = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
    tb = next((h for h in raiz['hijos'] if h['clase'] == 'NSToolbar'), None)
    if tb:
        caja.pack_start(barra_de_herramientas(tb, imgs), False, False, 0)
    fijo = Gtk.Fixed()
    m = raiz['props'].get('marco') or [0, 0, 400, 300]
    fijo.set_size_request(int(m[2]), int(m[3]))
    contenido = next((h for h in raiz['hijos'] if h['clase'] not in ('NSToolbar', 'NSMenu')), raiz)
    if raiz['clase'] == 'NSWindowTemplate':
        for h in contenido['hijos']:
            pintar(h, imgs, fijo, 0, 0, marcar)
    else:
        pintar(dict(raiz, props=dict(raiz['props'], marco=[0, 0, m[2], m[3]])), imgs, fijo, 0, 0, marcar)
    caja.pack_start(fijo, False, False, 0)
    return caja


def barra_de_menus(menu):
    barra = Gtk.MenuBar()

    def llenar(gmenu, nodo):
        for it in nodo['hijos']:
            p = it['props']
            if it['clase'] != 'NSMenuItem' or p.get('oculto'):
                continue
            if p.get('separador') or not p.get('titulo'):
                gmenu.append(Gtk.SeparatorMenuItem())
                continue
            mi = Gtk.MenuItem(label=p['titulo'] + ('\t' + p['atajo'] if p.get('atajo') else ''))
            sub = next((h for h in it['hijos'] if h['clase'] == 'NSMenu'), None)
            if sub:
                g = Gtk.Menu()
                llenar(g, sub)
                mi.set_submenu(g)
            gmenu.append(mi)

    llenar(barra, menu)
    return barra


def nombre_de(n):
    p = n['props']
    return '%s  %s' % (n['clase'], p.get('titulo') or p.get('texto') or p.get('clase_propia') or p.get('identificador') or '')


class Visor(Gtk.Window):
    def __init__(self, ruta):
        super().__init__(title='Visor de nib')
        self.set_default_size(1400, 860)
        # Una .app trae una lista de nib; un nib suelto, solo ese.
        if ruta.rstrip('/').endswith('.app') and os.path.isdir(ruta):
            self.app = os.path.basename(ruta.rstrip('/'))[:-4]
            self.nibs = nibs_del_bundle(ruta)
        else:
            self.app = None
            self.nibs = [(os.path.splitext(os.path.basename(ruta))[0], ruta_nib(ruta))]
        if not self.nibs:
            raise SystemExit('%s no tiene ningún nib' % ruta)
        caja = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.add(caja)
        if len(self.nibs) > 1:
            arriba = Gtk.Box(spacing=8)
            arriba.set_border_width(6)
            arriba.pack_start(Gtk.Label(label='Nib:'), False, False, 0)
            combo = Gtk.ComboBoxText()
            for n, _ in self.nibs:
                combo.append_text(n)
            combo.connect('changed', lambda c: self._cargar(c.get_active()))
            arriba.pack_start(combo, False, False, 0)
            caja.pack_start(arriba, False, False, 0)
        panel = Gtk.Paned(orientation=Gtk.Orientation.HORIZONTAL)
        caja.pack_start(panel, True, True, 0)
        # El árbol.
        self.modelo = Gtk.TreeStore(str, object)
        arbol = Gtk.TreeView(model=self.modelo)
        arbol.append_column(Gtk.TreeViewColumn('Objeto', Gtk.CellRendererText(), text=0))
        arbol.get_selection().connect('changed', self._elegido)
        izq = Gtk.Paned(orientation=Gtk.Orientation.VERTICAL)
        s = Gtk.ScrolledWindow()
        s.add(arbol)
        izq.pack1(s, True, False)
        self.props_modelo = Gtk.ListStore(str, str)
        tp = Gtk.TreeView(model=self.props_modelo)
        tp.append_column(Gtk.TreeViewColumn('Propiedad', Gtk.CellRendererText(), text=0))
        tp.append_column(Gtk.TreeViewColumn('Valor', Gtk.CellRendererText(), text=1))
        s2 = Gtk.ScrolledWindow()
        s2.add(tp)
        izq.pack2(s2, True, False)
        izq.set_position(520)
        izq.set_size_request(380, -1)
        panel.pack1(izq, False, False)
        self.der = Gtk.ScrolledWindow()
        panel.pack2(self.der, True, False)
        self.actual = None
        self.arbol = arbol
        if len(self.nibs) > 1:
            combo.set_active(0)
        else:
            self._cargar(0)

    def _cargar(self, i):
        nombre, ruta = self.nibs[i]
        self.set_title('%s — %s' % (self.app, nombre) if self.app else 'Visor de nib — ' + nombre)
        self.imgs = Imagenes(ruta)
        try:
            self.raices = nib.abrir(ruta).raices()
        except ValueError as e:
            self.raices = [{'id': None, 'clase': 'error', 'props': {'mensaje': str(e)}, 'hijos': []}]
        self.modelo.clear()
        self.actual = None
        for h in self.der.get_children():
            self.der.remove(h)
        for r in self.raices:
            self._poner(None, r)
        # Al abrir, la ventana más grande del nib, ya pintada.
        ventanas = [i for i, r in enumerate(self.raices) if r['clase'] == 'NSWindowTemplate']
        if ventanas:
            grande = max(ventanas, key=lambda i: (self.raices[i]['props'].get('marco') or [0, 0, 0, 0])[2])
            self.arbol.get_selection().select_path(Gtk.TreePath(grande))
        elif self.raices:
            # Un nib sin ventanas (el MainMenu de TextEdit): su barra de menús.
            self.arbol.get_selection().select_path(Gtk.TreePath(0))

    def _poner(self, padre, n):
        it = self.modelo.append(padre, [nombre_de(n), n])
        for h in n['hijos']:
            self._poner(it, h)

    def _raiz_de(self, it):
        while self.modelo.iter_parent(it) is not None:
            it = self.modelo.iter_parent(it)
        return self.modelo[it][1]

    def _elegido(self, sel):
        m, it = sel.get_selected()
        if it is None:
            return
        n = m[it][1]
        self.props_modelo.clear()
        self.props_modelo.append(['clase', n['clase']])
        for k, v in n['props'].items():
            self.props_modelo.append([k, json.dumps(v, ensure_ascii=False) if not isinstance(v, str) else v])
        raiz = self._raiz_de(it)
        if raiz is not self.actual:
            self.actual = raiz
            for h in self.der.get_children():
                self.der.remove(h)
            self.marcados = {}
            if raiz['clase'] == 'NSMenu':
                w = barra_de_menus(raiz)
            else:
                w = lienzo(raiz, self.imgs, self.marcados)
            self.der.add(w)
            self.der.show_all()
        # El seleccionado, resaltado.
        for w in getattr(self, 'marcados', {}).values():
            w.get_style_context().remove_class('visor-nib-elegido')
        w = self.marcados.get(id(n)) if hasattr(self, 'marcados') else None
        if w:
            w.get_style_context().add_class('visor-nib-elegido')


CSS = b'''
.visor-nib-recuadro { border: 1px dashed alpha(#888, 0.6); }
.visor-nib-recuadro > label { font-size: 8pt; color: #888; }
.visor-nib-elegido { box-shadow: inset 0 0 0 2px #3478f6; }
'''


def estilo():
    css = Gtk.CssProvider()
    css.load_from_data(CSS)
    Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)


def a_png(ruta, carpeta):
    """Cada ventana y vista suelta a un PNG, sin enseñar nada (Gtk.OffscreenWindow)."""
    estilo()
    imgs = Imagenes(ruta)
    os.makedirs(carpeta, exist_ok=True)
    hechos = []
    for i, r in enumerate(nib.abrir(ruta).raices()):
        if r['clase'] == 'NSMenu':
            continue
        off = Gtk.OffscreenWindow()
        off.add(lienzo(r, imgs))
        off.show_all()
        while Gtk.events_pending():
            Gtk.main_iteration()
        pb = off.get_pixbuf()
        nombre = '%02d-%s.png' % (i, (r['props'].get('titulo') or r['props'].get('clase_propia') or r['clase']).replace('/', '-'))
        if pb:
            pb.savev(os.path.join(carpeta, nombre), 'png', [], [])
            hechos.append((nombre, pb.get_width(), pb.get_height()))
        off.destroy()
    return hechos


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    ruta = sys.argv[1]
    if '--json' in sys.argv:
        salida = sys.argv[sys.argv.index('--json') + 1]
        json.dump(nib.abrir(ruta).raices(), open(salida, 'w'), ensure_ascii=False, indent=1)
        print(salida)
        return
    if '--png' in sys.argv:
        for nombre, w, h in a_png(ruta, sys.argv[sys.argv.index('--png') + 1]):
            print('%s  %dx%d' % (nombre, w, h))
        return
    estilo()
    v = Visor(ruta)
    v.connect('destroy', Gtk.main_quit)
    v.show_all()
    Gtk.main()


if __name__ == '__main__':
    main()
