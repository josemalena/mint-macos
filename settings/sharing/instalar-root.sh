#!/bin/bash
# Instala el ayudante de Sharing y su acción de polkit. REQUIERE ROOT:
#   sudo ./instalar-root.sh            instala
#   sudo ./instalar-root.sh --quitar   lo quita (no apaga los servicios que ya estén encendidos)
# (El panel muestra el estado sin esto, pero sin la acción no hay clave y no cambia nada.)
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "✗ Corre esto con sudo."; exit 1; }
AQUI="$(cd "$(dirname "$0")" && pwd)"
DEST=/usr/libexec/mint-macos/sharing
POL=/usr/share/polkit-1/actions/org.mintmacos.sharing.policy
if [ "${1:-}" = "--quitar" ]; then
  rm -f "$DEST" "$POL"; rmdir /usr/libexec/mint-macos 2>/dev/null || true
  echo "Quitado."; exit 0
fi
install -d -m 0755 /usr/libexec/mint-macos
install -m 0755 -o root -g root "$AQUI/mint-macos-sharing" "$DEST"
install -m 0644 -o root -g root "$AQUI/org.mintmacos.sharing.policy" "$POL"
echo "Instalado: $DEST y $POL"
