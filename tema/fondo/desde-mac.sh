#!/usr/bin/env bash
# Saca el fondo de Catalina del disco de la Mac y lo deja en
# ~/.local/share/backgrounds/constanza/catalina.jpg (uso local; la imagen de
# Apple no va al repo).
#
# Catalina.heic es un fondo dinámico de 8 cuadros, del amanecer a la noche.
# José eligió el 7, el atardecer (cielo violeta, la isla iluminada). Ojo: el
# «oscuro» que Apple marca para el modo Dark es el 1 (la noche, con
# estrellas); se ve en los metadatos apple_desktop:solar, clave ap → d.
# Otro cuadro: CUADRO=1 ./desde-mac.sh --forzar
#
# Sale con 3 si no hay disco de Mac, y no toca nada. Si la imagen ya existe,
# no la vuelve a convertir (6016×6016 tarda); --forzar la rehace.
set -euo pipefail
AQUI="$(cd "$(dirname "$0")" && pwd)"
source "$AQUI/../comun.sh"
DEST_DIR="$HOME/.local/share/backgrounds/constanza"
DEST="$DEST_DIR/catalina.jpg"
CUADRO="${CUADRO:-7}"

if [ -f "$DEST" ] && [ "${1:-}" != "--forzar" ]; then
  echo "  fondo: ya está en $DEST"; exit 0
fi
# Se lee a una variable: con pipefail, «convert -list | grep -q» falla al azar
# (grep corta la tubería y convert muere por SIGPIPE).
FORMATOS="$(convert -list format 2>/dev/null)"
grep -q '^ *HEIC' <<< "$FORMATOS" || {
  echo "  ImageMagick no lee HEIC (falta libheif): se queda el fondo actual"; exit 3; }

trap desmontar_mac EXIT
montar_mac_sistema || { echo "  sin disco de Mac: se queda el fondo actual"; exit 3; }
HEIC="$MAC_SISTEMA/System/Library/Desktop Pictures/Catalina.heic"
[ -f "$HEIC" ] || { echo "  esta Mac no trae Catalina.heic: se queda el fondo actual"; exit 3; }

N=$(identify "$HEIC" 2>/dev/null | wc -l)
[ "$CUADRO" -lt "$N" ] || { echo "  Catalina.heic tiene $N cuadros, no hay el $CUADRO"; exit 3; }

mkdir -p "$DEST_DIR"
convert "$HEIC[$CUADRO]" -quality 92 "$DEST.tmp.jpg" && mv "$DEST.tmp.jpg" "$DEST"
echo "  fondo: cuadro $CUADRO de $N en $DEST"
