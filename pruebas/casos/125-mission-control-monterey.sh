# caso: Mission Control con el perfil de Monterey: 3 filas de atajos con menús, la nota de Shift/Control/Option/Command y sin «Requires log out» ni «Spaces left and right»; con Catalina, como estaba
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
  lanzar mac-preferencias com.apple.preference.expose
  local v pid; v="$(esperar_ventana '[Mm]ac-settings' 40)"
  pid="$(xdotool getwindowpid "$v")"
  esperar_texto "$v" "Hot Corners…" 30
  VOLCADO="$(python3 "$(dirname "$PRUEBAS_LIB")/atspi.py" --pid "$pid" --volcar 2>&1)"
  captura "mc-$1"
  matar_preferencias
}
prueba() {
  requiere mac-preferencias xdotool python3
  export MP_PYTHON_DIR="$MINT_MACOS_REPO/settings"
  volcar monterey-12.7.6
  case "$VOLCADO" in *"additional choices press Shift"*) ;; *) falla "Monterey: falta la nota de Shift, Control, Option o Command" ;; esac
  case "$VOLCADO" in *"Requires log out"*) falla "Monterey: «Requires log out» sigue" ;; esac
  case "$VOLCADO" in *"Spaces left and right"*) falla "Monterey: «Spaces left and right» sigue" ;; esac
  paso "Monterey: nota sí; Requires log out y Spaces left and right no"
  volcar catalina-10.15
  case "$VOLCADO" in *"Requires log out"*) ;; *) falla "Catalina: falta «Requires log out»" ;; esac
  case "$VOLCADO" in *"Spaces left and right"*) ;; *) falla "Catalina: falta «Spaces left and right»" ;; esac
  case "$VOLCADO" in *"additional choices press"*) falla "Catalina: salió la nota de Monterey" ;; esac
  paso "Catalina: como estaba"
  true
}
