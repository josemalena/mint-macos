# caso: Energy Saver con el perfil de Monterey: barra lateral Power/Schedule, un solo deslizador «Turn display off after:» y la casilla de no suspender; con Catalina, «Computer sleep:» y «Display sleep:»
# límite: 120
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
volcar() {
  mkdir -p "$XDG_RUNTIME_DIR/mint-macos"
  printf '{"version":"%s"}' "$1" > "$XDG_RUNTIME_DIR/mint-macos/macos.json"
  lanzar mac-preferencias com.apple.preference.energysaver
  local v pid; v="$(esperar_ventana '[Mm]ac-settings' 40)"
  pid="$(xdotool getwindowpid "$v")"
  esperar_texto "$v" "Restore Defaults" 30
  VOLCADO="$(python3 "$(dirname "$PRUEBAS_LIB")/atspi.py" --pid "$pid" --volcar 2>&1)"
  captura "mc-$1"
  matar_preferencias
}
prueba() {
  requiere mac-preferencias xdotool python3
  export MP_PYTHON_DIR="$MINT_MACOS_REPO/settings"
  volcar monterey-12.7.6
  for t in "Turn display off after:" "Prevent your Mac from automatically sleeping when the display is off" "Schedule" "Power"; do
    case "$VOLCADO" in *"$t"*) ;; *) falla "Monterey: falta «$t»" ;; esac
  done
  case "$VOLCADO" in *"Computer sleep:"*) falla "Monterey: «Computer sleep:» sigue" ;; esac
  paso "Monterey: barra lateral, un deslizador y la casilla de no suspender"
  volcar catalina-10.15
  for t in "Computer sleep:" "Display sleep:"; do
    case "$VOLCADO" in *"$t"*) ;; *) falla "Catalina: falta «$t»" ;; esac
  done
  case "$VOLCADO" in *"Turn display off after:"*) falla "Catalina: salió el deslizador de Monterey" ;; esac
  paso "Catalina: como estaba"
  true
}
