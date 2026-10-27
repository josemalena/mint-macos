#!/usr/bin/env bash
# Un Xvfb propio con Muffin (o Cinnamon con la barra de menús de mint-macos) y el registrador del menú global, para que otra sesión pruebe una app
# dentro (por ejemplo una ventana X11 de Darling), sin tocar :0 ni el bus de José.
#
#   pruebas/xvfb-con-gestor.sh [--display :80] [--tamano 1600x1200] [--cinnamon] [--prefijo DIR] -- COMANDO [ARGS…]
#
# Qué arma, todo en un HOME de prueba nuevo (se borra al salir) y un bus de D-Bus propio (dbus-run-session):
#   - Xvfb en --display (por omisión :80);
#   - Muffin, o con --cinnamon Cinnamon entero con las extensiones y los applets del repo (menú Apple, appmenu@macos y globalmenu@macos) y sin animaciones;
#   - menu-global/registrador.py (com.canonical.AppMenu.Registrar) y, si están en el PATH o en --prefijo/bin, mac-menu o si no mac-ventanas --residente (org.mintmacos.Menu1).
# Corre COMANDO con DISPLAY y DBUS_SESSION_BUS_ADDRESS de ese bus y termina cuando COMANDO termina. Antes de correrlo escribe en stderr las variables
# (DISPLAY, el bus y el HOME de prueba), por si COMANDO está en un contenedor que necesita la ruta del socket.
set -uo pipefail
AQUI="$(cd "$(dirname "$0")" && pwd)"; REPO="$(dirname "$AQUI")"
DISPLAY_N=":80"; TAM="1600x1200"; CINNAMON=false; PREFIJO="$HOME/.local"
while [ $# -gt 0 ]; do
  case "$1" in
    --display) DISPLAY_N="$2"; shift 2 ;;
    --tamano) TAM="$2"; shift 2 ;;
    --cinnamon) CINNAMON=true; shift ;;
    --prefijo) PREFIJO="$2"; shift 2 ;;
    --) shift; break ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "parámetro desconocido: $1 (mira --help)" >&2; exit 2 ;;
  esac
done
[ $# -gt 0 ] || { echo "falta el COMANDO después de --" >&2; exit 2; }
[ ! -e "/tmp/.X11-unix/X${DISPLAY_N#:}" ] || { echo "el display $DISPLAY_N ya está en uso" >&2; exit 1; }
for c in Xvfb dbus-run-session muffin; do command -v "$c" > /dev/null || { echo "falta $c" >&2; exit 1; }; done

H="$(mktemp -d "${TMPDIR:-/tmp}/xvfb-gestor.XXXXXX")"
mkdir -p "$H/config" "$H/data" "$H/cache" "$H/state" "$H/run"; chmod 700 "$H/run"
export HOME="$H" XDG_CONFIG_HOME="$H/config" XDG_DATA_HOME="$H/data" XDG_CACHE_HOME="$H/cache" XDG_STATE_HOME="$H/state" XDG_RUNTIME_DIR="$H/run" \
  DISPLAY="$DISPLAY_N" PATH="$PREFIJO/bin:$PATH" GSETTINGS_BACKEND=keyfile
export PRUEBA_XVFB_HOME="$H"
Xvfb "$DISPLAY_N" -screen 0 "${TAM}x24" > "$H/xvfb.log" 2>&1 & XVFB=$!
trap 'kill "$XVFB" 2>/dev/null; rm -rf "$H"' EXIT
for _ in $(seq 50); do xdpyinfo -display "$DISPLAY_N" > /dev/null 2>&1 && break; sleep 0.1; done

export ARGS_CMD_FILE="$H/cmd"; printf '%s\0' "$@" > "$ARGS_CMD_FILE"
dbus-run-session -- bash -c '
  H="$PRUEBA_XVFB_HOME"; REPO="'"$REPO"'"; CINNAMON='"$CINNAMON"'
  python3 "$REPO/menu-global/registrador.py" > "$H/registrador.log" 2>&1 &
  if command -v mac-menu > /dev/null; then mac-menu > "$H/menu1.log" 2>&1 &
  elif command -v mac-ventanas > /dev/null; then mac-ventanas --residente > "$H/menu1.log" 2>&1 & fi
  if $CINNAMON; then
    mkdir -p "$XDG_DATA_HOME/cinnamon/extensions" "$XDG_DATA_HOME/cinnamon/applets"
    cp -r "$REPO"/extensions/*@macos "$XDG_DATA_HOME/cinnamon/extensions/"
    cp -r "$REPO"/applets/applemenu@macos "$REPO"/applets/appmenu@macos "$REPO"/applets/globalmenu@macos "$XDG_DATA_HOME/cinnamon/applets/"
    gsettings set org.cinnamon enabled-extensions "[\"cmdtab@macos\"]"
    gsettings set org.cinnamon panels-enabled "[\"1:0:top\"]"
    gsettings set org.cinnamon enabled-applets "[\"panel1:left:0:applemenu@macos:3\", \"panel1:left:1:appmenu@macos:1\", \"panel1:left:2:globalmenu@macos:2\"]"
    gsettings set org.cinnamon desktop-effects false
    (ulimit -c 0; exec cinnamon --replace) > "$H/gestor.log" 2>&1 &
    for _ in $(seq 600); do grep -q "Cinnamon started at" "$H/gestor.log" && break; sleep 0.1; done
  else
    (ulimit -c 0; exec muffin --replace --sm-disable) > "$H/gestor.log" 2>&1 &
    for _ in $(seq 50); do wmctrl -m > /dev/null 2>&1 && break; sleep 0.1; done
  fi
  echo "DISPLAY=$DISPLAY  DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS  HOME_DE_PRUEBA=$H" >&2
  mapfile -d "" CMD < "$ARGS_CMD_FILE"
  "${CMD[@]}"
  r=$?
  kill $(jobs -p) 2> /dev/null
  exit $r
'
