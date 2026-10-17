# caso: System Preferences (Vala) abre con su cuadrícula y, al pedirle un panel, lo muestra
# límite: 90
prueba() {
  requiere mac-preferencias xdotool
  export MP_PYTHON_DIR="$MINT_MACOS_REPO/settings"     # el CSS de Catalina sin instalar
  lanzar mac-preferencias
  local v; v="$(esperar_ventana '[Mm]ac-settings' 40)"
  [ "$(titulo "$v")" = "System Preferences" ] || falla "la ventana no se llama System Preferences: «$(titulo "$v")»"
  esperar_texto "$v" "Notifications" 30      # una celda de la cuadrícula
  esperar_texto "$v" "Sound" 10
  captura cuadricula

  # Pedir un panel: el segundo mac-preferencias se lo manda al primero (mismo id de aplicación).
  mac-preferencias notifications
  for _ in $(seq 50); do [ "$(titulo "$v")" = "Notifications" ] && break; sleep 0.2; done
  [ "$(titulo "$v")" = "Notifications" ] || falla "no abrió el panel Notifications: «$(titulo "$v")»"
  esperar_texto "$v" "Do Not Disturb" 20
  captura panel
  cerrar_ventana "$v"
}
