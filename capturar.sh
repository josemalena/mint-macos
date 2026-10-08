#!/usr/bin/env bash
# Trae al repo los ajustes tal como están ahora en esta computadora, para
# commitear lo que se fue ajustando a mano. Lo inverso de install.sh.
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"

dconf dump /org/cinnamon/desktop/keybindings/   > "$REPO/cinnamon/keybindings.dconf"
dconf dump /org/cinnamon/desktop/input-sources/ > "$REPO/cinnamon/input-sources.dconf"
dconf dump /org/gnome/libgnomekbd/keyboard/     > "$REPO/cinnamon/libgnomekbd-keyboard.dconf"

# kitty: si los atajos ya viven en macos-keys.conf, se copia ese; si no,
# se recorta del kitty.conf desde la marca «# Keybindings estilo macOS».
if [ -f "$HOME/.config/kitty/macos-keys.conf" ]; then
  cp "$HOME/.config/kitty/macos-keys.conf" "$REPO/kitty/macos-keys.conf"
else
  sed -n '/^# Keybindings estilo macOS/,$p' "$HOME/.config/kitty/kitty.conf" > "$REPO/kitty/macos-keys.conf"
fi

[ -f /etc/keyd/default.conf ] && cp /etc/keyd/default.conf "$REPO/keyd/default.conf"
[ -f "$HOME/.config/keyd/app.conf" ] && cp "$HOME/.config/keyd/app.conf" "$REPO/keyd/app.conf"

cp "$HOME/.config/Code/User/keybindings.json" "$REPO/vscode/keybindings.json"

for a in "$REPO"/applets/*@macos; do
  origen="$HOME/.local/share/cinnamon/applets/$(basename "$a")"
  [ -d "$origen" ] && rsync -a --delete --exclude __pycache__ "$origen/" "$a/"
done

git -C "$REPO" status --short
