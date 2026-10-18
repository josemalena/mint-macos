#!/usr/bin/env bash
# mint-macos-monitor de punta a punta: bus de sesión aparte con activación por D-Bus,
# contra el /proc de verdad (solo lee; los únicos procesos que cierra son dos sleep
# que lanza la prueba). Al final mide lo que gasta el servicio con y sin clientes.
#
#   rust/monitor/prueba.sh [BINARIO]
set -euo pipefail
AQUI="$(cd "$(dirname "$0")" && pwd)"
BIN="$(realpath "${1:-$AQUI/../target/debug/mint-macos-monitor}")"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/data/dbus-1/services" "$T/run"; chmod 700 "$T/run"
printf '[D-BUS Service]\nName=org.mintmacos.Monitor1\nExec=%s\n' "$BIN" > "$T/data/dbus-1/services/org.mintmacos.Monitor1.service"
cat > "$T/dentro.sh" <<'EOF'
set -euo pipefail
r=0; python3 -I "$1/prueba/cliente.py" || r=$?
P=$(busctl --user call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus GetConnectionUnixProcessID s org.mintmacos.Monitor1 | awk '{print $2}')
mide() { local a b; a=$(awk '{print $14+$15}' /proc/$P/stat); sleep 30; b=$(awk '{print $14+$15}' /proc/$P/stat); echo "$(( (b - a) )) ticks en 30 s, $(awk '/VmRSS/{print $2}' /proc/$P/status) kB"; }
echo "  · sin clientes: $(mide)"
python3 -I -c '
import time; from gi.repository import Gio, GLib
b = Gio.bus_get_sync(Gio.BusType.SESSION, None)
b.call_sync("org.mintmacos.Monitor1", "/org/mintmacos/Monitor1", "org.mintmacos.Monitor1", "Suscribir", GLib.Variant("(u)", (2000,)), None, 0, -1, None)
time.sleep(33)' & C=$!
sleep 2; echo "  · con un cliente (cada 2 s): $(mide)"
wait $C
kill "$P" 2>/dev/null || true
exit $r
EOF
XDG_DATA_HOME="$T/data" XDG_RUNTIME_DIR="$T/run" dbus-run-session -- bash "$T/dentro.sh" "$AQUI" 2>&1 | grep -v 'ctivat'
