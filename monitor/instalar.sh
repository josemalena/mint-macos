#!/bin/bash
# Los datos de Activity Monitor (mint-macos-monitor, rust/monitor): sin ventana; lo arranca
# la activación por D-Bus la primera vez que alguien llama a org.mintmacos.Monitor1
# mide solo con clientes y se va solo a los 2 minutos sin ellos. Sin sudo.
#
#   ./instalar.sh            instala el binario y el .service de D-Bus
#   ./instalar.sh --quitar   la vuelta atrás
#
# La interfaz: rust/monitor/DBUS.md. Su prueba: rust/monitor/prueba.sh.
set -euo pipefail
AQUI="$(cd "$(dirname "$0")" && pwd)"
# Destino: MINT_MACOS_DESTINO=usuario (por omisión) o sistema, para la imagen (lib/destino.sh).
source "$AQUI/../lib/destino.sh"
LIB="$D_LIB"
SERVICIOS="$D_DBUS"
ARCHIVO="$SERVICIOS/org.mintmacos.Monitor1.service"

parar() {
  local p
  p=$(busctl --user call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus GetConnectionUnixProcessID s org.mintmacos.Monitor1 2>/dev/null | awk '{print $2}') || true
  [ -n "$p" ] && kill "$p" 2>/dev/null || true
}

if [ "${1:-}" = "--quitar" ]; then
  parar
  rm -f "$ARCHIVO" "$LIB/mint-macos-monitor"
  echo "Quitado."
  exit 0
fi

RUST="$AQUI/../rust/target/release/mint-macos-monitor"
[ -x "$RUST" ] || { echo "✗ falta compilar $RUST (cd rust && cargo build --release -p mint-macos-monitor)"; exit 1; }
mkdir -p "$LIB" "$SERVICIOS"
install -m 755 "$RUST" "$LIB/mint-macos-monitor"
printf '[D-BUS Service]\nName=org.mintmacos.Monitor1\nExec=%s\n' "$R_LIB/mint-macos-monitor" > "$ARCHIVO"
# Si ya corría, que la próxima llamada arranque el binario nuevo.
es_sistema || parar
echo "  mint-macos-monitor: se arranca solo al primer uso ($ARCHIVO)"
