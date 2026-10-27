# caso: Dock & Menu Bar con el perfil de Monterey trae la barra lateral (Control Center, Other Modules, Menu Bar Only), «Show in Menu Bar» pone o quita el applet de la barra, y Date & Time ya no tiene la pestaña Clock
# límite: 150
matar_preferencias() {
  local p vivo i
  for i in $(seq 40); do
    vivo=false
    for p in $(pgrep -x mac-preferencia); do
      if grep -qz "^HOME=$HOME\$" "/proc/$p/environ" 2>/dev/null; then vivo=true; kill $([ "$i" -gt 12 ] && echo -KILL) "$p" 2>/dev/null; fi
    done
    $vivo || break; sleep 0.25
  done
  sleep 1
}
abrir() {   # abrir VERSION PANEL TEXTO_QUE_ESPERAR: deja $PID y $VENTANA
  mkdir -p "$XDG_RUNTIME_DIR/mint-macos"
  printf '{"version":"%s"}' "$1" > "$XDG_RUNTIME_DIR/mint-macos/macos.json"
  lanzar mac-preferencias "$2"
  VENTANA="$(esperar_ventana '[Mm]ac-settings' 40)"
  PID="$(xdotool getwindowpid "$VENTANA")"
  esperar_texto "$VENTANA" "$3" 30
}
prueba() {
  requiere mac-preferencias xdotool python3 gsettings
  export MP_PYTHON_DIR="$MINT_MACOS_REPO/settings"
  local esq; esq="$(dirname "$(command -v mac-preferencias)")/../esquemas"
  [ -d "$esq" ] && export GSETTINGS_SCHEMA_DIR="$esq"
  trap "gsettings reset org.cinnamon enabled-applets" EXIT
  gsettings set org.cinnamon enabled-applets "['panel1:left:1:applemenu@macos:24', 'panel1:right:8:network@cinnamon.org:26', 'panel1:right:9:sound@cinnamon.org:11']"
  local volcado atspi; atspi="$(dirname "$PRUEBAS_LIB")/atspi.py"
  abrir monterey-12.7.6 com.apple.preference.dock "Control Center"
  volcado="$(python3 "$atspi" --pid "$PID" --volcar 2>&1)"
  for t in "Wi-Fi" "Bluetooth" "Other Modules" "Menu Bar Only" "Clock" "Fast User Switching"; do
    case "$volcado" in *"$t"*) ;; *) falla "Monterey: falta «$t» en la barra lateral" ;; esac
  done
  paso "Monterey: la barra lateral con sus tres secciones"; captura barra-lateral
  # Wi-Fi: la casilla «Show in Menu Bar» quita su applet de la barra (network@cinnamon.org) y no toca los otros
  python3 "$atspi" --pid "$PID" --texto "Wi-Fi" --clic --segundos 10 > /dev/null 2>&1 || falla "no pude escoger «Wi-Fi» en la barra lateral"
  python3 "$atspi" --pid "$PID" --texto "Show in Menu Bar" --segundos 10 > /dev/null 2>&1 || falla "no salió «Show in Menu Bar» en la página de Wi-Fi"
  python3 "$atspi" --pid "$PID" --texto "Show in Menu Bar" --pulsar --segundos 10 > /dev/null 2>&1 || falla "no pude apagar «Show in Menu Bar»"
  sleep 1
  local lista; lista="$(gsettings get org.cinnamon enabled-applets)"
  paso "enabled-applets tras apagar Wi-Fi: $lista"
  case "$lista" in *network@cinnamon.org*) falla "Wi-Fi sigue en la barra" ;; esac
  case "$lista" in *sound@cinnamon.org*applemenu*|*applemenu@macos*sound@cinnamon.org*) ;; *) falla "se perdió otro applet (Sound o el menú Apple): $lista" ;; esac
  matar_preferencias
  # Date & Time sin la pestaña Clock en Monterey, con ella en Catalina
  abrir monterey-12.7.6 com.apple.preference.datetime "Time Zone"
  volcado="$(python3 "$atspi" --pid "$PID" --volcar 2>&1)"
  case "$volcado" in *"Clock"*) falla "Monterey: Date & Time conserva la pestaña Clock" ;; esac
  matar_preferencias
  abrir catalina-10.15 com.apple.preference.datetime "Time Zone"
  volcado="$(python3 "$atspi" --pid "$PID" --volcar 2>&1)"
  case "$volcado" in *"Clock"*) ;; *) falla "Catalina: Date & Time perdió la pestaña Clock" ;; esac
  paso "Date & Time: Clock solo en Catalina"
  matar_preferencias
  true
}
