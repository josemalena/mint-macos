#!/bin/bash
# Los montajes APFS de la Mac que usan los guiones de mint-macos, como
# servicios de usuario de systemd (sin sudo): se montan al iniciar sesión, por
# UUID del contenedor (los /dev/sdX cambian entre reinicios: el 16-10-2026
# Catalina era sdb y Sequoia sde) y se rehacen solos si el FUSE muere
# (segfault de libfsapfs, 14-10-2026). Todos en solo lectura: fsapfsmount no
# escribe.
#
#   apfs/montajes-usuario.sh --instalar   crea y habilita los servicios (montan al entrar)
#   apfs/montajes-usuario.sh --ahora      además los arranca ya (desmonta antes lo montado a mano)
#   apfs/montajes-usuario.sh --estado     qué está montado y qué no
#   apfs/montajes-usuario.sh --quitar     los deshabilita y borra; desmonta
#
# El usuario tiene que estar en el grupo disk (lo pone requisitos.sh) para leer
# el contenedor sin sudo. /media/jmalena/MacMini sigue siendo el de fstab (root).
set -euo pipefail

CACHE="$HOME/.cache/mint-macos"
UNIDADES="$HOME/.config/systemd/user"
# nombre | UUID del contenedor APFS | volumen (fsapfsmount -f) | punto de montaje
MONTAJES=(
  "disco-mac|ad6302c4-5b01-4d3f-b5f7-bcf7490190b3|1|$CACHE/disco-mac"
  "disco-mac-sistema|ad6302c4-5b01-4d3f-b5f7-bcf7490190b3|5|$CACHE/disco-mac-sistema"
  "disco-sequoia|3c3da2ad-c4c8-4275-9971-70b3f2616f13|1|$CACHE/disco-sequoia"
)
FSAPFS="$(command -v fsapfsmount || echo /usr/local/bin/fsapfsmount)"

unidad() { echo "mint-macos-apfs-$1.service"; }

case "${1:-}" in
  --instalar|--ahora)
    [ -x "$FSAPFS" ] || { echo "✗ falta fsapfsmount (sudo ./requisitos.sh)"; exit 1; }
    id -nG | grep -qw disk || echo "  ojo: $USER no está en el grupo disk; los montajes van a fallar hasta que lo esté"
    mkdir -p "$UNIDADES"
    for m in "${MONTAJES[@]}"; do
      IFS='|' read -r nombre uuid vol punto <<<"$m"
      mkdir -p "$punto"
      dev="/dev/disk/by-uuid/$uuid"
      cat > "$UNIDADES/$(unidad "$nombre")" <<EOF
[Unit]
Description=Mac APFS $nombre (volumen $vol de $uuid), solo lectura (mint-macos)
# Si el disco no está todavía (USB que tarda, o desconectado) reintenta sin fin.
StartLimitIntervalSec=0

[Service]
Type=forking
# Un montaje muerto («Transport endpoint is not connected») o hecho a mano se suelta antes.
ExecStartPre=-/usr/bin/fusermount -u -z $punto
ExecStartPre=/bin/sh -c 'i=0; while [ ! -e $dev ] && [ \$i -lt 30 ]; do sleep 2; i=\$((i+1)); done; [ -e $dev ]'
ExecStart=$FSAPFS -f $vol $dev $punto
ExecStop=/usr/bin/fusermount -u -z $punto
Restart=always
RestartSec=20

[Install]
WantedBy=default.target
EOF
      echo "  $(unidad "$nombre"): $punto ← volumen $vol de $uuid"
    done
    systemctl --user daemon-reload
    for m in "${MONTAJES[@]}"; do systemctl --user enable "$(unidad "${m%%|*}")" >/dev/null 2>&1; done
    if [ "$1" = --ahora ]; then
      for m in "${MONTAJES[@]}"; do systemctl --user restart "$(unidad "${m%%|*}")" || true; done
      sleep 3; "$0" --estado
    else
      echo "  habilitados: montan al iniciar sesión (o ya: $0 --ahora)"
    fi ;;
  --estado)
    for m in "${MONTAJES[@]}"; do
      IFS='|' read -r nombre uuid vol punto <<<"$m"
      real="$(readlink -f "$punto")"   # ~/.cache/mint-macos puede ser un enlace: /proc/mounts trae la ruta real
      if grep -q " $real fuse" /proc/mounts && timeout 5 ls "$punto" >/dev/null 2>&1; then e="montado"
      elif [ -e "/dev/disk/by-uuid/$uuid" ]; then e="NO montado (el disco está)"
      else e="NO montado (disco ausente)"; fi
      printf '  %-18s %-28s %s\n' "$nombre" "$e" "$(systemctl --user is-active "$(unidad "$nombre")" 2>/dev/null)"
    done ;;
  --quitar)
    for m in "${MONTAJES[@]}"; do
      u="$(unidad "${m%%|*}")"
      systemctl --user disable --now "$u" 2>/dev/null || true
      rm -f "$UNIDADES/$u"
    done
    systemctl --user daemon-reload
    echo "  quitados (los puntos de montaje vacíos se quedan)" ;;
  *) sed -n '2,16p' "$0"; exit 2 ;;
esac
