# caso: Software Update sale de «Checking for updates…» y dice si hay actualizaciones del sistema o que todo está al día
# límite: 120
prueba() {
  requiere mac-preferencias xdotool
  export MP_PYTHON_DIR="$MINT_MACOS_REPO/settings"
  export MINT_ACTUALIZACIONES_PRUEBA=1      # el botón no instala nada de verdad
  lanzar mac-preferencias
  local v; v="$(esperar_ventana '[Mm]ac-settings' 40)"
  mac-preferencias softwareupdate
  for _ in $(seq 50); do [ "$(titulo "$v")" = "Software Update" ] && break; sleep 0.2; done
  [ "$(titulo "$v")" = "Software Update" ] || falla "no abrió Software Update: «$(titulo "$v")»"
  captura software-update-revisando
  # Termina de revisar: «N updates available.» o «Your computer is up to date».
  local t="" pid arbol; pid="$(xdotool getwindowpid "$v")"
  for _ in $(seq 40); do
    arbol="$(python3 "$(dirname "$PRUEBAS_LIB")/atspi.py" --pid "$pid" --volcar 2>/dev/null || true)"
    t="$(printf '%s' "$arbol" | grep -oE "[0-9]+ updates? available|up to date" | head -1 || true)"
    [ -n "$t" ] && break
    sleep 1
  done
  captura software-update-listo
  [ -n "$t" ] && paso "dice «$t»"
  [ -n "$t" ] || falla "Software Update se quedó en «Checking for updates…»"
  cerrar_ventana "$v"
}
