#!/bin/bash
# Light, Dark, Auto, el acento y el resaltado (mint-macos-apariencia, rust/apariencia): lo arranca
# la activación por D-Bus cuando General ▸ Appearance llama a org.mintmacos.Apariencia1, y se va
# solo al minuto. Sin sudo. Instalarlo no cambia nada: el tema cambia cuando se escoge algo.
#
#   ./instalar.sh            instala el binario y el .service de D-Bus
#   ./instalar.sh --quitar   la vuelta atrás (también apaga el temporizador de Auto)
#
# La interfaz: rust/apariencia/DBUS.md. Su prueba: rust/apariencia/prueba.sh.
set -euo pipefail
AQUI="$(cd "$(dirname "$0")" && pwd)"
LIB="$HOME/.local/lib/mint-macos"
SERVICIOS="${XDG_DATA_HOME:-$HOME/.local/share}/dbus-1/services"
ARCHIVO="$SERVICIOS/org.mintmacos.Apariencia1.service"

parar() {
  local p
  p=$(busctl --user call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus GetConnectionUnixProcessID s org.mintmacos.Apariencia1 2>/dev/null | awk '{print $2}') || true
  [ -n "$p" ] && kill "$p" 2>/dev/null || true
}

if [ "${1:-}" = "--quitar" ]; then
  parar
  systemctl --user stop mint-macos-apariencia-auto.timer 2>/dev/null || true
  rm -f "$ARCHIVO" "$LIB/mint-macos-apariencia"
  echo "Quitado (el tema que estaba puesto se queda)."
  exit 0
fi

RUST="$AQUI/../rust/target/release/mint-macos-apariencia"
[ -x "$RUST" ] || { echo "✗ falta compilar $RUST (cd rust && cargo build --release -p mint-macos-apariencia)"; exit 1; }
mkdir -p "$LIB" "$SERVICIOS"
install -m 755 "$RUST" "$LIB/mint-macos-apariencia"
printf '[D-BUS Service]\nName=org.mintmacos.Apariencia1\nExec=%s\n' "$LIB/mint-macos-apariencia" > "$ARCHIVO"
parar
echo "  mint-macos-apariencia: se arranca solo al primer uso ($ARCHIVO)"
