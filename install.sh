#!/usr/bin/env bash
# Transforma Linux Mint (Cinnamon) para que se maneje como macOS:
# ⌘ = Super, ⌥ = Alt, en el escritorio, kitty y VS Code, más los applets
# del menú Apple. Antes de tocar un archivo lo respalda en
# ~/.mint-macos-respaldo/<fecha>/, así que se puede deshacer.
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
RESPALDO="$HOME/.mint-macos-respaldo/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$RESPALDO"

paso() { printf '\n▸ %s\n' "$*"; }
respaldar() { [ -e "$1" ] && cp -a "$1" "$RESPALDO/" && echo "  respaldo: $RESPALDO/$(basename "$1")" || true; }

paso "Dependencias de los applets (python3-gi, wmctrl)"
if ! dpkg -s python3-gi wmctrl >/dev/null 2>&1; then
  sudo apt install -y python3 python3-gi wmctrl
else
  echo "  ya están"
fi

paso "Cinnamon: atajos y fuentes de entrada"
for ruta in /org/cinnamon/desktop/keybindings/ /org/cinnamon/desktop/input-sources/ /org/gnome/libgnomekbd/keyboard/; do
  nombre="$(echo "$ruta" | tr '/' '_' | sed 's/^_//;s/_$//').dconf"
  dconf dump "$ruta" > "$RESPALDO/$nombre"
done
dconf load /org/cinnamon/desktop/keybindings/   < "$REPO/cinnamon/keybindings.dconf"
dconf load /org/cinnamon/desktop/input-sources/ < "$REPO/cinnamon/input-sources.dconf"
dconf load /org/gnome/libgnomekbd/keyboard/     < "$REPO/cinnamon/libgnomekbd-keyboard.dconf"
echo "  respaldo de dconf en $RESPALDO"

paso "kitty: atajos ⌘ y ⌥ (se incluyen, no se reemplaza el kitty.conf)"
KITTY="$HOME/.config/kitty"
mkdir -p "$KITTY"
respaldar "$KITTY/macos-keys.conf"
cp "$REPO/kitty/macos-keys.conf" "$KITTY/macos-keys.conf"
touch "$KITTY/kitty.conf"
if ! grep -q '^include macos-keys.conf' "$KITTY/kitty.conf"; then
  respaldar "$KITTY/kitty.conf"
  printf '\n# Atajos estilo macOS (repo mint-macos)\ninclude macos-keys.conf\n' >> "$KITTY/kitty.conf"
fi

paso "VS Code: keybindings.json"
VSCODE="$HOME/.config/Code/User"
mkdir -p "$VSCODE"
respaldar "$VSCODE/keybindings.json"
cp "$REPO/vscode/keybindings.json" "$VSCODE/keybindings.json"

paso "Applets del menú Apple"
APPLETS="$HOME/.local/share/cinnamon/applets"
mkdir -p "$APPLETS"
for a in "$REPO"/applets/*@macos; do
  [ -e "$APPLETS/$(basename "$a")" ] && respaldar "$APPLETS/$(basename "$a")"
  rm -rf "${APPLETS:?}/$(basename "$a")"
  cp -r "$a" "$APPLETS/"
  echo "  $(basename "$a")"
done

paso "Listo"
echo "  Agrega los applets al panel en System Settings → Applets."
echo "  En kitty: ctrl+shift+F5 recarga la configuración."
echo "  Para deshacer: los originales están en $RESPALDO"
