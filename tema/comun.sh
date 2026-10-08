# Funciones compartidas por los constructores de Constanza. Se carga con
# «source»; no se ejecuta solo.

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
  local dev vol punto
  for dev in $(lsblk -rno PATH,FSTYPE | awk '$2=="apfs"{print $1}'); do
    vol=$(fsapfsinfo "$dev" 2>/dev/null | awk -F': *' '
      /^Volume: [0-9]+ information/ {split($0,a," "); n=a[2]+0}
      /^\tName/ {gsub(/^[ \t]+|[ \t]+$/,"",$2); nombre[n]=$2}
      END {for (i in nombre) if (nombre[i] !~ / - Data$|^(Preboot|Recovery|VM|Update)$/) {print i; exit}}')
    [ -n "$vol" ] || continue
    punto="$(mktemp -d)"
    fsapfsmount -f "$vol" "$dev" "$punto" >/dev/null 2>&1 &
    sleep 2
    if [ -d "$punto/$prueba" ]; then MAC_SISTEMA="$punto"; MAC_MONTADO_AQUI="$punto"; return 0; fi
    fusermount -u "$punto" 2>/dev/null; rmdir "$punto" 2>/dev/null
  done
  return 1
}
desmontar_mac() {
  [ -n "$MAC_MONTADO_AQUI" ] || return 0
  fusermount -u "$MAC_MONTADO_AQUI" 2>/dev/null && rmdir "$MAC_MONTADO_AQUI"
  MAC_MONTADO_AQUI=""
}
