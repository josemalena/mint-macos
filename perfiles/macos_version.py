#!/usr/bin/env python3
"""La versión de macOS escogida y su perfil (ver ESQUEMA.md), para las piezas en Python, y el
comando que la escoge.

    from macos_version import activa, menu, item
    item('menu-apple', 'menu-apple', 'sysp')['texto']   # «System Preferences…» o «System Settings…»

    mint-macos-version                 la activa y la escogida
    mint-macos-version --lista         las que tienen perfil en esta máquina
    mint-macos-version --poner ID      escoge una (vale al volver a entrar)
    mint-macos-version --aplicar       la escogida pasa a activa (lo corre el arranque de la sesión)
"""
import json
import os
import sys

POR_DEFECTO = 'catalina-10.15'
PERFILES = os.path.expanduser('~/.local/share/mint-macos/macos')
ESCOGIDA = os.path.join(os.environ.get('XDG_CONFIG_HOME') or os.path.expanduser('~/.config'), 'mint-macos', 'macos.json')
ACTIVA = os.path.join(os.environ.get('XDG_RUNTIME_DIR') or '/tmp', 'mint-macos', 'macos.json')

_cache = {}


def _leer(ruta):
    try:
        return json.load(open(ruta))
    except (OSError, ValueError):
        return None


def disponibles():
    """Las versiones con perfil generado aquí, de la más vieja a la más nueva."""
    out = []
    for d in sorted(os.listdir(PERFILES)) if os.path.isdir(PERFILES) else []:
        v = _leer(os.path.join(PERFILES, d, 'version.json'))
        if v:
            out.append(v)
    return sorted(out, key=lambda v: [int(x) if x.isdigit() else 0 for x in v.get('numero', '0').split('.')])


def escogida():
    return (_leer(ESCOGIDA) or {}).get('version') or POR_DEFECTO


def activa():
    """La de esta sesión: la que se aplicó al entrar. Si no se aplicó (una pieza que corre fuera
    de la sesión), la escogida."""
    if 'activa' not in _cache:
        _cache['activa'] = (_leer(ACTIVA) or {}).get('version') or escogida()
    return _cache['activa']


def perfil(app, version=None):
    """apps/<app>.json de la versión (la activa si no se dice); {} si no existe."""
    version = version or activa()
    clave = (version, app)
    if clave not in _cache:
        _cache[clave] = _leer(os.path.join(PERFILES, version, 'apps', app + '.json')) or {}
    return _cache[clave]


def medida(*ruta, version=None):
    """Una medida de medidas.json: medida('pantalla', 'alto_barra_menu_pt')."""
    d = _leer(os.path.join(PERFILES, version or activa(), 'medidas.json')) or {}
    for k in ruta:
        if not isinstance(d, dict) or k not in d:
            return None
        d = d[k]
    return d


def menu(app, id_menu, version=None):
    """Los ítems de un menú: el menú Apple (app='menu-apple', id_menu='menu-apple') o uno de los
    estándar (app='menus-estandar', id_menu='app'|'file'|'edit'|'window'…)."""
    p = perfil(app, version)
    if p.get('id') == id_menu:
        return p.get('items', [])
    return next((m.get('items', []) for m in p.get('menus', []) if m.get('id') == id_menu), [])


def item(app, id_menu, id_item, version=None):
    """Un ítem por su id estable (comando o acción); None si en esa versión no existe."""
    return next((i for i in menu(app, id_menu, version) if i.get('id') == id_item), None)


def texto(app, clave, version=None):
    """Un texto de la tabla de textos de la app, por su clave."""
    return perfil(app, version).get('textos', {}).get(clave)


def main():
    a = sys.argv[1:]
    if not a:
        print('activa: %s\nescogida: %s' % (activa(), escogida()))
        return 0
    if a[0] == '--lista':
        for v in disponibles():
            faltan = [k for k, e in v.get('partes', {}).items() if e != 'ok']
            print('%-16s %s %s%s' % (v['id'], v['nombre'], v['numero'], ('  (falta: %s)' % ', '.join(faltan)) if faltan else ''))
        return 0
    if a[0] == '--poner' and len(a) > 1:
        if a[1] not in [v['id'] for v in disponibles()]:
            print('✗ %s no tiene perfil aquí (perfiles/generar.py --version %s)' % (a[1], a[1]), file=sys.stderr)
            return 1
        os.makedirs(os.path.dirname(ESCOGIDA), exist_ok=True)
        with open(ESCOGIDA, 'w') as f:
            json.dump({'version': a[1]}, f)
        print('Escogida %s: vale al volver a entrar.' % a[1])
        return 0
    if a[0] == '--aplicar':
        os.makedirs(os.path.dirname(ACTIVA), mode=0o700, exist_ok=True)
        with open(ACTIVA, 'w') as f:
            json.dump({'version': escogida()}, f)
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == '__main__':
    sys.exit(main())
