# caso: el panel de terceros Solaar sale en System Preferences y enseña los dispositivos Logitech con su batería y ajustes
# límite: 120
prueba() {
  requiere mac-preferencias xdotool solaar
  export MP_PYTHON_DIR="$MINT_MACOS_REPO/settings"
  lanzar mac-preferencias
  local v; v="$(esperar_ventana '[Mm]ac-settings' 40)"
  esperar_texto "$v" "Solaar" 30
  captura cuadricula-con-solaar
  mac-preferencias solaar
  for _ in $(seq 50); do [ "$(titulo "$v")" = "Solaar" ] && break; sleep 0.2; done
  [ "$(titulo "$v")" = "Solaar" ] || falla "no abrió el panel Solaar: «$(titulo "$v")»"
  esperar_texto "$v" "Wave Keys" 60
  captura panel-solaar
  cerrar_ventana "$v"
}
