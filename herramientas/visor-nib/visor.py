#!/usr/bin/env python3
"""Visor de nib: pinta en GTK3 las ventanas, las vistas y los menús de una app de macOS a
su tamaño en puntos, para comparar mint-macos con la Mac sin depender de capturas.

    herramientas/visor-nib/visor.py RUTA.app                 la app como en la Mac: abre solo su
                                                             ventana principal, con su menú en la
                                                             barra de arriba; en Window, las demás
                                                             ventanas y el Inspector (⌥⌘I)
    herramientas/visor-nib/visor.py RUTA.nib                 un nib suelto, igual
    herramientas/visor-nib/visor.py RUTA.nib --json SALIDA   el árbol en JSON (para Dev-Dock)
    herramientas/visor-nib/visor.py RUTA --png CARPETA       a PNG sin pantalla (Xvfb, pruebas):
                                                             un nib, cada ventana; una .app, la
                                                             principal

Una app o extensión SwiftUI (los paneles de System Settings de Sequoia) no trae nib: sus
vistas salen de la metadata de tipos de Swift del ejecutable (swiftui.py) y se pintan como un
panel de Settings. Los textos no están en esa metadata: los controles dicen «Text», y el
Inspector trae los textos del panel. Lo que depende de un if sale atenuado.

Lo que la app arma al correr (la ventana de Mail, el teclado de Calculator) no está en
ningún nib: el visor lo compone con una receta, ~/.local/share/mint-macos/visor-nib/
recetas/<App>.json, que dice qué vistas de qué nib van en qué sitio:

    {"titulo": "Inbox", "tam": [1200, 700], "barra": "MainWindow.toolbar",
     "piezas": [{"nib": "MailboxesViewController", "id": 124, "en": [0, 0], "tam": [200, 700]}]}

Límites: los controles salen con el tema de aquí (Constanza), no con AppKit; lo que la app
llena con datos no está; las vistas con constraints se estiran por sus resortes, no por las
constraints. Solo lee recursos (nib, .strings, .toolbar, Assets.car); los PNG, los JSON y las
recetas van a ~/.local/share/mint-macos/visor-nib, nunca al repo: tienen datos de Apple.
"""
import copy
import glob
import hashlib
import json
import os
import plistlib
import re
import subprocess
import sys
from struct import error as struct_error

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
import nib  # noqa: E402

import gi  # noqa: E402
gi.require_version('Gtk', '3.0')
gi.require_version('Gdk', '3.0')
gi.require_version('Pango', '1.0')
from gi.repository import Gtk, Gdk, GdkPixbuf, GLib, Pango  # noqa: E402

SALIDA = os.path.join(os.path.expanduser('~/.local/share/mint-macos'), 'visor-nib')
RECETAS = os.path.join(SALIDA, 'recetas')
CAR = os.path.join(os.path.dirname(os.path.dirname(AQUI)), 'tema', 'iconos', 'car.py')
# Un nib repetido para otra versión del sistema («ConversionSheet-BBBAA77A32-C4EBFEA440»).
VARIANTE = re.compile(r'-[0-9A-F]{10}-[0-9A-F]{10}$')


# --- una app entera --------------------------------------------------------------

def ruta_nib(p):
    """Un nib puede ser un archivo o una carpeta (keyedobjects.nib dentro)."""
    if os.path.isdir(p):
        for n in sorted(os.listdir(p)):
            if n.startswith('keyedobjects') and n.endswith('.nib'):
                return os.path.join(p, n)
        return None
    return p


def carpetas_de_recursos(app):
    """(prefijo, Resources) de la app y de lo que trae dentro: los plugins (el teclado de
    Calculator está en PlugIns/BasicAndSci.calcview), los frameworks y los servicios XPC (los
    nib del Dock están ahí). Las extensiones
    (.appex) son otros programas y no cuentan."""
    c = os.path.join(app, 'Contents')
    out = [('', os.path.join(c, 'Resources'))]
    for sub in ('PlugIns', 'Frameworks', 'XPCServices'):
        for b in sorted(glob.glob(os.path.join(glob.escape(c), sub, '*'))):
            if b.endswith('.appex'):
                continue
            for r in (os.path.join(b, 'Contents', 'Resources'), os.path.join(b, 'Resources')):
                if os.path.isdir(r):
                    out.append((os.path.splitext(os.path.basename(b))[0], r))
                    break
    return out


def nibs_del_bundle(app):
    """(nombre, ruta) de los nib de una .app: Base.lproj, en.lproj, los sueltos, los de los
    storyboards y los de sus plugins («BasicAndSci ▸ BasicAdvanced»); el principal
    (NSMainNibFile o NSMainStoryboardFile) primero."""
    principal = info_de(app).get('NSMainNibFile') or info_de(app).get('NSMainStoryboardFile')
    vistos, out = set(), []
    for prefijo, recursos in carpetas_de_recursos(app):
        for carpeta in ('Base.lproj', 'en.lproj', 'English.lproj', ''):
            d = os.path.join(recursos, carpeta)
            for n in sorted(os.listdir(d)) if os.path.isdir(d) else []:
                rutas = []
                if n.endswith('.nib') and not VARIANTE.search(n[:-4]):
                    rutas.append((n[:-4], os.path.join(d, n)))
                elif n.endswith('.storyboardc'):
                    for m in sorted(os.listdir(os.path.join(d, n))):
                        if m.endswith('.nib') and not VARIANTE.search(m[:-4]):
                            rutas.append(('%s ▸ %s' % (n[:-12], m[:-4]), os.path.join(d, n, m)))
                for nombre, r in rutas:
                    nombre = '%s ▸ %s' % (prefijo, nombre) if prefijo else nombre
                    r = ruta_nib(r)
                    if r and nombre not in vistos:
                        vistos.add(nombre)
                        out.append((nombre, r))
    out.sort(key=lambda x: (x[0] != principal and not x[0].startswith(str(principal) + ' ▸'),
                            ' ▸ ' in x[0] and not x[0].startswith(str(principal)), x[0].lower()))
    return out


def info_de(app):
    try:
        return plistlib.load(open(os.path.join(app, 'Contents', 'Info.plist'), 'rb'))
    except (OSError, ValueError):
        return {}


def buscar(n, ident):
    if n.get('id') == ident:
        return n
    for h in n['hijos']:
        r = buscar(h, ident)
        if r:
            return r
    return None


def redimensionar(n, ancho, alto):
    """Una copia de la vista con otro tamaño y sus subvistas movidas y estiradas por sus
    resortes, como lo hace AppKit (autoresizingMask, en sus coordenadas, origen abajo)."""
    m = n['props'].get('marco') or [0, 0, ancho, alto]
    viejo_an, viejo_al = m[2], m[3]
    dw, dh = ancho - viejo_an, alto - viejo_al
    nuevo = dict(n, props=dict(n['props'], marco=[m[0], m[1], ancho, alto]))

    def hijo(c):
        cm = c['props'].get('marco')
        if not cm:
            # Sin marco (NSTabViewItem): sus vistas cambian con el padre.
            return dict(c, hijos=[hijo(g) for g in c['hijos']])
        f = c['props'].get('autoajuste', 0)
        x, y, w, h = cm
        k = sum(1 for b in (1, 2, 4) if f & b)
        if k:
            s = dw / k
            x += s if f & 1 else 0
            w += s if f & 2 else 0
        yb = viejo_al - y - h
        k = sum(1 for b in (8, 16, 32) if f & b)
        if k:
            s = dh / k
            yb += s if f & 8 else 0
            h += s if f & 16 else 0
        y = alto - yb - h
        return redimensionar(dict(c, props=dict(c['props'], marco=[x, y, cm[2], cm[3]])), max(1, w), max(1, h))

    if dw or dh:
        nuevo['hijos'] = [hijo(c) for c in n['hijos']]
    return nuevo


def raices_con_cache(ruta):
    """Las raíces de un nib, guardadas en JSON: leer los 106 nib de Mail del disco de la Mac
    (FUSE) tardaba 2 s antes de enseñar la ventana. La firma lleva el tamaño y la fecha del nib
    y de nib.py, así que un cambio en cualquiera de los dos lo vuelve a leer."""
    try:
        st = os.stat(ruta)
        firma = [st.st_size, st.st_mtime, os.stat(nib.__file__).st_mtime]
        archivo = os.path.join(SALIDA, 'cache', hashlib.sha1(ruta.encode()).hexdigest() + '.json')
        try:
            d = json.load(open(archivo))
            if d.get('firma') == firma:
                return d['raices']
        except (OSError, ValueError):
            pass
        raices = nib.abrir(ruta).raices()
        try:
            os.makedirs(os.path.dirname(archivo), exist_ok=True)
            with open(archivo + '.nuevo', 'w') as f:
                json.dump({'ruta': ruta, 'firma': firma, 'raices': raices}, f, ensure_ascii=False)
            os.replace(archivo + '.nuevo', archivo)
        except OSError:
            pass
        return raices
    except Exception as e:  # pylint: disable=broad-except
        return [{'id': None, 'clase': 'error', 'props': {'mensaje': str(e)}, 'hijos': []}]


class VistaSwiftUI(dict):
    """Una vista SwiftUI como raíz del visor; sus hijos (el árbol de swiftui.a_ui) se arman al
    pedirlos la primera vez."""

    def __init__(self, nombre, vistas, titulo, textos):
        super().__init__(id=None, clase='SwiftUI', props={'titulo': titulo, 'vista': nombre,
                                                          'clase_propia': nombre, 'textos': textos})
        self._vistas, self._nombre = vistas, nombre

    def __getitem__(self, k):
        if k == 'hijos' and not dict.__contains__(self, 'hijos'):
            import swiftui  # pylint: disable=import-outside-toplevel
            dict.__setitem__(self, 'hijos', [swiftui.a_ui(self._vistas[self._nombre], self._vistas, self._nombre.split('.')[0])])
        return dict.__getitem__(self, k)

    def get(self, k, d=None):
        return self[k] if k == 'hijos' or k in self else d


class AppMac:
    """Una .app (o un nib suelto): sus nib, su menú principal, sus ventanas y la receta."""

    def __init__(self, ruta):
        ruta = ruta.rstrip('/')
        # Una .app o cualquier bundle con Info.plist (los .prefPane de System Preferences).
        if os.path.isdir(ruta) and os.path.exists(os.path.join(ruta, 'Contents', 'Info.plist')):
            self.ruta = ruta
            info = info_de(ruta)
            self.nombre = info.get('CFBundleName') or os.path.splitext(os.path.basename(ruta))[0]
            self.principal = info.get('NSMainNibFile') or info.get('NSMainStoryboardFile')
            self.nibs = nibs_del_bundle(ruta)
            icono = info.get('CFBundleIconFile')
            self.icono = None
            if icono:
                p = os.path.join(ruta, 'Contents', 'Resources', icono)
                self.icono = p if os.path.exists(p) else (p + '.icns' if os.path.exists(p + '.icns') else None)
        else:
            self.ruta = None
            self.nombre = os.path.splitext(os.path.basename(ruta))[0]
            self.principal = self.nombre
            self.nibs = [(self.nombre, ruta_nib(ruta))]
            self.icono = None
        # SwiftUI: las vistas salen de la metadata de tipos del ejecutable (swiftui.py).
        self.swiftui = None
        exe = os.path.join(ruta, 'Contents', 'MacOS', info_de(ruta).get('CFBundleExecutable', '')) if self.ruta else None
        if exe and os.path.isfile(exe):
            try:
                import swiftui  # pylint: disable=import-outside-toplevel
                vistas, raices = swiftui.app_swiftui(exe)
                if vistas:
                    self.swiftui = (vistas, raices, exe)
            except (ValueError, KeyError, OSError, struct_error):
                pass
        if not self.nibs and not self.swiftui:
            raise SystemExit('%s no tiene ningún nib ni vistas SwiftUI' % ruta)
        self._raices = {}
        self._imgs = {}
        self.receta = None
        p = os.path.join(RECETAS, self.nombre + '.json')
        if self.ruta and os.path.exists(p):
            self.receta = json.load(open(p))
            self.receta['_ruta'] = p

    def ruta_de(self, nombre):
        return dict(self.nibs).get(nombre)

    def raices(self, nombre):
        if nombre not in self._raices:
            self._raices[nombre] = raices_con_cache(self.ruta_de(nombre))
        return self._raices[nombre]

    def imgs(self, nombre):
        if nombre not in self._imgs:
            self._imgs[nombre] = Imagenes(self.ruta_de(nombre))
        return self._imgs[nombre]

    def menu_principal(self):
        """El menú de la barra: el NSMenu más grande del nib principal."""
        if not self.nibs:
            return None  # una extensión SwiftUI sin nib: sin barra de menús propia
        nombre = self.principal if self.ruta_de(self.principal) else self.nibs[0][0]
        menus = [r for r in self.raices(nombre) if r['clase'] == 'NSMenu']
        if not menus:
            # Sin NSMainNibFile (el Finder): la barra que tenga Edit o View, en cualquier nib.
            def de_barra(r):
                tops = {h['props'].get('titulo') for h in r['hijos']}
                return r['clase'] == 'NSMenu' and bool(tops & {'Edit', 'View', 'Window'})
            menus = [r for n, _ in self.nibs for r in self.raices(n) if de_barra(r)]
        return max(menus, key=lambda r: len(r['hijos'])) if menus else None

    def ventanas(self):
        """[{etiqueta, nib, raiz, imgs}]: la compuesta por la receta primero, después cada
        ventana de cada nib y al final las vistas sueltas (las que la app mete en una ventana)."""
        out = []
        if self.receta:
            out.append(self.componer())
        sueltas = []
        if self.swiftui:
            import swiftui  # pylint: disable=import-outside-toplevel
            vistas, raices, _exe = self.swiftui
            titulo, textos = self.titulo_swiftui(), self.textos_swiftui()
            for nombre in list(raices) + [v for v in sorted(vistas) if v not in raices]:
                # El árbol se arma al abrir la vista (VistaSwiftUI.hijos): armar todas al empezar
                # tardaba en las extensiones grandes.
                raiz = VistaSwiftUI(nombre, vistas, titulo, textos)
                e = {'etiqueta': 'SwiftUI: %s' % nombre.split('.', 1)[-1], 'nib': None, 'raiz': raiz, 'imgs': None}
                if nombre in raices:
                    out.append(e)
                else:
                    sueltas.append(dict(e, vista=True))
        for nombre, _ in self.nibs:
            for r in self.raices(nombre):
                p = r['props']
                if r['clase'] == 'NSWindowTemplate':
                    out.append({'etiqueta': '%s  (%s)' % (p.get('titulo') or p.get('clase_propia') or 'Sin título', nombre),
                                'nib': nombre, 'raiz': r, 'imgs': self.imgs(nombre)})
                elif r['clase'] not in ('NSMenu', 'error') and p.get('marco'):
                    sueltas.append({'etiqueta': 'Vista: %s  (%s)' % (p.get('clase_propia') or r['clase'], nombre),
                                    'nib': nombre, 'raiz': r, 'imgs': self.imgs(nombre), 'vista': True})
        return out + sueltas

    def inicial(self, ventanas):
        """La que abre la app: la de la receta; si no, la más grande del nib principal; si no, la
        más grande de todas."""
        if self.receta:
            return 0
        nib = [i for i, v in enumerate(ventanas) if not v.get('vista') and v['raiz']['clase'] != 'SwiftUI']
        if not nib and self.swiftui:
            # Sin ventanas en los nib: la vista SwiftUI raíz más grande (la primera).
            return next((i for i, v in enumerate(ventanas) if v['raiz']['clase'] == 'SwiftUI'), None)
        solo = [i for i, v in enumerate(ventanas) if not v.get('vista')]
        del_principal = [i for i in solo if ventanas[i]['nib'] == self.principal]
        grande = (lambda i: (ventanas[i]['raiz']['props'].get('marco') or [0, 0, 0, 0])[2]
                  * (ventanas[i]['raiz']['props'].get('marco') or [0, 0, 0, 0])[3])
        for grupo in (del_principal, solo, list(range(len(ventanas)))):
            if grupo:
                return max(grupo, key=grande)
        return None

    def textos_swiftui(self):
        """Los textos en inglés del bundle (Localizable.loctable o .strings), sin los de deshacer
        ni las ayudas: en SwiftUI no se sabe qué Text lleva cuál, así que van al Inspector."""
        rec = os.path.join(self.ruta, 'Contents', 'Resources')
        en = {}
        try:
            en = plistlib.load(open(os.path.join(rec, 'Localizable.loctable'), 'rb')).get('en', {})
        except (OSError, ValueError):
            en = nib.cadenas_de(os.path.join(rec, 'en.lproj', 'Localizable.strings'))
        return sorted({v for k, v in en.items() if isinstance(v, str) and not re.search(r'_(UNDO|TOOLTIP|HELP|AX)\b', k)})

    def titulo_swiftui(self):
        """El nombre visible: CFBundleDisplayName, de InfoPlist.loctable en inglés si está."""
        info = info_de(self.ruta)
        lt = os.path.join(self.ruta, 'Contents', 'Resources', 'InfoPlist.loctable')
        try:
            en = plistlib.load(open(lt, 'rb')).get('en', {})
        except (OSError, ValueError):
            en = {}
        return en.get('CFBundleDisplayName') or info.get('CFBundleDisplayName') or en.get('CFBundleName') or self.nombre

    def componer(self):
        """La ventana de la receta: las piezas de cada nib en su sitio y a su tamaño."""
        r = self.receta
        ancho, alto = r['tam']
        hijos, usadas = [], []
        for pz in r.get('piezas', []):
            raiz = None
            if pz.get('vista'):
                # Una vista que ningún nib trae (la hoja de TextEdit): la describe la receta.
                raiz = {'id': None, 'clase': pz['vista'].get('clase', 'NSView'),
                        'props': dict(pz['vista'].get('props', {}), marco=[0, 0] + list(pz['tam'])), 'hijos': []}
            for x in ([] if raiz else self.raices(pz['nib'])):
                raiz = buscar(x, pz['id']) if pz.get('id') is not None else x
                if raiz:
                    break
            if raiz is None:
                continue
            if raiz['clase'] == 'NSWindowTemplate':
                raiz = next((h for h in raiz['hijos'] if h['clase'] not in ('NSToolbar', 'NSMenu')), raiz)
            m = raiz['props'].get('marco') or [0, 0, ancho, alto]
            w, h = pz.get('tam') or m[2:]
            x, y = pz.get('en') or [0, 0]
            # Una copia: ocultar no puede tocar el árbol del nib, que se ve también suelto.
            nodo = redimensionar(copy.deepcopy(raiz), w, h)
            for ident in pz.get('ocultar', []):
                o = buscar(nodo, ident)
                if o:
                    o['props'] = dict(o['props'], oculta=True)
            nodo['props'] = dict(nodo['props'], marco=[x, y, w, h])
            nodo['_imgs'] = self.imgs(pz.get('nib') or self.nibs[0][0])
            hijos.append(nodo)
            usadas.append('%s #%s' % (pz.get('nib') or 'receta', pz.get('id', nodo['clase'])))
        contenido = {'id': None, 'clase': 'NSView', 'props': {'marco': [0, 0, ancho, alto]}, 'hijos': hijos}
        ventana = {'id': None, 'clase': 'NSWindowTemplate',
                   'props': {'titulo': r.get('titulo') or self.nombre, 'marco': [0, 0, ancho, alto],
                             'receta': r['_ruta'], 'piezas': usadas}, 'hijos': []}
        if r.get('barra'):
            p = os.path.join(self.ruta, 'Contents', 'Resources', r['barra'])
            cad = {}
            for f in glob.glob(os.path.join(glob.escape(os.path.join(self.ruta, 'Contents', 'Resources', 'en.lproj')), '*.strings')):
                cad.update(nib.cadenas_de(f))
            if os.path.exists(p):
                ventana['hijos'].append(nib.barra_de_archivo(p, cad))
        ventana['hijos'].append(contenido)
        primera = next((pz['nib'] for pz in r.get('piezas', []) if pz.get('nib')), self.nibs[0][0])
        return {'etiqueta': '%s  (receta)' % (r.get('titulo') or self.nombre), 'nib': primera,
                'raiz': ventana, 'imgs': self.imgs(primera or self.nibs[0][0])}


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
            # Las de la barra (NSToolbarDelete, NSToolbarCompose) están en la apariencia del sistema.
            self.cars.append(os.path.join(raiz, 'System/Library/CoreServices/SystemAppearance.bundle/Contents/Resources/Assets.car'))
        self.recursos = recursos
        self._listo = False

    def _sacar(self):
        if self._listo:
            return
        self._listo = True
        os.makedirs(self.carpeta, exist_ok=True)
        # Una vez por .car: la lista de los ya sacados, en la carpeta.
        hechos_p = os.path.join(self.carpeta, '.sacados')
        hechos = set(open(hechos_p).read().split('\n')) if os.path.exists(hechos_p) else set()
        if not hechos and len(os.listdir(self.carpeta)) > 1:
            hechos = set(self.cars[:2])  # sacados antes de llevar la lista
            with open(hechos_p, 'w') as f:
                f.write(''.join(c + '\n' for c in hechos))
        for car in self.cars:
            if os.path.exists(car) and car not in hechos:
                with open(hechos_p, 'a') as f:
                    f.write(car + '\n')
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
        if not candidatos and nombre.startswith('NS'):
            # Las del sistema van sin el «NS» en el catálogo (NSToolbarDelete → ToolbarDelete).
            return self.ruta(nombre[2:])
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
        w.set_xalign({'derecha': 1, 'centro': 0.5}.get(p.get('alineacion'), 0))
        if p.get('letra') and p['letra'][1]:
            nombre = p['letra'][0] or ''
            peso = 'Light' if 'Thin' in nombre or 'Light' in nombre else ('Bold' if 'Bold' in nombre else '')
            w.override_font(Pango.FontDescription('%s %g' % (peso, p['letra'][1])))
    elif c == 'NSBox':
        # Sin el nombre de la clase: en la Mac una caja no lleva rótulo salvo que tenga título.
        w = Gtk.Frame(label=p.get('titulo') if p.get('titulo') not in (None, 'Box', 'Title') else None)
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
            im = imagen(imgs, s.get('imagen'), (16, 16))
            b = Gtk.ToggleButton(label=None if im else (s.get('titulo') or ''))
            if im:
                b.set_image(im)
            b.set_tooltip_text(s.get('ayuda') or s.get('titulo') or '')
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
    elif c == 'NSTextView':
        w = Gtk.TextView()
        w.get_buffer().set_text(texto or '')
    return w


def pintar(n, imgs, fijo, x0=0.0, y0=0.0, marcar=None):
    """Pone cada vista en su marco. Las que tienen subvistas llevan su propio Gtk.Layout, que
    recorta como AppKit: una subvista más grande que su padre no se sale de él."""
    imgs = n.get('_imgs', imgs)
    if n['props'].get('oculta'):
        return
    m = n['props'].get('marco')
    if m:
        x, y = x0 + m[0], y0 + m[1]
        w = widget(n, imgs)
        ancho, alto = max(1, int(m[2])), max(1, int(m[3]))
        if w is None and n['clase'] not in ('NSView', 'NSClipView', 'NSScrollView', 'NSTabView'):
            # Sin rótulo: el nombre de la clase, al pasar el ratón y en el Inspector.
            w = Gtk.Frame()
            w.set_tooltip_text(n['props'].get('clase_propia') or n['clase'])
            w.get_style_context().add_class('visor-nib-recuadro')
        if w is not None:
            w.set_size_request(ancho, alto)
            fijo.put(w, int(x), int(y))
            if marcar is not None:
                marcar[id(n)] = w
            if n['clase'] in ('NSTableView', 'NSOutlineView', 'NSPopUpButton', 'NSSegmentedControl'):
                return
        if any(h['clase'] not in ('NSMenu', 'NSToolbar') for h in n['hijos']):
            capa = Gtk.Layout()
            capa.set_size(ancho, alto)
            capa.set_size_request(ancho, alto)
            fijo.put(capa, int(x), int(y))
            fijo, x, y = capa, 0, 0
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
        if ident == 'NSToolbarSpaceItem':
            hueco = Gtk.Box()
            hueco.set_size_request(16, -1)
            caja.pack_start(hueco, False, False, 0)
            continue
        if ident == 'NSToolbarSeparatorItem':
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
    if raiz['clase'] == 'SwiftUI':
        return lienzo_swiftui(raiz, marcar)
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
            pintar(h, contenido.get('_imgs', imgs), fijo, 0, 0, marcar)
    else:
        pintar(dict(raiz, props=dict(raiz['props'], marco=[0, 0, m[2], m[3]])), imgs, fijo, 0, 0, marcar)
    caja.pack_start(fijo, False, False, 0)
    return caja


# --- SwiftUI ----------------------------------------------------------------------

def hijos_planos(n):
    """Los hijos de una vista, con las tuplas (TupleView) abiertas en el mismo nivel."""
    out = []
    for h in n['hijos']:
        if h['clase'] in ('Tupla', 'FormFooterContent'):
            out.extend(hijos_planos(h))
        elif h['clase'] != 'EmptyView':
            out.append(h)
    return out


def texto_de(n):
    """La etiqueta de un control: no hay cadenas en la metadata, así que dice qué es."""
    for h in hijos_planos(n):
        if h['clase'] == 'Text':
            return 'Text'
        if h['clase'] == 'Label':
            return 'Label'
    return n['clase']


def fila(etiqueta, control):
    caja = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
    if etiqueta is not None:
        caja.pack_start(etiqueta, True, True, 0)
    if control is not None:
        caja.pack_end(control, False, False, 0)
    return caja


def etiqueta(texto, clase='visor-swiftui-texto'):
    w = Gtk.Label(label=texto)
    w.set_xalign(0)
    w.get_style_context().add_class(clase)
    return w


def ui_gtk(n, marcar, horizontal=False):
    """Un nodo de swiftui.a_ui como widget de GTK, con el aspecto de un panel de System Settings
    (Form agrupado: secciones redondeadas y una fila por control)."""
    c = n['clase']
    mods = ' '.join(n['props'].get('modificadores', []))
    hijos = hijos_planos(n)
    w = None
    if c in ('Form', 'List', 'ScrollView'):
        w = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
        w.set_border_width(20)
        for h in hijos:
            w.pack_start(ui_gtk(h, marcar), False, False, 0)
    elif c == 'Section':
        # Section<cabecera, contenido, pie>
        w = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        partes = [h for h in n['hijos']]
        cab = partes[0] if len(partes) == 3 else None
        cont = partes[1] if len(partes) == 3 else n
        pie = partes[2] if len(partes) == 3 else None
        if cab and cab['clase'] != 'EmptyView':
            w.pack_start(etiqueta('Section header', 'visor-swiftui-cabecera'), False, False, 0)
        caja = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        caja.get_style_context().add_class('visor-swiftui-seccion')
        filas = hijos_planos(cont) if cont is not n else hijos
        for i, h in enumerate(filas):
            if i:
                caja.pack_start(Gtk.Separator(), False, False, 0)
            f = ui_gtk(h, marcar, True)
            f.set_margin_start(10)
            f.set_margin_end(10)
            f.set_margin_top(7)
            f.set_margin_bottom(7)
            caja.pack_start(f, False, False, 0)
        w.pack_start(caja, False, False, 0)
        if pie and pie['clase'] != 'EmptyView':
            w.pack_start(etiqueta('Section footer', 'visor-swiftui-pie'), False, False, 0)
    elif c in ('VStack', 'LazyVStack', 'ForEach', 'Grid', 'GroupBox', 'DisclosureGroup', 'NavigationStack', 'Vista',
               'Incompleto', 'ZStack', 'GeometryReader'):
        w = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        for h in hijos:
            w.pack_start(ui_gtk(h, marcar), False, False, 0)
        if c == 'ForEach':
            w.get_style_context().add_class('visor-swiftui-foreach')
    elif c in ('HStack', 'LazyHStack', 'GridRow', 'ControlGroup'):
        w = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        for h in hijos:
            x = ui_gtk(h, marcar, True)
            w.pack_start(x, h['clase'] == 'Spacer', h['clase'] == 'Spacer', 0)
    elif c == 'LabeledContent':
        partes = hijos
        izq = ui_gtk(partes[0], marcar) if partes else None
        der = ui_gtk(partes[1], marcar, True) if len(partes) > 1 else None
        w = fila(izq, der)
    elif c == 'Toggle':
        sw = Gtk.Switch()
        sw.set_valign(Gtk.Align.CENTER)
        w = fila(etiqueta(texto_de(n)), sw) if 'checkbox' not in mods.lower() else Gtk.CheckButton(label=texto_de(n))
    elif c == 'Picker':
        if 'InlinePickerStyle' in mods or 'RadioGroup' in mods:
            w = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
            w.pack_start(etiqueta(texto_de(n)), False, False, 0)
            g = None
            for k in range(2):
                r = Gtk.RadioButton.new_with_label_from_widget(g, 'Option %d' % (k + 1))
                g = g or r
                w.pack_start(r, False, False, 0)
        else:
            combo = Gtk.ComboBoxText()
            combo.append_text('Option')
            combo.set_active(0)
            w = fila(etiqueta(texto_de(n)), combo)
    elif c == 'Button':
        dentro = hijos
        if dentro and dentro[0]['clase'] not in ('Text', 'Label'):
            w = Gtk.Button()
            w.add(ui_gtk(dentro[0], marcar))
            w.set_relief(Gtk.ReliefStyle.NONE if 'Plain' in mods else Gtk.ReliefStyle.NORMAL)
        else:
            w = Gtk.Button(label='Button')
        w.set_halign(Gtk.Align.START if not horizontal else Gtk.Align.CENTER)
    elif c == 'HelpLink':
        w = Gtk.Button(label='?')
        w.get_style_context().add_class('visor-swiftui-ayuda')
        w.set_halign(Gtk.Align.END)
    elif c == 'Text':
        w = etiqueta('Text')
    elif c == 'Label':
        w = Gtk.Box(spacing=6)
        w.pack_start(Gtk.Image.new_from_icon_name('image-x-generic-symbolic', Gtk.IconSize.MENU), False, False, 0)
        w.pack_start(etiqueta('Label'), False, False, 0)
    elif c == 'Image':
        w = Gtk.Image.new_from_icon_name('image-x-generic-symbolic', Gtk.IconSize.LARGE_TOOLBAR)
    elif c == 'Spacer':
        w = Gtk.Box()
    elif c == 'Divider':
        w = Gtk.Separator()
    elif c == 'Slider':
        w = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0, 1, 0.1)
        w.set_draw_value(False)
        w.set_size_request(180, -1)
    elif c == 'Stepper':
        w = Gtk.SpinButton.new_with_range(0, 100, 1)
    elif c in ('TextField', 'SecureField', 'TextEditor'):
        w = Gtk.Entry()
        w.set_visibility(c != 'SecureField')
    elif c in ('ProgressView', 'Gauge'):
        w = Gtk.ProgressBar()
    elif c in ('Color', 'Circle', 'Rectangle', 'RoundedRectangle', 'Capsule'):
        w = Gtk.Box()
        w.set_size_request(16, 16)
        w.get_style_context().add_class('visor-swiftui-forma')
    elif c in ('DatePicker', 'ColorPicker'):
        w = Gtk.Button(label=c)
    else:
        # Una vista de SwiftUI que no conozco: sus hijos, en columna, con el nombre al pasar el ratón.
        w = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL if horizontal else Gtk.Orientation.VERTICAL, spacing=6)
        for h in hijos:
            w.pack_start(ui_gtk(h, marcar, horizontal), False, False, 0)
        if not hijos:
            w.pack_start(etiqueta(c, 'visor-swiftui-desconocido'), False, False, 0)
    if n['props'].get('condicional'):
        # Sale solo a veces (un if sin else): atenuada, para no confundirla con lo de siempre.
        w.set_opacity(0.35)
        mods = ('solo a veces (if) ' + mods).strip()
    w.set_tooltip_text('%s%s%s' % (n['props'].get('vista', '') + ' — ' if n['props'].get('vista') else '', c,
                                     ('\n' + mods) if mods else ''))
    if marcar is not None:
        marcar[id(n)] = w
    return w


def lienzo_swiftui(raiz, marcar=None):
    caja = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
    caja.get_style_context().add_class('visor-swiftui-fondo')
    caja.set_size_request(520, -1)
    for h in raiz['hijos']:
        caja.pack_start(ui_gtk(h, marcar), False, False, 0)
    return caja


# Las teclas como las escribe la Mac → el nombre de GDK.
TECLAS_GDK = {'⌫': 'BackSpace', '⎋': 'Escape', '↩': 'Return', '⇥': 'Tab', 'Space': 'space', '↑': 'Up',
              '↓': 'Down', '←': 'Left', '→': 'Right', '⌦': 'Delete', '↖': 'Home', '↘': 'End',
              '⇞': 'Page_Up', '⇟': 'Page_Down'}


def tecla_gdk(atajo):
    """«⌥⌘I» → (keyval, mods) para GTK. ⌘ es Ctrl (keyd); ⌃ también cae en Ctrl."""
    mods = Gdk.ModifierType(0)
    i = 0
    while i < len(atajo) and atajo[i] in '⌃⌥⇧⌘':
        mods |= {'⌃': Gdk.ModifierType.CONTROL_MASK, '⌥': Gdk.ModifierType.MOD1_MASK,
                 '⇧': Gdk.ModifierType.SHIFT_MASK, '⌘': Gdk.ModifierType.CONTROL_MASK}[atajo[i]]
        i += 1
    t = atajo[i:]
    if t in TECLAS_GDK:
        k = Gdk.keyval_from_name(TECLAS_GDK[t])
    elif re.fullmatch(r'F\d+', t):
        k = Gdk.keyval_from_name(t)
    elif len(t) == 1:
        k = Gdk.unicode_to_keyval(ord(t.lower()))
    else:
        return None
    return (k, mods) if k and Gtk.accelerator_valid(k, mods) else None


def barra_de_menus(menu, grupo=None, acciones=None):
    """El NSMenu principal como Gtk.MenuBar; con appmenu-gtk-module sale en la barra de arriba.
    acciones: {título: función} para los pocos ítems que hacen algo (Quit)."""
    barra = Gtk.MenuBar()
    acciones = acciones or {}

    def llenar(gmenu, nodo):
        for it in nodo['hijos']:
            p = it['props']
            if it['clase'] != 'NSMenuItem' or p.get('oculto'):
                continue
            if p.get('separador') or not p.get('titulo'):
                gmenu.append(Gtk.SeparatorMenuItem())
                continue
            mi = Gtk.MenuItem(label=p['titulo'])
            mi.set_use_underline(False)
            if p.get('atajo') and grupo is not None:
                t = tecla_gdk(p['atajo'])
                if t:
                    mi.add_accelerator('activate', grupo, t[0], t[1], Gtk.AccelFlags.VISIBLE)
            f = next((f for k, f in acciones.items() if p['titulo'].startswith(k)), None)
            if f:
                mi.connect('activate', lambda _m, f=f: f())
            sub = next((h for h in it['hijos'] if h['clase'] == 'NSMenu'), None)
            if sub:
                g = Gtk.Menu()
                if grupo is not None:
                    g.set_accel_group(grupo)
                llenar(g, sub)
                mi.set_submenu(g)
            gmenu.append(mi)

    llenar(barra, menu)
    return barra


def nombre_de(n):
    p = n['props']
    return '%s  %s' % (n['clase'], p.get('titulo') or p.get('texto') or p.get('clase_propia') or p.get('identificador') or '')


class VentanaMac(Gtk.Window):
    """La ventana de la app como en la Mac, con el menú de la app; el Inspector va aparte."""

    def __init__(self, app):
        super().__init__(title=app.nombre)
        self.app = app
        self.ventanas = app.ventanas()
        if app.icono:
            try:
                self.set_icon(GdkPixbuf.Pixbuf.new_from_file_at_size(app.icono, 128, 128))
            except GLib.Error:
                pass
        self.grupo = Gtk.AccelGroup()
        self.add_accel_group(self.grupo)
        caja = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.add(caja)
        menu = app.menu_principal()
        barra = barra_de_menus(menu, self.grupo, {'Quit ': Gtk.main_quit}) if menu else Gtk.MenuBar()
        self._menu_window(barra)
        caja.pack_start(barra, False, False, 0)
        self.sitio = Gtk.ScrolledWindow()
        self.sitio.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        caja.pack_start(self.sitio, True, True, 0)
        self.inspector = Inspector(self)
        self.actual = None
        self.marcados = {}

    def _menu_window(self, barra):
        """Al menú Window de la app (o a uno nuevo) se le añaden el Inspector y las ventanas."""
        window = next((mi for mi in barra.get_children() if mi.get_label() == 'Window'), None)
        if window is None:
            window = Gtk.MenuItem(label='Window')
            barra.append(window)
        sub = window.get_submenu()
        if sub is None:
            sub = Gtk.Menu()
            window.set_submenu(sub)
        sub.set_accel_group(self.grupo)
        sub.append(Gtk.SeparatorMenuItem())
        mi = Gtk.MenuItem(label='Inspector del visor')
        k, m = tecla_gdk('⌥⌘I')
        mi.add_accelerator('activate', self.grupo, k, m, Gtk.AccelFlags.VISIBLE)
        mi.connect('activate', lambda _m: (self.inspector.show_all(), self.inspector.present()))
        sub.append(mi)
        # En el menú, las ventanas; las vistas sueltas, solo en el Inspector.
        solo = [(i, v) for i, v in enumerate(self.ventanas) if not v.get('vista')]
        lista = Gtk.MenuItem(label='Ventanas de %s (%d)' % (self.app.nombre, len(solo)))
        g = Gtk.Menu()
        grupo = None
        self.radios = {}
        for i, v in solo:
            r = Gtk.RadioMenuItem.new_with_label_from_widget(grupo, v['etiqueta'])
            grupo = grupo or r
            r.connect('toggled', lambda w, i=i: w.get_active() and self.mostrar(i))
            self.radios[i] = r
            g.append(r)
        lista.set_submenu(g)
        sub.append(lista)

    def mostrar(self, i):
        if i is None or i == self.actual:
            return
        self.actual = i
        v = self.ventanas[i]
        raiz = v['raiz']
        self.set_title(raiz['props'].get('titulo') or self.app.nombre)
        for h in self.sitio.get_children():
            self.sitio.remove(h)
        self.marcados = {}
        w = lienzo(raiz, v['imgs'], self.marcados)
        self.sitio.add(w)
        self.sitio.show_all()
        # A su tamaño en puntos (lo que quepa en la pantalla).
        _, nat = w.get_preferred_size()
        pantalla = Gdk.Screen.get_default()
        self.resize(min(nat.width + 2, pantalla.get_width() - 40), min(nat.height + 2, pantalla.get_height() - 80))
        if i in self.radios and not self.radios[i].get_active():
            self.radios[i].set_active(True)
        self.inspector.cargar(i)

    def marcar(self, n):
        for w in self.marcados.values():
            w.get_style_context().remove_class('visor-nib-elegido')
        w = self.marcados.get(id(n))
        if w:
            w.get_style_context().add_class('visor-nib-elegido')


class Inspector(Gtk.Window):
    """El selector de ventanas, el árbol de la que se ve y las propiedades del objeto elegido."""

    def __init__(self, principal):
        super().__init__(title='Inspector — %s' % principal.app.nombre)
        self.principal = principal
        self.set_transient_for(principal)
        self.set_type_hint(Gdk.WindowTypeHint.UTILITY)
        self.set_default_size(440, 720)
        self.connect('delete-event', lambda w, _e: w.hide() or True)
        caja = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        caja.set_border_width(6)
        self.add(caja)
        self.combo = Gtk.ComboBoxText()
        for v in principal.ventanas:
            self.combo.append_text(v['etiqueta'])
        self.combo.connect('changed', lambda c: self.principal.mostrar(c.get_active()))
        caja.pack_start(self.combo, False, False, 0)
        self.nib = Gtk.Label(xalign=0)
        self.nib.set_selectable(True)
        self.nib.set_line_wrap(True)
        caja.pack_start(self.nib, False, False, 0)
        panel = Gtk.Paned(orientation=Gtk.Orientation.VERTICAL)
        caja.pack_start(panel, True, True, 0)
        self.modelo = Gtk.TreeStore(str, object)
        self.arbol = Gtk.TreeView(model=self.modelo)
        self.arbol.append_column(Gtk.TreeViewColumn('Objeto', Gtk.CellRendererText(), text=0))
        self.arbol.get_selection().connect('changed', self._elegido)
        s = Gtk.ScrolledWindow()
        s.add(self.arbol)
        panel.pack1(s, True, False)
        self.props_modelo = Gtk.ListStore(str, str)
        tp = Gtk.TreeView(model=self.props_modelo)
        tp.append_column(Gtk.TreeViewColumn('Propiedad', Gtk.CellRendererText(), text=0))
        tp.append_column(Gtk.TreeViewColumn('Valor', Gtk.CellRendererText(), text=1))
        s2 = Gtk.ScrolledWindow()
        s2.add(tp)
        panel.pack2(s2, True, False)
        panel.set_position(440)

    def cargar(self, i):
        v = self.principal.ventanas[i]
        if self.combo.get_active() != i:
            self.combo.set_active(i)
        r = v['raiz']['props']
        if v['raiz']['clase'] == 'SwiftUI':
            textos = r.get('textos') or []
            self.nib.set_text('SwiftUI, desde la metadata de tipos de %s.\nTextos del panel (%d): %s' % (
                os.path.basename(self.principal.app.swiftui[2]), len(textos), ' · '.join(textos)[:1500]))
        elif r.get('receta'):
            self.nib.set_text('Compuesta con %s:\n%s' % (r['receta'], '\n'.join(r.get('piezas', []))))
        else:
            self.nib.set_text('Nib: %s' % self.principal.app.ruta_de(v['nib']))
        self.modelo.clear()
        self._poner(None, v['raiz'])
        self.arbol.expand_row(Gtk.TreePath(0), False)

    def _poner(self, padre, n):
        it = self.modelo.append(padre, [nombre_de(n), n])
        for h in n['hijos']:
            self._poner(it, h)

    def _elegido(self, sel):
        m, it = sel.get_selected()
        if it is None:
            return
        n = m[it][1]
        self.props_modelo.clear()
        self.props_modelo.append(['clase', n['clase']])
        for k, v in n['props'].items():
            self.props_modelo.append([k, json.dumps(v, ensure_ascii=False) if not isinstance(v, str) else v])
        self.principal.marcar(n)


CSS = b'''
.visor-nib-recuadro { border: 1px dashed alpha(#888, 0.35); }
.visor-nib-recuadro > label { font-size: 8pt; color: #888; }
.visor-nib-elegido { box-shadow: inset 0 0 0 2px #3478f6; }
.visor-swiftui-seccion { border-radius: 8px; background: alpha(@theme_fg_color, 0.04); border: 1px solid alpha(@theme_fg_color, 0.09); }
.visor-swiftui-cabecera { font-weight: bold; margin-left: 4px; }
.visor-swiftui-pie, .visor-swiftui-desconocido { font-size: 9pt; color: alpha(@theme_fg_color, 0.55); }
.visor-swiftui-texto { color: alpha(@theme_fg_color, 0.85); }
.visor-swiftui-ayuda { border-radius: 50%; min-width: 22px; min-height: 22px; padding: 0; }
.visor-swiftui-forma { border-radius: 50%; background: alpha(@theme_selected_bg_color, 0.8); }
.visor-swiftui-foreach { border-left: 2px dotted alpha(@theme_fg_color, 0.15); padding-left: 4px; }
'''


def estilo():
    css = Gtk.CssProvider()
    css.load_from_data(CSS)
    Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)


def a_png(ruta, carpeta):
    """A PNG sin enseñar nada (Gtk.OffscreenWindow): de un nib, cada ventana y vista suelta; de
    una .app, la ventana con la que abre."""
    estilo()
    os.makedirs(carpeta, exist_ok=True)
    app = AppMac(ruta)
    ventanas = app.ventanas()
    if app.ruta:
        i = app.inicial(ventanas)
        ventanas = [ventanas[i]] if i is not None else []
    hechos = []
    for i, v in enumerate(ventanas):
        r = v['raiz']
        off = Gtk.OffscreenWindow()
        off.add(lienzo(r, v['imgs']))
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
    app = AppMac(ruta)
    # El nombre de la app en la barra de arriba y en el Dock, como la de la Mac.
    GLib.set_prgname(app.nombre)
    GLib.set_application_name(app.nombre)
    Gdk.set_program_class(app.nombre)
    estilo()
    v = VentanaMac(app)
    v.connect('destroy', Gtk.main_quit)
    v.show_all()
    v.mostrar(app.inicial(v.ventanas))
    # Solo la ventana de la app, con el foco: el Inspector sale con Window ▸ Inspector (⌥⌘I).
    v.present()
    Gtk.main()


if __name__ == '__main__':
    main()
