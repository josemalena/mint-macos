#!/usr/bin/env bash
# Bloquear con la pantalla de inicio de Catalina (slick-greeter-mac), como la
# Mac: una sola pantalla para entrar y para desbloquear (José, 10-10-2026).
# Sin sudo; es de la sesión del usuario.
#
#   ./bloqueo.sh             bloquear con LightDM (dm-tool lock)
#   ./bloqueo.sh --en-sesion bloquear dentro de la sesión con mac-bloqueo, como loginwindow
#                            (José, 19-10-2026; nativo/bloqueo/LEEME.md). Vuelta atrás: ./bloqueo.sh
#   ./bloqueo.sh --deshacer  volver al bloqueo de Cinnamon
#
# Con --en-sesion, ⌃⌘Q, «Lock Screen», la esquina activa y la suspensión van por el mismo
# custom-screensaver-command (cinnamon-screensaver-command --lock lo corre), pero apuntando a
# ~/.local/bin/mac-bloqueo; la inactividad, por xss-lock -- mac-bloqueo; y el servicio de usuario
# mac-bloqueo-vigilante (mac-bloqueo --vigilar, Restart=always) relanza la pantalla si alguien la mata
# mientras el estado dice «bloqueado». LightDM queda solo para entrar al encender y tras Log Out.
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
BLOQUEAR="$HOME/.local/bin/mint-macos-bloquear"   # copia de login/bloquear.sh
AUTOSTART="$HOME/.config/autostart/mint-macos-bloqueo.desktop"
MAC_BLOQUEO="$HOME/.local/bin/mac-bloqueo"
VIGILANTE="$HOME/.config/systemd/user/mac-bloqueo-vigilante.service"
mkdir -p "$RESPALDO" "$(dirname "$AUTOSTART")"

quitar_vigilante() {
  if [ -f "$VIGILANTE" ]; then
    systemctl --user disable --now mac-bloqueo-vigilante.service >/dev/null 2>&1 || true
    rm -f "$VIGILANTE"; systemctl --user daemon-reload || true
    echo "  vigilante de mac-bloqueo quitado"
  fi
}

parar_xss_lock() {
  local p
  p="$(pgrep -u "$USER" -x xss-lock || true)"
  [ -n "$p" ] && kill $p || true
}

if [ "${1:-}" = "--deshacer" ]; then
  ANTES="$(cat "$RESPALDO/custom-screensaver-command.txt" 2>/dev/null || echo "''")"
  gsettings set org.cinnamon.desktop.screensaver custom-screensaver-command "$ANTES"
  rm -f "$AUTOSTART" "$BLOQUEAR"
  parar_xss_lock
  quitar_vigilante
  xset s 0 0
  # El demonio de Cinnamon vuelve con el próximo bloqueo; se arranca ya para
  # que el bloqueo por inactividad no quede sin nadie.
  (setsid cinnamon-screensaver >/dev/null 2>&1 &)
  echo "  listo: el bloqueo vuelve a ser el de Cinnamon"
  exit 0
fi

EN_SESION=false; [ "${1:-}" = "--en-sesion" ] && EN_SESION=true
command -v xss-lock >/dev/null || { echo "  ✗ falta xss-lock: sudo login/instalar.sh lo instala"; exit 1; }
if [ ! -f "$RESPALDO/custom-screensaver-command.txt" ]; then
  gsettings get org.cinnamon.desktop.screensaver custom-screensaver-command > "$RESPALDO/custom-screensaver-command.txt"
fi
ESPERA="$(gsettings get org.cinnamon.desktop.session idle-delay | awk '{print $NF}')"

if $EN_SESION; then
  [ -x "$MAC_BLOQUEO" ] || { echo "  ✗ falta $MAC_BLOQUEO (nativo/instalar.sh lo compila)"; exit 1; }
  gsettings set org.cinnamon.desktop.screensaver custom-screensaver-command "$MAC_BLOQUEO"
  rm -f "$BLOQUEAR"
  echo "  ⌃⌘Q, Lock Screen, la esquina y la suspensión: $MAC_BLOQUEO (dentro de la sesión)"
  mkdir -p "$(dirname "$VIGILANTE")"
  cat > "$VIGILANTE" <<EOF
[Unit]
Description=mint-macos: relanza la pantalla de bloqueo si cae mientras la sesión está bloqueada
PartOf=graphical-session.target
After=graphical-session.target

[Service]
ExecStart=$MAC_BLOQUEO --vigilar
Restart=always
RestartSec=1

[Install]
WantedBy=graphical-session.target
EOF
  systemctl --user daemon-reload
  systemctl --user enable --now mac-bloqueo-vigilante.service >/dev/null 2>&1 \
    && echo "  vigilante: mac-bloqueo-vigilante.service (Restart=always)" \
    || echo "  ⚠ no se pudo arrancar mac-bloqueo-vigilante.service (systemctl --user status mac-bloqueo-vigilante)"
  cat > "$AUTOSTART" <<EOF
[Desktop Entry]
Type=Application
Name=Bloqueo de Catalina (mint-macos)
Comment=Bloquea dentro de la sesión (mac-bloqueo) por inactividad
Exec=sh -c 'xset s $ESPERA $ESPERA; exec xss-lock --ignore-sleep -- $MAC_BLOQUEO'
X-GNOME-Autostart-enabled=true
NoDisplay=true
EOF
  parar_xss_lock
  if [ "$ESPERA" -gt 0 ]; then
    xset s "$ESPERA" "$ESPERA"
    (setsid xss-lock --ignore-sleep -- "$MAC_BLOQUEO" >/dev/null 2>&1 &)
    echo "  inactividad: xss-lock -- mac-bloqueo a los $ESPERA s (idle-delay de Cinnamon)"
  else
    echo "  inactividad: Cinnamon la tiene apagada (idle-delay 0), no se bloquea por tiempo"
  fi
  P="$(pgrep -u "$USER" -f 'cinnamon-screensaver-main\.py' || true)"
  if [ -n "$P" ]; then kill $P || true; fi
  echo "  Salida de emergencia (otra consola o ssh): XDG_RUNTIME_DIR=/run/user/\$(id -u) $MAC_BLOQUEO --liberar"
  echo "  Para volver a LightDM: $0"
  exit 0
fi

quitar_vigilante
command -v dm-tool >/dev/null || { echo "  ✗ falta dm-tool (paquete lightdm)"; exit 1; }
[ -n "${XDG_SEAT_PATH:-}" ] || { echo "  ✗ esta sesión no la abrió LightDM (sin XDG_SEAT_PATH): dm-tool lock no serviría"; exit 1; }

# Los dos caminos pasan por bloquear.sh: dm-tool lock suelto se repite solo
# (LightDM → logind Lock → xss-lock → otro dm-tool lock; ver bloquear.sh).
install -Dm755 "$(dirname "$0")/bloquear.sh" "$BLOQUEAR"
gsettings set org.cinnamon.desktop.screensaver custom-screensaver-command "$BLOQUEAR"
echo "  ⌃⌘Q, Lock Screen y la suspensión: $BLOQUEAR (dm-tool lock, uno a la vez)"

# Inactividad: xss-lock con el tiempo de Cinnamon (idle-delay, en segundos).
cat > "$AUTOSTART" <<EOF
[Desktop Entry]
Type=Application
Name=Bloqueo de Catalina (mint-macos)
Comment=Bloquea con la pantalla de inicio (dm-tool lock) por inactividad
Exec=sh -c 'xset s $ESPERA $ESPERA; exec xss-lock --ignore-sleep -- $BLOQUEAR'
X-GNOME-Autostart-enabled=true
NoDisplay=true
EOF
parar_xss_lock
if [ "$ESPERA" -gt 0 ]; then
  xset s "$ESPERA" "$ESPERA"
  (setsid xss-lock --ignore-sleep -- "$BLOQUEAR" >/dev/null 2>&1 &)
  echo "  inactividad: xss-lock a los $ESPERA s (idle-delay de Cinnamon)"
else
  echo "  inactividad: Cinnamon la tiene apagada (idle-delay 0), no se bloquea por tiempo"
fi

# Sin pantalla doble: el demonio de cinnamon-screensaver se va.
# Por la línea de comandos: «pgrep -x cinnamon-screensaver» (20 caracteres) nunca coincide, el nombre se trunca a 15.
# El demonio es el script que lanza /usr/bin/cinnamon-screensaver.
P="$(pgrep -u "$USER" -f 'cinnamon-screensaver-main\.py' || true)"
if [ -n "$P" ]; then kill $P || true; fi
echo "  cinnamon-screensaver cerrado (no vuelve mientras haya comando propio)"
echo "  Para volver: $0 --deshacer"
