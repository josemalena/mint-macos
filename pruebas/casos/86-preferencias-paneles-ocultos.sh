# caso: System Preferences no pinta (ni en gris ni en la búsqueda) los paneles que el perfil de la versión activa marca «ocultar»; con el perfil
# inventado de la prueba se oculta Screen Time y se queda Sound
# límite: 90
prueba() {
  requiere mac-preferencias xdotool python3
  export MP_PYTHON_DIR="$MINT_MACOS_REPO/settings"
  local base="$XDG_DATA_HOME/mint-macos/macos/prueba-1.0/apps"
  mkdir -p "$base" "$XDG_RUNTIME_DIR/mint-macos"
  cat > "$base/system-preferences.json" <<'J'
{"id":"system-preferences","grupos":[{"paneles":[
 {"id":"com.apple.preference.screentime","nombre":"Screen Time","ocultar":true,"motivo":"Pausado (José, 19-10-2026)"},
 {"id":"com.apple.preference.sound","nombre":"Sound"}]}]}
J
  echo '{"version":"prueba-1.0"}' > "$XDG_RUNTIME_DIR/mint-macos/macos.json"
  lanzar mac-preferencias
  local v; v="$(esperar_ventana '[Mm]ac-settings' 40)"
  esperar_texto "$v" "Sound" 20
  local volcado; volcado="$(python3 "$(dirname "$PRUEBAS_LIB")/atspi.py" --pid "$(xdotool getwindowpid "$v")" --volcar 2>&1)"
  case "$volcado" in *"Screen Time"*) falla "Screen Time sigue en la cuadrícula aunque el perfil lo oculta" ;; esac
  paso "Screen Time no sale; Sound sí"
  captura paneles-ocultos
}
