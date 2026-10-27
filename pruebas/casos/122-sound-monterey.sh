# caso: Sound con el perfil de Monterey: las alertas con sus nombres de Monterey y en orden (Boop, Breeze, Bubble…), y «Play sound on startup»; con Catalina, los nombres de archivo
# límite: 120
# (INFORME-B de trabajo-samana-20261026/preferencias: los 14 sonidos de alerta cambian de nombre en Monterey)
volcar() {
  mkdir -p "$XDG_RUNTIME_DIR/mint-macos"
  printf '{"version":"%s"}' "$1" > "$XDG_RUNTIME_DIR/mint-macos/macos.json"
  lanzar mac-preferencias com.apple.preference.sound
  local v pid; v="$(esperar_ventana '[Mm]ac-settings' 40)"
  pid="$(xdotool getwindowpid "$v")"
  esperar_texto "$v" "Sound Effects" 30
  python3 "$(dirname "$PRUEBAS_LIB")/atspi.py" --pid "$pid" --texto "Sound Effects" --pulsar > /dev/null 2>&1 || true
  sleep 2
  VOLCADO="$(python3 "$(dirname "$PRUEBAS_LIB")/atspi.py" --pid "$pid" --volcar 2>&1)"
  captura "sound-$1"
  for p in $(pgrep -x mac-preferenci); do grep -qz "^HOME=$HOME\$" "/proc/$p/environ" 2>/dev/null && kill "$p"; done
  sleep 2
}
prueba() {
  requiere mac-preferencias xdotool python3
  export MP_PYTHON_DIR="$MINT_MACOS_REPO/settings"
  local d="$HOME/.local/share/mint-macos/settings/sonidos" n
  mkdir -p "$d"
  for n in Basso Blow Bottle Frog Funk Glass Hero Morse Ping Pop Purr Sosumi Submarine Tink; do : > "$d/$n.wav"; done
  volcar monterey-12.7.6
  local nuevo
  for nuevo in Boop Breeze Bubble Crystal Funky Heroine Jump Mezzo Pebble Pluck Pong Sonar Sonumi Submerge; do
    case "$VOLCADO" in *"$nuevo"*) ;; *) falla "Monterey: falta la alerta «$nuevo»" ;; esac
  done
  case "$VOLCADO" in *"Tink"*|*"Basso"*) falla "Monterey: quedó un nombre de Catalina (Tink o Basso)" ;; esac
  case "$VOLCADO" in *"Play sound on startup"*) ;; *) falla "Monterey: falta «Play sound on startup»" ;; esac
  paso "Monterey: alertas con sus nombres y «Play sound on startup»"
  volcar catalina-10.15
  case "$VOLCADO" in *"Tink"*) ;; *) falla "Catalina: falta «Tink»" ;; esac
  case "$VOLCADO" in *"Boop"*|*"Play sound on startup"*) falla "Catalina: salió algo de Monterey" ;; esac
  paso "Catalina: como estaba"
  true
}
