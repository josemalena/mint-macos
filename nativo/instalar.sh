#!/usr/bin/env bash
# Instala los diálogos de sesión en Vala (mac-sesion), compilados del HEAD commiteado.
#   ./instalar.sh            compila e instala; los atajos y el applet usan el binario
#   ./instalar.sh --python   vuelta atrás: quita el binario y todo vuelve a applemenu.py
# El lanzador (mac-sesion-lanzar) decide solo: con el binario puesto lo usa, sin él cae a Python.
set -euo pipefail
AQUI="$(cd "$(dirname "$0")" && pwd)"
case "${1:-}" in
  --python)
    rm -f "$HOME/.local/bin/mac-sesion"
    echo "mac-sesion quitado: los diálogos de sesión vuelven a applemenu.py" ;;
  "")
    "$AQUI/compilar-desde-head.sh" "$HOME"
    echo "instalado en ~/.local/bin (mac-sesion y mac-sesion-lanzar)" ;;
  *) echo "uso: $0 [--python]" >&2; exit 2 ;;
esac
