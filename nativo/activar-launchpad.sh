#!/usr/bin/env bash
# Cambia el Launchpad residente entre el de Python y el de Vala (mac-launchpad-vala).
#   ./activar-launchpad.sh            activa el de Vala: deja el marcador, cierra el residente de Python y arranca el nuevo
#   ./activar-launchpad.sh --quitar   vuelta atrás: quita el marcador, cierra el de Vala y arranca el de Python
# Hace falta tener instalados mac-launchpad-vala (nativo/instalar.sh) y el comando mac-launchpad (launchpad/instalar.sh).
# Los dos comparten el id de aplicación D-Bus, así que solo uno puede ser el residente: por eso se cierra uno antes de
# arrancar el otro. Se cierran por ruta exacta del ejecutable, nunca por una cadena que aparezca en este comando.
set -euo pipefail
MARCA="$HOME/.config/mint-macos/launchpad-vala.activo"
BIN="$HOME/.local/bin/mac-launchpad"
NATIVO="$HOME/.local/bin/mac-launchpad-vala"
LIB="$HOME/.local/lib/mint-macos/launchpad/launchpad.py"
[ -x "$BIN" ] || { echo "✗ falta $BIN (launchpad/instalar.sh)" >&2; exit 1; }

cerrar_python() { for p in $(pgrep -f "^/usr/bin/python3 $LIB --residente" 2>/dev/null || true); do kill "$p" 2>/dev/null || true; done; }
cerrar_vala()   { for p in $(pgrep -x mac-launchpad-vala 2>/dev/null || true); do kill "$p" 2>/dev/null || true; done; }

case "${1:-}" in
  --quitar)
    rm -f "$MARCA"
    cerrar_vala; sleep 1
    setsid "$BIN" --residente >/dev/null 2>&1 < /dev/null &
    echo "Launchpad de Python otra vez (residente). Marcador quitado." ;;
  "")
    [ -x "$NATIVO" ] || { echo "✗ falta $NATIVO (nativo/instalar.sh)" >&2; exit 1; }
    mkdir -p "$(dirname "$MARCA")"; : > "$MARCA"
    cerrar_python; sleep 1
    setsid "$BIN" --residente >/dev/null 2>&1 < /dev/null &
    echo "Launchpad de Vala activo (residente). Vuelta atrás: $0 --quitar" ;;
  *) echo "uso: $0 [--quitar]" >&2; exit 2 ;;
esac
