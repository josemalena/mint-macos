#!/usr/bin/env bash
# Cambia la barra de ⇧⌘5 entre la de Python (herramienta.py) y la de Vala (mac-captura-herramienta-vala).
#   ./activar-captura.sh            activa la de Vala: deja el marcador; el próximo ⇧⌘5 abre el binario
#   ./activar-captura.sh --quitar   vuelta atrás: quita el marcador; ⇧⌘5 vuelve a herramienta.py
# Hace falta tener instalados mac-captura-herramienta-vala (nativo/instalar.sh) y el comando mac-captura (capturas/instalar.sh,
# la versión con el marcador). No hay residente que reiniciar: la barra se abre, captura y sale.
set -euo pipefail
MARCA="$HOME/.config/mint-macos/captura-vala.activo"
NATIVO="$HOME/.local/bin/mac-captura-herramienta-vala"
case "${1:-}" in
  --quitar)
    rm -f "$MARCA"
    echo "⇧⌘5 vuelve a la barra de Python. Marcador quitado." ;;
  "")
    [ -x "$NATIVO" ] || { echo "✗ falta $NATIVO (nativo/instalar.sh)" >&2; exit 1; }
    grep -q "captura-vala.activo" "$HOME/.local/bin/mac-captura" 2>/dev/null \
      || { echo "✗ el mac-captura instalado no conoce el marcador: corre capturas/instalar.sh" >&2; exit 1; }
    mkdir -p "$(dirname "$MARCA")"; : > "$MARCA"
    echo "⇧⌘5 con la barra de Vala. Vuelta atrás: $0 --quitar" ;;
  *) echo "uso: $0 [--quitar]" >&2; exit 2 ;;
esac
