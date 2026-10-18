#!/bin/bash
# Los discos APFS de la Mac en Fynder con su nombre, el ícono de su bus y una sola
# vez (18-10-2026). REQUIERE ROOT:
#
#   sudo apfs/discos-root.sh            lo aplica
#   sudo apfs/discos-root.sh --volver   deja todo como estaba antes de la última vez
#
# Qué hace:
#   1. udisks deja de enseñar el contenedor APFS crudo de cada disco de fstab
#      (la regla de /etc/udev/rules.d/99-hide-macmini-partition.rules, por UUID).
#      Sin ella sale un «1000 GB Volume» y un clic monta otra copia encima del
#      montaje de fstab (pasó el 18-10-2026 a las 14:06 con MacMiniHDD).
#   2. En /etc/fstab, cada disco fsapfs lleva x-gvfs-show, x-gvfs-name (el nombre
#      de su punto de montaje) y x-gvfs-icon según el bus real (lsblk TRAN y ROTA),
#      como GIO con un disco que conoce: usb → drive-harddisk-usb; SSD interno →
#      drive-harddisk-solidstate; de platos → drive-harddisk. Sin eso GIO no sabe de qué
#      disco es un FUSE y le pone drive-removable-media.
#   3. Instala apfs/mount.fsapfs (el de ahora pone el dueño del montaje: uid/gid) y
#      mint-macos-apfs-espacio, que mide el espacio libre al montar (statfs da 0).
#   4. Suelta los montajes fsapfs de fstab que no estén en uso, para que el
#      automount los rehaga con lo nuevo (y quita la copia de más, si hay).
# Antes de tocar nada guarda fstab, la regla y el ayudante en
# /var/backups/mint-macos/discos-<fecha>; --volver repone la última copia.
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "✗ Corre esto con sudo."; exit 1; }
AQUI="$(cd "$(dirname "$0")" && pwd)"
REGLA=/etc/udev/rules.d/99-hide-macmini-partition.rules
AYUDANTE=/sbin/mount.fsapfs
COPIAS=/var/backups/mint-macos

if [ "${1:-}" = --volver ]; then
  ULT="$(ls -d "$COPIAS"/discos-* 2>/dev/null | sort | tail -1)"
  [ -n "$ULT" ] || { echo "✗ no hay copia en $COPIAS"; exit 1; }
  install -m 644 "$ULT/fstab" /etc/fstab
  if [ -f "$ULT/regla" ]; then install -m 644 "$ULT/regla" "$REGLA"; else rm -f "$REGLA"; fi
  [ -f "$ULT/mount.fsapfs" ] && install -m 755 "$ULT/mount.fsapfs" "$AYUDANTE"
  systemctl daemon-reload
  udevadm control --reload
  udevadm trigger --subsystem-match=block --action=change
  echo "Repuesto de $ULT. Los montajes ya hechos siguen; al reiniciar quedan como antes."
  exit 0
fi

# Los discos fsapfs de fstab: UUID y punto.
mapfile -t DISCOS < <(awk '$1 ~ /^UUID=/ && $3 == "fsapfs" {sub(/^UUID=/, "", $1); print $1 " " $2}' /etc/fstab)
[ ${#DISCOS[@]} -gt 0 ] || { echo "✗ no hay discos fsapfs en /etc/fstab"; exit 1; }

D="$COPIAS/discos-$(date +%Y%m%d-%H%M%S)"
install -d -m 700 "$D"
cp -a /etc/fstab "$D/fstab"
[ -f "$REGLA" ] && cp -a "$REGLA" "$D/regla"
[ -f "$AYUDANTE" ] && cp -a "$AYUDANTE" "$D/mount.fsapfs"
echo "▸ Copia en $D"

echo "▸ udisks: el contenedor APFS crudo fuera"
touch "$REGLA"
for d in "${DISCOS[@]}"; do
  uuid="${d%% *}"
  grep -q "ENV{ID_FS_UUID}==\"$uuid\"" "$REGLA" ||
    echo "SUBSYSTEM==\"block\", ENV{ID_FS_UUID}==\"$uuid\", ENV{UDISKS_IGNORE}=\"1\"" >> "$REGLA"
  echo "  $uuid"
done
udevadm control --reload
udevadm trigger --subsystem-match=block --action=change

echo "▸ fstab: nombre e ícono según el bus"
TMP="$(mktemp)"
cp /etc/fstab "$TMP"
for d in "${DISCOS[@]}"; do
  uuid="${d%% *}"; punto="${d#* }"
  dev="$(readlink -f "/dev/disk/by-uuid/$uuid" 2>/dev/null || true)"
  tran="$( [ -n "$dev" ] && lsblk -ndo TRAN "/dev/$(lsblk -ndo PKNAME "$dev")" 2>/dev/null || true)"
  rota="$( [ -n "$dev" ] && lsblk -ndo ROTA "/dev/$(lsblk -ndo PKNAME "$dev")" 2>/dev/null | tr -d ' ' || true)"
  # Lo mismo que hace GIO con un disco que conoce: USB, SSD interno o disco de platos.
  if [ "$tran" = usb ]; then icono=drive-harddisk-usb
  elif [ "$rota" = 0 ]; then icono=drive-harddisk-solidstate
  else icono=drive-harddisk; fi
  nombre="$(basename "$punto")"
  # Sin espacios en el nombre: x-gvfs-name los pide como \040.
  nombre="${nombre// /\\040}"
  awk -v u="UUID=$uuid" -v n="$nombre" -v i="$icono" '
    $1 == u {
      m = split($4, o, ","); s = ""
      for (k = 1; k <= m; k++) if (o[k] !~ /^x-gvfs-(show|name|icon)/) s = s (s == "" ? "" : ",") o[k]
      $4 = s ",x-gvfs-show,x-gvfs-name=" n ",x-gvfs-icon=" i
    } { print }' OFS='  ' "$TMP" > "$TMP.n" && mv "$TMP.n" "$TMP"
  echo "  $punto: ${tran:-?}${rota:+, rota=$rota} → $icono"
done
# Se comprueba que fstab siga siendo válido antes de ponerlo.
findmnt --verify --tab-file "$TMP" >/dev/null 2>&1 || { echo "✗ el fstab nuevo no pasa findmnt --verify; no lo pongo"; findmnt --verify --tab-file "$TMP"; exit 1; }
install -m 644 "$TMP" /etc/fstab
rm -f "$TMP"
systemctl daemon-reload

echo "▸ El ayudante de mount(8) y el que mide el espacio libre"
install -m 755 "$AQUI/mount.fsapfs" "$AYUDANTE"
ESP="$AQUI/../rust/target/release/mint-macos-apfs-espacio"
if [ -x "$ESP" ]; then
  install -d -m 755 /usr/libexec/mint-macos
  install -m 755 -o root -g root "$ESP" /usr/libexec/mint-macos/apfs-espacio
  # Los que ya están montados no pasan otra vez por mount.fsapfs: se miden ahora.
  for d in "${DISCOS[@]}"; do
    /usr/libexec/mint-macos/apfs-espacio "/dev/disk/by-uuid/${d%% *}" --guardar >/dev/null || true
  done
  echo "  espacio libre en /run/mint-macos/apfs/"
else
  echo "  ⚠ falta compilar $ESP (cd rust && cargo build --release -p mint-macos-apfs-espacio, sin sudo)"
fi

echo "▸ Los montajes, de nuevo (solo los que nadie usa)"
for d in "${DISCOS[@]}"; do
  punto="${d#* }"
  n="$(findmnt -rn -t fuse -o TARGET | grep -cxF "$punto" || true)"
  [ "$n" -gt 0 ] || { echo "  $punto: sin montar (se monta al primer acceso)"; continue; }
  if fuser -sm "$punto" 2>/dev/null; then
    echo "  $punto: en uso, se queda como está hasta reiniciar${n:+ ($n montaje(s))}"
    continue
  fi
  for _ in $(seq "$n"); do umount "$punto" 2>/dev/null || umount -l "$punto"; done
  ls "$punto" >/dev/null 2>&1 || true          # el automount lo vuelve a montar
  echo "  $punto: rehecho ($n → $(findmnt -rn -t fuse -o TARGET | grep -cxF "$punto"))"
done
echo "Listo. Vuelta atrás: sudo $0 --volver"
