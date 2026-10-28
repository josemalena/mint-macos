#!/bin/bash
# El motor del App Store (mint-macos-tienda, rust/tienda): sin ventana; lo arranca
# la activación por D-Bus la primera vez que alguien llama a org.mintmacos.Tienda1
# y se va solo a los 10 minutos sin uso. Sin sudo.
#
#   ./instalar.sh            instala el binario y el .service de D-Bus
#   ./instalar.sh --quitar   la vuelta atrás (el caché de ~/.cache/mint-macos/tienda se queda)
#
# La interfaz: rust/tienda/DBUS.md. Sus pruebas: rust/tienda/prueba.sh y prueba-flatpak.sh.
set -euo pipefail
AQUI="$(cd "$(dirname "$0")" && pwd)"
# Destino: MINT_MACOS_DESTINO=usuario (por omisión) o sistema, para la imagen (lib/destino.sh).
source "$AQUI/../lib/destino.sh"
LIB="$D_LIB"
SERVICIOS="$D_DBUS"
ARCHIVO="$SERVICIOS/org.mintmacos.Tienda1.service"

parar() {
  local p
  p=$(busctl --user call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus GetConnectionUnixProcessID s org.mintmacos.Tienda1 2>/dev/null | awk '{print $2}') || true
  [ -n "$p" ] && kill "$p" 2>/dev/null || true
}

if [ "${1:-}" = "--quitar" ]; then
  parar
  rm -f "$ARCHIVO" "$LIB/mint-macos-tienda"
  echo "Quitado."
  exit 0
fi

RUST="$AQUI/../rust/target/release/mint-macos-tienda"
[ -x "$RUST" ] || { echo "✗ falta compilar $RUST (cd rust && cargo build --release -p mint-macos-tienda)"; exit 1; }
mkdir -p "$LIB" "$SERVICIOS"
install -m 755 "$RUST" "$LIB/mint-macos-tienda"
printf '[D-BUS Service]\nName=org.mintmacos.Tienda1\nExec=%s\n' "$R_LIB/mint-macos-tienda" > "$ARCHIVO"
# Si ya corría, que la próxima llamada arranque el binario nuevo.
es_sistema || parar
echo "  mint-macos-tienda: se arranca solo al primer uso ($ARCHIVO)"
