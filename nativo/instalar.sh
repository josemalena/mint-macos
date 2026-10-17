#!/usr/bin/env bash
# Instala los diálogos de sesión en Vala (mac-sesion), compilados del HEAD commiteado.
#   ./instalar.sh            compila e instala; los atajos y el applet usan el binario
#   ./instalar.sh --python   vuelta atrás: quita el binario y todo vuelve a applemenu.py
# El lanzador (mac-sesion-lanzar) decide solo: con el binario puesto lo usa, sin él cae a Python.
set -euo pipefail
AQUI="$(cd "$(dirname "$0")" && pwd)"
case "${1:-}" in
  --python)
    rm -f "$HOME/.local/bin/mac-sesion" "$HOME/.local/bin/mac-gatekeeper" "$HOME/.local/bin/mac-polkit" "$HOME/.local/bin/mac-forcequit" "$HOME/.local/bin/mac-launchpad-vala" "$HOME/.config/mint-macos/launchpad-vala.activo" \
      "$HOME/.local/bin/mac-captura-herramienta-vala" "$HOME/.config/mint-macos/captura-vala.activo" \
      "$HOME/.local/bin/mac-ventanas" "$HOME/.config/mint-macos/ventanas.activo" \
      "$HOME/.local/bin/mac-preferencias" "$HOME/.config/mint-macos/preferencias-vala.activo" "$HOME/.config/autostart/mint-macos-ventanas.desktop"
    echo "mac-sesion, mac-forcequit, mac-launchpad-vala, mac-captura-herramienta-vala, mac-ventanas, mac-preferencias y mac-polkit quitados (cierra antes el residente con activar-preferencias.sh --quitar) (si había un residente mac-ventanas, ciérralo con activar-ventanas.sh --quitar antes): los diálogos de sesión vuelven a applemenu.py, Force Quit a forcekill.py y el agente a agente.py, ⇧⌘5 a herramienta.py" ;;
  "")
    "$AQUI/compilar-desde-head.sh" "$HOME"
    echo "instalado en ~/.local/bin (mac-sesion, mac-forcequit, mac-launchpad-vala, mac-captura-herramienta-vala, mac-ventanas, mac-preferencias, mac-sesion-lanzar y, si hay headers de polkit, mac-polkit)" ;;
  *) echo "uso: $0 [--python]" >&2; exit 2 ;;
esac
