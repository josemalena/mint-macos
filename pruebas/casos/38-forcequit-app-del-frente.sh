# caso: ⌥⇧⌘⎋ (mac-forcequit --app-del-frente) fuerza la salida de la app que está al frente
# límite: 90
prueba() {
  requiere xed mac-forcequit wmctrl xdotool
  lanzar xed
  local x pid
  x="$(esperar_ventana '^[Xx]ed$' 20)"
  pid="$(xdotool getwindowpid "$x")"
  wmctrl -i -a "$x"
  sleep 1
  [ "$(xdotool getactivewindow)" = "$x" ] || falla "xed no quedó al frente"
  comprobar "xed está vivo antes" kill -0 "$pid"
  mac-forcequit --app-del-frente
  for _ in $(seq 50); do kill -0 "$pid" 2>/dev/null || break; sleep 0.2; done
  if kill -0 "$pid" 2>/dev/null; then falla "xed (pid $pid) sigue vivo"; fi
  paso "xed forzado a salir"
  esperar_sin_ventana "$x" 10
}
