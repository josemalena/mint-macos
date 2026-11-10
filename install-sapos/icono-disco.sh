#!/usr/bin/env bash
# El ícono y el nombre del disco en el arranque de la Mac (José, 10-11-2026): al dejar
# ⌥ apretada al encender, el Startup Manager enseña este ícono y este nombre en vez del
# genérico «EFI Boot». La Mac los lee de la partición EFI:
#   .VolumeIcon.icns                     en la raíz de la partición
#   .disk_label y .disk_label_2x         en la carpeta del cargador (EFI/BOOT)
#
#   sudo ./icono-disco.sh [opciones] [imagen]   la EFI de esta máquina (/boot/efi)
#   ./icono-disco.sh --disco sdX [opciones] [imagen]
#                                        la de una memoria USB (la VTOYEFI de Ventoy o su EFI);
#                                        sin sudo si ya está montada a nombre del usuario
#   sudo ./icono-disco.sh --deshacer [--disco sdX]   deja lo que había antes
#   ./icono-disco.sh --solo-icns imagen salida.icns  solo arma el .icns
#
# Opciones:
#   --etiqueta "sapOS"     arma el nombre con etiqueta-disco.py (sin bless)
#   --etiquetas-de DIR     copia un .disk_label y un .disk_label_2x ya hechos (los de bless)
#   --simular              dice qué partición y qué archivos tocaría, sin escribir nada
# Sin --etiqueta ni --etiquetas-de, el nombre que haya se queda como está.
#
# La imagen (PNG o WebP, cuadrada o casi) no va al repo: lleva la manzana. Sin
# argumento se usa ~/.local/share/mint-macos/arranque/icono-disco.png, o la que esté
# al lado de este guion.
#
# El .icns se arma aquí con Pillow, y no con png2icns: el firmware de una Mac de 2008
# (MacBook5,1) lee el 128×128 clásico (it32, comprimido, con su máscara t8mk), que los
# .icns de ahora ya no traen. Lleva 16, 32 y 128 clásicos, y 256 y 512 en PNG.
set -euo pipefail

AQUI="$(cd "$(dirname "$0")" && pwd)"
paso() { printf '\n▸ %s\n' "$*"; }
falla() { printf '✗ %s\n' "$*" >&2; exit 1; }

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

DISCO="" ETIQUETA="" ETIQUETAS_DE="" SIMULAR=0 DESHACER=0 IMAGEN=""
while [ $# -gt 0 ]; do
  case "$1" in
    --disco) DISCO="${2:?falta el disco: --disco sdX}"; shift 2 ;;
    --etiqueta) ETIQUETA="${2:?falta el texto: --etiqueta \"sapOS\"}"; shift 2 ;;
    --etiquetas-de) ETIQUETAS_DE="${2:?falta la carpeta}"; shift 2 ;;
    --simular) SIMULAR=1; shift ;;
    --deshacer) DESHACER=1; shift ;;
    -*) echo "✗ opción desconocida: $1" >&2; exit 2 ;;
    *) IMAGEN="$1"; shift ;;
  esac
done
[ -z "$ETIQUETA" ] || [ -z "$ETIQUETAS_DE" ] || falla "--etiqueta o --etiquetas-de, no las dos"

USUARIO="${SUDO_USER:-$(id -un)}"
[ "$USUARIO" != root ] || falla "córrelo desde tu usuario (con sudo si hace falta), no como root"
HOME_USUARIO="$(getent passwd "$USUARIO" | cut -d: -f6)"

# Lo temporal y lo que haya que desmontar, en un solo sitio.
TMP="$(mktemp -d)"; MONTADO_AQUI=""
limpiar() {
  rm -rf "$TMP"
  if [ -n "$MONTADO_AQUI" ]; then sync; umount "$MONTADO_AQUI" 2>/dev/null || true; rmdir "$MONTADO_AQUI" 2>/dev/null || true; fi
}
trap limpiar EXIT

# ── Dónde: la partición EFI y dónde está montada ─────────────────────────────────
MONTAJE=""
if [ -z "$DISCO" ]; then
  MONTAJE="$(findmnt -n -o TARGET -t vfat /boot/efi 2>/dev/null || true)"
  [ -n "$MONTAJE" ] || falla "/boot/efi no está montada como FAT32: ¿esta máquina arranca por EFI?"
  PARTICION="$(findmnt -n -o SOURCE /boot/efi)"
  echo "  la EFI de esta máquina: $PARTICION en $MONTAJE"
else
  [[ "$DISCO" == /dev/* ]] || DISCO="/dev/$DISCO"
  [ -b "$DISCO" ] || falla "$DISCO no existe"
  [ "$(lsblk -dno TYPE "$DISCO")" = disk ] || falla "$DISCO no es un disco entero (va sdX, no sdX1)"
  # Solo memorias: un disco interno nunca, aunque se equivoque la letra.
  EXTRAIBLE="$(lsblk -dno RM "$DISCO" | xargs)"; TRANSPORTE="$(lsblk -dno TRAN "$DISCO" | xargs)"
  if [ "$EXTRAIBLE" != 1 ] && [ "$TRANSPORTE" != usb ]; then
    falla "$DISCO no es una memoria extraíble ($(lsblk -dno SIZE,MODEL "$DISCO" | xargs)): no lo toco"
  fi
  # La VTOYEFI de Ventoy si está; si no, la partición EFI; si no, la primera FAT.
  PARTICION="$(lsblk -prn -o NAME,LABEL "$DISCO" | awk '$2 == "VTOYEFI" {print $1; exit}')"
  [ -n "$PARTICION" ] || PARTICION="$(lsblk -prn -o NAME,PARTTYPE "$DISCO" | awk 'tolower($2) == "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" {print $1; exit}')"
  [ -n "$PARTICION" ] || PARTICION="$(lsblk -prn -o NAME,FSTYPE "$DISCO" | awk '$2 == "vfat" {print $1; exit}')"
  [ -n "$PARTICION" ] || falla "$DISCO no tiene partición EFI, VTOYEFI ni FAT"
  MONTAJE="$(findmnt -n -o TARGET -S "$PARTICION" 2>/dev/null | head -1 || true)"
  echo "  la memoria: $DISCO ($(lsblk -dno SIZE,MODEL "$DISCO" | xargs)), partición $PARTICION ($(lsblk -no LABEL "$PARTICION" | xargs))"
fi

UUID="$(lsblk -no UUID "$PARTICION" | head -1 | xargs)"
RESPALDO="$HOME_USUARIO/.local/share/mint-macos/arranque/respaldos/${UUID:-sin-uuid}"
RESPALDO_VIEJO=/var/lib/mint-macos/arranque/VolumeIcon.icns.antes   # el de la primera versión

if [ "$SIMULAR" = 1 ]; then
  echo "  montada en: ${MONTAJE:-(no está montada: habría que montarla con sudo)}"
  echo "  escribiría: .VolumeIcon.icns en la raíz; .disk_label y .disk_label_2x en la carpeta del cargador"
  echo "  respaldo de lo que haya: $RESPALDO"
  exit 0
fi

# Montarla si hace falta (con sudo), y saber si se puede escribir.
if [ -z "$MONTAJE" ]; then
  [ "$(id -u)" = 0 ] || falla "$PARTICION no está montada: córrelo con sudo, o móntala antes"
  MONTAJE="$(mktemp -d)"; MONTADO_AQUI="$MONTAJE"
  mount -t vfat -o uid="$(id -u "$USUARIO")",gid="$(id -g "$USUARIO")" "$PARTICION" "$MONTAJE" || falla "no se pudo montar $PARTICION"
fi
[ -w "$MONTAJE" ] || falla "no puedo escribir en $MONTAJE: córrelo con sudo"

# La carpeta del cargador: donde esté BOOTX64.EFI (en FAT el nombre no distingue mayúsculas).
CARGADOR="$(find "$MONTAJE/EFI" -maxdepth 2 -ipath '*/boot/bootx64.efi' 2>/dev/null | head -1)"
if [ -n "$CARGADOR" ]; then
  CARGADOR="$(dirname "$CARGADOR")"
else
  echo "  ⚠ falta EFI/BOOT/BOOTX64.EFI: la Mac puede no enseñar este disco al dejar ⌥ apretada"
  CARGADOR="$MONTAJE/EFI/BOOT"
fi

# Copiar sin pelear con los permisos de FAT: los pone el montaje.
poner() { cp "$1" "$2.nuevo" && mv -f "$2.nuevo" "$2"; }
guardar() {   # guardar ARCHIVO NOMBRE: el que había, una sola vez (el primero es el bueno)
  mkdir -p "$RESPALDO"
  if [ -f "$1" ] && [ ! -e "$RESPALDO/$2" ]; then cp "$1" "$RESPALDO/$2"; fi
  if [ ! -f "$1" ] && [ ! -e "$RESPALDO/$2" ] && [ ! -e "$RESPALDO/$2.no-habia" ]; then : > "$RESPALDO/$2.no-habia"; fi
}
dueno() { [ "$(id -u)" != 0 ] || chown -R "$USUARIO": "$HOME_USUARIO/.local/share/mint-macos/arranque"; }

if [ "$DESHACER" = 1 ]; then
  paso "El ícono y el nombre como estaban"
  for par in "$MONTAJE/.VolumeIcon.icns:VolumeIcon.icns" "$CARGADOR/.disk_label:disk_label" "$CARGADOR/.disk_label_2x:disk_label_2x"; do
    destino="${par%%:*}"; nombre="${par##*:}"
    if [ -f "$RESPALDO/$nombre" ]; then
      poner "$RESPALDO/$nombre" "$destino"; rm -f "$RESPALDO/$nombre"; echo "  volvió el $nombre de antes"
    elif [ -e "$RESPALDO/$nombre.no-habia" ]; then
      rm -f "$destino" "$RESPALDO/$nombre.no-habia"; echo "  sin $nombre, como antes"
    elif [ "$nombre" = VolumeIcon.icns ] && [ -z "$DISCO" ] && [ -f "$RESPALDO_VIEJO" ]; then
      poner "$RESPALDO_VIEJO" "$destino"; rm -f "$RESPALDO_VIEJO"; echo "  volvió el ícono de antes"
    fi
  done
  sync
  exit 0
fi

if [ -z "$IMAGEN" ]; then
  IMAGEN="$HOME_USUARIO/.local/share/mint-macos/arranque/icono-disco.png"
  [ -f "$IMAGEN" ] || IMAGEN="$AQUI/icono-disco.png"
fi
[ -f "$IMAGEN" ] || falla "no encuentro la imagen: pon icono-disco.png en ~/.local/share/mint-macos/arranque/ o pásala como argumento"

paso "El ícono ($(basename "$IMAGEN"))"
armar_icns "$IMAGEN" "$TMP/VolumeIcon.icns"
guardar "$MONTAJE/.VolumeIcon.icns" VolumeIcon.icns
poner "$TMP/VolumeIcon.icns" "$MONTAJE/.VolumeIcon.icns"
echo "  .VolumeIcon.icns ($(du -k "$MONTAJE/.VolumeIcon.icns" | cut -f1) KB)"

if [ -n "$ETIQUETA" ] || [ -n "$ETIQUETAS_DE" ]; then
  paso "El nombre"
  if [ -n "$ETIQUETA" ]; then
    ETIQUETA_HOME="$HOME_USUARIO" python3 -I "$AQUI/etiqueta-disco.py" "$ETIQUETA" "$TMP"
    ORIGEN="$TMP"
  else
    ORIGEN="$ETIQUETAS_DE"
    [ -f "$ORIGEN/.disk_label" ] || falla "no hay .disk_label en $ORIGEN"
  fi
  mkdir -p "$CARGADOR"
  for n in .disk_label .disk_label_2x; do
    [ -f "$ORIGEN/$n" ] || { echo "  ⚠ no hay $n en $ORIGEN"; continue; }
    guardar "$CARGADOR/$n" "${n#.}"
    poner "$ORIGEN/$n" "$CARGADOR/$n"
    echo "  $n en ${CARGADOR#"$MONTAJE"/}"
  done
fi
dueno
sync

echo
echo "Listo: reinicia y deja ⌥ apretada al encender para verlo."
echo "  Para quitarlo: $([ -z "$DISCO" ] && echo "sudo ")$0 --deshacer${DISCO:+ --disco ${DISCO#/dev/}}"
