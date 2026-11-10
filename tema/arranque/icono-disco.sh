#!/usr/bin/env bash
# El ícono del disco en el arranque de la Mac (José, 10-11-2026): al dejar ⌥
# apretada al encender, el Startup Manager enseña este ícono en vez del
# genérico de «EFI Boot». La Mac lo lee de .VolumeIcon.icns en la raíz de la
# partición EFI.
#
#   sudo ./icono-disco.sh [imagen]        lo pone (PNG o WebP, cuadrada o casi)
#   sudo ./icono-disco.sh --deshacer      lo quita, o deja el que había antes
#   ./icono-disco.sh --solo-icns imagen salida.icns   solo arma el .icns, sin sudo
#
# La imagen no va al repo (lleva la manzana): sin argumento se usa la del
# usuario en ~/.local/share/mint-macos/arranque/icono-disco.png.
#
# El .icns se arma aquí con Pillow, y no con png2icns: el firmware de una Mac
# de 2008 (MacBook5,1) lee el 128×128 clásico (it32, comprimido, con su
# máscara t8mk), que los .icns de ahora ya no traen. Lleva 16, 32 y 128
# clásicos, y 256 y 512 en PNG para los firmwares nuevos.
# El nombre de debajo («EFI Boot») no cambia: ese es el .disk_label, que se
# genera con bless desde macOS (pendiente).
set -euo pipefail

AQUI="$(cd "$(dirname "$0")" && pwd)"
RESPALDO_DIR=/var/lib/mint-macos/arranque
RESPALDO="$RESPALDO_DIR/VolumeIcon.icns.antes"

paso() { printf '\n▸ %s\n' "$*"; }

# armar_icns IMAGEN SALIDA: el .icns, recortado al dibujo y centrado en un
# cuadrado transparente.
armar_icns() {
  python3 -I - "$1" "$2" <<'PY'
import struct, sys
from io import BytesIO
from PIL import Image

def rle(canal):
    # El RLE de los íconos clásicos: un byte < 128 copia los n+1 que siguen;
    # uno >= 128 repite el que sigue n-125 veces (de 3 a 130).
    out, i, n = bytearray(), 0, len(canal)
    while i < n:
        j = i
        while j < n and j - i < 130 and canal[j] == canal[i]:
            j += 1
        if j - i >= 3:
            out += bytes((j - i + 125, canal[i])); i = j; continue
        j = i
        while j < n and j - i < 128 and not (j + 2 < n and canal[j] == canal[j + 1] == canal[j + 2]):
            j += 1
        out += bytes((j - i - 1,)) + canal[i:j]; i = j
    return bytes(out)

def entrada(tipo, datos):
    return tipo.encode() + struct.pack('>I', len(datos) + 8) + datos

im = Image.open(sys.argv[1]).convert('RGBA')
caja = im.getbbox()
if not caja:
    sys.exit('✗ la imagen está vacía (toda transparente)')
im = im.crop(caja)
lado = max(im.size)
cuadro = Image.new('RGBA', (lado, lado), (0, 0, 0, 0))
cuadro.paste(im, ((lado - im.width) // 2, (lado - im.height) // 2))
if lado < 512:
    print(f'  ⚠ la imagen es de {lado} px: se ve mejor desde 512', file=sys.stderr)

partes = []
for px, rgb, mascara in ((16, 'is32', 's8mk'), (32, 'il32', 'l8mk'), (128, 'it32', 't8mk')):
    t = cuadro.resize((px, px), Image.LANCZOS)
    r, g, b, a = t.split()
    datos = b''.join(rle(c.tobytes()) for c in (r, g, b))
    if rgb == 'it32':
        datos = b'\0\0\0\0' + datos   # el it32 lleva 4 ceros delante
    partes += [entrada(rgb, datos), entrada(mascara, a.tobytes())]
for px, tipo in ((256, 'ic08'), (512, 'ic09')):
    buf = BytesIO()
    cuadro.resize((px, px), Image.LANCZOS).save(buf, 'PNG')
    partes.append(entrada(tipo, buf.getvalue()))
cuerpo = b''.join(partes)
with open(sys.argv[2], 'wb') as f:
    f.write(b'icns' + struct.pack('>I', len(cuerpo) + 8) + cuerpo)
PY
}

if [ "${1:-}" = --solo-icns ]; then
  [ $# = 3 ] || { echo "uso: $0 --solo-icns imagen salida.icns" >&2; exit 2; }
  armar_icns "$2" "$3"
  echo "  $3"
  exit 0
fi

[ "$(id -u)" = 0 ] || { echo "✗ con sudo: sudo $0 ${1:-}"; exit 1; }
USUARIO="${SUDO_USER:-}"
[ -n "$USUARIO" ] && [ "$USUARIO" != root ] || { echo "✗ córrelo con sudo desde tu usuario"; exit 1; }
HOME_USUARIO="$(getent passwd "$USUARIO" | cut -d: -f6)"

EFI="$(findmnt -n -o TARGET -t vfat /boot/efi 2>/dev/null || true)"
[ -n "$EFI" ] || { echo "✗ /boot/efi no está montada como FAT32: ¿esta máquina arranca por EFI?"; exit 1; }
DESTINO="$EFI/.VolumeIcon.icns"

if [ "${1:-}" = --deshacer ]; then
  paso "El ícono del disco como estaba"
  if [ -f "$RESPALDO" ]; then
    cp "$RESPALDO" "$DESTINO.nuevo" && mv -f "$DESTINO.nuevo" "$DESTINO"
    rm -f "$RESPALDO"
    echo "  volvió el que había antes"
  else
    rm -f "$DESTINO"
    echo "  sin ícono: la Mac enseña el genérico de «EFI Boot»"
  fi
  sync
  exit 0
fi

IMAGEN="${1:-$HOME_USUARIO/.local/share/mint-macos/arranque/icono-disco.png}"
[ -f "$IMAGEN" ] || { echo "✗ no encuentro la imagen: $IMAGEN"; exit 1; }

paso "El cargador que la Mac busca"
# Sin EFI/BOOT/BOOTX64.EFI el Startup Manager ni siquiera enseña el disco (las
# Mac viejas no leen las entradas de arranque de la NVRAM como un PC). En FAT
# el nombre no distingue mayúsculas.
if find "$EFI/EFI" -maxdepth 2 -ipath '*/boot/bootx64.efi' 2>/dev/null | grep -q .; then
  echo "  está: EFI/BOOT/BOOTX64.EFI"
else
  echo "  ⚠ falta EFI/BOOT/BOOTX64.EFI: la Mac puede no enseñar este disco al dejar ⌥ apretada"
fi

paso "El ícono"
mkdir -p "$RESPALDO_DIR"
if [ -f "$DESTINO" ] && [ ! -f "$RESPALDO" ]; then
  cp "$DESTINO" "$RESPALDO"
  echo "  guardé el que había en $RESPALDO"
fi
# Se arma en /tmp y se pasa a la EFI de una vez. En FAT no hay permisos que
# poner: los pone el montaje.
TMP="$(mktemp --suffix=.icns)"
trap 'rm -f "$TMP"' EXIT
armar_icns "$IMAGEN" "$TMP"
cp "$TMP" "$DESTINO.nuevo" && mv -f "$DESTINO.nuevo" "$DESTINO"
sync
echo "  $(basename "$IMAGEN") → $DESTINO ($(du -k "$DESTINO" | cut -f1) KB)"

echo
echo "Listo: reinicia y deja ⌥ apretada al encender para verlo."
echo "  Para quitarlo: sudo $AQUI/$(basename "$0") --deshacer"
