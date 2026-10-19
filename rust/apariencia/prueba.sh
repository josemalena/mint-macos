#!/bin/bash
# El servicio de apariencia en un bus aparte, sin tocar el tema de la sesión: APARIENCIA_SIMULAR
# anota los comandos (gsettings, dconf, systemd-run) en vez de correrlos.
set -euo pipefail
AQUI="$(cd "$(dirname "$0")" && pwd)"
BIN="$(realpath "${1:-$AQUI/../target/release/mint-macos-apariencia}")"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export XDG_CONFIG_HOME="$T/cfg" XDG_RUNTIME_DIR="$T/run" APARIENCIA_SIMULAR="$T/comandos.txt"
mkdir -m 700 -p "$XDG_RUNTIME_DIR"
fallas=0
mal() { echo "  ✗ $*"; fallas=$((fallas + 1)); }
llamar() { gdbus call --session -d org.mintmacos.Apariencia1 -o /org/mintmacos/Apariencia1 -m "org.mintmacos.Apariencia1.$@"; }
export -f llamar
# 16:00 hora de Santo Domingo (20:00 UTC) del 18-10-2026: de día.
export APARIENCIA_AHORA=1792353600
dbus-run-session -- bash -c "
  '$BIN' & P=\$!; sleep 1
  llamar Estado > '$T/e0'
  llamar Poner auto Green '' > '$T/p1'
  llamar Poner nada '' '' > '$T/p2'
  llamar Poner '' '' '#12345G' > '$T/p3'
  llamar Estado > '$T/e1'
  grep VmRSS /proc/\$P/status > '$T/rss'
  kill \$P"
grep -q "'tema': <'Constanza-Oscuro'>" "$T/e0" || mal "sin escoger debe ser Constanza-Oscuro: $(cat "$T/e0")"
grep -q "(true,)" "$T/p1" || mal "Poner auto Green"
grep -q "(false,)" "$T/p2" || mal "una apariencia inválida debe dar false"
grep -q "(false,)" "$T/p3" || mal "un color inválido debe dar false"
grep -q "'tema': <'Constanza-Claro-Green'>" "$T/e1" || mal "a las 16:00 en Auto, claro: $(cat "$T/e1")"
grep -q "proximo_cambio" "$T/e1" || mal "Auto sin próximo cambio"
grep -q "gsettings set org.cinnamon.desktop.interface gtk-theme Constanza-Claro-Green" "$T/comandos.txt" || mal "no cambió el tema GTK"
grep -q "systemd-run --user --quiet --unit=mint-macos-apariencia-auto --on-calendar=2026-10-18 22:" "$T/comandos.txt" || mal "el temporizador de la puesta del sol (22:xx UTC): $(grep systemd-run "$T/comandos.txt")"
grep -q 'mint-macos-resaltado.css' "$T/cfg/gtk-3.0/gtk.css" || mal "el gtk.css no importa el resaltado"
echo "  · $(cat "$T/rss")"
[ $fallas = 0 ] && echo "  ✓ apariencia: 9 de 9" || { echo "  ✗ $fallas fallas"; exit 1; }
