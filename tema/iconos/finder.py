#!/usr/bin/env python3
"""Genera los íconos del Finder para el tema Constanza desde el volumen de
sistema de una Mac montado (uso local: nada de esto se sube al repo).

Uso: finder.py <raíz del volumen de sistema> <directorio del tema> [gris]

- Los íconos a color (carpetas, documentos, discos, papelera) salen con sus
  nombres freedesktop normales, en 16…256 px.
- Las plantillas de la barra lateral y de la barra de herramientas son negras
  con alfa: se pintan del gris del Finder oscuro y salen como *-symbolic.
"""
import os, sys
from PIL import Image
from PIL.IcnsImagePlugin import IcnsFile

RAIZ, TEMA = sys.argv[1], sys.argv[2]
GRIS = sys.argv[3] if len(sys.argv) > 3 else '#c4c4c4'
RGB = tuple(int(GRIS.lstrip('#')[i:i + 2], 16) for i in (0, 2, 4))

CT = 'System/Library/CoreServices/CoreTypes.bundle/Contents/Resources'
EXT = 'System/Library/Extensions'

# (archivo .icns relativo a la raíz, [nombres freedesktop])
COLOR = [
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
    (f'{CT}/SidebariCloud.icns',          ['weather-overcast-symbolic']),
    (f'{CT}/SidebarInternalDisk.icns',    ['drive-harddisk-symbolic']),
    (f'{CT}/SidebarExternalDisk.icns',    ['drive-harddisk-usb-symbolic']),
    (f'{CT}/SidebarRemovableDisk.icns',   ['drive-removable-media-symbolic', 'drive-removable-media-usb-symbolic']),
    (f'{CT}/SidebarOpticalDisk.icns',     ['drive-optical-symbolic', 'media-optical-symbolic']),
    (f'{CT}/SidebarNetwork.icns',         ['network-workgroup-symbolic']),
    (f'{CT}/SidebarMacMini.icns',         ['computer-symbolic']),
    (f'{CT}/SidebarGenericFolder.icns',   ['folder-symbolic']),
    # Los Toolbar*.icns son los íconos viejos de Aqua a color (el «prohibido»
    # rojo, la «i» azul): no son glifos. De ahí solo sirve el engranaje. La
    # papelera sale del bote de rejilla de la barra de estado.
    (f'{CT}/StatusBarTrashIcon.icns',     ['user-trash-symbolic', 'user-trash-full-symbolic']),
    (f'{CT}/ToolbarAdvanced.icns',        ['emblem-system-symbolic']),
]

# Glifos de la barra exportados en la Mac con macos/exportar-glifos.swift
# (/Users/Shared/glifos-finder/png en el volumen de datos). Nombre del PNG →
# nombres freedesktop. Si no están, la barra sigue con los de Os-Catalina.
BARRA = [
    ('NSGoLeftTemplate',      ['go-previous-symbolic']),
    ('NSGoRightTemplate',     ['go-next-symbolic']),
    ('NSIconViewTemplate',    ['view-grid-symbolic', 'view-app-grid-symbolic']),
    ('NSListViewTemplate',    ['view-list-symbolic']),
    ('NSColumnViewTemplate',  ['view-column-symbolic', 'view-dual-symbolic']),
    ('NSFlowViewTemplate',    ['view-paged-symbolic']),
    ('NSActionTemplate',      ['emblem-system-symbolic', 'open-menu-symbolic']),
    ('NSShareTemplate',       ['emblem-shared-symbolic', 'send-to-symbolic']),
    ('NSSearchField-lupa',    ['edit-find-symbolic', 'system-search-symbolic']),
    ('NSSearchField-borrar',  ['edit-clear-symbolic']),
    ('NSQuickLookTemplate',   ['view-reveal-symbolic']),
    ('NSAddTemplate',         ['list-add-symbolic']),
    ('NSRemoveTemplate',      ['list-remove-symbolic']),
]
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


def pintar(im):
    gris = Image.new('RGBA', im.size, RGB + (0,))
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
    """Los PNG exportados en la Mac (1x y @2x), pintados de gris."""
    dirs, hechos = [], 0
    if not GLIFOS or not os.path.isdir(os.path.join(GLIFOS, 'png')):
        return dirs, hechos
    for t, esc in tamanos:
        sub = f'{t}x{t}' + ('@2x' if esc == 2 else '') + f'/{carpeta}'
        os.makedirs(os.path.join(TEMA, sub), exist_ok=True)
        for origen, nombres in BARRA:
            base = os.path.join(GLIFOS, 'png', origen)
            ruta = base + '@2x.png' if os.path.exists(base + '@2x.png') else base + '.png'
            if not os.path.exists(ruta):
                continue
            im = Image.open(ruta).convert('RGBA')
            # Se centra en un lienzo cuadrado: los glifos de la barra son anchos.
            lado = max(im.size); lienzo = Image.new('RGBA', (lado, lado), (0, 0, 0, 0))
            lienzo.paste(im, ((lado - im.size[0]) // 2, (lado - im.size[1]) // 2))
            im = pintar(lienzo.resize((t * esc, t * esc), Image.LANCZOS))
            for n in nombres:
                im.save(os.path.join(TEMA, sub, n + '.png'))
            hechos += (t, esc) == tamanos[0]
    return dirs, hechos


d1, h1, f1 = generar(COLOR, TAM_COLOR, 'finder', False)
_, h3 = generar_barra(TAM_SIMB, 'finder-symbolic')
d2, h2, f2 = generar(SIMBOLICOS, TAM_SIMB, 'finder-symbolic', True)
with open(os.path.join(TEMA, 'finder-dirs.txt'), 'w') as f:
    for sub, t, esc in d1 + d2:
        f.write(f'{sub} {t} {esc}\n')
print(f'finder: {h1} íconos a color, {h2} glifos del lateral y {h3} de la barra', ('· faltan ' + ', '.join(f1 + f2)) if f1 + f2 else '')
