#!/usr/bin/env bash
# Tema de íconos «Constanza» en ~/.local/share/icons/Constanza.
#  1. Instala Os-Catalina (zayronxio, GPL-3.0) en ~/.icons, versión fijada.
#  2. Constanza hereda de Os-Catalina y pone encima:
#     - las carpetas azules de 128 px también en tamaño chico (en Os-Catalina
#       son monocromas oscuras y en un tema oscuro salen negras);
#     - los logos de VS Code y Edge que traen esas aplicaciones;
#     - si hay disco de Mac, los íconos del Finder (finder.py): carpetas,
#       documentos, discos, papelera y los glifos del lateral.
# Nada de Apple se guarda en el repo: se genera aquí desde el disco.
set -euo pipefail
AQUI="$(cd "$(dirname "$0")" && pwd)"
source "$AQUI/../comun.sh"
OS_CATALINA_COMMIT=aeb32ce
TEMA="$HOME/.local/share/icons/Constanza"
TMP="$(mktemp -d)"
trap 'desmontar_mac; rm -rf "$TMP"' EXIT

OSC="$HOME/.icons/Os-Catalina"
# Solo se reinstala si cambia la versión: reinstalarlo borra los arreglos de
# abajo, y si es el tema activo las carpetas salen negras mientras tanto.
if [ "$(cat "$OSC/.version-constanza" 2>/dev/null)" != "$OS_CATALINA_COMMIT" ]; then
  echo "  Os-Catalina $OS_CATALINA_COMMIT"
  git clone -q https://github.com/zayronxio/Os-Catalina-icons.git "$TMP/osc"
  git -C "$TMP/osc" checkout -q "$OS_CATALINA_COMMIT"
  rm -rf "$TMP/osc/.git"
  mkdir -p "$HOME/.icons"
  rm -rf "$OSC.nuevo"; cp -r "$TMP/osc" "$OSC.nuevo"
  sed -i 's/^Inherits=.*/Inherits=McMojave-circle-dark,WhiteSur-dark,gnome,hicolor/' "$OSC.nuevo/index.theme"
  echo "$OS_CATALINA_COMMIT" > "$OSC.nuevo/.version-constanza"
  rm -rf "$OSC"; mv "$OSC.nuevo" "$OSC"
fi
# Arreglos sobre Os-Catalina (sirven también sin disco de Mac):
# carpetas chicas azules (eran monocromas oscuras) y logos oficiales.
for d in 16x16/places 16x16@2x/places symbolic/places; do
  for f in "$OSC/$d"/*.svg; do
    b="$(basename "$f")"; case "$b" in *-symbolic.svg) continue ;; esac
    [ -e "$OSC/128x128/places/$b" ] || continue
    [ "$(readlink "$f")" = "../../128x128/places/$b" ] && continue
    rm -f "$f"; ln -s "../../128x128/places/$b" "$f"
  done
done

rm -rf "$TEMA"; mkdir -p "$TEMA/escalables/places" "$TEMA/escalables/apps"
DIRS=()

# Carpetas azules a cualquier tamaño (los *-symbolic del lateral no se tocan).
for f in "$OSC"/128x128/places/*.svg; do
  b="$(basename "$f")"; case "$b" in *-symbolic.svg) continue ;; esac
  ln -s "$f" "$TEMA/escalables/places/$b"
done

# Logos oficiales que traen las aplicaciones instaladas.
logo() { [ -f "$1" ] || return 0; local origen="$1" n="$2" a dir; shift 2
  for dir in "$TEMA/escalables/apps" "$OSC/128x128/apps"; do
    rm -f "$dir/$n.svg"; convert "$origen" -resize 256x256 "$dir/$n.png"
    for a in "$@"; do rm -f "$dir/$a.svg"; ln -sf "$n.png" "$dir/$a.png"; done
  done; }
logo /usr/share/code/resources/app/resources/linux/code.png vscode code visual-studio-code com.visualstudio.code visualstudiocode
logo /opt/microsoft/msedge/product_logo_256.png microsoft-edge microsoft-edge-stable com.microsoft.Edge

# Íconos del Finder si hay disco de Mac.
if montar_mac_sistema; then
  # Glifos de la barra, si ya se exportaron en la Mac (macos/exportar-glifos.swift).
  for g in "${GLIFOS_FINDER:-}" "/media/$USER/MacMini/Users/Shared/glifos-finder"; do
    [ -n "$g" ] && [ -d "$g/png" ] && { export GLIFOS_FINDER="$g"; break; }
  done
  python3 "$AQUI/finder.py" "$MAC_SISTEMA" "$TEMA" "#c4c4c4"
  while read -r sub t esc; do DIRS+=("$sub $t $esc Fixed"); done < "$TEMA/finder-dirs.txt"
  rm -f "$TEMA/finder-dirs.txt"
  desmontar_mac
else
  echo "  sin disco de Mac: Constanza queda como Os-Catalina con sus arreglos"
fi

# Los del Finder van primero en la lista: si un nombre existe también en los
# escalables, GTK se queda con el que encuentra antes.
DIRS+=("escalables/places 128 1 Scalable" "escalables/apps 128 1 Scalable")

{
  echo "[Icon Theme]"
  echo "Name=Constanza"
  echo "Comment=Os-Catalina con los íconos del Finder (generados en local)"
  echo "Inherits=Os-Catalina"
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
echo "  íconos: $TEMA"
