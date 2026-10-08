#!/usr/bin/env bash
# Arma el tema de íconos «Os-Catalina-Finder» con los íconos originales del
# lateral del Finder (Sidebar*.icns) copiados del disco de la Mac en esta
# misma computadora. Es para uso local: los íconos son de Apple y NO se suben
# a ningún repo; el tema vive en ~/.local/share/icons y hereda de Os-Catalina.
#
# Uso: ./finder-desde-mac.sh [/ruta/al/volumen/de/sistema/montado]
# Sin argumento busca el contenedor APFS, monta en solo lectura el volumen
# de sistema (no « - Data», Preboot, Recovery ni VM) con fsapfsmount y lo
# desmonta al terminar. Si no hay disco de Mac, sale con código 3 y no toca
# nada (catalina.sh se queda con Os-Catalina).
set -euo pipefail

TEMA="$HOME/.local/share/icons/Os-Catalina-Finder"
GRIS="${GRIS:-#c4c4c4}"   # el gris de los íconos del lateral en modo oscuro
RECURSOS="System/Library/CoreServices/CoreTypes.bundle/Contents/Resources"
MONTADO=""

limpiar() { [ -n "$MONTADO" ] && fusermount -u "$MONTADO" 2>/dev/null && rmdir "$MONTADO"; return 0; }
trap limpiar EXIT

SISTEMA="${1:-}"
if [ -z "$SISTEMA" ]; then
  command -v fsapfsinfo >/dev/null || { echo "Sin fsapfsinfo: ver apfs/README.md"; exit 3; }
  for DEV in $(lsblk -rno PATH,FSTYPE | awk '$2=="apfs"{print $1}'); do
    VOL=$(fsapfsinfo "$DEV" 2>/dev/null | awk -F': *' '
      /^Volume: [0-9]+ information/ {split($0,a," "); n=a[2]+0}
      /^\tName/ {gsub(/^[ \t]+|[ \t]+$/,"",$2); nombre[n]=$2}
      END {for (i in nombre) if (nombre[i] !~ / - Data$|^(Preboot|Recovery|VM|Update)$/) {print i; exit}}')
    [ -n "$VOL" ] || continue
    MONTADO="$(mktemp -d)"
    fsapfsmount -f "$VOL" "$DEV" "$MONTADO" >/dev/null 2>&1 || { rmdir "$MONTADO"; MONTADO=""; continue; }
    sleep 1
    if [ -d "$MONTADO/$RECURSOS" ]; then SISTEMA="$MONTADO"; break; fi
    limpiar; MONTADO=""
  done
fi
[ -n "$SISTEMA" ] && [ -d "$SISTEMA/$RECURSOS" ] || { echo "No encontré el disco de la Mac: se queda Os-Catalina."; exit 3; }

python3 - "$SISTEMA/$RECURSOS" "$TEMA" "$GRIS" <<'PY'
import os, sys
from PIL import Image
from PIL.IcnsImagePlugin import IcnsFile

recursos, tema, gris = sys.argv[1], sys.argv[2], sys.argv[3]
rgb = tuple(int(gris.lstrip('#')[i:i+2], 16) for i in (0, 2, 4))

# Ícono del Finder → nombres freedesktop que pide el lateral de nemo-mac.
MAPA = {
    'SidebarRecents':         ['document-open-recent-symbolic'],
    'SidebarHomeFolder':      ['user-home-symbolic'],
    'SidebarDesktopFolder':   ['user-desktop-symbolic'],
    'SidebarDocumentsFolder': ['folder-documents-symbolic'],
    'SidebarDownloadsFolder': ['folder-download-symbolic'],
    'SidebarMusicFolder':     ['folder-music-symbolic'],
    'SidebarPicturesFolder':  ['folder-pictures-symbolic'],
    'SidebarMoviesFolder':    ['folder-videos-symbolic'],
    'SidebariCloud':          ['weather-overcast-symbolic'],
    'SidebarInternalDisk':    ['drive-harddisk-symbolic'],
    'SidebarExternalDisk':    ['drive-harddisk-usb-symbolic'],
    'SidebarRemovableDisk':   ['drive-removable-media-symbolic', 'drive-removable-media-usb-symbolic'],
    'SidebarOpticalDisk':     ['drive-optical-symbolic', 'media-optical-symbolic'],
    'SidebarNetwork':         ['network-workgroup-symbolic'],
    'SidebarMacMini':         ['computer-symbolic'],
    'SidebarGenericFolder':   ['folder-symbolic'],
}
TAMANOS = [16, 22, 24, 32]

def plantilla(icns, px):
    """La plantilla del tamaño más cercano por arriba, pintada de gris con su alfa."""
    with open(icns, 'rb') as f:
        disponibles = sorted({s[0] * s[2] for s in IcnsFile(f).itersizes()})
    origen = next((s for s in disponibles if s >= px), disponibles[-1])
    im = Image.open(icns)
    for s in IcnsFile(open(icns, 'rb')).itersizes():
        if s[0] * s[2] == origen:
            im.size = s; break
    im.load()
    im = im.convert('RGBA')
    if im.size[0] != px:
        im = im.resize((px, px), Image.LANCZOS)
    alfa = im.getchannel('A')
    pintado = Image.new('RGBA', im.size, rgb + (0,))
    pintado.putalpha(alfa)
    return pintado

dirs = []
for t in TAMANOS:
    for escala in (1, 2):
        sub = f'{t}x{t}' + ('@2x' if escala == 2 else '') + '/places'
        os.makedirs(os.path.join(tema, sub), exist_ok=True)
        dirs.append((sub, t, escala))
        for icono, nombres in MAPA.items():
            ruta = os.path.join(recursos, icono + '.icns')
            if not os.path.exists(ruta):
                continue
            png = plantilla(ruta, t * escala)
            for n in nombres:
                png.save(os.path.join(tema, sub, n + '.png'))

with open(os.path.join(tema, 'index.theme'), 'w') as f:
    f.write('[Icon Theme]\nName=Os-Catalina-Finder\n'
            'Comment=Os-Catalina con los íconos del lateral del Finder de la Mac (uso local)\n'
            'Inherits=Os-Catalina\n'
            f'Directories={",".join(d for d, _, _ in dirs)}\n\n')
    for d, t, escala in dirs:
        f.write(f'[{d}]\nSize={t}\nScale={escala}\nContext=Places\nType=Fixed\n\n')
print('tema:', tema, '·', len(MAPA), 'íconos ×', len(dirs), 'tamaños')
PY
gtk-update-icon-cache -q -f "$TEMA" 2>/dev/null || true
echo "Listo. Para activarlo: gsettings set org.cinnamon.desktop.interface icon-theme 'Os-Catalina-Finder'"
