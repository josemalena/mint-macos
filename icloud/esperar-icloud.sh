#!/usr/bin/env bash
# Arranca un programa (el escritorio de Fynder) solo cuando iCloud Drive ya
# está montado, si ~/Desktop vive ahí. Mientras espera, el cursor es la
# ruedita de espera y sale un aviso «Conectando con iCloud…», como al entrar
# a una Mac. Si en 3 minutos no monta, arranca igual y lo dice.
#
#   esperar-icloud.sh <programa> [argumentos…]
#
# Por qué: el montaje de rclone tarda cerca de un minuto en iniciar sesión
# (autenticarse y leer el árbol). Si el escritorio arranca antes, encuentra
# ~/Desktop vacío y no se refresca solo (13-10-2026).
set -u
CARPETA="${ICLOUD_CARPETA:-$HOME/iCloud Drive}"
LIMITE="${ICLOUD_ESPERA:-180}"

listo() { findmnt -no FSTYPE "$CARPETA" 2>/dev/null | grep -q fuse && [ -e "$HOME/Desktop/." ]; }

# Solo espera si el escritorio está dentro de iCloud.
case "$(readlink -f "$HOME/Desktop" 2>/dev/null)" in
  "$CARPETA"/*) ;;
  *) exec "$@" ;;
esac
listo && exec "$@"

xsetroot -cursor_name watch 2>/dev/null || true
aviso=$(notify-send --print-id -i content-loading-symbolic -u low -t 0 \
  "Conectando con iCloud…" "El escritorio aparece cuando iCloud Drive termine de montar." 2>/dev/null || true)

inicio=$(date +%s)
while ! listo && [ $(( $(date +%s) - inicio )) -lt "$LIMITE" ]; do
  sleep 1
done

xsetroot -cursor_name left_ptr 2>/dev/null || true
if [ -n "$aviso" ]; then
  gdbus call --session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications \
    --method org.freedesktop.Notifications.CloseNotification "$aviso" >/dev/null 2>&1 || true
fi
listo || notify-send -i dialog-warning "iCloud Drive no montó" \
  "Pasaron $LIMITE s. El escritorio arranca igual; mira «icloud.sh estado»." 2>/dev/null || true
exec "$@"
