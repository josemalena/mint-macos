#!/bin/bash
# Los eventos de Thunderbird para el widget Calendar del Notification Center (mint-macos-calendario,
# rust/calendario): sin ventana, solo lectura; lo arranca la activación por D-Bus la primera vez que
# alguien llama a org.mintmacos.Calendario1 y se va solo a los 2 minutos sin llamadas. Sin sudo.
#
#   ./instalar.sh            instala el binario y el .service de D-Bus
#   ./instalar.sh --quitar   la vuelta atrás
#
# La interfaz: rust/calendario/DBUS.md. Su prueba: cargo test -p mint-macos-calendario.
set -euo pipefail
AQUI="$(cd "$(dirname "$0")" && pwd)"
# Destino: MINT_MACOS_DESTINO=usuario (por omisión) o sistema, para la imagen (lib/destino.sh).
source "$AQUI/../lib/destino.sh"
LIB="$D_LIB"
SERVICIOS="$D_DBUS"
ARCHIVO="$SERVICIOS/org.mintmacos.Calendario1.service"

parar() {
  local p
  p=$(busctl --user call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus GetConnectionUnixProcessID s org.mintmacos.Calendario1 2>/dev/null | awk '{print $2}') || true
  [ -n "$p" ] && kill "$p" 2>/dev/null || true
}

if [ "${1:-}" = "--quitar" ]; then
  parar
  rm -f "$ARCHIVO" "$LIB/mint-macos-calendario"
  echo "Quitado."
  exit 0
fi

RUST="$AQUI/../rust/target/release/mint-macos-calendario"
[ -x "$RUST" ] || { echo "✗ falta compilar $RUST (cd rust && cargo build --release -p mint-macos-calendario)"; exit 1; }
mkdir -p "$LIB" "$SERVICIOS"
install -m 755 "$RUST" "$LIB/mint-macos-calendario"
printf '[D-BUS Service]\nName=org.mintmacos.Calendario1\nExec=%s\n' "$R_LIB/mint-macos-calendario" > "$ARCHIVO"
# Si ya corría, que la próxima llamada arranque el binario nuevo.
es_sistema || parar
echo "  mint-macos-calendario: se arranca solo al primer uso ($ARCHIVO)"
