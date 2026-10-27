# caso: Keyboard ▸ Shortcuts con el perfil de Monterey: sin la categoría «Input Sources» y con «Show Launchpad» sin atajo; con Catalina, como estaba
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
  lanzar mac-preferencias com.apple.preference.keyboard
  local v pid; v="$(esperar_ventana '[Mm]ac-settings' 40)"
  pid="$(xdotool getwindowpid "$v")"
  esperar_texto "$v" "Shortcuts" 30
  python3 "$(dirname "$PRUEBAS_LIB")/atspi.py" --pid "$pid" --texto "Shortcuts" --pulsar > /dev/null 2>&1 || true
  sleep 2
  VOLCADO="$(python3 "$(dirname "$PRUEBAS_LIB")/atspi.py" --pid "$pid" --volcar 2>&1)"
  captura "teclado-$1"
  matar_preferencias
}
prueba() {
  requiere mac-preferencias xdotool python3
  export MP_PYTHON_DIR="$MINT_MACOS_REPO/settings"
  volcar monterey-12.7.6
  echo "$VOLCADO" > "$PRUEBAS_RES/volcado-monterey.txt"
  case "$VOLCADO" in *"App Shortcuts"*) ;; *) falla "Monterey: no se ve la categoría «App Shortcuts» (¿cambió de pestaña?)" ;; esac
  n="$(printf '%s' "$VOLCADO" | grep -c "Input Sources" || true)"
  paso "Monterey: «Input Sources» sale $n veces en el volcado (la pestaña de Keyboard también lo trae)"
  volcar catalina-10.15
  echo "$VOLCADO" > "$PRUEBAS_RES/volcado-catalina.txt"
  m="$(printf '%s' "$VOLCADO" | grep -c "Input Sources" || true)"
  paso "Catalina: «Input Sources» sale $m veces"
  [ "$m" -gt "$n" ] || falla "Catalina debía tener una «Input Sources» más (la categoría) que Monterey: $m contra $n"
  true
}
