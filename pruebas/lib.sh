# shellcheck shell=bash
# Lo que un caso tiene a mano (sesion.sh lo carga antes del caso). Un caso
# define prueba(); si una comprobación no se cumple, falla y el caso termina.
#
#   saltar MOTIVO                      el caso no aplica aquí (sale con 77)
#   falla MOTIVO                       el caso falla
#   requiere PROGRAMA…                 salta si falta alguno
#   necesita_teclado                   salta en --pantalla-real: a :0 no se mandan teclas
#   lanzar PROGRAMA ARG…               lo arranca aparte (sesion.sh lo cierra al final)
#   esperar_ventana CLASE [SEG]        espera una ventana visible de esa clase
#                                      (expresión regular de WM_CLASS); imprime su id
#   esperar_sin_ventana ID [SEG]       espera a que esa ventana se cierre
#   titulo ID                          el título de la ventana
#   esperar_texto ID TEXTO [SEG]       espera a que la app de esa ventana muestre un
#                                      elemento con ese nombre (accesibilidad, AT-SPI)
#   pulsar ID TEXTO [SEG]              pulsa el botón con ese nombre (AT-SPI, como un
#                                      clic; no depende del botón por defecto)
#   cerrar_ventana ID                  la cierra como el botón rojo (sin teclas)
#   teclas TECLA…                      xdotool key (solo en Xephyr)
#   captura NOMBRE                     la pantalla a resultados/<caso>-NOMBRE.png
#   comprobar DESCRIPCIÓN CMD…         corre CMD; si falla, falla con DESCRIPCIÓN
#   paso TEXTO                         una línea en el registro del caso
#   md5_uri RUTA                       el md5 de la URI file:// (spec de miniaturas;
#                                      el nombre de los lanzadores de AppImage)
#   binario_rust NOMBRE                la ruta de un binario de rust/ (el de
#                                      PRUEBAS_RUST, el compilado en el repo o el del
#                                      PATH); salta si no hay
#
# Cabecera del caso: «# caso: …», «# límite: SEG» y, si hace falta Cinnamon
# entero (extensiones como cmdtab@macos), «# gestor: cinnamon» (sesion.sh).
#
# Variables: PRUEBAS_CASO (el nombre), PRUEBAS_RES (resultados), PRUEBAS_REAL,
# PRUEBAS_PREFIJO, MINT_MACOS_REPO, y HOME/XDG_* de prueba (se pueden ensuciar).

set -euo pipefail

# Todo lo que se escribe va a stderr: stdout queda para lo que devuelve una
# función (el id de esperar_ventana). Un falla o saltar dentro de $(…) termina
# el caso igual, por set -e.
saltar() { echo "$*" >&2; exit 77; }
falla() { echo "✗ $*" >&2; exit 1; }
paso() { echo "· $*" >&2; }

requiere() {
  local p
  for p in "$@"; do command -v "$p" >/dev/null || saltar "falta $p"; done
}

necesita_teclado() {
  [ "$PRUEBAS_REAL" != true ] || saltar "necesita teclado, y en la pantalla de José no se mandan teclas"
}

# liberar_nombre_dbus NOMBRE: si alguien del bus de la prueba ya tiene ese nombre (un servicio que se activó solo cuando un panel le
# preguntó algo en un caso anterior), lo cierra por su pid: el de mentira del caso necesita el nombre. Es el bus de la prueba, no
# el de la sesión de José, y se mata por pid, nunca por nombre.
# bloqueo_pids: los pids de mac-bloqueo de ESTA prueba (los que tienen su XDG_RUNTIME_DIR). La sesión de José tiene su propio mac-bloqueo --vigilar
# corriendo y, si está bloqueada, su pantalla: no se cuentan ni se tocan.
bloqueo_pids() {
  local p
  for p in $(pgrep -x mac-bloqueo); do
    tr '\0' '\n' < "/proc/$p/environ" 2>/dev/null | grep -qx "XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR" && [ "$(awk '{print $3}' "/proc/$p/stat" 2>/dev/null)" != Z ] && echo "$p"
  done
  return 0
}

# despejar_pantalla: cierra lo que otro caso de la misma corrida dejó abierto (una ventana de Edge grande, por ejemplo, hace que el Dock se
# esconda solo y un clic en su franja caiga en esa ventana). Solo procesos del sandbox (su HOME).
despejar_pantalla() {
  case "$HOME" in */pruebas/home*) ;; *) return 0 ;; esac   # nunca fuera del sandbox: mataría los programas de José
  local p
  for p in $(pgrep -u "$(id -u)" -x 'msedge|chrome|firefox|xed|nemo|fynder|kitty' 2>/dev/null); do
    if grep -qz "^HOME=$HOME$" "/proc/$p/environ" 2>/dev/null; then kill "$p" 2>/dev/null || true; fi
  done
  # Edge/Chrome no dejan leer su /proc/PID/environ (no son «dumpable»): se reconocen por su perfil de prueba, que va bajo el HOME del sandbox
  # (--user-data-dir=$HOME/edge-prueba). Nunca por el nombre: el Edge de José también se llama msedge.
  pkill -u "$(id -u)" -f -- "--user-data-dir=$HOME/edge-prueba" 2>/dev/null || true   # (pkill sale con 1 si no hay nada: con errexit mataría al caso)
  sleep 1
}

liberar_nombre_dbus() {
  local nombre="$1" pid=""
  [ "$(gdbus call --session -d org.freedesktop.DBus -o /org/freedesktop/DBus -m org.freedesktop.DBus.NameHasOwner "$nombre" 2>/dev/null)" = "(true,)" ] || return 0
  pid="$(gdbus call --session -d org.freedesktop.DBus -o /org/freedesktop/DBus -m org.freedesktop.DBus.GetConnectionUnixProcessID "$nombre" 2>/dev/null | sed -n 's/.*uint32 \([0-9]*\).*/\1/p')"
  [ -n "$pid" ] || return 0
  paso "libero $nombre: cierro el pid $pid de este bus"
  kill "$pid" 2>/dev/null || true
  for _ in $(seq 25); do
    [ "$(gdbus call --session -d org.freedesktop.DBus -o /org/freedesktop/DBus -m org.freedesktop.DBus.NameHasOwner "$nombre" 2>/dev/null)" = "(true,)" ] || return 0
    sleep 0.2
  done
}

lanzar() {
  local log="$PRUEBAS_RES/$PRUEBAS_CASO-$(basename "$1").log"
  paso "lanzo: $* ($(command -v "$1"))"
  setsid "$@" >> "$log" 2>&1 < /dev/null &
}

esperar_ventana() {
  local clase="$1" seg="${2:-15}" id=""
  for _ in $(seq $((seg * 5))); do
    id="$(xdotool search --onlyvisible --class "$clase" 2>/dev/null | tail -1 || true)"
    [ -n "$id" ] && { paso "ventana $clase: $id «$(titulo "$id")»"; echo "$id"; return 0; }
    sleep 0.2
  done
  falla "no salió ninguna ventana de clase $clase en ${seg}s"
}

esperar_sin_ventana() {
  local id="$1" seg="${2:-10}"
  for _ in $(seq $((seg * 5))); do
    xdotool getwindowname "$id" >/dev/null 2>&1 || return 0
    sleep 0.2
  done
  falla "la ventana $id sigue abierta después de ${seg}s"
}

titulo() { xdotool getwindowname "$1" 2>/dev/null || true; }

esperar_texto() {
  local pid; pid="$(xdotool getwindowpid "$1")"
  python3 "$(dirname "$PRUEBAS_LIB")/atspi.py" --pid "$pid" --texto "$2" --segundos "${3:-15}" >&2 \
    || falla "la ventana $1 no muestra «$2»"
  paso "se ve «$2»"
}

pulsar() {
  necesita_teclado
  local pid; pid="$(xdotool getwindowpid "$1")"
  python3 "$(dirname "$PRUEBAS_LIB")/atspi.py" --pid "$pid" --texto "$2" --rol "push button" --pulsar --segundos "${3:-10}" >&2 \
    || falla "no se pudo pulsar «$2» en la ventana $1"
  paso "pulso «$2»"
}

cerrar_ventana() { paso "cierro $1"; wmctrl -i -c "$1"; }

teclas() {
  necesita_teclado
  paso "teclas: $*"
  xdotool key --clearmodifiers "$@"
}

captura() {
  local f="$PRUEBAS_RES/$PRUEBAS_CASO-$1.png" antes="" ahora
  # Una ventana recién mapeada tarda en pintarse, y con Cinnamon el panel ya da
  # colores antes de que la ventana salga: se repite hasta que dos capturas
  # seguidas, con contenido, den los mismos píxeles (o 5 s).
  for _ in $(seq 25); do
    import -display "$DISPLAY" -window root "$f" 2>/dev/null || true
    if [ "$(identify -format '%k' "$f" 2>/dev/null || echo 0)" -gt 2 ]; then
      ahora="$(identify -format '%#' "$f" 2>/dev/null || true)"
      [ -n "$ahora" ] && [ "$ahora" = "$antes" ] && { paso "captura: $f"; return 0; }
      antes="$ahora"
    fi
    sleep 0.2
  done
  [ -n "$antes" ] || falla "la captura $f salió vacía"
  paso "captura: $f (la pantalla seguía cambiando a los 5 s)"
}

md5_uri() {
  python3 -I -c 'import hashlib, sys
from gi.repository import Gio
print(hashlib.md5(Gio.File.new_for_path(sys.argv[1]).get_uri().encode()).hexdigest())' "$1"
}

binario_rust() {
  local d
  for d in "${PRUEBAS_RUST:-}" "$MINT_MACOS_REPO/rust/target/release"; do
    [ -n "$d" ] && [ -x "$d/$1" ] && { echo "$d/$1"; return 0; }
  done
  command -v "$1" || saltar "falta $1 (cd rust && cargo build --release)"
}

comprobar() {
  local desc="$1"; shift
  if "$@"; then paso "bien: $desc"; else falla "$desc"; fi
}
