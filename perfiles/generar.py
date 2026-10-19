#!/usr/bin/env python3
"""Genera los perfiles de versión de macOS (ver ESQUEMA.md) desde el disco de la Mac o desde las
referencias de extraer-mac. Lo que sale tiene textos y menús de Apple: va a
~/.local/share/mint-macos/macos/<versión>/, nunca al repo.

    perfiles/generar.py                      todas las versiones que tengan fuente aquí
    perfiles/generar.py --version sequoia-15.8.1
    perfiles/generar.py --version X --sistema RAIZ [RAIZ…] [--medidas medidas.json]

Cada RAIZ tiene System/… (el disco de la Mac montado, o recursos/sistema-nib de una referencia).
Si un archivo está en varias raíces, gana la primera.
"""
import json
import os
import plistlib
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(AQUI), 'herramientas', 'visor-nib'))
import nib  # noqa: E402

MM = os.path.expanduser('~/.local/share/mint-macos')
REF = os.path.join(MM, 'referencias')
SALIDA = os.path.join(MM, 'macos')

# Las versiones que manejamos y de dónde salen aquí.
VERSIONES = {
    'catalina-10.15': {'nombre': 'macOS Catalina', 'numero': '10.15.8',
                       'raices': [os.path.join(MM, 'montajes', 'disco-mac-sistema')],
                       'medidas': os.path.join(REF, 'catalina-extraer-20261015', 'medidas', 'medidas.json'),
                       'capturas': None},
    'monterey-12.7.6': {'nombre': 'macOS Monterey', 'numero': '12.7.6',
                        'raices': [os.path.join(REF, 'monterey-20261015', 'recursos', 'sistema-nib')],
                        'medidas': os.path.join(REF, 'monterey-20261015', 'medidas', 'medidas.json'),
                        'capturas': os.path.join(REF, 'monterey-20261015', 'capturas')},
    'sequoia-15.8.1': {'nombre': 'macOS Sequoia', 'numero': '15.8.1',
                       'raices': [os.path.join(REF, 'sequoia-15.8.1-20261016', 'recursos', 'sistema-swiftui'),
                                  os.path.join(REF, 'sequoia-15.8.1-20261016', 'recursos', 'sistema-nib')],
                       'medidas': os.path.join(REF, 'sequoia-15.8.1-20261016', 'medidas', 'medidas.json'),
                       'capturas': os.path.join(REF, 'sequoia-15.8.1-20261016', 'capturas')},
    'macos-27': {'nombre': 'macOS 27', 'numero': '27.0',
                 'raices': [os.path.join(REF, 'macos27-20261014', 'recursos', 'sistema-nib')],
                 'medidas': os.path.join(REF, 'macos27-20261014', 'medidas', 'medidas.json'),
                 'capturas': os.path.join(REF, 'macos27-20261014', 'capturas')},
}

HITOOLBOX = 'System/Library/Frameworks/Carbon.framework/Versions/A/Frameworks/HIToolbox.framework/Versions/A/Resources'
APPKIT = 'System/Library/Frameworks/AppKit.framework/Versions/C/Resources'
TEXTEDIT = 'System/Applications/TextEdit.app/Contents/Resources/Base.lproj/Edit.nib'

# Menú Apple: el código de Carbon de cada ítem → la clave de su texto en Menus.loctable de AppKit
# (desde Ventura el menú Apple lo arma AppKit y el texto sale de ahí, no del xib de HIToolbox, que
# en Sequoia sigue diciendo «System Preferences…»).
CLAVES_APPLE = {'abtm': 'About This Mac', 'spro': 'System Information', 'sysp': 'System Settings...',
                'soft': 'App Store', 'rcnt': 'Recent Items', 'apwn': 'Force Quit...', 'exit': 'Force Quit %@',
                'slep': 'Sleep', 'rrst': 'Restart...', 'rest': 'Restart', 'rsdn': 'Shut Down...', 'shut': 'Shut Down',
                'lock': 'Lock Screen', 'logo': 'Log Out %@...', 'rlgo': 'Log Out %@', 'loca': 'Location (%@)'}
# Lo que dicen las capturas y no los archivos (gana la captura).
CAPTURAS_APPLE = {
    # Menus.loctable trae «App Store» y «App Store…»; la captura de Sequoia enseña el primero.
    'sequoia-15.8.1': {'soft': ('App Store', '02-barra-menu-apple-abierto-claro.png')},
}
VARIABLES = {'logo': {'%@': 'nombre completo del usuario'}, 'rlgo': {'%@': 'nombre completo del usuario'},
             'exit': {'%@': 'nombre de la app al frente'}, 'loca': {'%@': 'ubicación de red'}}


def buscar(raices, rel):
    for r in raices:
        p = os.path.join(r, rel)
        if os.path.exists(p):
            return p
    return None


def loctable(ruta):
    try:
        return plistlib.load(open(ruta, 'rb')).get('en', {})
    except (OSError, ValueError):
        return {}


def mods_de(atajo_a, atajo_b):
    """Los modificadores que tiene b y no a (el ⌥ de un alterno)."""
    ma = set(c for c in (atajo_a or '') if c in '⌃⌥⇧⌘')
    mb = set(c for c in (atajo_b or '') if c in '⌃⌥⇧⌘')
    return ''.join(c for c in '⌃⌥⇧⌘' if c in mb - ma) or '⌥'


def menu_apple(version, raices):
    xib = buscar(raices, os.path.join(HITOOLBOX, 'English.lproj', 'StandardMenus.nib', 'objects.xib'))
    if not xib:
        return None
    menus = nib.menus_carbon(xib)
    apple = next((m for m in menus if m['props'].get('menu_id') == '-21629'), None)
    if apple is None:
        return None
    lt_ruta = buscar(raices, os.path.join(APPKIT, 'Menus.loctable'))
    lt = loctable(lt_ruta) if lt_ruta else {}
    capturas = CAPTURAS_APPLE.get(version, {})
    items, anterior = [], None
    for it in apple['hijos']:
        p = it['props']
        if p.get('separador'):
            if not p.get('oculto'):
                items.append({'separador': True})
            anterior = None
            continue
        c = p.get('comando')
        e = {'id': c, 'texto': p.get('titulo'), 'fuente': 'HIToolbox StandardMenus.nib'}
        if c in CLAVES_APPLE and CLAVES_APPLE[c] in lt:
            e['texto'] = lt[CLAVES_APPLE[c]]
            e['fuente'] += '; AppKit Menus.loctable'
        if c in capturas:
            e['texto'], cap = capturas[c]
            e['fuente'] = 'captura %s' % cap
        if p.get('atajo'):
            e['atajo'] = p['atajo']
        if c in VARIABLES:
            e['variables'] = VARIABLES[c]
        if p.get('oculto') or c == 'loca':
            # Location solo sale con más de una ubicación de red.
            e['oculto'] = True
        # Un dinámico detrás de otro dinámico es su alterno (sale con ⌥), salvo que diga lo contrario.
        if p.get('dinamico') and anterior is not None and anterior[1].get('dinamico') and not p.get('no_alterno') \
                and 'alterno_de' not in anterior[0]:
            e['alterno_de'] = anterior[0]['id']
            e['mods_alterno'] = mods_de(anterior[0].get('atajo'), e.get('atajo')) if e.get('atajo') else '⌥'
        if p.get('cabecera'):
            e['cabecera'] = True
        sub = next((h for h in it['hijos'] if h['clase'] == 'NSMenu'), None)
        if sub:
            e['submenu'] = [{'id': s['props'].get('comando'), 'texto': s['props'].get('titulo'),
                             **({'cabecera': True} if s['props'].get('cabecera') else {})}
                            if not s['props'].get('separador') else {'separador': True} for s in sub['hijos']]
        items.append(e)
        anterior = (e, p)
    return {'id': 'menu-apple', 'items': items}


def menus_estandar(version, raices):
    """Los menús que AppKit pone en todas las apps, sacados del MainMenu de TextEdit: el menú de la
    app (con %@ por el nombre), File, Edit, Format, View, Window y Help. El id de cada ítem es su
    acción (terminate:, performClose:…)."""
    ruta = buscar(raices, TEXTEDIT)
    if not ruta:
        return None
    ruta = nib.os.path.join(ruta, 'keyedobjects.nib') if os.path.isdir(ruta) else ruta
    raices_nib = [x for x in nib.abrir(ruta).raices() if x['clase'] == 'NSMenu']
    barra = max(raices_nib, key=lambda x: len(x['hijos']))
    mc_ruta = buscar(raices, os.path.join(APPKIT, 'MenuCommands.loctable'))
    mc = loctable(mc_ruta) if mc_ruta else {}
    menus = []
    for i, top in enumerate(barra['hijos']):
        sub = next((h for h in top['hijos'] if h['clase'] == 'NSMenu'), None)
        nombre = top['props'].get('titulo') or ''
        m = {'id': 'app' if i == 0 else nombre.lower(), 'texto': '%@' if i == 0 else nombre, 'items': []}
        for it in (sub['hijos'] if sub else []):
            p = it['props']
            if p.get('oculto'):
                continue
            if p.get('separador') or not p.get('titulo'):
                m['items'].append({'separador': True})
                continue
            t = p['titulo'].replace('TextEdit', '%@') if i == 0 else p['titulo']
            e = {'id': p.get('accion') or 'titulo:' + p['titulo'], 'texto': t, 'fuente': 'TextEdit Edit.nib'}
            if p.get('atajo'):
                e['atajo'] = p['atajo']
            # Desde Ventura, AppKit cambia «Preferences…» (⌘,) por «Settings…» al correr.
            if t == 'Preferences…' and 'Settings\\U2026' in mc:
                e['texto'] = mc['Settings\\U2026']
                e['fuente'] = 'AppKit MenuCommands.loctable (lo cambia AppKit al correr)'
            if '%@' in e['texto']:
                e['variables'] = {'%@': 'nombre de la app'}
            hijo = next((h for h in it['hijos'] if h['clase'] == 'NSMenu'), None)
            if hijo:
                e['submenu'] = [{'id': s['props'].get('accion') or 'titulo:' + (s['props'].get('titulo') or ''),
                                 'texto': s['props'].get('titulo'), **({'atajo': s['props']['atajo']} if s['props'].get('atajo') else {})}
                                if s['props'].get('titulo') else {'separador': True}
                                for s in hijo['hijos'] if not s['props'].get('oculto')]
            m['items'].append(e)
        menus.append(m)
    return {'id': 'menus-estandar', 'menus': menus,
            'nota': 'Del MainMenu de TextEdit. Lo que AppKit agrega al correr (en Sequoia: Window ▸ Move & Resize, '
                    'Fill & Arrange…) no está en el nib: se completa desde las capturas.'}


def generar(version, raices=None, medidas=None):
    v = VERSIONES.get(version, {'nombre': version, 'numero': '', 'raices': [], 'medidas': None})
    raices = [r for r in (raices or v['raices']) if os.path.isdir(r)]
    destino = os.path.join(SALIDA, version)
    os.makedirs(os.path.join(destino, 'apps'), exist_ok=True)
    partes = {}

    def guardar(nombre, datos):
        if datos is None:
            partes[nombre] = 'falta: sin fuente en %s' % (raices or 'ninguna raíz')
            return
        with open(os.path.join(destino, 'apps', nombre + '.json'), 'w') as f:
            json.dump(datos, f, ensure_ascii=False, indent=1)
        partes[nombre] = 'ok'

    guardar('menu-apple', menu_apple(version, raices))
    guardar('menus-estandar', menus_estandar(version, raices))
    med = medidas or v.get('medidas')
    try:
        datos = json.load(open(med)) if med else None
    except (OSError, ValueError):
        datos = None  # el de Catalina salió vacío de extraer-mac
    if datos:
        with open(os.path.join(destino, 'medidas.json'), 'w') as f:
            json.dump(datos, f, ensure_ascii=False, indent=1)
        partes['medidas'] = 'ok'
    else:
        partes['medidas'] = 'falta: %s vacío o sin leer' % med
    info = {'id': version, 'nombre': v['nombre'], 'numero': v['numero'], 'raices': raices, 'partes': partes}
    with open(os.path.join(destino, 'version.json'), 'w') as f:
        json.dump(info, f, ensure_ascii=False, indent=1)
    return info


def main():
    args = sys.argv[1:]
    version = args[args.index('--version') + 1] if '--version' in args else None
    raices = None
    if '--sistema' in args:
        i = args.index('--sistema') + 1
        raices = []
        while i < len(args) and not args[i].startswith('--'):
            raices.append(args[i])
            i += 1
    medidas = args[args.index('--medidas') + 1] if '--medidas' in args else None
    for v in ([version] if version else list(VERSIONES)):
        info = generar(v, raices, medidas)
        print('%s: %s' % (v, ', '.join('%s %s' % (k, e) for k, e in info['partes'].items())))


if __name__ == '__main__':
    main()
