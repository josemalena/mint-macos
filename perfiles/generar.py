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
import shutil
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(AQUI), 'herramientas', 'visor-nib'))
import nib  # noqa: E402
import swiftui  # noqa: E402
sys.path.insert(0, AQUI)
import vocabulario  # noqa: E402

MM = os.path.expanduser('~/.local/share/mint-macos')
REF = os.path.join(MM, 'referencias')
SALIDA = os.path.join(MM, 'macos')

# Las versiones que manejamos y de dónde salen aquí.
def _ultima(patron):
    """La referencia más nueva de una versión («highsierra-*»), o la ruta del patrón si no hay."""
    import glob as _g
    hay = sorted(_g.glob(os.path.join(REF, patron)))
    return hay[-1] if hay else os.path.join(REF, patron)


VERSIONES = {
    # La MacBook Pro Early 2011 de la esposa de José (José, 18-10-2026): menos prioridad que Catalina.
    'highsierra-10.13': {'tema': 'Constanza', 'nombre': 'macOS High Sierra', 'numero': '10.13.6',
                         'raices': [os.path.join(_ultima('highsierra-*'), 'recursos', 'sistema-nib')],
                         'medidas': os.path.join(_ultima('highsierra-*'), 'medidas', 'medidas.json'),
                         'capturas': os.path.join(_ultima('highsierra-*'), 'capturas')},
    'catalina-10.15': {'tema': 'Constanza', 'nombre': 'macOS Catalina', 'numero': '10.15.8',
                       'raices': [os.path.join(MM, 'montajes', 'disco-mac-sistema')],
                       'medidas': os.path.join(REF, 'catalina-extraer-20261015', 'medidas', 'medidas.json'),
                       'capturas': None},
    'monterey-12.7.6': {'tema': 'Samana', 'nombre': 'macOS Monterey', 'numero': '12.7.6',
                        # sistema-xml: los NSPrefPaneGroups*.xml de la tanda del 26-10 (el del 15-10 no los traía)
                        'raices': [os.path.join(REF, 'monterey-20261015', 'recursos', 'sistema-nib'),
                                   os.path.join(REF, 'monterey-20261026', 'recursos', 'sistema-xml')],
                        'medidas': os.path.join(REF, 'monterey-20261015', 'medidas', 'medidas.json'),
                        'capturas': os.path.join(REF, 'monterey-20261015', 'capturas')},
    'sequoia-15.8.1': {'tema': 'ValleNuevo', 'nombre': 'macOS Sequoia', 'numero': '15.8.1',
                       'raices': [os.path.join(REF, 'sequoia-15.8.1-20261016', 'recursos', 'sistema-swiftui'),
                                  os.path.join(REF, 'sequoia-15.8.1-20261016', 'recursos', 'sistema-nib')],
                       'medidas': os.path.join(REF, 'sequoia-15.8.1-20261016', 'medidas', 'medidas.json'),
                       'capturas': os.path.join(REF, 'sequoia-15.8.1-20261016', 'capturas')},
    'macos-27': {'tema': 'Ozama', 'nombre': 'macOS 27', 'numero': '27.0',
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


PREFAPP = 'System/Applications/System Preferences.app/Contents/Resources'
SETTINGSAPP = 'System/Applications/System Settings.app/Contents/Resources'


def info_bundle(ruta):
    """Info.plist con los textos en inglés por encima (InfoPlist.strings o InfoPlist.loctable)."""
    try:
        info = plistlib.load(open(os.path.join(ruta, 'Contents', 'Info.plist'), 'rb'))
    except (OSError, ValueError):
        return {}
    rec = os.path.join(ruta, 'Contents', 'Resources')
    en = loctable(os.path.join(rec, 'InfoPlist.loctable')) or nib.cadenas_de(os.path.join(rec, 'en.lproj', 'InfoPlist.strings')) \
        or nib.cadenas_de(os.path.join(rec, 'English.lproj', 'InfoPlist.strings'))
    return dict(info, **{k: v for k, v in en.items() if isinstance(v, str)})


def bundles(raices, carpeta, ext):
    """{CFBundleIdentifier: (ruta, info)} de los bundles de una carpeta del sistema, en todas las raíces."""
    out = {}
    for r in raices:
        d = os.path.join(r, carpeta)
        for n in sorted(os.listdir(d)) if os.path.isdir(d) else []:
            if n.endswith(ext):
                info = info_bundle(os.path.join(d, n))
                if info.get('CFBundleIdentifier'):
                    out.setdefault(info['CFBundleIdentifier'], (os.path.join(d, n), info))
    return out


def panel_de(ruta, info, id_propio):
    """Un panel del índice: el id estable (el del prefPane de Catalina, también en Sequoia por
    legacyBundleIdentifier), su nombre como se ve y su ícono."""
    attrs = (info.get('EXAppExtensionAttributes') or {}).get('SettingsExtensionAttributes') or {}
    nombre = info.get('NSPrefPaneIconLabel') or info.get('CFBundleDisplayName') or info.get('CFBundleName')
    nombre = ' '.join((nombre or '').replace('\\n', ' ').split())
    viejo = attrs.get('legacyBundleIdentifier')
    if isinstance(viejo, list):
        # Un panel nuevo que junta varios viejos (General de Sequoia): el primero es su id.
        viejos, viejo = viejo, (viejo[0] if viejo else None)
    else:
        viejos = None
    p = {'id': viejo or id_propio, 'nombre': nombre, 'bundle': os.path.basename(ruta)}
    if viejos and len(viejos) > 1:
        p['ids_viejos'] = viejos
    if not (info.get('NSPrefPaneIconLabel') or info.get('CFBundleDisplayName')):
        # Sin nombre visible en los archivos (la batería de Sequoia se llama según el equipo): el
        # interno, marcado; lo corrige una captura.
        p['nombre_provisional'] = True
    if p['id'] != id_propio:
        p['id_propio'] = id_propio
    grafico = ((info.get('CFBundleIcons') or {}).get('ISGraphicIconConfiguration') or {}).get('ISTypeIdentifier')
    if grafico:
        p['icono'] = {'grafico': grafico}
    elif info.get('NSPrefPaneIconFile') or info.get('CFBundleIconFile'):
        p['icono'] = {'archivo': os.path.join(p['bundle'], 'Contents', 'Resources',
                                              info.get('NSPrefPaneIconFile') or info.get('CFBundleIconFile'))}
    return p


def system_preferences(version, raices):
    """El índice de paneles: la rejilla de System Preferences (Catalina, Monterey:
    NSPrefPaneGroups.xml) o la barra lateral de System Settings (Ventura en adelante: Sidebar.plist)."""
    panes = bundles(raices, 'System/Library/PreferencePanes', '.prefPane')
    sidebar = buscar(raices, os.path.join(SETTINGSAPP, 'Sidebar.plist'))
    if sidebar:
        exts = bundles(raices, 'System/Library/ExtensionKit/Extensions', '.appex')
        exts.update({k: v for k, v in bundles(raices, os.path.join(os.path.dirname(SETTINGSAPP), 'PlugIns'), '.appex').items()
                     if k not in exts})
        grupos = []
        for i, g in enumerate(plistlib.load(open(sidebar, 'rb'))):
            if g.get('catch_all'):
                grupos.append({'id': 'otros', 'titulo': 'Other', 'paneles': [], 'resto': True,
                               'fuente': 'System Settings Sidebar.plist (SECTION_OTHERS: lo que no está arriba)'})
                continue
            ps = []
            for ident in g.get('content', []):
                b = exts.get(ident) or panes.get(ident)
                ps.append(panel_de(b[0], b[1], ident) if b else {'id': ident, 'falta': 'no está en esta Mac'})
            grupos.append({'id': 'grupo-%d' % (i + 1), 'titulo': None, 'paneles': ps})
        # Lo de «otros» son las extensiones de terceros: aquí no hay; un grupo vacío no se enseña.
        return {'id': 'system-preferences', 'tipo': 'barra-lateral', 'nombre': 'System Settings',
                'grupos': [g for g in grupos if g['paneles']], 'fuente': 'System Settings Sidebar.plist; ExtensionKit Info.plist e InfoPlist.loctable'}
    # Con Apple ID la rejilla es la de NSPrefPaneGroupsBanner.xml (la franja de arriba con Apple ID
    # y Family Sharing, y dos filas): es la que se ve en las capturas de Catalina.
    grupos_xml = buscar(raices, os.path.join(PREFAPP, 'NSPrefPaneGroupsBanner.xml'))
    fuente = 'System Preferences NSPrefPaneGroupsBanner.xml (con Apple ID; sin él, NSPrefPaneGroups.xml)'
    if not grupos_xml:
        grupos_xml = buscar(raices, os.path.join(PREFAPP, 'NSPrefPaneGroups.xml'))
        fuente = 'System Preferences NSPrefPaneGroups.xml'
    if not grupos_xml:
        # Monterey: extraer-mac no traía los .xml (ya los trae); el orden de Catalina, marcado.
        grupos_xml = buscar(VERSIONES['catalina-10.15']['raices'], os.path.join(PREFAPP, 'NSPrefPaneGroupsBanner.xml'))
        fuente = 'PROVISIONAL: orden de Catalina (falta NSPrefPaneGroupsBanner.xml de esta versión)'
    if not grupos_xml:
        return None
    d = plistlib.load(open(grupos_xml, 'rb'))
    titulos = nib.cadenas_de(buscar(raices, os.path.join(PREFAPP, 'en.lproj', 'NSPrefPaneGroups.strings')) or '')
    grupos, usados = [], set()
    for g in d.get('groups', []):
        ps = []
        for ident in g.get('panes', []):
            if ident in panes:
                ps.append(panel_de(panes[ident][0], panes[ident][1], ident))
                usados.add(ident)
        grupos.append({'id': 'banner' if g['identifier'] == '__banner' else g['identifier'],
                       'titulo': titulos.get(g['identifier']), 'paneles': ps})
    # Los paneles que no están en ningún grupo van al de «catchAllGroupID» (Other).
    resto = [panel_de(r, i, k) for k, (r, i) in sorted(panes.items(), key=lambda x: x[1][1].get('CFBundleName', ''))
             if k not in usados and i.get('NSPrefPaneIconLabel', i.get('CFBundleName'))]
    otros = next((g for g in grupos if g['id'] == d.get('catchAllGroupID', 'addons')), None)
    if otros is None:
        otros = {'id': d.get('catchAllGroupID', 'addons'), 'titulo': titulos.get(d.get('catchAllGroupID', 'addons')), 'paneles': []}
        grupos.append(otros)
    otros['paneles'] += resto
    otros['resto'] = True
    grupos = [g for g in grupos if g['paneles']]
    return {'id': 'system-preferences', 'tipo': 'rejilla', 'nombre': 'System Preferences', 'grupos': grupos, 'fuente': fuente}


def textos_de(rec):
    """Los textos en inglés de un bundle: Localizable.loctable (Ventura en adelante) o .strings."""
    en = {}
    for f in sorted(os.listdir(rec)) if os.path.isdir(rec) else []:
        if f.endswith('.loctable') and f != 'InfoPlist.loctable':
            en.update(loctable(os.path.join(rec, f)))
    if not en:
        for carpeta in ('en.lproj', 'English.lproj', 'Base.lproj'):
            d = os.path.join(rec, carpeta)
            for f in sorted(os.listdir(d)) if os.path.isdir(d) else []:
                if f.endswith('.strings') and f != 'InfoPlist.strings':
                    en.update(nib.cadenas_de(os.path.join(d, f)))
    return {k: v for k, v in en.items() if isinstance(v, str)}


def nibs_de(bundle):
    rec = os.path.join(bundle, 'Contents', 'Resources')
    out = []
    for carpeta in ('Base.lproj', 'en.lproj', 'English.lproj', ''):
        d = os.path.join(rec, carpeta)
        for f in sorted(os.listdir(d)) if os.path.isdir(d) else []:
            if f.endswith('.nib') and f[:-4] not in [x[0] for x in out]:
                r = os.path.join(d, f)
                if os.path.isdir(r):
                    k = [x for x in os.listdir(r) if x.startswith('keyedobjects')]
                    r = os.path.join(r, k[0]) if k else None
                if r:
                    out.append((f[:-4], r))
    return out


def contenido_panel(bundle, info):
    """Lo que tiene un panel en el vocabulario común: sus vistas de nib (Catalina, Monterey) o de
    SwiftUI (Sequoia en adelante), con sus textos."""
    rec = os.path.join(bundle, 'Contents', 'Resources')
    out = {'textos': textos_de(rec), 'vistas': []}
    principal = info.get('NSMainNibFile')
    for nombre, ruta in nibs_de(bundle):
        try:
            raices = nib.abrir(ruta).raices()
        except Exception as e:  # pylint: disable=broad-except
            out['vistas'].append({'nib': nombre, 'error': str(e)})
            continue
        for r in raices:
            if r['clase'] == 'NSMenu':
                continue
            v = vocabulario.desde_nib(r)
            if v:
                out['vistas'].append({'nib': nombre, 'principal': nombre == principal and r['clase'] == 'NSWindowTemplate',
                                      'raiz': v})
    exe = os.path.join(bundle, 'Contents', 'MacOS', info.get('CFBundleExecutable', ''))
    if not out['vistas'] and info.get('CFBundleExecutable') and os.path.isfile(exe):
        try:
            vistas, raices = swiftui.app_swiftui(exe)
        except (ValueError, KeyError, OSError):
            vistas, raices = {}, []
        por_vista = swiftui.textos_swiftui(exe, out['textos'])
        for i, nombre in enumerate(raices):
            v = vocabulario.desde_swiftui(swiftui.a_ui(vistas[nombre], vistas, nombre.split('.')[0], textos=dict(por_vista)))
            if v:
                out['vistas'].append({'swiftui': nombre, 'principal': i == 0, 'raiz': v})
        out['nota'] = ('SwiftUI: cada Text toma, en orden, las claves que usa el body de su vista (leído del '
                       'código con la excepción de José); un control sin texto no lo encontró.')
    return out


def contenidos_paneles(version, raices, indice):
    """apps/system-preferences/<id>.json por cada panel del índice."""
    if not indice:
        return 0
    destino = os.path.join(SALIDA, version, 'apps', 'system-preferences')
    os.makedirs(destino, exist_ok=True)
    rutas = {}
    for r in raices:
        for carpeta in ('System/Library/PreferencePanes', 'System/Library/ExtensionKit/Extensions',
                        os.path.join(os.path.dirname(SETTINGSAPP), 'PlugIns')):
            d = os.path.join(r, carpeta)
            for n in os.listdir(d) if os.path.isdir(d) else []:
                rutas.setdefault(n, os.path.join(d, n))
    hechos = 0
    for g in indice['grupos']:
        for p in g['paneles']:
            b = rutas.get(p.get('bundle'))
            if not b:
                continue
            datos = dict(p, **contenido_panel(b, info_bundle(b)))
            # Por el id propio cuando lo hay: en Sequoia General y Appearance vienen los dos del
            # General de Catalina y se pisarían.
            nombre = p.get('id_propio') or p['id']
            with open(os.path.join(destino, nombre + '.json'), 'w') as f:
                json.dump(datos, f, ensure_ascii=False, indent=1)
            p['archivo'] = 'system-preferences/%s.json' % nombre
            hechos += 1
    return hechos


def adaptaciones():
    try:
        return json.load(open(os.path.join(AQUI, 'adaptaciones.json')))
    except (OSError, ValueError):
        return {}


def adaptar(nodo, reglas):
    """Pone «ocultar» o «aplica_a» (y su «ajuste»: qué clave escribir y con qué valores), con su motivo, a los
    controles de un panel por su id estable.
    Solo las reglas aprobadas; las propuestas van aparte, en «propuestas»."""
    # El id del control, o el de su etiqueta (en SwiftUI el título va en el Text de adentro).
    ids = {nodo['props'].get('id')} | {h['props'].get('id') for h in nodo['hijos'][:1] if h['clase'] == 'texto'}
    for r in reglas:
        if nodo['clase'] != 'texto' and ids & set(r['ids']) or nodo['props'].get('id') in r['ids']:
            for k in ('ocultar', 'aplica_a', 'ajuste'):
                if k in r:
                    nodo['props'][k] = r[k]
            nodo['props']['motivo'] = r.get('motivo')
    for h in nodo['hijos']:
        adaptar(h, reglas)
    for k in ('cabecera', 'pie'):
        if isinstance(nodo['props'].get(k), dict):
            adaptar(nodo['props'][k], reglas)


def generar(version, raices=None, medidas=None):
    v = VERSIONES.get(version, {'nombre': version, 'numero': '', 'raices': [], 'medidas': None})
    raices = [r for r in (raices or v['raices']) if os.path.isdir(r)]
    destino = os.path.join(SALIDA, version)
    viejo = os.path.join(destino, 'version.json')
    if not raices and os.path.exists(viejo):
        # Sin fuente aquí (otra computadora, que recibió el perfil en el paquete): no se pisa.
        info = json.load(open(viejo))
        info['partes'] = dict(info.get('partes', {}), nota='sin fuente aquí: se queda el que vino en el paquete')
        # Lo que no sale de la Mac sino de aquí (el tema base de la versión) sí se pone al día.
        info['tema'] = v.get('tema', 'Constanza')
        info['tema_visible'] = {'Samana': 'Samaná', 'ValleNuevo': 'Valle Nuevo'}.get(info['tema'], info['tema'])
        with open(viejo, 'w') as f:
            json.dump(info, f, ensure_ascii=False, indent=1)
        return info
    os.makedirs(os.path.join(destino, 'apps'), exist_ok=True)
    partes = {}

    def guardar(nombre, datos):
        if datos is None:
            partes[nombre] = 'falta: sin fuente en %s' % (raices or 'ninguna raíz')
            return
        with open(os.path.join(destino, 'apps', nombre + '.json'), 'w') as f:
            json.dump(datos, f, ensure_ascii=False, indent=1)
        partes[nombre] = 'ok'

    ad = adaptaciones()
    apple = menu_apple(version, raices)
    # Lo que José quitó del menú Apple (adaptaciones.json, «menus»: «menu-apple:<id>»).
    quitar = {i.split(':', 1)[1]: r.get('motivo') for r in ad.get('menus', []) if r.get('estado') == 'aprobado'
              and r.get('ocultar') for i in r['ids'] if i.startswith('menu-apple:')}
    for e in (apple or {}).get('items', []):
        if e.get('id') in quitar:
            e['ocultar'], e['motivo'] = True, quitar[e['id']]
    guardar('menu-apple', apple)
    guardar('menus-estandar', menus_estandar(version, raices))
    indice = system_preferences(version, raices)
    n = contenidos_paneles(version, raices, indice)
    if indice:
        aprob = [r for r in ad.get('paneles', []) if r.get('estado') == 'aprobado']
        for g in indice['grupos']:
            for p in g['paneles']:
                # Por el id propio, o por el viejo cuando el panel viene de uno solo (Spotlight de
                # Sequoia junta varios viejos, entre ellos el de Siri). La del id propio gana: Touch ID
                # & Password de Sequoia se queda con la clave aunque el Touch ID de Catalina se oculte.
                propias = [r for r in ad.get('paneles', []) if p.get('id_propio') in r['ids']]
                viejas = [r for r in ad.get('paneles', []) if p['id'] in r['ids'] and not p.get('ids_viejos')]
                for r in propias or viejas:
                    if r in aprob and r.get('ocultar_parte'):
                        p['ocultar_parte'], p['motivo'] = r['ocultar_parte'], r.get('motivo')
                    elif r in aprob:
                        p['ocultar'], p['motivo'] = True, r.get('motivo')
                    else:
                        p.setdefault('propuestas', []).append({'ocultar': True, 'motivo': r.get('motivo')})
        controles = [r for r in ad.get('controles', []) if r.get('estado') == 'aprobado']
        carpeta = os.path.join(SALIDA, version, 'apps', 'system-preferences')
        for f in os.listdir(carpeta) if os.path.isdir(carpeta) else []:
            ruta = os.path.join(carpeta, f)
            d = json.load(open(ruta))
            for vista in d.get('vistas', []):
                if 'raiz' in vista:
                    adaptar(vista['raiz'], controles)
            with open(ruta, 'w') as fh:
                json.dump(d, fh, ensure_ascii=False, indent=1)
    guardar('system-preferences', indice)
    if indice:
        partes['paneles'] = '%d con contenido' % n
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
    # El tema base de la versión (José, 18-10-2026): Constanza, Samana (Samaná), ValleNuevo (Valle
    # Nuevo) y Ozama; mientras uno no se construye, las piezas caen a Constanza.
    info = {'id': version, 'nombre': v['nombre'], 'numero': v['numero'], 'tema': v.get('tema', 'Constanza'),
            'tema_visible': {'Samana': 'Samaná', 'ValleNuevo': 'Valle Nuevo'}.get(v.get('tema'), v.get('tema', 'Constanza')),
            'raices': raices, 'partes': partes}
    with open(os.path.join(destino, 'version.json'), 'w') as f:
        json.dump(info, f, ensure_ascii=False, indent=1)
    return info


def copiar_medidas_propias(version):
    """perfiles/<versión>/animaciones.json y efectos.json (medidas nuestras, versionadas) a apps/ del perfil generado."""
    aqui = os.path.join(os.path.dirname(os.path.abspath(__file__)), version)
    estado = {}
    for nombre in ('animaciones', 'efectos'):
        fuente = os.path.join(aqui, nombre + '.json')
        if not os.path.isfile(fuente):
            estado[nombre] = 'sin medidas'
            continue
        destino = os.path.join(SALIDA, version, 'apps')
        os.makedirs(destino, exist_ok=True)
        shutil.copyfile(fuente, os.path.join(destino, nombre + '.json'))
        estado[nombre] = 'ok'
    return estado


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
        info['partes'].update(copiar_medidas_propias(v))
        # version.json se escribió antes de copiar las medidas: se pone al día para que quede el estado («ok» o «sin medidas»)
        ruta = os.path.join(SALIDA, v, 'version.json')
        if os.path.isfile(ruta):
            with open(ruta, 'w') as f:
                json.dump(info, f, ensure_ascii=False, indent=1)
        print('%s: %s' % (v, ', '.join('%s %s' % (k, e) for k, e in info['partes'].items())))


if __name__ == '__main__':
    main()
