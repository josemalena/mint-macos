# caso: General no dibuja «Allow Handoff between this Mac and your iCloud devices» (ni en gris) cuando el perfil de la versión lo marca «ocultar»
# (José lo descartó, 19-10-2026), y sí el resto (font smoothing)
# límite: 90
prueba() {
  requiere mac-preferencias xdotool python3
  export MP_PYTHON_DIR="$MINT_MACOS_REPO/settings"
  local base="$XDG_DATA_HOME/mint-macos/macos/prueba-2.0/apps/system-preferences"
  mkdir -p "$base" "$XDG_RUNTIME_DIR/mint-macos"
  cat > "$base/com.apple.preference.general.json" <<'J'
{"id":"com.apple.preference.general","vistas":[{"raiz":{"hijos":[
 {"props":{"id":"clave:KCv-2t-qIH","texto":"Allow Handoff between this Mac and your iCloud devices","clave":"KCv-2t-qIH","ocultar":true}}]}}]}
J
  echo '{"version":"prueba-2.0"}' > "$XDG_RUNTIME_DIR/mint-macos/macos.json"
  lanzar mac-preferencias com.apple.preference.general
  local v; v="$(esperar_ventana '[Mm]ac-settings' 40)"
  esperar_texto "$v" "Use font smoothing when available" 30
  local volcado; volcado="$(python3 "$(dirname "$PRUEBAS_LIB")/atspi.py" --pid "$(xdotool getwindowpid "$v")" --volcar 2>&1)"
  case "$volcado" in *"Allow Handoff"*) falla "Handoff sigue en General aunque el perfil lo oculta" ;; esac
  paso "Handoff no sale; el suavizado de fuentes sí"
  captura general-sin-handoff
}
