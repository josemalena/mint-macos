# caso: el panel Dock con el perfil de Monterey se llama «Dock & Menu Bar», trae la sección Menu Bar y no trae «Prefer tabs…»; con Catalina, como estaba
# límite: 120
matar_preferencias() {   # la app es de instancia única: hasta que se vaya de verdad, o la siguiente solo activaría la vieja con su perfil
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
  lanzar mac-preferencias com.apple.preference.dock
  local v pid; v="$(esperar_ventana '[Mm]ac-settings' 40)"
  pid="$(xdotool getwindowpid "$v")"
  esperar_texto "$v" "Size:" 30
  VOLCADO="$(python3 "$(dirname "$PRUEBAS_LIB")/atspi.py" --pid "$pid" --volcar 2>&1)"
  TITULO="$(titulo "$v")"; paso "versión $1: título «$TITULO»"; cat "$XDG_RUNTIME_DIR/mint-macos/macos.json" >&2; echo >&2
  captura "dock-$1"
  matar_preferencias
}
prueba() {
  requiere mac-preferencias xdotool python3
  export MP_PYTHON_DIR="$MINT_MACOS_REPO/settings"
  local esq; esq="$(dirname "$(command -v mac-preferencias)")/../esquemas"
  [ -d "$esq" ] && export GSETTINGS_SCHEMA_DIR="$esq"
  volcar monterey-12.7.6
  [ "$TITULO" = "Dock & Menu Bar" ] || falla "Monterey: el título es «$TITULO», no «Dock & Menu Bar»"
  case "$VOLCADO" in *"Menu Bar:"*) ;; *) falla "Monterey: falta la sección «Menu Bar:»" ;; esac
  case "$VOLCADO" in *"Prefer tabs when opening documents"*) falla "Monterey: «Prefer tabs…» sigue en Dock" ;; esac
  paso "Monterey: título, sección Menu Bar y sin Prefer tabs"
  volcar catalina-10.15
  [ "$TITULO" = "Dock" ] || falla "Catalina: el título es «$TITULO», no «Dock»"
  case "$VOLCADO" in *"Prefer tabs when opening documents"*) ;; *) falla "Catalina: falta «Prefer tabs…»" ;; esac
  case "$VOLCADO" in *"Menu Bar:"*) falla "Catalina: salió la sección Menu Bar" ;; esac
  paso "Catalina: como estaba"
  true
}
