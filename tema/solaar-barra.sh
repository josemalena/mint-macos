#!/bin/bash
# Solaar sin ícono en la barra de menús (José, 18-10-2026: «lo pueden quitar de ahí, debe salir en el pref pane del mouse»).
#
# Solaar guarda ajustes que logid no tiene (en ~/.config/solaar/config.yaml, p. ej. fn-swap del teclado Wave Keys y
# multiplatform) y los vuelve a poner cada vez que el dispositivo se conecta: por eso sigue corriendo, pero sin ícono.
# Solaar solo sabe arrancar sin ícono mostrando la ventana (--window=only); este lanzador arranca el programa normal
# (--window=hide) con la función que crea el ícono anulada. La ventana de Solaar se abre con `solaar` (o desde
# System Preferences ▸ Mouse). Solo toca el home: ~/.local/bin/mint-macos-solaar y ~/.config/autostart/solaar.desktop.
#
#   ./solaar-barra.sh            arranca Solaar sin ícono, ahora y en cada sesión
#   ./solaar-barra.sh --con-icono    vuelta atrás: con el ícono de batería simbólico de antes
#   ./solaar-barra.sh --quitar   deja el arranque del sistema (/etc/xdg/autostart)
set -euo pipefail

DEST="$HOME/.config/autostart/solaar.desktop"
ORIGEN=/etc/xdg/autostart/solaar.desktop
LANZADOR="$HOME/.local/bin/mint-macos-solaar"

reiniciar() {   # reinicia el Solaar de esta sesión con el comando nuevo
  if pgrep -f "/usr/bin/python3 /usr/bin/solaar --window=hide" >/dev/null 2>&1 || pgrep -f "solaar.ui.tray" >/dev/null 2>&1; then
    pkill -f "/usr/bin/python3 /usr/bin/solaar --window=hide" || true
    pkill -f "solaar.ui.tray" || true
    sleep 2
  fi
  setsid nohup "$@" >/dev/null 2>&1 < /dev/null &
}

if [ "${1:-}" = "--quitar" ]; then
  rm -f "$DEST" "$LANZADOR"
  echo "Quitado: Solaar arranca con el del sistema."
  exit 0
fi

command -v solaar >/dev/null || { echo "Solaar no está instalado: no hay nada que hacer."; exit 0; }
[ -f "$ORIGEN" ] || { echo "Falta $ORIGEN"; exit 1; }
mkdir -p "$(dirname "$DEST")" "$(dirname "$LANZADOR")"

if [ "${1:-}" = "--con-icono" ]; then
  sed 's|^Exec=solaar --window=hide.*|Exec=solaar --window=hide --battery-icons=symbolic|' "$ORIGEN" > "$DEST"
  rm -f "$LANZADOR"
  echo "Listo: $DEST (con ícono, símbolos para la barra oscura)"
  reiniciar solaar --window=hide --battery-icons=symbolic
  exit 0
fi

cat > "$LANZADOR" <<'SH'
#!/bin/sh
# Solaar sin ícono en la barra (lo instala tema/solaar-barra.sh): el programa de siempre con la creación del ícono anulada.
exec /usr/bin/python3 -c '
import sys
sys.path.insert(0, "/usr/share/solaar/lib")
import solaar.ui.tray as tray
tray.init = lambda *args, **kwargs: None      # sin ícono; update() ya ignora un ícono que no existe
import solaar.gtk
sys.argv = ["solaar", "--window=hide"]
solaar.gtk.main()
' "$@"
SH
chmod +x "$LANZADOR"
sed "s|^Exec=solaar --window=hide.*|Exec=$LANZADOR|" "$ORIGEN" > "$DEST"
echo "Listo: $DEST y $LANZADOR"
reiniciar "$LANZADOR"
