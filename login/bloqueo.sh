#!/usr/bin/env bash
# Bloquear con la pantalla de inicio de Catalina (slick-greeter-mac), como la
# Mac: una sola pantalla para entrar y para desbloquear (José, 10-10-2026).
# Sin sudo; es de la sesión del usuario.
#
#   ./bloqueo.sh             bloquear con LightDM
#   ./bloqueo.sh --deshacer  volver al bloqueo de Cinnamon
#
# Cómo queda cada camino:
#   ⌃⌘Q, «Lock Screen» del menú Apple y el bloqueo antes de suspender
#       Cinnamon los manda a cinnamon-screensaver-command --lock, que con
#       custom-screensaver-command corre ese comando en vez de su pantalla:
#       aquí, dm-tool lock (LightDM cambia al greeter y vuelve a la sesión
#       al poner la clave).
#   Inactividad
#       la hacía el demonio de cinnamon-screensaver, que con un comando
#       propio ya no arranca. La toma xss-lock (lo instala login/instalar.sh)
#       con el mismo tiempo que Cinnamon (idle-delay). --ignore-sleep: la
#       suspensión ya la bloquea Cinnamon y dos dm-tool lock seguidos sobran.
#   Pantalla doble
#       el demonio de cinnamon-screensaver se cierra y no vuelve a arrancar
#       mientras haya comando propio.
set -euo pipefail

RESPALDO="$HOME/.local/share/mint-macos/respaldos"
AUTOSTART="$HOME/.config/autostart/mint-macos-bloqueo.desktop"
mkdir -p "$RESPALDO" "$(dirname "$AUTOSTART")"

parar_xss_lock() {
  local p
  p="$(pgrep -u "$USER" -x xss-lock || true)"
  [ -n "$p" ] && kill $p || true
}

if [ "${1:-}" = "--deshacer" ]; then
  ANTES="$(cat "$RESPALDO/custom-screensaver-command.txt" 2>/dev/null || echo "''")"
  gsettings set org.cinnamon.desktop.screensaver custom-screensaver-command "$ANTES"
  rm -f "$AUTOSTART"
  parar_xss_lock
  xset s 0 0
  # El demonio de Cinnamon vuelve con el próximo bloqueo; se arranca ya para
  # que el bloqueo por inactividad no quede sin nadie.
  (setsid cinnamon-screensaver >/dev/null 2>&1 &)
  echo "  listo: el bloqueo vuelve a ser el de Cinnamon"
  exit 0
fi

command -v dm-tool >/dev/null || { echo "  ✗ falta dm-tool (paquete lightdm)"; exit 1; }
command -v xss-lock >/dev/null || { echo "  ✗ falta xss-lock: sudo login/instalar.sh lo instala"; exit 1; }
[ -n "${XDG_SEAT_PATH:-}" ] || { echo "  ✗ esta sesión no la abrió LightDM (sin XDG_SEAT_PATH): dm-tool lock no serviría"; exit 1; }

# Respaldo del valor de antes, solo la primera vez (si no, el respaldo
# guardaría el nuestro).
if [ ! -f "$RESPALDO/custom-screensaver-command.txt" ]; then
  gsettings get org.cinnamon.desktop.screensaver custom-screensaver-command > "$RESPALDO/custom-screensaver-command.txt"
fi
gsettings set org.cinnamon.desktop.screensaver custom-screensaver-command 'dm-tool lock'
echo "  ⌃⌘Q, Lock Screen y la suspensión: dm-tool lock"

# Inactividad: xss-lock con el tiempo de Cinnamon (idle-delay, en segundos).
ESPERA="$(gsettings get org.cinnamon.desktop.session idle-delay | awk '{print $NF}')"
cat > "$AUTOSTART" <<EOF
[Desktop Entry]
Type=Application
Name=Bloqueo de Catalina (mint-macos)
Comment=Bloquea con la pantalla de inicio (dm-tool lock) por inactividad
Exec=sh -c 'xset s $ESPERA $ESPERA; exec xss-lock --ignore-sleep -- dm-tool lock'
X-GNOME-Autostart-enabled=true
NoDisplay=true
EOF
parar_xss_lock
if [ "$ESPERA" -gt 0 ]; then
  xset s "$ESPERA" "$ESPERA"
  (setsid xss-lock --ignore-sleep -- dm-tool lock >/dev/null 2>&1 &)
  echo "  inactividad: xss-lock a los $ESPERA s (idle-delay de Cinnamon)"
else
  echo "  inactividad: Cinnamon la tiene apagada (idle-delay 0), no se bloquea por tiempo"
fi

# Sin pantalla doble: el demonio de cinnamon-screensaver se va.
P="$(pgrep -u "$USER" -x cinnamon-screensaver || true)"
if [ -n "$P" ]; then kill $P || true; fi
echo "  cinnamon-screensaver cerrado (no vuelve mientras haya comando propio)"
echo "  Para volver: $0 --deshacer"
