#!/usr/bin/env bash
# Cambia las ventanas chicas (diálogos de sesión, Force Quit, ⇧⌘5) entre los binarios sueltos / Python y el residente mac-ventanas.
#   ./activar-ventanas.sh                       activa el residente: marcador, arranque con la sesión y lo arranca ahora
#   ./activar-ventanas.sh --sin-ayudante        lo mismo y además quita el ayudante de Python (mint-macos-ayudante)
#   ./activar-ventanas.sh --quitar              vuelta atrás: quita el marcador y el arranque y cierra el residente
# Los lanzadores (mac-sesion-lanzar, mac-forcequit-lanzar, mac-captura) usan mac-ventanas solo si existen el marcador
# ~/.config/mint-macos/ventanas.activo y el binario; sin ellos siguen con los binarios sueltos o con Python.
# El residente se cierra por la ruta exacta de su ejecutable (nunca «pgrep -x»: el nombre se trunca a 15 caracteres).
set -euo pipefail
MARCA="$HOME/.config/mint-macos/ventanas.activo"
BIN="$HOME/.local/bin/mac-ventanas"
AUTO="$HOME/.config/autostart/mint-macos-ventanas.desktop"
AQUI="$(cd "$(dirname "$0")" && pwd)"

cerrar_residente() { for p in $(pgrep -f "^$BIN --residente" 2>/dev/null || true); do kill "$p" 2>/dev/null || true; done; }

case "${1:-}" in
  --quitar)
    rm -f "$MARCA" "$AUTO"
    cerrar_residente
    echo "Sin residente de ventanas: los atajos vuelven a los binarios sueltos (o a Python si no están). Marcador y arranque quitados." ;;
  ""|--sin-ayudante)
    [ -x "$BIN" ] || { echo "✗ falta $BIN (nativo/instalar.sh)" >&2; exit 1; }
    mkdir -p "$(dirname "$MARCA")" "$(dirname "$AUTO")"
    : > "$MARCA"
    cat > "$AUTO" <<DESK
[Desktop Entry]
Type=Application
Name=mint-macos-ventanas
Comment=Diálogos de sesión, Force Quit y la barra de capturas, listos para abrirse al instante
Exec=$BIN --residente
Terminal=false
X-GNOME-Autostart-enabled=true
DESK
    cerrar_residente; sleep 1
    setsid "$BIN" --residente >/dev/null 2>&1 < /dev/null &
    if [ "${1:-}" = "--sin-ayudante" ]; then
      "$AQUI/../ayudante/instalar.sh" --quitar
    fi
    echo "Residente de ventanas activo. Vuelta atrás: $0 --quitar" ;;
  *) echo "uso: $0 [--sin-ayudante|--quitar]" >&2; exit 2 ;;
esac
