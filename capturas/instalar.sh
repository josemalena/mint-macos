#!/bin/bash
# Capturas y emojis como en macOS: instala los dos guiones en ~/.local/bin,
# donde los buscan los atajos de cinnamon/keybindings.dconf (custom2…custom7).
#
#   mac-captura   ⇧⌘3 ⇧⌘4 ⇧⌘5 ⌃⇧⌘3 ⌃⇧⌘4  (⇧⌘5 abre mac-captura-herramienta, la barra de Catalina)
#   mac-emojis    ⌃⌘Espacio
#
# Para quitarlos: rm ~/.local/bin/mac-captura ~/.local/bin/mac-emojis (los
# atajos quedan apuntando a nada y no hacen nada).
set -euo pipefail
AQUI="$(cd "$(dirname "$0")" && pwd)"
# Destino: ~/.local/bin, o /usr/local/bin para la imagen (MINT_MACOS_DESTINO=sistema, lib/destino.sh).
source "$AQUI/../lib/destino.sh"
mkdir -p "$D_BIN"
install -m 755 "$AQUI/captura.sh" "$D_BIN/mac-captura"
install -m 755 "$AQUI/emojis.py" "$D_BIN/mac-emojis"
install -m 755 "$AQUI/herramienta.py" "$D_BIN/mac-captura-herramienta"
for p in gnome-screenshot xdotool xdg-user-dir import ffmpeg; do
  command -v "$p" >/dev/null || echo "Falta $p (sudo apt install $( [ $p = xdg-user-dir ] && echo xdg-user-dirs || { [ $p = import ] && echo imagemagick || echo $p; } ))"
done
echo "Capturas y emojis instalados en $D_BIN."
