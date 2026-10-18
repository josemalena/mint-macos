#!/usr/bin/env bash
# Prueba de mint-macos-avisos de punta a punta, sin tocar la sesión de José: bus
# de sesión aparte (dbus-run-session), un servidor de notificaciones de mentira,
# gsettings en un keyfile propio, informes de juguete con el cargador de Mint y un
# «mintreport» falso que solo deja una marca.
#
#   rust/avisos/prueba.sh [BINARIO]     (por defecto rust/target/debug/mint-macos-avisos)
set -euo pipefail
AQUI="$(cd "$(dirname "$0")" && pwd)"
BIN="$(realpath "${1:-$AQUI/../target/debug/mint-macos-avisos}")"
[ -x "$BIN" ] || { echo "✗ falta $BIN (cargo build -p mint-macos-avisos)"; exit 1; }
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/informes" "$T/bin" "$T/config" "$T/state"

informe() {   # carpeta, título, condición de Python para is_pertinent
  mkdir -p "$T/informes/$1"
  cat > "$T/informes/$1/MintReportInfo.py" <<FIN_PY
import os
from mintreport import InfoReport
class Report(InfoReport):
    def __init__(self):
        self.title = "$2"
        self.icon = "xsi-dialog-information-symbolic"
        self.has_ignore_button = True
    def is_pertinent(self):
        return $3
    def get_descriptions(self):
        return []
    def get_actions(self):
        return []
FIN_PY
}
informe 010_uno "Uno" 'not os.path.exists("'"$T"'/uno-no")'
informe 020_dos "Dos" 'False'
informe 030_tres "Tres" 'True'
mkdir -p "$T/informes/040_roto"; echo 'raise RuntimeError("roto a propósito")' > "$T/informes/040_roto/MintReportInfo.py"

printf '#!/bin/sh\necho "$@" >> "%s/mintreport-abierto"\n' "$T" > "$T/bin/mintreport"; chmod +x "$T/bin/mintreport"

# El servidor de notificaciones: anota cada Notify y, para «Uno», contesta «default»
# (Show) y para «Tres», «ignore».
cat > "$T/notificaciones.py" <<'FIN_PY'
import sys
from gi.repository import Gio, GLib
XML = """<node><interface name="org.freedesktop.Notifications">
<method name="Notify"><arg type="s" direction="in"/><arg type="u" direction="in"/><arg type="s" direction="in"/>
<arg type="s" direction="in"/><arg type="s" direction="in"/><arg type="as" direction="in"/><arg type="a{sv}" direction="in"/>
<arg type="i" direction="in"/><arg type="u" direction="out"/></method>
<method name="GetCapabilities"><arg type="as" direction="out"/></method>
<signal name="ActionInvoked"><arg type="u"/><arg type="s"/></signal>
<signal name="NotificationClosed"><arg type="u"/><arg type="u"/></signal>
</interface></node>"""
registro = open(sys.argv[1], "a", buffering=1)
cuenta = [0]
def llamada(con, remitente, ruta, iface, metodo, params, inv):
    if metodo == "GetCapabilities":
        inv.return_value(GLib.Variant("(as)", (["actions", "body"],))); return
    app, _, icono, titulo, cuerpo, acciones, hints, _ = params.unpack()
    cuenta[0] += 1; i = cuenta[0]
    registro.write("%d\t%s\t%s\t%s\t%s\t%s\n" % (i, app, titulo, icono, ",".join(acciones), hints.get("desktop-entry", "")))
    inv.return_value(GLib.Variant("(u)", (i,)))
    accion = {"Uno": "default", "Tres": "ignore"}.get(titulo)
    def emitir():
        con.emit_signal(None, ruta, iface, "ActionInvoked", GLib.Variant("(us)", (i, accion)))
        con.emit_signal(None, ruta, iface, "NotificationClosed", GLib.Variant("(uu)", (i, 2)))
        return False
    if accion: GLib.timeout_add(300, emitir)
def adquirido(con, nombre):
    open(sys.argv[2], "w").close()
def bus(con, nombre):
    con.register_object("/org/freedesktop/Notifications", Gio.DBusNodeInfo.new_for_xml(XML).interfaces[0], llamada, None, None)
Gio.bus_own_name(Gio.BusType.SESSION, "org.freedesktop.Notifications", 0, bus, adquirido, None)
GLib.MainLoop().run()
FIN_PY

cat > "$T/dentro.sh" <<'FIN'
set -euo pipefail
T="$1"; BIN="$2"
export GSETTINGS_BACKEND=keyfile GIO_USE_VFS=local XDG_CONFIG_HOME="$T/config" XDG_STATE_HOME="$T/state" \
  MINT_MACOS_AVISOS_INFORMES="$T/informes" PATH="$T/bin:$PATH"
python3 -I "$T/notificaciones.py" "$T/notif.log" "$T/notif.listo" & NP=$!
for _ in $(seq 50); do [ -e "$T/notif.listo" ] && break; sleep 0.1; done
gsettings set com.linuxmint.report ignored-reports "['dos']"
fallas=0
mal() { echo "  ✗ $*"; fallas=$((fallas + 1)); }
contar() { [ -f "$T/notif.log" ] && wc -l < "$T/notif.log" || echo 0; }

"$BIN" --espera 0 --una-vez 3 2> "$T/avisos1.err"
[ "$(contar)" = 2 ] || mal "primera ronda: $(contar) avisos, se esperaban 2"
grep -q $'\tSystem Reports\tUno\txsi-dialog-information-symbolic\tdefault,Show,ignore,Ignore\tmintreport$' "$T/notif.log" || mal "el aviso de Uno no es como se espera: $(cat "$T/notif.log")"
grep -q $'\tTres\t' "$T/notif.log" || mal "no avisó Tres"
grep -q $'\tDos\t' "$T/notif.log" && mal "avisó Dos, que está ignorado"
grep -q 'roto a propósito' "$T/avisos1.err" || mal "el informe roto no quedó en el registro"
[ "$(cat "$T/mintreport-abierto" 2>/dev/null)" = "--reports" ] || mal "Show no abrió mintreport --reports"
gsettings get com.linuxmint.report ignored-reports | grep -q "'tres'" || mal "Ignore no agregó tres a ignored-reports: $(gsettings get com.linuxmint.report ignored-reports)"
gsettings get com.linuxmint.report ignored-reports | grep -q "'dos'" || mal "Ignore pisó la lista"
[ "$(cat "$T/state/mint-macos/avisos-mint")" = $'tres\nuno' ] || mal "estado: $(cat "$T/state/mint-macos/avisos-mint")"

"$BIN" --espera 0 --una-vez 1 2>/dev/null
[ "$(contar)" = 2 ] || mal "segunda ronda repitió: $(contar) avisos"

touch "$T/uno-no"
"$BIN" --espera 0 --una-vez 1 2>/dev/null
[ "$(cat "$T/state/mint-macos/avisos-mint")" = "tres" ] || mal "Uno no salió del estado al dejar de aplicar"
rm "$T/uno-no"
"$BIN" --espera 0 --una-vez 1 2>/dev/null
[ "$(contar)" = 3 ] || mal "Uno no volvió a avisar al aplicar otra vez: $(contar) avisos"

kill "$NP" 2>/dev/null || true
[ "$fallas" = 0 ] && echo "  ✓ mint-macos-avisos: 10 comprobaciones" || exit 1
FIN
# XDG_RUNTIME_DIR propio: si no, lo que active el bus de prueba (gvfs, dconf) se
# monta y escribe en el de José.
mkdir -m 700 "$T/runtime"
XDG_RUNTIME_DIR="$T/runtime" dbus-run-session -- bash "$T/dentro.sh" "$T" "$BIN" || { echo "  registro: $(cat "$T/avisos1.err" 2>/dev/null)"; exit 1; }
