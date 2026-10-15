#!/bin/sh
# Lo corre fsapfs-vigilar.timer (root) cada minuto. Si el proceso FUSE de un
# montaje APFS murió (segfault de libfsapfs, 14-10-2026), el punto queda en
# «Transport endpoint is not connected» y systemd lo sigue viendo montado.
# Aquí se desmonta en perezoso; el automount de fstab lo vuelve a montar en
# el próximo acceso. Un montaje sano o desmontado no se toca. Si el FUSE
# está colgado en vez de muerto, el stat se quedaría esperando para siempre:
# va con timeout (y SIGKILL a los 2 s más, que FUSE sí atiende), y el
# servicio tiene su propio tope para que el timer siga corriendo.
#
#   instalar:  sudo apfs/vigilar.sh --instalar
#   quitar:    sudo apfs/vigilar.sh --quitar
set -eu
case "${1:-}" in
  --instalar)
    AQUI="$(cd "$(dirname "$0")" && pwd)"
    install -m 755 "$AQUI/vigilar.sh" /usr/local/sbin/fsapfs-vigilar
    cat > /etc/systemd/system/fsapfs-vigilar.service <<'U'
[Unit]
Description=Rehace los montajes APFS cuyo proceso FUSE murió (mint-macos)

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/fsapfs-vigilar
TimeoutStartSec=45
U
    cat > /etc/systemd/system/fsapfs-vigilar.timer <<'U'
[Unit]
Description=Revisa cada minuto los montajes APFS (mint-macos)

[Timer]
OnBootSec=2min
OnUnitActiveSec=1min

[Install]
WantedBy=timers.target
U
    systemctl daemon-reload
    systemctl enable --now fsapfs-vigilar.timer
    echo "listo: fsapfs-vigilar.timer activo"; exit 0 ;;
  --quitar)
    systemctl disable --now fsapfs-vigilar.timer 2>/dev/null || true
    rm -f /etc/systemd/system/fsapfs-vigilar.service /etc/systemd/system/fsapfs-vigilar.timer /usr/local/sbin/fsapfs-vigilar
    systemctl daemon-reload
    echo "quitado"; exit 0 ;;
esac
# Los montajes de fstab con tipo fsapfs; en /proc/mounts salen como «fuse».
awk '$3 == "fsapfs" && $1 !~ /^#/ {print $2}' /etc/fstab | while read -r p; do
  grep -q " $p fuse " /proc/mounts || continue
  r=0; timeout -k 2 5 stat -t "$p" >/dev/null 2>&1 || r=$?
  [ "$r" = 0 ] && continue
  # 124/137: colgado; cualquier otro (ENOTCONN): muerto.
  [ "$r" = 124 ] || [ "$r" = 137 ] && motivo="colgado" || motivo="muerto"
  umount -l "$p" && logger -t fsapfs-vigilar "$p no respondía (FUSE $motivo): desmontado; el automount lo rehace"
done
