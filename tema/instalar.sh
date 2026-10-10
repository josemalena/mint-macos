#!/usr/bin/env bash
# Instala y activa el tema Constanza (oscuro, estilo macOS Catalina/Mojave).
#   ./instalar.sh             construye todo y lo activa
#   ./instalar.sh --construir solo construye (no cambia nada de la sesión)
#   ./instalar.sh --deshacer  vuelve a como estaba antes de la última activación
# Respaldos en ~/.mint-macos-respaldo/<fecha>-constanza/.
set -euo pipefail
AQUI="$(cd "$(dirname "$0")" && pwd)"
source "$AQUI/comun.sh"
RESP_BASE="$HOME/.mint-macos-respaldo"
ULTIMO="$RESP_BASE/ultimo-constanza"
KITTY="$HOME/.config/kitty/kitty.conf"
GTKCSS="$HOME/.config/gtk-3.0/gtk.css"
paso() { printf '\n▸ %s\n' "$*"; }

DCONF_RUTAS=(/org/cinnamon/desktop/interface/ /org/gnome/desktop/interface/ \
             /org/cinnamon/desktop/wm/preferences/ /org/cinnamon/theme/ \
             /net/launchpad/plank/docks/ /org/nemo/ \
             /org/cinnamon/desktop/background/)

reiniciar_plank() {
  for p in $(pgrep -x plank); do kill "$p"; done; sleep 1
  setsid nohup plank >/dev/null 2>&1 < /dev/null &
}

if [ "${1:-}" = "--deshacer" ]; then
  R="$(cat "$ULTIMO" 2>/dev/null)" || { echo "No hay respaldo de Constanza."; exit 1; }
  paso "Volviendo al respaldo $R"
  for ruta in "${DCONF_RUTAS[@]}"; do
    f="$R/$(echo "$ruta" | tr '/' '_' | sed 's/^_//;s/_$//').dconf"
    [ -f "$f" ] && dconf load "$ruta" < "$f"
  done
  [ -f "$R/kitty.conf" ] && cp "$R/kitty.conf" "$KITTY"
  [ -f "$R/gtk.css" ] && cp "$R/gtk.css" "$GTKCSS"
  reiniciar_plank
  echo "  listo; en kitty, ctrl+shift+F5 recarga la fuente"
  exit 0
fi

trap desmontar_mac EXIT
paso "Disco de la Mac (íconos del Finder, San Francisco y fondo)"
if montar_mac_sistema; then echo "  $MAC_SISTEMA"; export MAC_SISTEMA; HAY_MAC=1
else echo "  no está: Os-Catalina e Inter"; HAY_MAC=0; fi

paso "Tema GTK Constanza-Oscuro";  "$AQUI/gtk/construir.sh"
paso "Íconos Constanza";           "$AQUI/iconos/construir.sh"
paso "Fuentes San Francisco";      "$AQUI/fuentes/desde-mac.sh" || true
paso "Fondo de Catalina";         "$AQUI/fondo/desde-mac.sh" || true
paso "Manzana del menú Apple";     python3 "$AQUI/manzana/desde-fuente.py" || true
desmontar_mac

[ "${1:-}" = "--construir" ] && { echo; echo "Construido; no se activó nada."; exit 0; }

paso "Respaldo de lo actual"
R="$RESP_BASE/$(date +%Y%m%d-%H%M%S)-constanza"; mkdir -p "$R"
for ruta in "${DCONF_RUTAS[@]}"; do
  dconf dump "$ruta" > "$R/$(echo "$ruta" | tr '/' '_' | sed 's/^_//;s/_$//').dconf"
done
[ -f "$KITTY" ] && cp "$KITTY" "$R/kitty.conf"
[ -f "$GTKCSS" ] && cp "$GTKCSS" "$R/gtk.css"
echo "$R" > "$ULTIMO"; echo "  $R"

paso "Activando"
gsettings set org.cinnamon.desktop.interface gtk-theme 'Constanza-Oscuro'
gsettings set org.cinnamon.desktop.wm.preferences theme 'Constanza-Oscuro'
gsettings set org.cinnamon.theme name 'Constanza-Oscuro'
gsettings set org.cinnamon.desktop.interface icon-theme 'Constanza'
gsettings set org.cinnamon.desktop.interface cursor-theme 'McMojave-cursors' 2>/dev/null || true
gsettings set org.cinnamon.desktop.wm.preferences button-layout 'close,minimize,maximize:'
dconf write /net/launchpad/plank/docks/dock1/theme "'Constanza-Oscuro'"

# Fondo: Catalina al atardecer, si se pudo sacar de la Mac; si no, se queda
# el que haya. «zoom» llena los dos monitores (16:10 y 5:4) recortando
# arriba y abajo de la imagen cuadrada, sin franjas.
FONDO="$HOME/.local/share/backgrounds/constanza/catalina.jpg"
if [ -f "$FONDO" ]; then
  gsettings set org.cinnamon.desktop.background picture-uri "file://$FONDO"
  gsettings set org.cinnamon.desktop.background picture-options 'zoom'
  echo "  fondo: $FONDO"
fi

# Ojo con pipefail: «fc-list | grep -q» falla al azar porque grep corta la
# tubería y fc-list muere por SIGPIPE. Por eso se lee primero a una variable.
FAMILIAS="$(fc-list : family)"
if grep -q '^\.SF NS$\|,\.SF NS$\|^\.SF NS,' <<< "$FAMILIAS"; then
  FUENTE='.SF NS'; TITULO='.SF NS Semibold'
else
  dpkg -s fonts-inter >/dev/null 2>&1 || sudo apt install -y fonts-inter
  FUENTE='Inter'; TITULO='Inter Semi-Bold'
fi
gsettings set org.cinnamon.desktop.interface font-name "$FUENTE 10"
gsettings set org.gnome.desktop.interface font-name "$FUENTE 10"
gsettings set org.gnome.desktop.interface document-font-name "$FUENTE 10"
gsettings set org.cinnamon.desktop.wm.preferences titlebar-font "$TITULO 10"
# Los nombres del escritorio, como en macOS: negrita a 12 px (9 pt a 96 ppp).
# Sin la SF se queda la fuente de interfaz normal.
if [ "$FUENTE" = '.SF NS' ]; then
  gsettings set org.nemo.desktop font '.SF NS Bold 9'
else
  gsettings set org.nemo.desktop font "$FUENTE 10"
fi
echo "  fuente: $FUENTE"

# El segmentado y demás retoques ya vienen dentro del tema: el gtk.css del
# usuario deja de importar mint-macos.css.
[ -f "$GTKCSS" ] && sed -i '/@import url("mint-macos.css");/d' "$GTKCSS"

# kitty con SF Mono, si está. Los glifos de Nerd Font del prompt siguen
# saliendo de MesloLGS NF con symbol_map.
if [ -f "$KITTY" ] && grep -qx 'SF Mono' <<< "$FAMILIAS"; then
  sed -i -e 's/^font_family .*/font_family      SF Mono/' \
         -e 's/^bold_font .*/bold_font        auto/' \
         -e 's/^italic_font .*/italic_font      auto/' \
         -e 's/^bold_italic_font .*/bold_italic_font auto/' "$KITTY"
  grep -q '^symbol_map .*MesloLGS' "$KITTY" || \
    printf '\n# Glifos de Nerd Font (prompt, íconos) desde MesloLGS NF\nsymbol_map U+E000-U+F8FF,U+F0000-U+FFFFF MesloLGS NF\n' >> "$KITTY"
  echo "  kitty: SF Mono (ctrl+shift+F5 para recargar)"
fi

reiniciar_plank
echo; echo "Constanza activado. Para volver atrás: $0 --deshacer"
