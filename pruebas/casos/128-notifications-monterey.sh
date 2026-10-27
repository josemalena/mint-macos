# caso: Notifications con el perfil de Monterey se llama «Notifications & Focus», con las pestañas Notifications y Focus y «Notification grouping:»; con Catalina, «Notification Center sort order:»
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
  lanzar mac-preferencias com.apple.preference.notifications
  local v pid; v="$(esperar_ventana '[Mm]ac-settings' 40)"
  pid="$(xdotool getwindowpid "$v")"
  esperar_texto "$v" "$2" 30
  VOLCADO="$(python3 "$(dirname "$PRUEBAS_LIB")/atspi.py" --pid "$pid" --volcar 2>&1)"; TITULO="$(titulo "$v")"
  captura "mc-$1"
  matar_preferencias
}
prueba() {
  requiere mac-preferencias xdotool python3
  export MP_PYTHON_DIR="$MINT_MACOS_REPO/settings"
  volcar monterey-12.7.6 "Show previews:"
  for t in "Notifications & Focus" "Focus" "Notification grouping:" "Allow time sensitive alerts"; do
    case "$VOLCADO$TITULO" in *"$t"*) ;; *) falla "Monterey: falta «$t»" ;; esac
  done
  case "$VOLCADO" in *"Notification Center sort order:"*) falla "Monterey: «Notification Center sort order:» sigue" ;; esac
  paso "Monterey: título, pestañas y la página de la app de Monterey"
  volcar catalina-10.15 "Notification Center sort order:"
  case "$VOLCADO" in *"Notification Center sort order:"*) ;; *) falla "Catalina: falta «Notification Center sort order:»" ;; esac
  case "$VOLCADO$TITULO" in *"Notifications & Focus"*|*"Notification grouping:"*) falla "Catalina: salió algo de Monterey" ;; esac
  paso "Catalina: como estaba"
  true
}
