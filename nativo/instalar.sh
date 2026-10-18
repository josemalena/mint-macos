#!/usr/bin/env bash
# Instala los diálogos de sesión en Vala (mac-sesion), compilados del HEAD commiteado.
#   ./instalar.sh            compila e instala; los atajos y el applet usan el binario
#   ./instalar.sh --reiniciar   además reinicia los residentes (mac-ventanas, mac-preferencias) para que atiendan con lo nuevo
#   ./instalar.sh --python   vuelta atrás: quita el binario y todo vuelve a applemenu.py
# El lanzador (mac-sesion-lanzar) decide solo: con el binario puesto lo usa, sin él cae a Python.
set -euo pipefail
AQUI="$(cd "$(dirname "$0")" && pwd)"
case "${1:-}" in
  --python)
    rm -f "$HOME/.local/bin/mac-sesion" "$HOME/.local/bin/mac-gatekeeper" "$HOME/.local/bin/mac-polkit" "$HOME/.local/bin/mac-forcequit" "$HOME/.local/bin/mac-launchpad-vala" "$HOME/.config/mint-macos/launchpad-vala.activo" \
      "$HOME/.local/bin/mac-captura-herramienta-vala" "$HOME/.config/mint-macos/captura-vala.activo" \
      "$HOME/.local/bin/mac-ventanas" "$HOME/.config/mint-macos/ventanas.activo" \
      "$HOME/.local/bin/mac-preferencias" "$HOME/.local/bin/mac-acerca" "$HOME/.local/bin/mac-acerca-lanzar" "$HOME/.config/mint-macos/preferencias-vala.activo" "$HOME/.config/autostart/mint-macos-ventanas.desktop"
    echo "mac-sesion, mac-forcequit, mac-launchpad-vala, mac-captura-herramienta-vala, mac-ventanas, mac-preferencias y mac-polkit quitados (cierra antes el residente con activar-preferencias.sh --quitar) (si había un residente mac-ventanas, ciérralo con activar-ventanas.sh --quitar antes): los diálogos de sesión vuelven a applemenu.py, Force Quit a forcekill.py y el agente a agente.py, ⇧⌘5 a herramienta.py" ;;
  ""|--reiniciar)
    "$AQUI/compilar-desde-head.sh" "$HOME"
    echo "instalado en ~/.local/bin (mac-sesion, mac-forcequit, mac-launchpad-vala, mac-captura-herramienta-vala, mac-ventanas, mac-preferencias, mac-sesion-lanzar y, si hay headers de polkit, mac-polkit)"
    # Un residente sigue con el código viejo en memoria y es el que atiende los atajos (⇧⌘5, Force Quit, los
    # diálogos de sesión, System Preferences): con el binario nuevo en disco no basta. Se compara la hora de
    # arranque del proceso con la del binario, y se avisa o, con --reiniciar, se reinicia.
    viejo=0
    for r in mac-ventanas mac-preferencias; do
      bin="$HOME/.local/bin/$r"
      [ -x "$bin" ] || continue
      for pid in $(pgrep -f "^$bin --residente" 2>/dev/null || true); do
        arranque="$(date -d "$(ps -o lstart= -p "$pid")" +%s)"
        if [ "$arranque" -lt "$(stat -c %Y "$bin")" ]; then
          echo "⚠ $r --residente (pid $pid, arrancó $(date -d @"$arranque" '+%F %T')) sigue con el código viejo: el binario es de $(date -d @"$(stat -c %Y "$bin")" '+%F %T')"
          viejo=1
        fi
      done
    done
    if [ "$viejo" = 1 ]; then
      if [ "${1:-}" = "--reiniciar" ]; then
        "$AQUI/activar-ventanas.sh" >/dev/null
        [ -f "$HOME/.config/mint-macos/preferencias-vala.activo" ] && "$AQUI/activar-preferencias.sh" >/dev/null
        echo "residentes reiniciados"
      else
        echo "  → reinícialos con: $0 --reiniciar (o activar-ventanas.sh / activar-preferencias.sh)"
      fi
    fi ;;
  *) echo "uso: $0 [--reiniciar|--python]" >&2; exit 2 ;;
esac
