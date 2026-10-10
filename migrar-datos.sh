#!/usr/bin/env bash
# Copia los datos del usuario de la Mac a las carpetas del usuario de Linux:
# Desktop, Documents, Downloads, Pictures, Movies y Music.
#
#   ./migrar-datos.sh --usuario-mac NOMBRE [--usuario-linux NOMBRE]
#                     [--disco /dev/sdX2] [--volumen-datos N]
#                     [--carpetas "Desktop Documents …"] [--simular]
#
# Reglas:
#   - El disco de la Mac se monta en SOLO LECTURA; no se toca.
#   - Nunca sobrescribe: lo que ya exista en Linux con el mismo nombre se
#     queda como está (rsync --ignore-existing) y sale en el informe.
#   - Sigue los enlaces del destino: si ~/Documents es un enlace a otro disco,
#     se copia allá y el enlace no se rompe.
#   - --simular hace todo menos copiar: tamaños, archivos y espacio libre.
#     Conviene correrlo primero.
#   - Fotos: la fototeca (*.photoslibrary) se copia entera, como carpeta.
#     En Linux no se navega como en Fotos: las fotos originales están dentro,
#     en «originals» (o «Masters» en las viejas).
#
# Las carpetas de destino son las de xdg-user-dir (Escritorio, Documentos…
# si el sistema está en español), no un nombre fijo.
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
SIMULAR=false
USUARIO_MAC="${MAC_USUARIO:-}"
USUARIO_LINUX="${USER}"
CARPETAS="Desktop Documents Downloads Pictures Movies Music"
while [ $# -gt 0 ]; do
  case "$1" in
    --disco) export MAC_DISCO="$2"; shift 2 ;;
    --volumen-datos) export MAC_VOL_DATOS="$2"; shift 2 ;;
    --usuario-mac) USUARIO_MAC="$2"; shift 2 ;;
    --usuario-linux) USUARIO_LINUX="$2"; shift 2 ;;
    --carpetas) CARPETAS="$2"; shift 2 ;;
    --simular) SIMULAR=true; shift ;;
    -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
    *) echo "✗ parámetro desconocido: $1 (mira --help)"; exit 2 ;;
  esac
done

paso() { printf '\n▸ %s\n' "$*"; }
humano() { numfmt --to=iec --suffix=B "${1:-0}" 2>/dev/null || echo "${1:-0} B"; }

# El usuario de Linux: su $HOME y sus carpetas de xdg-user-dirs.
HOME_LINUX="$(getent passwd "$USUARIO_LINUX" | cut -d: -f6)"
[ -n "$HOME_LINUX" ] && [ -d "$HOME_LINUX" ] || { echo "✗ no existe el usuario de Linux «$USUARIO_LINUX»"; exit 1; }
[ "$USUARIO_LINUX" = "$USER" ] || [ "$(id -u)" = 0 ] || { echo "✗ para copiar a otro usuario hay que correrlo como ese usuario (o con sudo)"; exit 1; }
destino_de() { # carpeta de la Mac → carpeta de Linux
  local xdg
  case "$1" in
    Desktop) xdg=DESKTOP ;; Documents) xdg=DOCUMENTS ;; Downloads) xdg=DOWNLOAD ;;
    Pictures) xdg=PICTURES ;; Movies) xdg=VIDEOS ;; Music) xdg=MUSIC ;;
    *) echo "$HOME_LINUX/$1"; return ;;
  esac
  local d
  d="$(HOME="$HOME_LINUX" xdg-user-dir "$xdg" 2>/dev/null || true)"
  d="${d%/}"
  # xdg-user-dir devuelve el $HOME mismo cuando la carpeta no está definida
  # (o está como «$HOME/»): ahí NUNCA se copia, se usa ~/<Nombre>.
  if [ -z "$d" ] || [ "$d" = "${HOME_LINUX%/}" ]; then d="$HOME_LINUX/$1"; fi
  echo "$d"
}

source "$REPO/tema/comun.sh"
trap desmontar_mac EXIT

paso "El disco de la Mac (solo lectura)"
command -v fsapfsmount >/dev/null || { echo "  ✗ falta fsapfsmount: corre antes sudo ./requisitos.sh"; exit 1; }
command -v rsync >/dev/null || { echo "  ✗ falta rsync: corre antes sudo ./requisitos.sh"; exit 1; }
montar_mac_datos || { echo "  ✗ no encontré el volumen de datos (prueba --disco y --volumen-datos)"; exit 1; }
echo "  datos montados en $MAC_DATOS"
USUARIOS="$(ls "$MAC_DATOS/Users" | grep -v -x -E 'Shared|Guest|\.localized' || true)"
if [ -z "$USUARIO_MAC" ]; then
  [ "$(echo "$USUARIOS" | grep -c .)" = 1 ] && USUARIO_MAC="$USUARIOS" \
    || { echo "  ✗ hay varios usuarios en la Mac: $(echo $USUARIOS); di cuál con --usuario-mac"; exit 1; }
fi
ORIGEN="$MAC_DATOS/Users/$USUARIO_MAC"
[ -d "$ORIGEN" ] || { echo "  ✗ no existe /Users/$USUARIO_MAC en la Mac (hay: $(echo $USUARIOS))"; exit 1; }
echo "  usuario de la Mac: $USUARIO_MAC → usuario de Linux: $USUARIO_LINUX ($HOME_LINUX)"
$SIMULAR && echo "  SIMULACIÓN: no se copia nada"

TOTAL_NUEVO=0; TOTAL_YA=0; COPIAR=()
declare -A NECESITA   # bytes nuevos por sistema de archivos de destino
for c in $CARPETAS; do
  paso "$c"
  if [ ! -d "$ORIGEN/$c" ]; then echo "  no existe en la Mac"; continue; fi
  DEST="$(destino_de "$c")"
  # Si el destino es un enlace, se copia a donde apunta (y el enlace queda).
  REAL="$(readlink -f "$DEST" 2>/dev/null || echo "$DEST")"
  # Segundo candado: jamás copiar a la raíz del $HOME ni a /.
  case "${REAL%/}" in ""|/|"${HOME_LINUX%/}") echo "  ✗ el destino de $c sería ${REAL:-/}: no se copia"; exit 1 ;; esac
  [ "$REAL" != "$DEST" ] && echo "  $DEST es un enlace: se copia a $REAL"
  # rsync -n con estadísticas: cuánto es nuevo y cuánto ya estaba.
  STATS="$(rsync -a -n --stats --ignore-existing --exclude='.DS_Store' --exclude='.localized' \
           "$ORIGEN/$c/" "$REAL/" 2>/dev/null || true)"
  N_ARCH="$(echo "$STATS" | awk -F': ' '/Number of regular files transferred/ {gsub(/[,.]/,"",$2); print $2+0}')"
  B_NUEVO="$(echo "$STATS" | awk -F': ' '/Total transferred file size/ {gsub(/[^0-9]/,"",$2); print $2+0}')"
  B_TOTAL="$(echo "$STATS" | awk -F': ' '/Total file size/ {gsub(/[^0-9]/,"",$2); print $2+0}')"
  B_YA=$(( ${B_TOTAL:-0} - ${B_NUEVO:-0} ))
  echo "  en la Mac: $(humano "$B_TOTAL") · nuevo para copiar: $(humano "$B_NUEVO") en ${N_ARCH:-0} archivos · ya está en Linux (no se toca): $(humano "$B_YA")"
  for lib in "$ORIGEN/$c"/*.photoslibrary; do
    [ -d "$lib" ] && echo "  ojo: $(basename "$lib") se copia como carpeta; en Linux las fotos están dentro, en «originals» o «Masters»"
  done
  TOTAL_NUEVO=$(( TOTAL_NUEVO + ${B_NUEVO:-0} )); TOTAL_YA=$(( TOTAL_YA + B_YA ))
  FS="$(df --output=target "$(dirname "$REAL")" 2>/dev/null | tail -1)"
  NECESITA[$FS]=$(( ${NECESITA[$FS]:-0} + ${B_NUEVO:-0} ))
  COPIAR+=("$c|$REAL")
done

paso "Espacio"
FALTA=false
for fs in "${!NECESITA[@]}"; do
  libre=$(( $(df --output=avail -B1 "$fs" | tail -1) ))
  echo "  $fs: hace falta $(humano "${NECESITA[$fs]}"), libre $(humano "$libre")"
  [ "${NECESITA[$fs]}" -gt "$libre" ] && { echo "  ✗ no cabe en $fs"; FALTA=true; }
done
echo "  total nuevo: $(humano "$TOTAL_NUEVO") · ya estaba (no se tocó): $(humano "$TOTAL_YA")"
if $SIMULAR; then
  $FALTA && echo "  ✗ hay que liberar espacio antes de copiar" || echo "  cabe: corre lo mismo sin --simular para copiar"
  exit 0
fi
$FALTA && { echo "  ✗ no se copió nada: hay que liberar espacio"; exit 1; }

for par in "${COPIAR[@]}"; do
  c="${par%%|*}"; REAL="${par#*|}"
  paso "Copiando $c → $REAL"
  mkdir -p "$REAL"
  rsync -a --ignore-existing --info=progress2 --exclude='.DS_Store' --exclude='.localized' \
    "$ORIGEN/$c/" "$REAL/"
done
paso "Listo"
echo "  Lo que ya existía en Linux no se tocó. El disco de la Mac tampoco."
