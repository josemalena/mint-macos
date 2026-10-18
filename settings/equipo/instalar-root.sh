#!/bin/bash
# Instala mint-macos-equipo: al arrancar escribe /run/mint-macos/equipo.json (0640 root:users: Mac o PC,
# modelo, sistema, logo, serie, procesador, memoria y gráficos) para About This Mac/PC. REQUIERE ROOT:
#   sudo ./instalar-root.sh            instala el binario y el servicio, y lo corre ya
#   sudo ./instalar-root.sh --python   igual (no hay versión en Python)
#   sudo ./instalar-root.sh --quitar   lo quita, con el archivo de /run
# Lo corre también el instalador único (settings/instalar-root.sh).
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "✗ Corre esto con sudo."; exit 1; }
AQUI="$(cd "$(dirname "$0")" && pwd)"
DEST=/usr/libexec/mint-macos/equipo
UNIDAD=/etc/systemd/system/mint-macos-equipo.service
if [ "${1:-}" = "--quitar" ]; then
  systemctl disable --now mint-macos-equipo.service 2>/dev/null || true
  rm -f "$UNIDAD" "$DEST" /run/mint-macos/equipo.json
  rmdir /run/mint-macos /usr/libexec/mint-macos 2>/dev/null || true
  systemctl daemon-reload
  echo "Quitado."; exit 0
fi
# rust/equipo, compilado antes como tu usuario (NO con sudo): cd rust && cargo build --release.
# Se COPIA a /usr/libexec con dueño root: lo corre systemd como root.
RUST="$AQUI/../../rust/target/release/mint-macos-equipo"
[ -x "$RUST" ] || { echo "✗ falta compilar $RUST (cd rust && cargo build --release, sin sudo)"; exit 1; }
install -d -m 0755 /usr/libexec/mint-macos
install -m 0755 -o root -g root "$RUST" "$DEST"
install -m 0644 -o root -g root "$AQUI/mint-macos-equipo.service" "$UNIDAD"
systemctl daemon-reload
systemctl enable mint-macos-equipo.service >/dev/null 2>&1
systemctl restart mint-macos-equipo.service
echo "Instalado: $DEST y $UNIDAD ($(systemctl is-active mint-macos-equipo.service))"
