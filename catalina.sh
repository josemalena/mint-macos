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

paso "Tema Mojave oscuro: ventanas, bordes y panel (pide sassc y glib-compile-resources)"
if ! command -v sassc >/dev/null || ! command -v glib-compile-resources >/dev/null; then
  sudo apt install -y sassc libglib2.0-dev-bin
fi
git clone -q --depth 1 https://github.com/vinceliuice/Mojave-gtk-theme.git "$TMP/Mojave-gtk-theme"
rm -rf "$HOME/.themes/Mojave-Dark"*
"$TMP/Mojave-gtk-theme/install.sh" -d "$HOME/.themes" -c dark >/dev/null
gsettings set org.cinnamon.desktop.interface gtk-theme 'Mojave-Dark'
gsettings set org.cinnamon.desktop.wm.preferences theme 'Mojave-Dark'
gsettings set org.cinnamon.theme name 'Mojave-Dark'

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
# En 16 y 24 px el tema usa carpetas monocromas oscuras (pensadas para
# fondo claro): en Nemo oscuro salen negras. Finder las enseña azules a
# cualquier tamaño, así que los chicos apuntan al dibujo de 128 px. Los
# *-symbolic (los del lateral) no se tocan.
I="$HOME/.icons/Os-Catalina"
for d in 16x16/places 16x16@2x/places symbolic/places; do
  for f in "$I/$d"/*.svg; do
    b="$(basename "$f")"
    case "$b" in *-symbolic.svg) continue ;; esac
    [ -e "$I/128x128/places/$b" ] || continue
    rm -f "$f"; ln -s "../../128x128/places/$b" "$f"
  done
done
gsettings set org.cinnamon.desktop.interface icon-theme 'Os-Catalina'

# Si está el disco de la Mac en esta computadora, el lateral usa los íconos
# originales del Finder (Os-Catalina-Finder, hereda de Os-Catalina). Se
# generan aquí mismo desde el disco: los íconos de Apple no van al repo.
# Sin disco de Mac (sale con 3), se queda Os-Catalina.
REPO_CAT="$(cd "$(dirname "$0")" && pwd)"
if "$REPO_CAT/iconos/finder-desde-mac.sh"; then
  gsettings set org.cinnamon.desktop.interface icon-theme 'Os-Catalina-Finder'
fi

paso "Fuente: San Francisco si está instalada, si no Inter"
# San Francisco se instala aparte desde el disco de la Mac (fuentes/san-francisco.md);
# no viene en el repo. Su familia en gsettings es «.SF NS». Si no está, Inter
# (la alternativa libre con las mismas proporciones; «Inter», no «Inter
# Display», que es para títulos grandes).
if fc-list : family | grep -q '^\.SF NS$\|,\.SF NS$\|^\.SF NS,'; then
  FUENTE='.SF NS'; TITULO='.SF NS Semibold'
else
  dpkg -s fonts-inter >/dev/null 2>&1 || sudo apt install -y fonts-inter
  FUENTE='Inter'; TITULO='Inter Semi-Bold'
fi
{ gsettings get org.cinnamon.desktop.interface font-name
  gsettings get org.gnome.desktop.interface document-font-name
  gsettings get org.cinnamon.desktop.wm.preferences titlebar-font; } > "$RESPALDO/fuentes.txt"
gsettings set org.cinnamon.desktop.interface font-name "$FUENTE 10"
gsettings set org.gnome.desktop.interface font-name "$FUENTE 10"
gsettings set org.gnome.desktop.interface document-font-name "$FUENTE 10"
gsettings set org.cinnamon.desktop.wm.preferences titlebar-font "$TITULO 10"
gsettings set org.nemo.desktop font "$FUENTE 10"
echo "  fuente: $FUENTE"

paso "Retoques de GTK (selector de vista segmentado de nemo-mac)"
REPO="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$HOME/.config/gtk-3.0"
cp "$REPO/gtk/mint-macos.css" "$HOME/.config/gtk-3.0/mint-macos.css"
touch "$HOME/.config/gtk-3.0/gtk.css"
grep -q 'mint-macos.css' "$HOME/.config/gtk-3.0/gtk.css" || sed -i '1i @import url("mint-macos.css");' "$HOME/.config/gtk-3.0/gtk.css"

paso "Dock: tema Mojave oscuro"
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
echo "  Pendiente: la ventana de login."
echo "  Para volver atrás: dconf load con los archivos de $RESPALDO"
