#!/bin/bash
# Configura el Dock (Muelle, o el Plank de antes si Muelle no está: tema/dock.sh) como el Dock de
# macOS Catalina.
#
# Lo llama instalar.sh en el paso «Activando», después del respaldo, que ya
# cubre el árbol de dconf del Dock y los .dockitem: --deshacer devuelve el
# dock anterior. Se puede correr solo. No reinicia Plank: eso lo hace
# instalar.sh al final.
#
# Escribe las claves de $DOCK_DCONF/docks/dock1/ menos «theme», que
# es del tema (Constanza-Oscuro, de Infra), y los lanzadores del separador y
# de la pila de Descargas.
#
# El separador y la pila son docklets de Muelle (el fork de
# plank-reloaded), que construir.sh compila en ~/.local. Con el
# Plank del sistema esos dos lanzadores no existen y no se ponen.
#
# Variables:
#   PLANK_ORDEN_MAC=1  vuelve a crear los lanzadores que falten y a poner el
#                   orden de la Mac aunque ya se hubiera puesto (instalar-aqui.sh,
#                   después de instalar Launchpad y System Preferences)
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

source "$(cd "$(dirname "$0")/.." && pwd)/dock.sh"
CLAVES="$DOCK_DCONF/docks/dock1"
LANZADORES="$DOCK_CONFIG/dock1/launchers"
DOCKLETS="$HOME/.local/lib/x86_64-linux-gnu/plank/docklets"

# El orden del Dock de la Mac (c17): Finder, Siri, Launchpad, Spark, Calendar…
# App Store, System Preferences, Console, Terminal… Edge, Chrome, Safari y VS
# Code. Cada uno va en el lugar de su equivalente; los que no tienen uno van
# donde va su par por función: Thunderbird donde Spark (el correo), kitty donde
# Terminal y Firefox donde Safari. Los que no existan aquí se saltan.
ANTES=(finder launchpad applications thunderbird org.gnome.Calendar mintinstall
       system-preferences cinnamon-settings kitty microsoft-edge firefox code)
DESPUES=(separator separator-sistema downloads-stack trash)

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

# System Preferences de mint-macos (settings/), si está instalada: ocupa el lugar
# de «System Preferences» y el engranaje de cinnamon-settings se quita, para no
# tener los dos. Sin ella el dock sigue con el de Cinnamon.
if [ -f "$APPS/mint-macos-settings.desktop" ]; then
  escribir_lanzador system-preferences "file://$APPS/mint-macos-settings.desktop"
  rm -f "$LANZADORES/cinnamon-settings.dockitem"
fi

if [ -f "$DOCKLETS/libdocklet-separator.so" ] && [ -f "$DOCKLETS/libdocklet-stacks.so" ]; then
  escribir_lanzador separator docklet://separator
  # El segundo separador, como el Dock de la Mac: apps fijas | apps abiertas sin fijar | Downloads y Trash.
  # El fork pone las apps sin fijar entre los dos.
  escribir_lanzador separator-sistema docklet://separator
  escribir_lanzador downloads-stack docklet://stacks
  # La pila reemplaza a la carpeta Descargas suelta.
  rm -f "$LANZADORES/downloads.dockitem"
else
  echo "$DOCK_BIN: sin el fork en ~/.local; van sin separador ni pila." >&2
  DESPUES=(trash)
fi

# La primera vez (sin la marca de abajo) se crean los lanzadores de la Mac que
# falten, si la app está instalada: en una computadora nueva no hay ninguno y
# el dock quedaba con el Finder y la pila nada más (iMac, 15-10-2026). Después
# no se crean: si José quitó uno del dock, no vuelve.
MARCA="$LANZADORES/../.orden-mac-aplicado"
[ "${PLANK_ORDEN_MAC:-}" = 1 ] && rm -f "$MARCA"
if [ ! -f "$MARCA" ]; then
  for n in "${ANTES[@]}"; do
    [ -f "$LANZADORES/$n.dockitem" ] && continue
    case "$n" in finder|system-preferences) continue ;; esac
    # El engranaje de Cinnamon solo sin la System Preferences de mint-macos.
    [ "$n" = cinnamon-settings ] && [ -f "$APPS/mint-macos-settings.desktop" ] && continue
    for d in "$APPS/$n.desktop" "/usr/share/applications/$n.desktop" "/var/lib/flatpak/exports/share/applications/$n.desktop"; do
      [ -f "$d" ] && { escribir_lanzador "$n" "file://$d"; break; }
    done
  done
  escribir_lanzador trash docklet://trash
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
# se lo deshace. Para volver al orden de la Mac: PLANK_ORDEN_MAC=1 (borra la
# marca) y correr esto.
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

echo "$DOCK_BIN: Finder $(basename "$FINDER_DESKTOP" .desktop), ${#lista[@]} ítems, ícono 56, ampliación 170 %, monitor «${PLANK_MONITOR:-el principal}»."
