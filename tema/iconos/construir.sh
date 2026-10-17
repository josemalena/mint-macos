#!/usr/bin/env bash
# Tema de íconos «Constanza» en ~/.local/share/icons/Constanza (CONSTANZA_DESTINO lo cambia,
# para armarlo aparte y comparar antes de cambiarlo por el activo).
#
# Todo sale del disco de la Mac o es el logo que trae cada app; lo que Apple no tiene cae a
# Adwaita, gnome y hicolor (los de Linux). Ya no hereda de Os-Catalina, McMojave ni WhiteSur
# (decisión de José, 14-10-2026):
#     - los logos que traen las apps (VS Code, Edge, Thunderbird, LibreOffice, Firefox,
#       VLC…), del paquete, Flatpak o snap;
#     - si hay disco de Mac: los íconos de las apps de macOS para sus equivalentes de Linux
#       y los paneles de Ajustes (macos_apps.py), los cursores de Catalina (cursores.py) y
#       los íconos del Finder (finder.py): carpetas, documentos, discos, papelera y los
#       glifos del lateral; y los glifos de la barra de menú (barra.py: Bluetooth).
# Nada de Apple se guarda en el repo: se genera aquí desde el disco.
set -euo pipefail
AQUI="$(cd "$(dirname "$0")" && pwd)"
source "$AQUI/../comun.sh"
DESTINO="${CONSTANZA_DESTINO:-$HOME/.local/share/icons/Constanza}"
# Se arma en una carpeta hermana y solo si todo salió bien se cambia por la de siempre: el tema
# activo no se toca mientras tanto, y si el guion se cae no se pierde (queda la nueva a medias, que se borra).
TEMA="$DESTINO.nueva-$$"
TMP="$(mktemp -d)"
LISTO=0
limpiar() {
  desmontar_mac
  rm -rf "${TMP:?}"
  [ "$LISTO" = 1 ] || rm -rf "${TEMA:?}"
}
trap limpiar EXIT

rm -rf "${TEMA:?}"; mkdir -p "$TEMA/escalables/places" "$TEMA/escalables/apps"
DIRS=()

# Logos oficiales que traen las aplicaciones instaladas.
logo() { [ -f "$1" ] || return 0; local origen="$1" n="$2" a dir; shift 2
  for dir in "$TEMA/escalables/apps"; do
    rm -f "$dir/$n.svg"; convert "$origen" -resize 256x256 "$dir/$n.png"
    for a in "$@"; do rm -f "$dir/$a.svg"; ln -sf "$n.png" "$dir/$a.png"; done
  done; }
logo /usr/share/code/resources/app/resources/linux/code.png vscode code visual-studio-code com.visualstudio.code visualstudiocode
logo /opt/microsoft/msedge/product_logo_256.png microsoft-edge microsoft-edge-stable com.microsoft.Edge
# Thunderbird con su propio logo (José no quiere el del Mail).
logo /usr/share/icons/hicolor/256x256/apps/thunderbird.png thunderbird mozilla-thunderbird thunderbird-bin net.thunderbird.Thunderbird org.mozilla.Thunderbird
# LibreOffice con sus logos. Vienen en SVG: se enlazan tal cual.
for f in /usr/share/icons/hicolor/scalable/apps/libreoffice-*.svg; do
  [ -f "$f" ] && ln -sf "$f" "$TEMA/escalables/apps/$(basename "$f")"
done

# Los logos que traen las apps (K3b, Plank…). Primero el SVG de hicolor; si no hay, el PNG
# más grande. Si después el disco de la Mac trae un equivalente (abajo), ese gana. GTK sabe
# dónde buscar: hicolor del sistema, Flatpak, categories/, stock/…
python3 "$AQUI/originales.py" "$TEMA/escalables/apps" k3b stock_xfburn winetricks plank cs-color gtk-select-color cs-applets cs-desklets \
         mintdrivers accessories-character-map ibus-setup \
         firefox google-chrome vlc com.obsproject.Studio fr.handbrake.ghb kitty com.gexperts.Tilix \
         transmission lutris timeshift ulauncher solaar org.raspberrypi.rpi-imager gvim fish btop \
         org.x.Warpinator forticlient com.github.maoschanz.drawing bulky \
         org.gnome.Terminal org.gnome.Calculator xreader xviewer pix org.gnome.FileRoller \
         org.gnome.DiskUtility org.gnome.SystemMonitor org.gnome.font-viewer org.gnome.Screenshot \
         sticky org.gnome.Rhythmbox3 io.github.celluloid_player.Celluloid org.gnome.seahorse.Application \
         org.gnome.SimpleScan mintbackup mintreport mintupdate

# Íconos del Finder si hay disco de Mac.
if montar_mac_sistema; then
  # Glifos de la barra (SystemAppearance.bundle/Assets.car). Sus mapas de
  # bits van en deepmap2, que solo abre CoreUI, pero cada glifo trae su
  # vector en PDF: car.py lo dibuja aquí a 1x y 2x (pdftocairo), y en su
  # versión de modo oscuro, que en Catalina cambia de forma (la vista de
  # íconos, la Galería y Arrange son rellenos). La carpeta sacada en una Mac
  # (GLIFOS_FINDER o la de siempre) queda de respaldo: es de modo claro.
  CAR_SISTEMA="$MAC_SISTEMA/System/Library/CoreServices/SystemAppearance.bundle/Contents/Resources/Assets.car"
  if [ -f "$CAR_SISTEMA" ] && command -v pdftocairo >/dev/null \
     && python3 "$AQUI/car.py" glifos "$CAR_SISTEMA" "$TMP/glifos" --oscuro; then
    export GLIFOS_FINDER="$TMP/glifos"
  else
    for g in "${GLIFOS_FINDER:-}" "$HOME/.local/share/constanza/glifos-finder"; do
      [ -n "$g" ] && [ -f "$g/GoBack@1x.png" ] && { export GLIFOS_FINDER="$g"; break; }
    done
  fi
  # Connect de la barra del Finder (ToolbarConnectTemplate) está en el catálogo del propio Finder.app, no en SystemAppearance.
  CAR_FINDER="$MAC_SISTEMA/System/Library/CoreServices/Finder.app/Contents/Resources/Assets.car"
  if [ "${GLIFOS_FINDER:-}" = "$TMP/glifos" ] && [ -f "$CAR_FINDER" ] && command -v pdftocairo >/dev/null; then
    python3 "$AQUI/car.py" glifos "$CAR_FINDER" "$TMP/glifos" ToolbarConnectTemplate --oscuro \
      || echo "  ⚠ sin el glifo Connect del Finder"
  fi
  python3 "$AQUI/finder.py" "$MAC_SISTEMA" "$TEMA" "#98999b" "#eaebed"   # lateral y barra
  # Las apps de Linux con equivalente en macOS (Terminal, Preview, Disk
  # Utility…) y los paneles de Ajustes, con el ícono de la Mac.
  python3 "$AQUI/macos_apps.py" "$MAC_SISTEMA" "$TEMA/escalables/apps"
  # Los glifos de la barra de menú (Bluetooth) de los Menu Extras de la Mac.
  mkdir -p "$TEMA/escalables/status"
  python3 "$AQUI/barra.py" "$MAC_SISTEMA" "$TEMA/escalables/status" || echo "  ⚠ sin glifos de la barra de la Mac"
  DIRS+=("escalables/status 16 1 Scalable")
  # Los cursores de Catalina (los vectores de HIServices) en $TEMA/cursors,
  # sobre McMojave-cursors, que pone los nombres que faltan.
  python3 "$AQUI/cursores.py" \
    "$MAC_SISTEMA/System/Library/Frameworks/ApplicationServices.framework/Versions/A/Frameworks/HIServices.framework/Versions/A/Resources/cursors" \
    "$TEMA" || echo "  ⚠ sin cursores de Catalina"
  while read -r sub t esc; do DIRS+=("$sub $t $esc Fixed"); done < "$TEMA/finder-dirs.txt"
  rm -f "$TEMA/finder-dirs.txt"
  desmontar_mac
else
  echo "  sin disco de Mac: Constanza solo trae los logos de las apps; el resto cae a Adwaita y hicolor"
fi

# Los del Finder van primero en la lista: si un nombre existe también en los
# escalables, GTK se queda con el que encuentra antes.
DIRS+=("escalables/places 128 1 Scalable" "escalables/apps 128 1 Scalable")

{
  echo "[Icon Theme]"
  echo "Name=Constanza"
  echo "Comment=Íconos de la Mac (generados en local) sobre Adwaita"
  echo "Inherits=Adwaita,gnome,hicolor"
  printf 'Directories=%s\n\n' "$(printf '%s\n' "${DIRS[@]}" | awk '{print $1}' | paste -sd,)"
  for d in "${DIRS[@]}"; do
    set -- $d
    echo "[$1]"; echo "Size=$2"; echo "Scale=$3"; echo "Type=$4"
    [ "$4" = Scalable ] && { echo "MinSize=8"; echo "MaxSize=512"; }
    case "$1" in *symbolic*|*places*) echo "Context=Places";; *apps*) echo "Context=Applications";; *) echo "Context=Places";; esac
    echo
  done
} > "$TEMA/index.theme"
gtk-update-icon-cache -q -f "$TEMA" 2>/dev/null || true

# El cambio de un golpe: el tema de antes pasa a respaldo (uno solo) y el nuevo ocupa su lugar.
# Dentro del tema solo hay rutas relativas, así que mover la carpeta no lo rompe.
RESPALDO="$HOME/.local/share/mint-macos/respaldos/$(basename "$DESTINO")-anterior"
if [ -e "$DESTINO" ] || [ -L "$DESTINO" ]; then
  mkdir -p "$(dirname "$RESPALDO")"
  rm -rf "${RESPALDO:?}"
  mv "$DESTINO" "$RESPALDO"
fi
mv "$TEMA" "$DESTINO"
LISTO=1
gtk-update-icon-cache -q -f "$DESTINO" 2>/dev/null || true
echo "  íconos: $DESTINO (el anterior quedó en $RESPALDO)"
