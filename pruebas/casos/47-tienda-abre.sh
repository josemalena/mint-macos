# caso: el App Store abre con su barra lateral (Discover … Updates), no se cae al cabo de unos segundos y Esc no lo cierra
# límite: 60
prueba() {
  requiere mac-tienda xdotool
  lanzar mac-tienda
  local w; w="$(esperar_ventana '[Mm]ac-tienda' 30)"
  sleep 4
  captura tienda-abierta
  pgrep -x mac-tienda >/dev/null || falla "mac-tienda se cayó"
  xdotool search --onlyvisible --class '[Mm]ac-tienda' >/dev/null || falla "la ventana del App Store desapareció"
  paso "ventana: $w"
}
