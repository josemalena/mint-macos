#!/usr/bin/env python3
"""Instala el tema de íconos Mint-Macos-<versión> (los glifos de Apple de esa versión, hechos por el paso «simbolos» de car-mac) en
$XDG_DATA_HOME/icons (~/.local/share/icons). No lo activa: activarlo en la sesión es decisión de José.

    construir-tema-macos.py VERSIÓN [--salida SAL | --origen CARPETA] [--hereda TEMA] [--quitar]

- VERSIÓN: 12.7.6, 27.0.1… (el nombre del tema es Mint-Macos-<versión>).
- --salida: la carpeta de salida de extraer-mac de la máquina del usuario (<SAL>, con <SAL>/iconos-simbolicos/Mint-Macos-<versión>/); también
  vale la variable MINT_MACOS_SALIDA. Se busca ahí primero; el migrador la usa así.
- --origen: la carpeta Mint-Macos-<versión> que dejó car-mac («<SAL>/iconos-simbolicos/Mint-Macos-<versión>/»); por omisión se busca en
  ~/.local/share/mint-macos/referencias/simbolos-*/<versión>/. Son de Apple: se quedan en la máquina, nunca en el repo ni en el paquete.
- --hereda: el tema de íconos que va debajo (el de la versión: Constanza o Samaná; si no existe en esta máquina, Constanza), y después
  Adwaita y hicolor. La tabla de correspondencia SF → freedesktop está en extraer-mac/simbolos-freedesktop.tsv; lo que no está en ella queda
  en scalable/sf/ con su nombre de SF y nadie lo usa mientras no se mapee."""
import glob, os, re, shutil, subprocess, sys

DATOS = os.environ.get('XDG_DATA_HOME') or os.path.expanduser('~/.local/share')
ICONOS = os.path.join(DATOS, 'icons')
REFS = os.path.join(DATOS, 'mint-macos', 'referencias')


def buscar_origen(version, salida=None):
    """Primero la salida de extraer-mac del usuario (--salida o MINT_MACOS_SALIDA), después las referencias de la máquina de trabajo."""
    for sal in (salida, os.environ.get('MINT_MACOS_SALIDA')):
        if sal:
            c = os.path.join(sal, 'iconos-simbolicos', 'Mint-Macos-' + version)
            if os.path.isfile(os.path.join(c, 'index.theme')):
                return c
    for c in sorted(glob.glob(os.path.join(REFS, 'simbolos-*', version, '*', 'iconos-simbolicos', 'Mint-Macos-' + version)), reverse=True):
        if os.path.isfile(os.path.join(c, 'index.theme')):
            return c
    return None


def tema_base(version):
    """El tema de íconos de la versión (version.json: «tema»); Constanza si no está instalado."""
    dirs = [ICONOS, '/usr/share/icons', os.path.expanduser('~/.icons')]
    for pid in glob.glob(os.path.join(DATOS, 'mint-macos', 'macos', '*', 'version.json')):
        try:
            import json
            v = json.load(open(pid))
        except (OSError, ValueError):
            continue
        if v.get('numero') == version or v.get('numero', '').startswith(version):
            for nombre in (v.get('tema_visible'), v.get('tema')):
                if nombre and any(os.path.isdir(os.path.join(d, nombre)) for d in dirs):
                    return nombre
    return 'Constanza'


def sin_tapar_regulares(carpeta, hereda):
    """Quita del tema los glifos «X-symbolic» cuyo ícono regular «X» ya existe en el tema de la versión (o los que hereda).

    GTK 3 busca tema por tema con TODOS los nombres que pide una app, en el orden de la lista: un GThemedIcon de carpeta pide «inode-directory»,
    «folder» y «folder-symbolic»; si este tema (el primero) trae «folder-symbolic», gana a la carpeta regular del tema de la versión (el 27-10-2026 las
    carpetas de Fynder salieron como el glifo de línea de Apple). Los glifos solo deben llenar lo que no hay: los simbólicos sin regular.
    Devuelve los nombres quitados. Sin gi (GTK), no filtra."""
    try:
        import gi
        gi.require_version('Gtk', '3.0')
        from gi.repository import Gtk
    except (ImportError, ValueError):
        return []
    tema = Gtk.IconTheme.new()
    tema.set_custom_theme(hereda)
    quitados = []
    for raiz, _dirs, archivos in os.walk(os.path.join(carpeta, 'scalable')):
        for f in archivos:
            if not f.endswith('-symbolic.svg'):
                continue
            base = f[:-len('-symbolic.svg')]
            info = tema.lookup_icon(base, 48, 0)
            if info and ('/%s/' % hereda) in (info.get_filename() or ''):   # solo si el regular es del tema de la versión, no de Adwaita/hicolor
                os.remove(os.path.join(raiz, f))
                quitados.append(base)
    return quitados


def main():
    a = sys.argv[1:]
    if not a or a[0].startswith('-'):
        print(__doc__); return 2
    version = a[0]
    destino = os.path.join(ICONOS, 'Mint-Macos-' + version)
    if '--quitar' in a:
        shutil.rmtree(destino, ignore_errors=True)
        shutil.rmtree(destino + '-glifos', ignore_errors=True)
        print('quitado', destino); return 0
    salida = a[a.index('--salida') + 1] if '--salida' in a else None
    origen = a[a.index('--origen') + 1] if '--origen' in a else buscar_origen(version, salida)
    if not origen or not os.path.isfile(os.path.join(origen, 'index.theme')):
        print('no encuentro los glifos de %s (paso «simbolos» de car-mac): %s' % (version, origen or 'sin carpeta'), file=sys.stderr)
        return 1
    hereda = a[a.index('--hereda') + 1] if '--hereda' in a else tema_base(version)
    tmp = destino + '.nuevo'
    shutil.rmtree(tmp, ignore_errors=True)
    shutil.copytree(origen, tmp)
    idx = os.path.join(tmp, 'index.theme')
    texto = open(idx).read()
    texto = re.sub(r'(?m)^Inherits=.*$', 'Inherits=%s,Adwaita,hicolor' % hereda, texto)
    open(idx, 'w').write(texto)
    quitados = sin_tapar_regulares(tmp, hereda)
    shutil.rmtree(destino, ignore_errors=True)
    shutil.rmtree(destino + '-glifos', ignore_errors=True)   # (una versión anterior de este script los dejaba aparte)
    os.rename(tmp, destino)
    subprocess.run(['gtk-update-icon-cache', '-q', '-t', '-f', destino], check=False)
    if quitados:
        print('  no se instalan %d glifos porque taparían el ícono regular del tema %s (carpeta, home, trash…): %s' % (len(quitados), hereda, ', '.join(sorted(quitados)[:12])))
    n = sum(len(f) for _, _, f in os.walk(os.path.join(destino, 'scalable')))
    print('Mint-Macos-%s: %d glifos en %s (hereda %s)' % (version, n, destino, hereda))
    return 0


if __name__ == '__main__':
    sys.exit(main())
