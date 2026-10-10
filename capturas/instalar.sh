#!/bin/bash
# Capturas y emojis como en macOS: instala los dos guiones en ~/.local/bin,
# donde los buscan los atajos de cinnamon/keybindings.dconf (custom2…custom7).
#
#   mac-captura   ⇧⌘3 ⇧⌘4 ⇧⌘5 ⌃⇧⌘3 ⌃⇧⌘4
#   mac-emojis    ⌃⌘Espacio
#
# Para quitarlos: rm ~/.local/bin/mac-captura ~/.local/bin/mac-emojis (los
# atajos quedan apuntando a nada y no hacen nada).
set -euo pipefail
AQUI="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$HOME/.local/bin"
install -m 755 "$AQUI/captura.sh" "$HOME/.local/bin/mac-captura"
install -m 755 "$AQUI/emojis.py" "$HOME/.local/bin/mac-emojis"
for p in gnome-screenshot xdotool xdg-user-dir; do
  command -v "$p" >/dev/null || echo "Falta $p (sudo apt install $( [ $p = xdg-user-dir ] && echo xdg-user-dirs || echo $p ))"
done
echo "Capturas y emojis instalados en ~/.local/bin."
