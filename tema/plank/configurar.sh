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
#   PLANK_MONITOR   monitor al que se fija el dock. Por defecto, el principal
#                   de ahora, por su nombre: si se desconecta, el dock se va al
#                   otro; cuando vuelve, regresa solo. Vacío = el principal del
#                   momento (lo de antes, que se quedaba en el otro monitor).
set -euo pipefail

CLAVES=/net/launchpad/plank/docks/dock1
LANZADORES="$HOME/.config/plank/dock1/launchers"
DOCKLETS="$HOME/.local/lib/x86_64-linux-gnu/plank/docklets"

# El orden del Dock de la Mac, con los equivalentes que eligió José. Los que no
# existan en esta computadora se saltan.
ANTES=(launchpad nemo mintinstall applications microsoft-edge thunderbird
       org.gnome.Calendar firefox cinnamon-settings kitty code)
DESPUES=(separator downloads-stack trash)

mkdir -p "$LANZADORES"

escribir_lanzador() { # nombre uri
  local f="$LANZADORES/$1.dockitem"
  [ -f "$f" ] && grep -q "^Launcher=$2\$" "$f" && return
  printf '[PlankDockItemPreferences]\nLauncher=%s\n' "$2" > "$f"
}

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
  [[ " ${ANTES[*]} ${DESPUES[*]} downloads " == *" $n "* ]] && continue
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

dconf write "$CLAVES/dock-items" "$items"
dconf write "$CLAVES/icon-size" 56
dconf write "$CLAVES/zoom-enabled" true
dconf write "$CLAVES/zoom-percent" 170
dconf write "$CLAVES/position" "'bottom'"
dconf write "$CLAVES/alignment" "'center'"
dconf write "$CLAVES/hide-mode" "'none'"
dconf write "$CLAVES/monitor" "'$PLANK_MONITOR'"

echo "Plank: ${#lista[@]} ítems, ícono 56, ampliación 170 %, monitor «${PLANK_MONITOR:-el principal}»."
