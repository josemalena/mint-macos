#!/bin/bash
# Instala el ayudante de Sharing y su acción de polkit. REQUIERE ROOT:
#   sudo ./instalar-root.sh            instala
#   sudo ./instalar-root.sh --python   instala el de Python aunque esté el de Rust
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
# El ayudante en Rust (rust/sharing, mismo comportamiento que el Python, 16-10-2026)
# si está compilado: cd rust && cargo build --release (como tu usuario, NO con sudo).
# Si no, el de Python. --python fuerza el de Python. Siempre se COPIA a
# /usr/libexec con dueño root: la .policy nunca apunta a algo que el usuario pueda escribir.
RUST="$AQUI/../../rust/target/release/mint-macos-sharing"
if [ "${1:-}" != "--python" ] && [ -x "$RUST" ]; then
  install -m 0755 -o root -g root "$RUST" "$DEST"; echo "  ayudante: Rust ($RUST)"
else
  install -m 0755 -o root -g root "$AQUI/mint-macos-sharing" "$DEST"; echo "  ayudante: Python"
fi
install -m 0644 -o root -g root "$AQUI/org.mintmacos.sharing.policy" "$POL"
echo "Instalado: $DEST y $POL"
