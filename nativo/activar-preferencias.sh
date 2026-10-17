#!/usr/bin/env bash
# Cambia System Preferences entre el de Python (preferencias.py) y el de Vala (mac-preferencias).
#   ./activar-preferencias.sh            activa el de Vala: deja el marcador, cierra el residente de Python y arranca el nuevo
#   ./activar-preferencias.sh --quitar   vuelta atrás: quita el marcador, cierra el de Vala y arranca el de Python
# Hace falta tener instalados mac-preferencias (nativo/instalar.sh) y System Preferences (settings/instalar.sh, que deja el comando
# mac-settings con el marcador). Los dos comparten el id de aplicación D-Bus: solo uno puede ser el residente, por eso se cierra uno
# antes de arrancar el otro. Se cierran por la ruta exacta de su ejecutable, nunca por una cadena que aparezca en este comando.
# Los paneles que todavía no son de Vala (Accessibility, Internet Accounts, Extensions, Trackpad con touchpad, Apple ID y la hoja
# Advanced de Network) los abre el de Python en su propia ventana, sin residente.
set -euo pipefail
MARCA="$HOME/.config/mint-macos/preferencias-vala.activo"
BIN="$HOME/.local/bin/mac-settings"
NATIVO="$HOME/.local/bin/mac-preferencias"
LIB="$HOME/.local/lib/mint-macos/settings/preferencias.py"
[ -x "$BIN" ] || { echo "✗ falta $BIN (settings/instalar.sh)" >&2; exit 1; }

cerrar_python() { for p in $(pgrep -f "^(/usr/bin/)?python3 $LIB --residente" 2>/dev/null || true); do kill "$p" 2>/dev/null || true; done; }
cerrar_vala()   { for p in $(pgrep -f "^$NATIVO( |\$)" 2>/dev/null || true); do kill "$p" 2>/dev/null || true; done; }

case "${1:-}" in
  --quitar)
    rm -f "$MARCA"
    cerrar_vala; sleep 1
    setsid "$BIN" --residente >/dev/null 2>&1 < /dev/null &
    echo "System Preferences de Python otra vez (residente). Marcador quitado." ;;
  "")
    [ -x "$NATIVO" ] || { echo "✗ falta $NATIVO (nativo/instalar.sh)" >&2; exit 1; }
    grep -q "preferencias-vala.activo" "$BIN" || { echo "✗ el mac-settings instalado no conoce el marcador: corre settings/instalar.sh" >&2; exit 1; }
    mkdir -p "$(dirname "$MARCA")"; : > "$MARCA"
    cerrar_python; cerrar_vala; sleep 1          # también uno de Vala ya corriendo: sirve para reiniciarlo tras actualizar
    setsid "$BIN" --residente >/dev/null 2>&1 < /dev/null &
    echo "System Preferences de Vala activo (residente). Vuelta atrás: $0 --quitar" ;;
  *) echo "uso: $0 [--quitar]" >&2; exit 2 ;;
esac
