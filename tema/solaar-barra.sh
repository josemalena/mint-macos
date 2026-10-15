#!/bin/bash
# Solaar con el ícono de batería de la barra oscura.
#
# Solaar pide por defecto «battery-good» (regular), que en Os-Catalina/Constanza
# es un SVG oscuro pensado para una barra clara: en la barra de menú oscura sale
# negro y no se ve. Con --battery-icons=symbolic pide «battery-good-symbolic» y
# xapp-status lo recolorea como a los demás íconos de la barra.
#
#   ./solaar-barra.sh            arranca Solaar así, ahora y en cada sesión
#   ./solaar-barra.sh --quitar   deja el arranque del sistema (/etc/xdg/autostart)
#
# Solo toca el home: ~/.config/autostart/solaar.desktop pisa al del sistema.
set -euo pipefail

DEST="$HOME/.config/autostart/solaar.desktop"
ORIGEN=/etc/xdg/autostart/solaar.desktop

if [ "${1:-}" = "--quitar" ]; then
  rm -f "$DEST"
  echo "Quitado: Solaar arranca con el del sistema."
  exit 0
fi

command -v solaar >/dev/null || { echo "Solaar no está instalado: no hay nada que hacer."; exit 0; }
[ -f "$ORIGEN" ] || { echo "Falta $ORIGEN"; exit 1; }

mkdir -p "$(dirname "$DEST")"
sed 's|^Exec=solaar --window=hide.*|Exec=solaar --window=hide --battery-icons=symbolic|' "$ORIGEN" > "$DEST"
echo "Listo: $DEST"

# Si está corriendo con el estilo de antes, se reinicia con el nuevo.
if pgrep -x -f "/usr/bin/python3 /usr/bin/solaar --window=hide" >/dev/null 2>&1; then
  pkill -x -f "/usr/bin/python3 /usr/bin/solaar --window=hide" || true
  sleep 2
  setsid nohup solaar --window=hide --battery-icons=symbolic >/dev/null 2>&1 < /dev/null &
  echo "Solaar reiniciado con --battery-icons=symbolic."
fi
