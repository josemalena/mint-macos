#!/bin/bash
# Configura el dock (Plank) como el Dock de macOS Catalina.
#
# Lo llama instalar.sh en el paso «Activando», después del respaldo, que ya
# cubre /net/launchpad/plank/docks/ y los .dockitem: --deshacer devuelve el
# dock anterior. Se puede correr solo. No reinicia Plank: eso lo hace
# instalar.sh al final.
#
# Escribe las claves de /net/launchpad/plank/docks/dock1/ menos «theme», que
# es del tema (Constanza-Oscuro, de Infra), y los lanzadores del separador y
# de la pila de Descargas.
#
# El separador y la pila son docklets de plank-reloaded, compilado en
# ~/.local desde ~/Documents/Dev/repos/plank-reloaded (rama macos). Con el
# Plank del sistema esos dos lanzadores no existen y no se ponen.
#
# Variables:
#   PLANK_FINDER    el Finder del dock: fynder (por defecto, si está su
#                   .desktop; es el gestor de archivos de la casa) o nemo-mac. El
#                   lanzador fijado tiene que ser el .desktop de la app que
#                   abre las ventanas, para que caigan en ese ícono y no salgan
#                   aparte: Plank empareja la ventana con el .desktop por su
#                   clase (nemo-mac, fynder). Si no está, el nemo del sistema.
#   PLANK_MONITOR   monitor al que se fija el dock. Por defecto, el principal
#                   de ahora, por su nombre: si se desconecta, el dock se va al
#                   otro; cuando vuelve, regresa solo. Vacío = el principal del
#                   momento (lo de antes, que se quedaba en el otro monitor).
set -euo pipefail

CLAVES=/net/launchpad/plank/docks/dock1
LANZADORES="$HOME/.config/plank/dock1/launchers"
DOCKLETS="$HOME/.local/lib/x86_64-linux-gnu/plank/docklets"

# El orden del Dock de la Mac (c17): Finder, Siri, Launchpad, Spark, Calendar…
# App Store, System Preferences, Console, Terminal… Edge, Chrome, Safari y VS
# Code. Cada uno va en el lugar de su equivalente; los que no tienen uno van
# donde va su par por función: Thunderbird donde Spark (el correo), kitty donde
# Terminal y Firefox donde Safari. Los que no existan aquí se saltan.
ANTES=(finder launchpad applications thunderbird org.gnome.Calendar mintinstall
       cinnamon-settings kitty microsoft-edge firefox code)
DESPUES=(separator downloads-stack trash)

mkdir -p "$LANZADORES"

escribir_lanzador() { # nombre uri
  local f="$LANZADORES/$1.dockitem"
  [ -f "$f" ] && grep -q "^Launcher=$2\$" "$f" && return
  printf '[PlankDockItemPreferences]\nLauncher=%s\n' "$2" > "$f"
}

# El Finder: el .desktop de la app que de verdad abre las ventanas.
APPS="$HOME/.local/share/applications"
if [ -z "${PLANK_FINDER:-}" ]; then
  PLANK_FINDER=nemo-mac
  [ -f "$APPS/fynder.desktop" ] && PLANK_FINDER=fynder
fi
FINDER_DESKTOP="$APPS/$PLANK_FINDER.desktop"
[ -f "$FINDER_DESKTOP" ] || FINDER_DESKTOP="$APPS/nemo-mac.desktop"
[ -f "$FINDER_DESKTOP" ] || FINDER_DESKTOP=/usr/share/applications/nemo.desktop
escribir_lanzador finder "file://$FINDER_DESKTOP"
# El lanzador viejo apuntaba a nemo.desktop: sus ventanas (nemo-mac) salían
# como otro ícono.
rm -f "$LANZADORES/nemo.dockitem"

if [ -f "$DOCKLETS/libdocklet-separator.so" ] && [ -f "$DOCKLETS/libdocklet-stacks.so" ]; then
  escribir_lanzador separator docklet://separator
  escribir_lanzador downloads-stack docklet://stacks
  # La pila reemplaza a la carpeta Descargas suelta.
  rm -f "$LANZADORES/downloads.dockitem"
else
  echo "Plank: sin plank-reloaded en ~/.local; van sin separador ni pila." >&2
  DESPUES=(trash)
fi

# El orden: los de la Mac, después cualquier otro que haya, el separador, la
# pila y la Papelera.
lista=()
agregar() { [ -f "$LANZADORES/$1.dockitem" ] && lista+=("'$1.dockitem'") || true; }
for n in "${ANTES[@]}"; do agregar "$n"; done
for f in "$LANZADORES"/*.dockitem; do
  n="$(basename "$f" .dockitem)"
  [[ " ${ANTES[*]} ${DESPUES[*]} downloads nemo " == *" $n "* ]] && continue
  agregar "$n"
done
for n in "${DESPUES[@]}"; do agregar "$n"; done
items="[$(IFS=,; echo "${lista[*]}" | sed 's/,/, /g')]"

if [ -z "${PLANK_MONITOR+x}" ]; then
  PLANK_MONITOR="$(python3 - <<'PY' 2>/dev/null || true
import gi
gi.require_version('Gdk', '3.0')
from gi.repository import Gdk
d = Gdk.Display.get_default()
m = d.get_primary_monitor() if d else None
print(m.get_model() or '' if m else '')
PY
)"
fi

# El orden de la Mac se pone una sola vez: después José reorganiza el dock a
# mano (arrastrar, «Keep in Dock», «Remove from Dock») y una reinstalación no
# se lo deshace. Para volver al orden de la Mac: borrar la marca y correr esto.
MARCA="$LANZADORES/../.orden-mac-aplicado"
if [ ! -f "$MARCA" ]; then
  dconf write "$CLAVES/dock-items" "$items"
  touch "$MARCA"
else
  items="(se respeta el orden de José)"
fi
dconf write "$CLAVES/icon-size" 56
dconf write "$CLAVES/zoom-enabled" true
dconf write "$CLAVES/zoom-percent" 170
dconf write "$CLAVES/position" "'bottom'"
dconf write "$CLAVES/alignment" "'center'"
dconf write "$CLAVES/hide-mode" "'none'"
# Sin bloquear: se reordena arrastrando y se quita sacándolo del dock o con
# «Options ▸ Remove from Dock», como en macOS.
dconf write "$CLAVES/lock-items" false
dconf write "$CLAVES/monitor" "'$PLANK_MONITOR'"

echo "Plank: Finder $(basename "$FINDER_DESKTOP" .desktop), ${#lista[@]} ítems, ícono 56, ampliación 170 %, monitor «${PLANK_MONITOR:-el principal}»."
