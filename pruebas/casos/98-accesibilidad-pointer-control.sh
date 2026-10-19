# caso: Accessibility es un panel de verdad (lista de secciones a la izquierda) y Pointer Control trae Double-click speed y Spring-loading delay,
# con las claves de Fynder si existen
# límite: 120
prueba() {
  requiere mac-preferencias xdotool python3
  export MP_PYTHON_DIR="$MINT_MACOS_REPO/settings"
  export MINT_ACCESIBILIDAD_PRUEBA=1      # no escribe en gsettings
  lanzar mac-preferencias com.apple.preference.universalaccess
  local v; v="$(esperar_ventana '[Mm]ac-settings' 40)"
  esperar_texto "$v" "Pointer Control" 20
  esperar_texto "$v" "Double-click speed:" 20
  esperar_texto "$v" "Spring-loading delay:" 20
  esperar_texto "$v" "Mouse & Trackpad" 20
  esperar_texto "$v" "Alternate Control Methods" 20
  esperar_texto "$v" "Keyboard" 20
  esperar_texto "$v" "Zoom" 20
  esperar_texto "$v" "Show Accessibility status in menu bar" 20
  captura accesibilidad-pointer-control
}
