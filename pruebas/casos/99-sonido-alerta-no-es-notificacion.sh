# caso: escoger una alerta en Sound Effects la vuelve el sonido del aviso del sistema (bell-window-system de un tema propio) y NO toca los
# sonidos de las notificaciones (org.cinnamon.sounds notification-file / notification-enabled)
# límite: 120
prueba() {
  requiere mac-preferencias xdotool python3 gsettings
  export MP_PYTHON_DIR="$MINT_MACOS_REPO/settings"
  # Una alerta de prueba (un WAV de un segundo de silencio) en la carpeta de sonidos de las apps del sandbox
  local sonidos="$HOME/.local/share/mint-macos/settings/sonidos"   # (el panel la busca bajo HOME, no bajo XDG_DATA_HOME)
  mkdir -p "$sonidos"
  python3 - "$sonidos/Prueba.wav" <<'PY'
import sys, wave
w = wave.open(sys.argv[1], "wb"); w.setnchannels(1); w.setsampwidth(2); w.setframerate(8000); w.writeframes(b"\0\0" * 8000); w.close()
PY
  gsettings set org.cinnamon.sounds notification-enabled false
  local antes_arch antes_act; antes_arch="$(gsettings get org.cinnamon.sounds notification-file)"; antes_act="$(gsettings get org.cinnamon.sounds notification-enabled)"
  lanzar mac-preferencias com.apple.preference.sound
  local v; v="$(esperar_ventana '[Mm]ac-settings' 40)"
  esperar_texto "$v" "Sound Effects" 20
  # Pestaña Sound Effects, y la alerta Prueba
  python3 "$(dirname "$PRUEBAS_LIB")/atspi.py" --pid "$(xdotool getwindowpid "$v")" --texto "Sound Effects" --rol "radio button" --pulsar --segundos 10 >&2 || falla "no pude abrir Sound Effects"
  esperar_texto "$v" "Prueba" 20
  python3 "$(dirname "$PRUEBAS_LIB")/atspi.py" --pid "$(xdotool getwindowpid "$v")" --texto "Prueba" --clic --segundos 10 >&2 || falla "no pude escoger la alerta Prueba"
  sleep 3
  local tema="$XDG_DATA_HOME/sounds/mint-macos"
  [ -f "$tema/index.theme" ] || falla "no se escribió el tema de sonido ($tema/index.theme)"
  [ -s "$tema/stereo/bell-window-system.wav" ] || falla "la alerta no quedó como bell-window-system.wav"
  paso "la alerta es el evento bell-window-system del tema mint-macos"
  [ "$(gsettings get org.cinnamon.sounds notification-enabled)" = "$antes_act" ] || falla "se tocó notification-enabled"
  [ "$(gsettings get org.cinnamon.sounds notification-file)" = "$antes_arch" ] || falla "se tocó notification-file"
  paso "los sonidos de las notificaciones quedaron como estaban"
}
