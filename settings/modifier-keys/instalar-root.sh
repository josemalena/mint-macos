#!/bin/bash
# Instala el ayudante de Keyboard ▸ Modifier Keys y su acción de polkit. REQUIERE ROOT:
#   sudo ./instalar-root.sh            instala
#   sudo ./instalar-root.sh --python   instala el de Python aunque esté el de Rust
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
# El ayudante en Rust (rust/modifier-keys, mismo comportamiento byte a byte que el
# Python, 16-10-2026) si está compilado: cd rust && cargo build --release (como tu
# usuario, NO con sudo). Si no, el de Python. --python fuerza el de Python.
RUST="$AQUI/../../rust/target/release/mint-macos-modifier-keys"
if [ "${1:-}" != "--python" ] && [ -x "$RUST" ]; then
  install -m 0755 -o root -g root "$RUST" "$DEST"; echo "  ayudante: Rust ($RUST)"
else
  install -m 0755 -o root -g root "$AQUI/mint-macos-modifier-keys" "$DEST"; echo "  ayudante: Python"
fi
install -m 0644 -o root -g root "$AQUI/org.mintmacos.modifierkeys.policy" "$POL"
echo "Instalado: $DEST y $POL"
