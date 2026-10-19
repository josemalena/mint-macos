# El Dock: Muelle (el fork de plank-reloaded con su nombre propio, José 18-10-2026; Dev-Dock lo
# renombró el 19-10) o el Plank de antes, según cuál esté instalado. Se carga con «source»; todo lo
# que toca el Dock (configurar.sh, tema/instalar.sh, construir.sh, el tema) usa estas variables en
# vez de escribir «plank» a mano, así la transición no rompe nada y la vuelta atrás (plank-viejo)
# sigue sirviendo. DOCK=muelle|plank lo fuerza.
#
#   DOCK          muelle | plank
#   DOCK_BIN      el ejecutable (en ~/.local/bin)
#   DOCK_DCONF    la raíz de su árbol de dconf (…/docks/dock1/ cuelga de ahí)
#   DOCK_ESQUEMA  el esquema reubicable de cada dock, con su ruta, para gsettings
#   DOCK_CONFIG   ~/.config/<dock> (los .dockitem van en dock1/launchers)
#   DOCK_TEMAS    ~/.local/share/<dock>/themes
#   DOCK_PROCESOS los nombres de proceso que hay que parar para reiniciarlo (los dos)
if [ -z "${DOCK:-}" ]; then
  if [ -x "$HOME/.local/bin/muelle" ] || command -v muelle >/dev/null 2>&1; then DOCK=muelle; else DOCK=plank; fi
fi
case "$DOCK" in
  muelle)
    DOCK_BIN=muelle
    DOCK_DCONF=/org/mintmacos/muelle
    DOCK_ESQUEMA=org.mintmacos.muelle.dock.settings:/org/mintmacos/muelle/docks/dock1/
    DOCK_CONFIG="$HOME/.config/muelle"
    DOCK_TEMAS="$HOME/.local/share/muelle/themes" ;;
  *)
    DOCK=plank
    DOCK_BIN=plank
    DOCK_DCONF=/net/launchpad/plank
    DOCK_ESQUEMA=net.launchpad.plank.dock.settings:/net/launchpad/plank/docks/dock1/
    DOCK_CONFIG="$HOME/.config/plank"
    DOCK_TEMAS="$HOME/.local/share/plank/themes" ;;
esac
DOCK_PROCESOS="muelle plank plank-viejo"
