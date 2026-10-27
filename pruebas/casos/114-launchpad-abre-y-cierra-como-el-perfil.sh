# caso: el Launchpad abre en 250 ms (easeIn, de escala 1.05 a 1.00) y cierra en 217 ms (easeOut) con el perfil de Monterey; sin perfil, como antes (0.18 s al abrir, sin animar el cierre)
# límite: 150
# Xvfb con llvmpipe pinta a pocos cuadros por segundo: una grabación no mide el tiempo. Se lee el registro de la propia ventana (LAUNCHPAD_DEBUG=1):
# cada cuadro anota su tiempo, alfa y escala, y se comparan con la curva del perfil calculada aparte (ayudantes/comprobar-launchpad-anim.py).
ciclo() {   # ciclo ETIQUETA: arranca el residente y lo abre y lo cierra; deja el registro en $LOG
  export LAUNCHPAD_DEBUG=1
  LOG="$PRUEBAS_RES/$PRUEBAS_CASO-$1.log"
  setsid mac-launchpad-vala --residente > "$LOG" 2>&1 < /dev/null &
  sleep 8
  mac-launchpad-vala; sleep 2    # abre
  mac-launchpad-vala; sleep 2    # cierra
  for p in $(pgrep -x mac-launchpad-v); do grep -qz "^HOME=$HOME\$" "/proc/$p/environ" 2>/dev/null && kill "$p"; done
  sleep 1
}
prueba() {
  requiere mac-launchpad-vala ffmpeg
  AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  mkdir -p "$XDG_CONFIG_HOME/mint-macos" "$XDG_DATA_HOME/mint-macos/macos/monterey-12.7.6/apps"
  echo '{"version": "monterey-12.7.6"}' > "$XDG_CONFIG_HOME/mint-macos/macos.json"
  cp "$AQUI/../perfiles/monterey-12.7.6/animaciones.json" "$XDG_DATA_HOME/mint-macos/macos/monterey-12.7.6/apps/"
  ciclo con-perfil
  python3 -I "$AQUI/ayudantes/comprobar-launchpad-anim.py" "$LOG" abrir 250 easeIn 1.05 || falla "al abrir no sigue la curva del perfil"
  python3 -I "$AQUI/ayudantes/comprobar-launchpad-anim.py" "$LOG" cerrar 217 easeOut 1.05 || falla "al cerrar no sigue la curva del perfil"
  # sin perfil: como antes (sin escala, sin animar el cierre)
  rm -f "$XDG_CONFIG_HOME/mint-macos/macos.json"; rm -rf "$XDG_DATA_HOME/mint-macos/macos"
  ciclo sin-perfil
  grep -q '^\[launchpad [0-9.]*\] \(abrir\|cerrar\) t=' "$LOG" && falla "sin perfil hubo animación de abrir o cerrar"
  true
}
