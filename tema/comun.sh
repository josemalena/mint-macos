# Funciones compartidas por los constructores de Constanza. Se carga con
# «source»; no se ejecuta solo.

# El disco de la Mac. Se puede fijar con variables (desde-mac.sh y
# migrar-datos.sh las ponen a partir de sus parámetros):
#   MAC_DISCO        el contenedor APFS, p. ej. /dev/sdb2
#   MAC_VOL_SISTEMA  índice del volumen de sistema (el que trae System/Library)
#   MAC_VOL_DATOS    índice del volumen de datos («<nombre> - Data», con Users/)
# Sin ellas se busca el primer contenedor APFS y los volúmenes por su nombre.
# Todo se monta en SOLO LECTURA (fsapfsmount no sabe escribir).

# volumenes_apfs <disco>: «índice<TAB>nombre» de cada volumen.
volumenes_apfs() {
  fsapfsinfo "$1" 2>/dev/null | awk -F': *' '
    /^Volume: [0-9]+ information/ {split($0,a," "); n=a[2]+0}
    /^\tName/ {gsub(/^[ \t]+|[ \t]+$/,"",$2); print n "\t" $2}'
}
discos_apfs() {
  if [ -n "${MAC_DISCO:-}" ]; then echo "$MAC_DISCO"; else lsblk -rno PATH,FSTYPE | awk '$2=="apfs"{print $1}'; fi
}

# montar_volumen <disco> <índice> <prueba>: monta en un punto temporal y
# deja la ruta en MONTADO si existe <prueba> dentro. Devuelve 1 si no.
MAC_MONTADOS=()
montar_volumen() {
  local dev="$1" vol="$2" prueba="$3" punto
  punto="$(mktemp -d)"
  fsapfsmount -f "$vol" "$dev" "$punto" >/dev/null 2>&1 &
  for _ in 1 2 3 4 5 6; do [ -e "$punto/$prueba" ] && break; sleep 1; done
  if [ -e "$punto/$prueba" ]; then MONTADO="$punto"; MAC_MONTADOS+=("$punto"); return 0; fi
  fusermount -u "$punto" 2>/dev/null; rmdir "$punto" 2>/dev/null
  return 1
}

# montar_mac_sistema: deja en MAC_SISTEMA la raíz del volumen de sistema de
# una Mac (el que trae System/Library/CoreServices). Si MAC_SISTEMA ya viene
# definida, la respeta. Si no, busca el contenedor APFS y monta en solo
# lectura el volumen que no es «- Data», Preboot, Recovery, VM ni Update.
# Devuelve 1 si no hay disco de Mac. desmontar_mac lo suelta.
MAC_MONTADO_AQUI=""
montar_mac_sistema() {
  local prueba="System/Library/CoreServices/CoreTypes.bundle"
  if [ -n "${MAC_SISTEMA:-}" ]; then [ -d "$MAC_SISTEMA/$prueba" ]; return; fi
  command -v fsapfsinfo >/dev/null || return 1
  local dev vol
  for dev in $(discos_apfs); do
    if [ -n "${MAC_VOL_SISTEMA:-}" ]; then vol="$MAC_VOL_SISTEMA"
    else vol=$(volumenes_apfs "$dev" | awk -F'\t' '$2 !~ / - Data$|^(Preboot|Recovery|VM|Update)$/ {print $1; exit}'); fi
    [ -n "$vol" ] || continue
    if montar_volumen "$dev" "$vol" "$prueba"; then MAC_SISTEMA="$MONTADO"; MAC_MONTADO_AQUI="$MONTADO"; return 0; fi
  done
  return 1
}

# montar_mac_datos: deja en MAC_DATOS la raíz del volumen de datos (el que
# trae Users/). Respeta MAC_DATOS si ya viene definida.
montar_mac_datos() {
  if [ -n "${MAC_DATOS:-}" ]; then [ -d "$MAC_DATOS/Users" ]; return; fi
  command -v fsapfsinfo >/dev/null || return 1
  local dev vol
  for dev in $(discos_apfs); do
    if [ -n "${MAC_VOL_DATOS:-}" ]; then vol="$MAC_VOL_DATOS"
    else vol=$(volumenes_apfs "$dev" | awk -F'\t' '$2 ~ / - Data$/ {print $1; exit}'); fi
    [ -n "$vol" ] || continue
    if montar_volumen "$dev" "$vol" "Users"; then MAC_DATOS="$MONTADO"; return 0; fi
  done
  return 1
}
desmontar_mac() {
  local p
  for p in "${MAC_MONTADOS[@]}"; do
    fusermount -u "$p" 2>/dev/null && rmdir "$p" 2>/dev/null
  done
  MAC_MONTADOS=(); MAC_MONTADO_AQUI=""
}
