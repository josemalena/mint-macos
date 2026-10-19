#!/bin/bash
# El Apple ID de System Preferences (mint-macos-appleid, rust/appleid): iCloud Drive con rclone y
# Mail y Calendar en Thunderbird, sin ventana; lo arranca la activación por D-Bus la primera vez
# que alguien llama a org.mintmacos.AppleID1 y se va solo a los 2 minutos sin llamadas. Sin sudo.
#
#   ./instalar.sh            instala el binario y el .service de D-Bus
#   ./instalar.sh --quitar   la vuelta atrás
#
# La interfaz: rust/appleid/DBUS.md. Sus pruebas: cargo test -p mint-macos-appleid y rust/appleid/prueba-llavero.sh.
set -euo pipefail
AQUI="$(cd "$(dirname "$0")" && pwd)"
LIB="$HOME/.local/lib/mint-macos"
SERVICIOS="${XDG_DATA_HOME:-$HOME/.local/share}/dbus-1/services"
ARCHIVO="$SERVICIOS/org.mintmacos.AppleID1.service"

parar() {
  local p
  p=$(busctl --user call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus GetConnectionUnixProcessID s org.mintmacos.AppleID1 2>/dev/null | awk '{print $2}') || true
  [ -n "$p" ] && kill "$p" 2>/dev/null || true
}

if [ "${1:-}" = "--quitar" ]; then
  parar
  rm -f "$ARCHIVO" "$LIB/mint-macos-appleid"
  echo "Quitado."
  exit 0
fi

RUST="$AQUI/../rust/target/release/mint-macos-appleid"
[ -x "$RUST" ] || { echo "✗ falta compilar $RUST (cd rust && cargo build --release -p mint-macos-appleid)"; exit 1; }
mkdir -p "$LIB" "$SERVICIOS"
install -m 755 "$RUST" "$LIB/mint-macos-appleid"
printf '[D-BUS Service]\nName=org.mintmacos.AppleID1\nExec=%s\n' "$LIB/mint-macos-appleid" > "$ARCHIVO"
# Si ya corría, que la próxima llamada arranque el binario nuevo.
parar
echo "  mint-macos-appleid: se arranca solo al primer uso ($ARCHIVO)"
