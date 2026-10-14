#!/usr/bin/env bash
# Tema «Constanza» de ULauncher (Spotlight de Catalina). Necesita el disco de
# la Mac para la lupa; lo monta en solo lectura con tema/comun.sh.
set -euo pipefail
AQUI="$(cd "$(dirname "$0")" && pwd)"
source "$AQUI/../comun.sh"; trap desmontar_mac EXIT
montar_mac_sistema || { echo "  ✗ sin disco de Mac: no hay lupa de Catalina"; exit 1; }
python3 "$AQUI/construir.py" "$MAC_SISTEMA/System/Library/CoreServices/SystemAppearance.bundle/Contents/Resources/Assets.car"
