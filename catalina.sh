#!/usr/bin/env bash
# Apariencia de macOS Catalina en modo oscuro: íconos con las formas de
# Catalina, dock Mojave, botones de ventana en el orden de macOS y Nemo
# acomodado como Finder. Respalda en ~/.mint-macos-respaldo/<fecha>-catalina/.
set -euo pipefail

RESPALDO="$HOME/.mint-macos-respaldo/$(date +%Y%m%d-%H%M%S)-catalina"
TMP="$(mktemp -d)"
mkdir -p "$RESPALDO"
paso() { printf '\n▸ %s\n' "$*"; }

paso "Respaldo de la apariencia actual"
dconf dump /org/cinnamon/desktop/interface/       > "$RESPALDO/interface.dconf"
dconf dump /org/cinnamon/desktop/wm/preferences/  > "$RESPALDO/wm-preferences.dconf"
dconf dump /org/cinnamon/theme/                   > "$RESPALDO/cinnamon-theme.dconf"
dconf dump /net/launchpad/plank/docks/            > "$RESPALDO/plank.dconf"
dconf dump /org/nemo/                             > "$RESPALDO/nemo.dconf"
echo "  $RESPALDO"

paso "Íconos Os-Catalina (formas de Catalina; lo que falta lo toma de McMojave)"
git clone -q --depth 1 https://github.com/vinceliuice/McMojave-circle.git "$TMP/McMojave-circle"
"$TMP/McMojave-circle/install.sh" -d "$HOME/.icons" >/dev/null
git clone -q --depth 1 https://github.com/zayronxio/Os-Catalina-icons.git "$TMP/Os-Catalina-icons"
rm -rf "$HOME/.icons/Os-Catalina" "$TMP/Os-Catalina-icons/.git"
cp -r "$TMP/Os-Catalina-icons" "$HOME/.icons/Os-Catalina"
sed -i 's/^Inherits=.*/Inherits=McMojave-circle-dark,WhiteSur-dark,gnome,hicolor/' "$HOME/.icons/Os-Catalina/index.theme"

# El tema trae dibujos viejos de VS Code y Edge: se usan los logos que
# trae cada aplicación instalada.
APPS="$HOME/.icons/Os-Catalina/128x128/apps"
logo() {  # logo <png oficial> <nombre principal> [otros nombres…]
  local origen="$1" nombre="$2"; shift 2
  [ -f "$origen" ] || return 0
  rm -f "$APPS/$nombre.svg"
  convert "$origen" -resize 256x256 "$APPS/$nombre.png"
  for n in "$@"; do rm -f "$APPS/$n.svg"; ln -sf "$nombre.png" "$APPS/$n.png"; done
  echo "  logo oficial: $nombre"
}
logo /usr/share/code/resources/app/resources/linux/code.png vscode code visual-studio-code com.visualstudio.code visualstudiocode
logo /opt/microsoft/msedge/product_logo_256.png microsoft-edge microsoft-edge-stable com.microsoft.Edge
gsettings set org.cinnamon.desktop.interface icon-theme 'Os-Catalina'

paso "Dock: tema Mojave oscuro"
git clone -q --depth 1 https://github.com/vinceliuice/Mojave-gtk-theme.git "$TMP/Mojave-gtk-theme"
mkdir -p "$HOME/.local/share/plank/themes/Mojave-Dark"
cp "$TMP/Mojave-gtk-theme/src/other/plank/Theme-Dark/"* "$HOME/.local/share/plank/themes/Mojave-Dark/"
dconf write /net/launchpad/plank/docks/dock1/theme "'Mojave-Dark'"

paso "Ventanas: botones cerrar, minimizar, maximizar a la izquierda"
gsettings set org.cinnamon.desktop.wm.preferences button-layout 'close,minimize,maximize:'

paso "Nemo como Finder"
P=org.nemo.preferences
for k in show-up-icon-toolbar show-edit-icon-toolbar show-home-icon-toolbar show-computer-icon-toolbar \
         show-reload-icon-toolbar show-new-folder-icon-toolbar show-open-in-terminal-toolbar \
         show-show-thumbnails-toolbar show-toggle-extra-pane-toolbar; do gsettings set $P $k false; done
for k in show-previous-icon-toolbar show-next-icon-toolbar show-icon-view-icon-toolbar \
         show-list-view-icon-toolbar show-compact-view-icon-toolbar show-search-icon-toolbar; do gsettings set $P $k true; done
gsettings set $P default-folder-viewer 'list-view'
gsettings set $P show-location-entry false
gsettings set org.nemo.window-state start-with-location-bar false
gsettings set org.nemo.window-state start-with-status-bar true
gsettings set org.nemo.window-state sidebar-width 200
gsettings set org.nemo.list-view enable-folder-expansion true
gsettings set org.nemo.list-view default-visible-columns "['name', 'date_modified', 'size']"
gsettings set org.nemo.list-view default-column-order "['name', 'date_modified', 'size', 'type']"
gsettings set org.nemo.list-view default-zoom-level 'small'

paso "Reiniciando Plank"
for p in $(pgrep -x plank); do kill "$p"; done
sleep 2
setsid nohup plank >/dev/null 2>&1 < /dev/null &

paso "Listo"
echo "  Pendiente: el tema Mojave de ventanas, Cinnamon y la ventana de login."
echo "  Para volver atrás: dconf load con los archivos de $RESPALDO"
