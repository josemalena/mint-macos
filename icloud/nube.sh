#!/usr/bin/env bash
# Otra nube (Google Drive, OneDrive o cualquier remoto de rclone) montada como
# carpeta, igual que iCloud Drive: mismo envoltorio de rclone (la clave de
# rclone.conf sale del llavero), caché completa y socket --rc para Fynder.
# Sin sudo. El remoto lo da de alta el usuario con «rclone config»; este guion
# no ve ni guarda nada de la cuenta.
#
#   ./nube.sh montar REMOTO "CARPETA" [SERVICIO]   p. ej. GDrive "$HOME/Google Drive"
#                                                  o OneDrive "$HOME/OneDrive"
#   ./nube.sh quitar REMOTO [SERVICIO]             la vuelta atrás: para y borra el servicio
#   ./nube.sh estado [REMOTO]                      qué remotos hay y qué servicios corren
#
# SERVICIO por omisión: rclone-<remoto en minúsculas> (GDrive → rclone-gdrive).
# Solo monta si el remoto existe en el rclone.conf del usuario; si no, no hace nada.
# Requiere el envoltorio de ./icloud.sh instalar (~/.local/bin/rclone).
#
# Variables para probar: NUBE_UNIDADES (~/.config/systemd/user), NUBE_SIN_SYSTEMCTL=1.
set -euo pipefail

BIN="$HOME/.local/bin/rclone"
UNIDADES="${NUBE_UNIDADES:-$HOME/.config/systemd/user}"
CACHE_MAX="${NUBE_CACHE_MAX:-10G}"
paso() { printf '\n▸ %s\n' "$*"; }
ctl() { [ -n "${NUBE_SIN_SYSTEMCTL:-}" ] && { echo "  (systemctl --user $*)"; return 0; }; systemctl --user "$@"; }

servicio_de() { echo "${2:-rclone-$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9-' '-')}"; }
hay_remoto() { "$BIN" listremotes 2>/dev/null | grep -qx "$1:"; }

montar() {
  local remoto="${1:?falta REMOTO}" carpeta="${2:?falta CARPETA}" servicio; servicio="$(servicio_de "$1" "${3:-}")"
  case "$carpeta" in /*) ;; *) echo "✗ CARPETA tiene que ser una ruta absoluta"; exit 1 ;; esac
  [ -x "$BIN" ] || { echo "✗ falta el rclone de mint-macos: corre antes ./icloud.sh instalar"; exit 1; }
  if ! hay_remoto "$remoto"; then
    echo "  no hay remoto «$remoto» en rclone.conf: no se monta nada (dalo de alta con «rclone config»)"
    return 0
  fi
  paso "$remoto en $carpeta ($servicio)"
  mkdir -p "$UNIDADES"
  # La misma unidad que la de iCloud (icloud.sh, unidad_montaje): ver allí el porqué de cada opción.
  cat > "$UNIDADES/$servicio.service" <<EOF
[Unit]
Description=$remoto montado en $carpeta (rclone, mint-macos)
After=network-online.target

[Service]
Type=notify
${RCLONE_CONFIG:+Environment=RCLONE_CONFIG=$RCLONE_CONFIG}
# rclone.conf va cifrado: la clave la da el envoltorio desde el llavero; si el
# llavero sigue cerrado, el montaje reintenta, nunca pregunta.
Environment=RCLONE_ASK_PASSWORD=false
ExecStartPre=-/bin/rm -f %t/$servicio.sock
ExecStartPre=/bin/mkdir -p "$carpeta"
ExecStart=$BIN mount "$remoto:" "$carpeta" --vfs-cache-mode full --vfs-cache-max-size $CACHE_MAX --cache-dir "%h/.cache/rclone/$servicio" --dir-cache-time 1h --rc --rc-addr "unix://%t/$servicio.sock" --rc-no-auth
ExecStop=/bin/fusermount -uz "$carpeta"
Restart=on-failure
RestartSec=30

[Install]
WantedBy=default.target
EOF
  ctl daemon-reload
  ctl enable --now "$servicio.service"
  # enable --now no reinicia una unidad que ya corre: una regenerada seguiría con las opciones viejas.
  ctl restart "$servicio.service"
  echo "  listo: $UNIDADES/$servicio.service (vuelta atrás: $0 quitar $remoto${3:+ $3})"
}

quitar() {
  local remoto="${1:?falta REMOTO}" servicio; servicio="$(servicio_de "$1" "${2:-}")"
  paso "Quitando $servicio"
  local u="$UNIDADES/$servicio.service"
  if [ ! -f "$u" ]; then echo "  no está $u: nada que quitar"; return 0; fi
  grep -q '(rclone, mint-macos)' "$u" || { echo "  ✗ $u no lo hizo mint-macos: no se toca"; exit 1; }
  local carpeta; carpeta="$(sed -n 's/^ExecStop=\/bin\/fusermount -uz "\(.*\)"$/\1/p' "$u")"
  ctl disable --now "$servicio.service" || true
  rm -f "$u"
  ctl daemon-reload
  # La carpeta solo se quita si quedó vacía (desmontada no tiene nada).
  [ -n "$carpeta" ] && rmdir -- "$carpeta" 2>/dev/null && echo "  quitada la carpeta vacía $carpeta"
  echo "  listo. Quedan: el remoto en rclone.conf («rclone config delete $remoto» lo borra) y la caché en ~/.cache/rclone/$servicio."
}

estado() {
  echo "remotos: $("$BIN" listremotes 2>/dev/null | tr '\n' ' ')"
  for u in "$UNIDADES"/rclone-*.service; do
    [ -f "$u" ] && grep -q '(rclone, mint-macos)' "$u" || continue
    local n; n="$(basename "$u" .service)"
    { [ -z "${1:-}" ] || [ "$n" = "$(servicio_de "$1")" ]; } || continue
    echo "  $n: $(systemctl --user is-active "$n.service" 2>/dev/null || true)"
  done
}

case "${1:-}" in
  montar) shift; montar "$@" ;;
  quitar) shift; quitar "$@" ;;
  estado) shift; estado "$@" ;;
  *) sed -n '2,17p' "$0"; exit 2 ;;
esac
