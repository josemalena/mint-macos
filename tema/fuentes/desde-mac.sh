#!/usr/bin/env bash
# Copia las fuentes San Francisco del disco de la Mac a
# ~/.local/share/fonts/san-francisco (uso local; las fuentes de Apple no van
# al repo): «.SF NS» (la del sistema, con su Mono y Rounded), SF Compact y SF
# Mono, que en Catalina viene dentro de Terminal.app.
# Sale con 3 si no hay disco de Mac, y no toca nada.
set -euo pipefail
AQUI="$(cd "$(dirname "$0")" && pwd)"
source "$AQUI/../comun.sh"
trap desmontar_mac EXIT
montar_mac_sistema || { echo "  sin disco de Mac: se queda Inter"; exit 3; }

DEST="$HOME/.local/share/fonts/san-francisco"
mkdir -p "$DEST"
n=0
for f in "$MAC_SISTEMA"/System/Library/Fonts/SF*.{ttf,otf} \
         "$MAC_SISTEMA"/Library/Fonts/SF*.{ttf,otf} \
         "$MAC_SISTEMA"/System/Applications/Utilities/Terminal.app/Contents/Resources/Fonts/SFMono-*.otf \
         "$MAC_SISTEMA"/Applications/Utilities/Terminal.app/Contents/Resources/Fonts/SFMono-*.otf; do
  [ -f "$f" ] || continue
  cp -u "$f" "$DEST/"; n=$((n+1))
done
fc-cache -f "$DEST" >/dev/null
echo "  fuentes: $n archivos en $DEST"
