#!/usr/bin/env python3
"""Genera los íconos del Finder para el tema Constanza desde el volumen de
sistema de una Mac montado (uso local: nada de esto se sube al repo).

Uso: finder.py <raíz del volumen de sistema> <directorio del tema> [gris]

- Los íconos a color (carpetas, documentos, discos, papelera) salen con sus
  nombres freedesktop normales, en 16…256 px.
- Las apps del Dock de la Mac con equivalente claro en Mint (Finder,
  Launchpad, Calendar, System Preferences, App Store) prestan su ícono a la
  app de Linux, con los nombres que esas apps piden.
- Las plantillas de la barra lateral y de la barra de herramientas son negras
  con alfa: se pintan del gris del Finder oscuro y salen como *-symbolic.
"""
import os, sys, plistlib
from PIL import Image
from PIL.IcnsImagePlugin import IcnsFile

RAIZ, TEMA = sys.argv[1], sys.argv[2]
# Colores medidos en el Finder de Catalina oscuro (capturas de José,
# 10-10-2026): los glifos del lateral #98999b y los de la barra #eaebed.
GRIS = sys.argv[3] if len(sys.argv) > 3 else '#98999b'
GRIS_BARRA = sys.argv[4] if len(sys.argv) > 4 else GRIS
def rgb(hexa):
    return tuple(int(hexa.lstrip('#')[i:i + 2], 16) for i in (0, 2, 4))
RGB, RGB_BARRA = rgb(GRIS), rgb(GRIS_BARRA)
# El segmento elegido del selector de vista lleva el glifo oscuro sobre fondo
# claro (#b0b2b5): Fynder pide <nombre>-selected-symbolic mientras está activo.
RGB_ELEGIDO = rgb(sys.argv[5] if len(sys.argv) > 5 else '#2e3033')
ELEGIDOS = {'IconView': 'view-grid-selected-symbolic', 'ListView': 'view-list-selected-symbolic',
            'ColumnView': 'view-column-selected-symbolic', 'GalleryView': 'view-coverflow-selected-symbolic'}

CT = 'System/Library/CoreServices/CoreTypes.bundle/Contents/Resources'
EXT = 'System/Library/Extensions'

# (archivo .icns relativo a la raíz, [nombres freedesktop])
COLOR = [
    # Pestañas de las Preferencias del Finder (las pide Fynder). La de Tags
    # (PrefToolbarTagsIcon_32 en el Assets.car del Finder) va en deepmap2 y
    # no sale; ToolbarLabels.icns es otra (la píldora vieja) y no se usa.
    (f'{CT}/General.icns',                ['pref-general']),
    (f'{CT}/SidebarPrefs.icns',           ['pref-sidebar']),
    (f'{CT}/ToolbarAdvanced.icns',        ['pref-advanced']),
    (f'{CT}/GenericFolderIcon.icns',      ['folder', 'inode-directory', 'folder-templates']),
    (f'{CT}/OpenFolderIcon.icns',         ['folder-open', 'folder-drag-accept']),
    (f'{CT}/HomeFolderIcon.icns',         ['user-home', 'folder-home']),
    (f'{CT}/DesktopFolderIcon.icns',      ['user-desktop', 'folder-desktop']),
    (f'{CT}/DocumentsFolderIcon.icns',    ['folder-documents']),
    (f'{CT}/DownloadsFolder.icns',        ['folder-download', 'folder-downloads']),
    (f'{CT}/MusicFolderIcon.icns',        ['folder-music']),
    (f'{CT}/PicturesFolderIcon.icns',     ['folder-pictures']),
    (f'{CT}/MovieFolderIcon.icns',        ['folder-videos']),
    (f'{CT}/PublicFolderIcon.icns',       ['folder-publicshare']),
    (f'{CT}/ApplicationsFolderIcon.icns', ['folder-applications']),
    (f'{CT}/LibraryFolderIcon.icns',      ['folder-library']),
    (f'{CT}/UsersFolderIcon.icns',        ['folder-users']),
    (f'{CT}/UtilitiesFolder.icns',        ['folder-utilities']),
    (f'{CT}/SmartFolderIcon.icns',        ['folder-saved-search']),
    (f'{CT}/GenericFileServerIcon.icns',  ['network-server']),
    (f'{CT}/GenericDocumentIcon.icns',    ['text-x-generic', 'text-plain', 'application-x-generic', 'unknown']),
    (f'{CT}/ExecutableBinaryIcon.icns',   ['application-x-executable']),
    (f'{CT}/GenericApplicationIcon.icns', ['application-default-icon']),
    (f'{CT}/GenericFontIcon.icns',        ['font-x-generic']),
    (f'{CT}/GenericNetworkIcon.icns',     ['network-workgroup']),
    (f'{CT}/TrashIcon.icns',              ['user-trash']),
    (f'{CT}/FullTrashIcon.icns',          ['user-trash-full']),
    (f'{CT}/com.apple.macmini-unibody-no-optical.icns', ['computer']),
    (f'{EXT}/IOStorageFamily.kext/Contents/Resources/Internal.icns',  ['drive-harddisk', 'drive-harddisk-system']),
    (f'{EXT}/IOStorageFamily.kext/Contents/Resources/External.icns',  ['drive-harddisk-usb', 'drive-harddisk-ieee1394']),
    (f'{EXT}/IOStorageFamily.kext/Contents/Resources/Removable.icns', ['drive-removable-media', 'drive-removable-media-usb', 'media-flash']),
    (f'{EXT}/IOCDStorageFamily.kext/Contents/Resources/CD.icns',      ['media-optical', 'media-optical-cd', 'drive-optical']),
    (f'{EXT}/IODVDStorageFamily.kext/Contents/Resources/DVD.icns',    ['media-optical-dvd']),
    (f'{EXT}/IOBDStorageFamily.kext/Contents/Resources/BD.icns',      ['media-optical-bd']),
]

SIMBOLICOS = [
    (f'{CT}/SidebarRecents.icns',         ['document-open-recent-symbolic']),
    (f'{CT}/SidebarHomeFolder.icns',      ['user-home-symbolic']),
    (f'{CT}/SidebarDesktopFolder.icns',   ['user-desktop-symbolic']),
    (f'{CT}/SidebarDocumentsFolder.icns', ['folder-documents-symbolic']),
    (f'{CT}/SidebarDownloadsFolder.icns', ['folder-download-symbolic']),
    (f'{CT}/SidebarMusicFolder.icns',     ['folder-music-symbolic']),
    (f'{CT}/SidebarPicturesFolder.icns',  ['folder-pictures-symbolic']),
    (f'{CT}/SidebarMoviesFolder.icns',    ['folder-videos-symbolic']),
    (f'{CT}/SidebarApplicationsFolder.icns', ['folder-applications-symbolic']),
    (f'{CT}/SidebarUtilitiesFolder.icns',    ['folder-utilities-symbolic']),
    (f'{CT}/SidebariCloud.icns',          ['weather-overcast-symbolic']),
    (f'{CT}/SidebarInternalDisk.icns',    ['drive-harddisk-symbolic']),
    (f'{CT}/SidebarExternalDisk.icns',    ['drive-harddisk-usb-symbolic']),
    (f'{CT}/SidebarRemovableDisk.icns',   ['drive-removable-media-symbolic', 'drive-removable-media-usb-symbolic']),
    (f'{CT}/SidebarOpticalDisk.icns',     ['drive-optical-symbolic', 'media-optical-symbolic']),
    (f'{CT}/SidebarNetwork.icns',         ['network-workgroup-symbolic']),
    (f'{CT}/SidebarServerDrive.icns',     ['folder-remote-symbolic', 'network-server-symbolic']),
    (f'{CT}/SidebarMacMini.icns',         ['computer-symbolic']),
    (f'{CT}/SidebarGenericFolder.icns',   ['folder-symbolic']),
    # Los Toolbar*.icns son los íconos viejos de Aqua a color (el «prohibido»
    # rojo, la «i» azul): no son glifos. De ahí solo sirve el engranaje. La
    # papelera sale del bote de rejilla de la barra de estado.
    (f'{CT}/StatusBarTrashIcon.icns',     ['user-trash-symbolic', 'user-trash-full-symbolic']),
    (f'{CT}/ToolbarAdvanced.icns',        ['emblem-system-symbolic']),
]

# Glifos de la barra del Finder de Catalina. Están en
# SystemAppearance.bundle/Contents/Resources/Assets.car, con nombres sin NS ni
# Template (GoBack, IconView, Action…). Sus mapas de bits van en deepmap2,
# que solo abre CoreUI, pero cada glifo trae su PDF: construir.sh los dibuja
# con car.py. GLIFOS_FINDER apunta a la carpeta con los PNG (<Nombre>@1x.png
# y @2x.png), dibujados aquí o sacados en una Mac. Si no está, la barra sigue
# con Os-Catalina.
BARRA = [
    ('GoBack',           ['go-previous-symbolic']),
    ('GoForward',        ['go-next-symbolic']),
    ('IconView',         ['view-grid-symbolic', 'view-app-grid-symbolic']),
    ('ListView',         ['view-list-symbolic']),
    ('ColumnView',       ['view-column-symbolic', 'view-dual-symbolic']),
    ('GalleryView',      ['view-paged-symbolic', 'view-coverflow-symbolic']),
    ('Action',           ['emblem-system-symbolic']),
    ('Share',            ['emblem-shared-symbolic', 'send-to-symbolic']),
    ('SearchMagGlass',   ['edit-find-symbolic', 'system-search-symbolic']),
    ('Cancel',           ['edit-clear-symbolic']),
    ('ToolbarTagIcon',   ['tag-symbolic']),
    ('ToolbarGetInfo',   ['document-properties-symbolic', 'dialog-information-symbolic']),
    ('ToolbarDelete',    ['edit-delete-symbolic', 'user-trash-symbolic', 'user-trash-full-symbolic']),
    ('ToolbarNewFolder', ['folder-new-symbolic']),
    ('QuickLook',        ['view-reveal-symbolic']),
    ('Sidebar',          ['view-sidebar-symbolic', 'sidebar-show-symbolic']),
    ('ToolbarArrangeBy', ['view-sort-ascending-symbolic']),
    ('Path',             ['view-path-symbolic']),
    ('PulldownArrowSmall', ['pan-down-symbolic']),
    ('Refresh',          ['view-refresh-symbolic']),
    ('Add',              ['list-add-symbolic']),
    ('Remove',           ['list-remove-symbolic']),
]
# Apps del Dock de la Mac → los nombres de ícono de su equivalente en Mint
# (los que piden sus .desktop). El .icns se busca en el Info.plist de la app.
APPS = [
    ('System/Library/CoreServices/Finder.app',     ['system-file-manager', 'nemo', 'nemo-mac', 'fynder', 'io.github.josemalena.Fynder']),
    ('System/Applications/Launchpad.app',          ['launchpad']),
    ('System/Applications/Calendar.app',           ['org.gnome.Calendar', 'gnome-calendar']),
    ('System/Applications/System Preferences.app', ['preferences-desktop', 'cinnamon-settings']),
    ('System/Applications/App Store.app',          ['mintinstall']),
]
def icns_de_app(app):
    with open(os.path.join(RAIZ, app, 'Contents/Info.plist'), 'rb') as f:
        ic = plistlib.load(f).get('CFBundleIconFile') or 'AppIcon'
    return os.path.join(app, 'Contents/Resources', ic if ic.endswith('.icns') else ic + '.icns')
GLIFOS = os.environ.get('GLIFOS_FINDER', '')

TAM_COLOR = [(16, 1), (22, 1), (24, 1), (32, 1), (48, 1), (64, 1), (96, 1), (128, 1), (256, 1),
             (16, 2), (24, 2), (32, 2), (48, 2), (128, 2)]
TAM_SIMB = [(16, 1), (22, 1), (24, 1), (32, 1), (16, 2), (22, 2), (24, 2), (32, 2)]


def cargar(icns, px):
    """La imagen del .icns del tamaño más cercano por arriba, ya en px×px."""
    with open(icns, 'rb') as f:
        tam = sorted(IcnsFile(f).itersizes(), key=lambda s: s[0] * s[2])
    elegido = next((s for s in tam if s[0] * s[2] >= px), tam[-1])
    im = Image.open(icns)
    im.size = elegido
    im.load()
    im = im.convert('RGBA')
    return im if im.size[0] == px else im.resize((px, px), Image.LANCZOS)


def pintar(im, color=None):
    gris = Image.new('RGBA', im.size, (color or RGB) + (0,))
    gris.putalpha(im.getchannel('A'))
    return gris


def generar(lista, tamanos, carpeta, simbolico):
    dirs, hechos, faltan = [], 0, []
    for t, esc in tamanos:
        sub = f'{t}x{t}' + ('@2x' if esc == 2 else '') + f'/{carpeta}'
        os.makedirs(os.path.join(TEMA, sub), exist_ok=True)
        dirs.append((sub, t, esc))
        for rel, nombres in lista:
            ruta = os.path.join(RAIZ, rel)
            if not os.path.exists(ruta):
                if (t, esc) == tamanos[0]:
                    faltan.append(os.path.basename(rel))
                continue
            im = cargar(ruta, t * esc)
            if simbolico:
                im = pintar(im)
            for n in nombres:
                im.save(os.path.join(TEMA, sub, n + '.png'))
            hechos += (t, esc) == tamanos[0]
    return dirs, hechos, faltan


def generar_barra(tamanos, carpeta):
    """Glifos de la barra a su tamaño natural, centrados en el cuadrado del
    tamaño pedido (16 px = 1x del Finder) y pintados de gris."""
    hechos = 0
    if not GLIFOS or not os.path.isdir(GLIFOS):
        return [], hechos
    for t, esc in tamanos:
        sub = f'{t}x{t}' + ('@2x' if esc == 2 else '') + f'/{carpeta}'
        os.makedirs(os.path.join(TEMA, sub), exist_ok=True)
        lado = t * esc
        k = lado / 16                      # cuánto crece respecto del 1x
        for origen, nombres in BARRA:
            uno = os.path.join(GLIFOS, origen + '@1x.png')
            dos = os.path.join(GLIFOS, origen + '@2x.png')
            if not os.path.exists(uno):
                continue
            w1, h1 = Image.open(uno).size
            fuente = dos if (k > 1 and os.path.exists(dos)) else uno
            im = Image.open(fuente).convert('RGBA')
            w, h = max(1, round(w1 * k)), max(1, round(h1 * k))
            if (w, h) != im.size:
                im = im.resize((w, h), Image.LANCZOS)
            if w > lado or h > lado:       # por si un glifo es más ancho que el cuadro
                f = lado / max(w, h); im = im.resize((max(1, int(w * f)), max(1, int(h * f))), Image.LANCZOS)
            lienzo = Image.new('RGBA', (lado, lado), (0, 0, 0, 0))
            lienzo.paste(im, ((lado - im.size[0]) // 2, (lado - im.size[1]) // 2), im)
            im = pintar(lienzo, RGB_BARRA)
            for n in nombres:
                im.save(os.path.join(TEMA, sub, n + '.png'))
            if origen in ELEGIDOS:
                pintar(lienzo, RGB_ELEGIDO).save(os.path.join(TEMA, sub, ELEGIDOS[origen] + '.png'))
            hechos += (t, esc) == tamanos[0]
    return [], hechos


# El diálogo Info del Finder (lo pide Fynder). Colores medidos en la captura
# de José del Info de Catalina oscuro (12.33.16 PM): personas #c0c0c0 y
# triángulos #717171. Las personas y los candados vienen de CoreTypes (los
# candados son dorados y van tal cual); los triángulos y el engranaje, del
# catálogo de SystemAppearance en su versión oscura. (nombre, origen, color,
# fracción del cuadro que ocupa)
INFO_ICNS = [
    ('info-user-symbolic', 'UserIcon.icns', (192, 192, 192), 0.75),
    ('info-group-symbolic', 'GroupIcon.icns', (192, 192, 192), 0.75),
    ('info-everyone-symbolic', 'Everyone.icns', (192, 192, 192), 0.75),
    ('info-lock-symbolic', 'LockedIcon.icns', None, 0.9),
    ('info-lock-open-symbolic', 'UnlockedIcon.icns', None, 0.9),
]
INFO_GLIFOS = [
    ('info-disclosure-open-symbolic', 'Disclosed', (113, 113, 113)),
    ('info-disclosure-closed-symbolic', 'Disclosable', (113, 113, 113)),
    ('info-gear-symbolic', 'Action', RGB),
]


def generar_info(tamanos, carpeta):
    import tempfile
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import car
    hechos = 0
    car_sistema = os.path.join(RAIZ, 'System/Library/CoreServices/SystemAppearance.bundle/Contents/Resources/Assets.car')
    with tempfile.TemporaryDirectory() as tmp:
        if os.path.exists(car_sistema):
            car.glifos(car_sistema, tmp, {o for _, o, _ in INFO_GLIFOS}, oscuro=True)
        for t, esc in tamanos:
            sub = f'{t}x{t}' + ('@2x' if esc == 2 else '') + f'/{carpeta}'
            lado = t * esc
            for nombre, icns, color, parte in INFO_ICNS:
                ruta = os.path.join(RAIZ, CT, icns)
                if not os.path.exists(ruta):
                    continue
                px = max(1, round(lado * parte))
                im = cargar(ruta, px)
                if color:
                    im = pintar(im, color)
                lienzo = Image.new('RGBA', (lado, lado), (0, 0, 0, 0))
                lienzo.paste(im, ((lado - px) // 2, (lado - px) // 2), im)
                lienzo.save(os.path.join(TEMA, sub, nombre + '.png'))
                hechos += (t, esc) == tamanos[0]
            k = lado / 16
            for nombre, origen, color in INFO_GLIFOS:
                uno = os.path.join(tmp, origen + '@1x.png')
                if not os.path.exists(uno):
                    continue
                w1, h1 = Image.open(uno).size
                dos = os.path.join(tmp, origen + '@2x.png')
                im = Image.open(dos if k > 1 and os.path.exists(dos) else uno).convert('RGBA')
                w, h = max(1, round(w1 * k)), max(1, round(h1 * k))
                im = im.resize((w, h), Image.LANCZOS) if (w, h) != im.size else im
                lienzo = Image.new('RGBA', (lado, lado), (0, 0, 0, 0))
                lienzo.paste(im, ((lado - w) // 2, (lado - h) // 2), im)
                pintar(lienzo, color).save(os.path.join(TEMA, sub, nombre + '.png'))
                hechos += (t, esc) == tamanos[0]
    return hechos


d1, h1, f1 = generar(COLOR, TAM_COLOR, 'finder', False)
APPS_ICNS = []
for app, nombres in APPS:
    try:
        APPS_ICNS.append((icns_de_app(app), nombres))
    except OSError:
        pass
d4, h4, f4 = generar(APPS_ICNS, TAM_COLOR, 'finder-apps', False)
d2, h2, f2 = generar(SIMBOLICOS, TAM_SIMB, 'finder-symbolic', True)
_, h3 = generar_barra(TAM_SIMB, 'finder-symbolic')
h5 = generar_info(TAM_SIMB, 'finder-symbolic')
with open(os.path.join(TEMA, 'finder-dirs.txt'), 'w') as f:
    for sub, t, esc in d1 + d4 + d2:
        f.write(f'{sub} {t} {esc}\n')
print(f'finder: {h1} íconos a color, {h4} apps del Dock, {h2} glifos del lateral, {h3} de la barra y {h5} del Info', ('· faltan ' + ', '.join(f1 + f4 + f2)) if f1 + f4 + f2 else '')
