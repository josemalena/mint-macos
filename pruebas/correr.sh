#!/usr/bin/env bash
# Pruebas de tareas reales: abrir apps, archivos y la Trash, capturas, ⌘Tab,
# Force Quit, preferencias… Cada caso es un archivo en pruebas/casos/ (ver
# pruebas/LEEME.md para escribir uno).
#
#   pruebas/correr.sh                    todos los casos, en un X aparte que no se ve
#                                        (Xvfb, 1600×1200); sin Xvfb, en Xephyr
#   pruebas/correr.sh --ver              en Xephyr, a la vista dentro del Dell
#                                        (1280×1000 en +0+0): los casos que miden
#                                        el tamaño de la pantalla pueden fallar
#   pruebas/correr.sh 10 trash           solo esos (por el principio del número o
#                                        parte del nombre: «7» son los 7x)
#   pruebas/correr.sh --pantalla-real    en :0, con gui-lock y SIN mandar teclas:
#                                        los casos que necesitan teclado se saltan
#   pruebas/correr.sh --prefijo DIR      los programas de DIR/bin (y DIR/lib, DIR/share)
#                                        en vez de ~/.local: armar.sh lo usa para
#                                        probar lo recién compilado
#   pruebas/correr.sh --lista            los casos, sin correr nada
#
# Nada de la sesión de José entra en las pruebas: su propio X (una copia de
# Xvfb o Xephyr con otro nombre, para que un «pkill Xephyr» ajeno no la mate), su
# propio bus de D-Bus, y HOME y XDG_* propios exportados ANTES de arrancar el
# bus (si no, el dconf-service del bus de prueba escribe en el dconf de José).
# Al terminar se cierran todos los procesos que llevan la marca de esta corrida
# en su entorno, y se comprueba que el dconf de José no cambió.
#
# Resultados (registro de cada caso y capturas) en ~/.cache/mint-macos/pruebas/
# resultados, o en --resultados DIR. Sale con 1 si algún caso falla, y con 2 si
# el dconf de José cambió (después de cada caso se mira, y la corrida se para).
set -euo pipefail

AQUI="$(cd "$(dirname "$0")" && pwd)"
REAL=false
VER=false
PREFIJO="$HOME/.local"
RES=""
LISTA=false
FILTROS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --pantalla-real) REAL=true; shift ;;
    --ver) VER=true; shift ;;
    --prefijo) PREFIJO="$(cd "$2" && pwd)"; shift 2 ;;
    --resultados) RES="$2"; shift 2 ;;
    --lista) LISTA=true; shift ;;
    -h|--help) sed -n '2,27p' "$0"; exit 0 ;;
    -*) echo "opción desconocida: $1" >&2; exit 2 ;;
    *) FILTROS+=("$1"); shift ;;
  esac
done

# Los casos, en orden de nombre; con filtros, los que casan con alguno.
CASOS=()
for c in "$AQUI"/casos/*.sh; do
  n="$(basename "$c" .sh)"
  if [ ${#FILTROS[@]} -gt 0 ]; then
    ok=false
    # Un número casa con el principio («7» son los 7x, no el 37); un texto, con
    # cualquier parte del nombre.
    for f in "${FILTROS[@]}"; do
      if [[ "$f" =~ ^[0-9]+$ ]]; then [[ "$n" == "$f"* ]] && ok=true
      else [[ "$n" == *"$f"* ]] && ok=true; fi
    done
    $ok || continue
  fi
  CASOS+=("$c")
done
if $LISTA; then
  for c in "${CASOS[@]}"; do printf '%-28s %s\n' "$(basename "$c" .sh)" "$(sed -n 's/^# caso: //p' "$c" | head -1)"; done
  exit 0
fi
[ ${#CASOS[@]} -gt 0 ] || { echo "ningún caso casa con: ${FILTROS[*]}"; exit 2; }

CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/mint-macos"
mkdir -p "$CACHE"
exec 8> "$CACHE/pruebas.lock"
flock -n 8 || { echo "  ✗ ya hay otra corrida de pruebas"; exit 1; }
TRABAJO="$CACHE/pruebas"
RES="${RES:-$TRABAJO/resultados}"
rm -rf "${TRABAJO:?}/home" "${TRABAJO:?}/x"
mkdir -p "$TRABAJO/home" "$TRABAJO/x" "$RES"
rm -f "$RES"/*.log "$RES"/*.png "$RES"/resumen.txt
MARCA="mmp-$$-$RANDOM"

# El dconf de José, para comprobar al final que nadie lo tocó.
# PRUEBAS_DCONF_JOSE: otro archivo en su lugar, para probar este mismo chequeo.
DCONF_JOSE="${PRUEBAS_DCONF_JOSE:-$HOME/.config/dconf/user}"
DCONF_ANTES="$(sha256sum "$DCONF_JOSE" 2>/dev/null | cut -d' ' -f1 || true)"
# Y una copia, para poder decir qué clave cambió si cambia. Lleva los ajustes
# de José: va aparte de los resultados y solo la lee él.
DCOPIA="${XDG_DATA_HOME:-$HOME/.local/share}/mint-macos/pruebas-dconf"
rm -rf "$DCOPIA"
(umask 077; mkdir -p "$DCOPIA/dconf-antes/dconf")
install -m 600 "$DCONF_JOSE" "$DCOPIA/dconf-antes/dconf/user" 2>/dev/null || true
# dconf dump de una copia: lee el archivo directo (sin dconf-service) con un
# perfil que solo tiene esa base.
volcar_dconf() {
  printf 'user-db:user\n' > "$1/perfil"
  XDG_CONFIG_HOME="$1" DCONF_PROFILE="$1/perfil" dconf dump / 2>/dev/null
}

XPID=""
XNOMBRE=""
LOCK=false
limpiar() {
  local p
  # Todo lo que lleva la marca de esta corrida (lo lanzado por los casos, el bus,
  # lo que el bus activó: gvfs, dconf-service…), sin pgrep -f de una ruta que
  # está en el propio comando.
  for _ in 1 2; do
    for p in $(grep -lzx "MINT_MACOS_PRUEBA=$MARCA" /proc/[0-9]*/environ 2>/dev/null | cut -d/ -f3); do
      [ "$p" = "$$" ] || kill "$p" 2>/dev/null || true
    done
    sleep 0.5
  done
  [ -n "$XPID" ] && kill "$XPID" 2>/dev/null || true
  fusermount -uz "$TRABAJO/home/run/gvfs" 2>/dev/null || true
  $LOCK && gui-lock soltar >/dev/null 2>&1 || true
}
trap limpiar EXIT

# El tamaño de la pantalla de prueba; los casos lo leen de PRUEBAS_ANCHO y PRUEBAS_ALTO.
PRUEBAS_ANCHO=1600 PRUEBAS_ALTO=1200
if $REAL; then
  PANT=":0"
  read -r PRUEBAS_ANCHO PRUEBAS_ALTO < <(xdpyinfo -display :0 | awk '/dimensions:/{split($2, d, "x"); print d[1], d[2]}')
  gui-lock tomar Pruebas 900 || { echo "  ✗ la pantalla la tiene otra sesión"; exit 1; }
  LOCK=true
else
  # Una copia del X con otro nombre, en el primer display libre desde :70. Por
  # defecto Xvfb, que no se ve: la regla de José es que nada se abra en el LEN
  # (HDMI-3), y a 1600×1200 Xephyr no cabe en el Dell (HDMI-1, 1280×1024, en +0+0).
  n=70
  while [ -e "/tmp/.X11-unix/X$n" ] || [ -e "/tmp/.X$n-lock" ]; do n=$((n + 1)); done
  PANT=":$n"
  if ! $VER && [ -x /usr/bin/Xvfb ]; then
    cp /usr/bin/Xvfb "$TRABAJO/x/xpruebas"; XNOMBRE="Xvfb, no se ve"
    MINT_MACOS_PRUEBA="$MARCA" "$TRABAJO/x/xpruebas" "$PANT" -screen 0 "${PRUEBAS_ANCHO}x${PRUEBAS_ALTO}x24" -nolisten tcp \
      > "$RES/xephyr.log" 2>&1 &
  else
    if $VER; then
      PRUEBAS_ANCHO=1280 PRUEBAS_ALTO=1000
    else
      echo "  ⚠ sin Xvfb (sudo apt install xvfb): Xephyr a ${PRUEBAS_ANCHO}×${PRUEBAS_ALTO} se pasa del Dell al LEN" >&2
    fi
    cp /usr/bin/Xephyr "$TRABAJO/x/xpruebas"; XNOMBRE="Xephyr"
    MINT_MACOS_PRUEBA="$MARCA" "$TRABAJO/x/xpruebas" "$PANT" -screen "${PRUEBAS_ANCHO}x${PRUEBAS_ALTO}+0+0" -nolisten tcp -br \
      > "$RES/xephyr.log" 2>&1 &
  fi
  XPID=$!
  for _ in $(seq 50); do [ -e "/tmp/.X11-unix/X$n" ] && break; sleep 0.1; done
  [ -e "/tmp/.X11-unix/X$n" ] || { echo "  ✗ Xephyr no arrancó"; cat "$RES/xephyr.log"; exit 1; }
fi

# Los esquemas de GSettings: los del sistema y, encima, los del prefijo.
H="$TRABAJO/home"
mkdir -p "$H"/{config,data,cache,state,esquemas} "$H/run"; chmod 700 "$H/run"
cp /usr/share/glib-2.0/schemas/*.xml "$H/esquemas/"
[ -d "$PREFIJO/share/glib-2.0/schemas" ] && cp -f "$PREFIJO"/share/glib-2.0/schemas/*.xml "$H/esquemas/" 2>/dev/null || true
glib-compile-schemas "$H/esquemas"

HOME_REAL="$HOME"
ARCH="$(dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null || echo x86_64-linux-gnu)"
export MINT_MACOS_PRUEBA="$MARCA" MINT_MACOS_REPO="$(dirname "$AQUI")" PRUEBAS_RES="$RES" PRUEBAS_REAL="$REAL"
export PRUEBAS_PREFIJO="$PREFIJO" PRUEBAS_LIB="$AQUI/lib.sh" PRUEBAS_CACHE_REAL="$CACHE"
# PRUEBAS_RUST: la carpeta de los binarios de rust/ que se prueban (armar.sh la
# pasa con lo recién compilado); si no, los de rust/target/release.
export PRUEBAS_RUST="${PRUEBAS_RUST:-}"
export PRUEBAS_DCONF_JOSE="$DCONF_JOSE" PRUEBAS_DCONF_ANTES="$DCONF_ANTES"
export PRUEBAS_ANCHO PRUEBAS_ALTO
export DISPLAY="$PANT" HOME="$H" XDG_CONFIG_HOME="$H/config" XDG_DATA_HOME="$H/data" \
  XDG_CACHE_HOME="$H/cache" XDG_STATE_HOME="$H/state" XDG_RUNTIME_DIR="$H/run" GSETTINGS_SCHEMA_DIR="$H/esquemas" \
  XDG_DATA_DIRS="$PREFIJO/share:/usr/local/share:/usr/share" PATH="$PREFIJO/bin:$PATH" \
  GTK_IM_MODULE=gtk-im-context-simple QT_IM_MODULE=simple XMODIFIERS=
# Un prefijo que no es el ~/.local de verdad: sus librerías (libplank) primero.
if [ "$PREFIJO" != "$HOME_REAL/.local" ]; then
  export LD_LIBRARY_PATH="$PREFIJO/lib/$ARCH${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
unset DBUS_SESSION_BUS_ADDRESS SESSION_MANAGER

printf '▸ Pruebas en %s (%s), %s casos\n' "$PANT" "$($REAL && echo 'la pantalla de José, sin teclas' || echo "$XNOMBRE")" "${#CASOS[@]}"
ESTADO=0
# Lo que escriben el bus y los servicios que activa (gvfs, portales…) va a
# bus.log; por la terminal, solo el resumen.
dbus-run-session -- bash "$AQUI/sesion.sh" "${CASOS[@]}" 2> "$RES/bus.log" || ESTADO=$?

# sesion.sh ya lo mira después de cada caso; esto cubre lo que pase al cerrar.
DCONF_DESPUES="$(sha256sum "$DCONF_JOSE" 2>/dev/null | cut -d' ' -f1 || true)"
if [ "$DCONF_ANTES" != "$DCONF_DESPUES" ]; then
  echo "  ✗ el dconf de José ($DCONF_JOSE) cambió durante las pruebas: la corrida no vale." | tee -a "$RES/resumen.txt"
  (umask 077; mkdir -p "$DCOPIA/dconf-despues/dconf")
  install -m 600 "$DCONF_JOSE" "$DCOPIA/dconf-despues/dconf/user" 2>/dev/null || true
  (umask 077; diff <(volcar_dconf "$DCOPIA/dconf-antes") <(volcar_dconf "$DCOPIA/dconf-despues") > "$DCOPIA/dconf.diff")
  echo "    lo que cambió: $DCOPIA/dconf.diff ($(grep -c '^[<>]' "$DCOPIA/dconf.diff") líneas)" | tee -a "$RES/resumen.txt"
  echo "    Si fue una prueba, revisar con dconf dump / y reponer; si fue José usando su sesión, repetir." | tee -a "$RES/resumen.txt"
  ESTADO=2
fi
echo "  resultados: $RES"
exit "$ESTADO"
