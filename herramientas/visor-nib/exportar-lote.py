#!/usr/bin/env python3
"""Exporta en lote los nib de varios bundles de la Mac a JSON y PNG, para revisar las
piezas sin abrir el visor una por una.

    exportar-lote.py [--version NOMBRE] BUNDLE…   cada .app o .prefPane: sus nib (los de sus
                                                 plugins también); con --version, todo va a
                                                 visor-nib/<NOMBRE>/ para no mezclar Catalina,
                                                 Monterey, Sequoia y macOS 27

Deja en ~/.local/share/mint-macos/visor-nib/<bundle>/ un json/<nib>.json por nib y un
png/<nib>/NN-<título>.png por ventana o vista suelta, y en ~/.local/share/mint-macos/
visor-nib/INDICE.md, para cada bundle, cada nib con lo que trae (ventana, vista o menú, título y
tamaño). Un nib que no se deja leer queda anotado en el índice y se sigue con el próximo. Nada de
esto va al repo: tiene datos de Apple. Correr con prioridad baja y en Xvfb:

    xvfb-run -a nice -n 19 ionice -c3 python3 -I exportar-lote.py RUTA…
"""
import json
import os
import re
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import visor  # noqa: E402
from visor import Gtk  # noqa: E402


def limpio(t):
    return re.sub(r'[/\\:*?"<>|\n]+', '-', t or '').strip()[:60] or 'sin-titulo'


def que_es(r):
    p = r['props']
    if r['clase'] == 'NSMenu':
        tops = [h['props'].get('titulo') for h in r['hijos'] if h['props'].get('titulo')]
        return 'menú', ', '.join(tops[:9]) + ('…' if len(tops) > 9 else ''), ''
    m = p.get('marco') or [0, 0, 0, 0]
    tam = '%d×%d' % (m[2], m[3])
    if r['clase'] == 'NSWindowTemplate':
        return 'ventana', p.get('titulo') or p.get('clase_propia') or '', tam
    return 'vista', p.get('clase_propia') or r['clase'], tam


def pintar_png(r, imgs, ruta):
    off = Gtk.OffscreenWindow()
    off.add(visor.lienzo(r, imgs))
    off.show_all()
    while Gtk.events_pending():
        Gtk.main_iteration()
    pb = off.get_pixbuf()
    if pb:
        pb.savev(ruta, 'png', [], [])
    off.destroy()
    return bool(pb)


def exportar(bundle):
    app = visor.AppMac(bundle)
    base = os.path.join(visor.SALIDA, os.path.basename(bundle.rstrip('/')))
    filas, leidos, fallidos = [], 0, 0
    for nombre, ruta in app.nibs:
        archivo = limpio(nombre.replace(' ▸ ', '--'))
        raices = app.raices(nombre)
        if raices and raices[0]['clase'] == 'error':
            fallidos += 1
            filas.append((nombre, 'NO SE PUDO LEER', raices[0]['props'].get('mensaje', ''), '', ''))
            continue
        leidos += 1
        os.makedirs(os.path.join(base, 'json'), exist_ok=True)
        json.dump(raices, open(os.path.join(base, 'json', archivo + '.json'), 'w'), ensure_ascii=False, indent=1)
        if not raices:
            filas.append((nombre, '—', 'sin ventanas, vistas ni menús de primer nivel', '', ''))
        for i, r in enumerate(raices):
            tipo, titulo, tam = que_es(r)
            png = ''
            if tipo != 'menú':
                d = os.path.join(base, 'png', archivo)
                os.makedirs(d, exist_ok=True)
                p = os.path.join(d, '%02d-%s.png' % (i, limpio(titulo)))
                try:
                    if pintar_png(r, app.imgs(nombre), p):
                        png = os.path.relpath(p, visor.SALIDA)
                except Exception as e:  # pylint: disable=broad-except
                    png = 'falló el PNG: %s' % e
            filas.append((nombre, tipo, titulo, tam, png))
    return app, filas, leidos, fallidos


def main():
    args = sys.argv[1:]
    version = None
    if args[:1] == ['--version']:
        version, args = args[1], args[2:]
        # Las imágenes, las recetas y el caché de cada versión, aparte: los nib cambian de una a otra.
        visor.SALIDA = os.path.join(visor.SALIDA, version)
        visor.RECETAS = os.path.join(visor.SALIDA, 'recetas')
    visor.estilo()
    secciones, totales = [], []
    for bundle in args:
        t = time.time()
        try:
            app, filas, leidos, fallidos = exportar(bundle)
        except (Exception, SystemExit) as e:  # pylint: disable=broad-except
            secciones.append('## %s\n\nNo se pudo abrir: %s\n' % (bundle, e))
            totales.append((os.path.basename(bundle), 0, 0))
            continue
        nombre = os.path.basename(bundle.rstrip('/'))
        totales.append((nombre, leidos, fallidos))
        print('%s: %d leídos, %d fallidos (%.0f s)' % (nombre, leidos, fallidos, time.time() - t), flush=True)
        lineas = ['## %s' % nombre, '', '`%s` — %d nib leídos, %d fallidos.' % (bundle, leidos, fallidos), '',
                  '| Nib | Tipo | Título o clase | Tamaño | PNG |', '|---|---|---|---|---|']
        for f in filas:
            lineas.append('| %s |' % ' | '.join(str(x).replace('|', '\\|') for x in f))
        secciones.append('\n'.join(lineas) + '\n')
    cab = ['# Nib de la Mac exportados' + (' — %s' % version if version else ''), '',
           'Generado por `herramientas/visor-nib/exportar-lote.py` el %s. Cada bundle tiene su carpeta '
           'aquí al lado, con `json/` y `png/`. Para verlos en el visor: `mac-visor-nib <bundle>`.' % time.strftime('%d-%m-%Y %H:%M'),
           '', '| Bundle | Leídos | Fallidos |', '|---|---|---|']
    cab += ['| %s | %d | %d |' % t for t in totales]
    os.makedirs(visor.SALIDA, exist_ok=True)
    with open(os.path.join(visor.SALIDA, 'INDICE.md'), 'w') as f:
        f.write('\n'.join(cab) + '\n\n' + '\n'.join(secciones))
    print(os.path.join(visor.SALIDA, 'INDICE.md'))


if __name__ == '__main__':
    main()
