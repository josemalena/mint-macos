#!/bin/bash
# Instala el ayudante de Keyboard ▸ Modifier Keys y su acción de polkit. REQUIERE ROOT:
#   sudo ./instalar-root.sh            instala
#   sudo ./instalar-root.sh --quitar   lo quita (y deja /etc/keyd/default.conf sin el bloque de mint-macos)
# (El panel funciona sin esto, pero sin la acción no hay clave y Modifier Keys no cambia nada.)
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "✗ Corre esto con sudo."; exit 1; }
AQUI="$(cd "$(dirname "$0")" && pwd)"
DEST=/usr/libexec/mint-macos/modifier-keys
POL=/usr/share/polkit-1/actions/org.mintmacos.modifierkeys.policy
if [ "${1:-}" = "--quitar" ]; then
  [ -x "$DEST" ] && "$DEST" capslock=capslock control=control option=option command=command || true
  rm -f "$DEST" "$POL"; rmdir /usr/libexec/mint-macos 2>/dev/null || true
  echo "Quitado."; exit 0
fi
command -v keyd >/dev/null || { echo "✗ No encuentro keyd."; exit 1; }
install -d -m 0755 /usr/libexec/mint-macos
install -m 0755 -o root -g root "$AQUI/mint-macos-modifier-keys" "$DEST"
install -m 0644 -o root -g root "$AQUI/org.mintmacos.modifierkeys.policy" "$POL"
echo "Instalado: $DEST y $POL"
