# caso: la barra de ⇧⌘5 se arrastra, «pantalla entera» pone la cámara y un clic captura, y Esc sale de la herramienta
# límite: 120
prueba() {
  requiere mac-captura-herramienta-vala xdotool identify
  [ "$PRUEBAS_REAL" != true ] || saltar "captura la pantalla entera: en la de José no se hace"
  mkdir -p "$HOME/Desktop"
  rm -f "$HOME/Desktop"/Screen\ Shot*
  lanzar mac-captura-herramienta-vala
  esperar_ventana '[Mm]ac-captura-herramienta' 30 >/dev/null
  sleep 1
  local b; b="$(xdotool search --onlyvisible --name '^Screenshot$' | tail -1)"
  [ -n "$b" ] || falla "no está la ventana «Screenshot» de la barra"
  local X Y WIDTH HEIGHT
  eval "$(xdotool getwindowgeometry --shell "$b")"
  local x0=$X y0=$Y
  paso "barra en $x0,$y0 (${WIDTH}x${HEIGHT})"

  # Se agarra por el borde de la barra (fuera de los botones) y se lleva a otro sitio.
  xdotool mousemove $((X + 5)) $((Y + HEIGHT / 2)) mousedown 1
  for paso_ in 1 2 3 4 5 6 7 8; do xdotool mousemove_relative -- 25 -12; sleep 0.05; done
  xdotool mouseup 1
  sleep 0.5
  eval "$(xdotool getwindowgeometry --shell "$b")"
  paso "barra ahora en $X,$Y"
  comprobar "la barra se movió a la derecha" test "$((X - x0))" -ge 150
  comprobar "la barra se movió hacia arriba" test "$((y0 - Y))" -ge 70
  captura barra-movida

  # Pantalla entera: el puntero es la cámara y un clic en el escritorio captura (sin usar el botón Capture).
  xdotool mousemove 300 300
  sleep 0.3
  xdotool click 1
  local f=""
  for _ in $(seq 100); do
    f="$(ls "$HOME/Desktop"/Screen\ Shot*.png 2>/dev/null | head -1 || true)"
    [ -n "$f" ] && break
    sleep 0.2
  done
  [ -n "$f" ] || falla "el clic con la cámara no dejó ningún «Screen Shot …png» en $HOME/Desktop"
  for _ in $(seq 50); do identify "$f" >/dev/null 2>&1 && break; sleep 0.2; done
  comprobar "capturó la pantalla entera (1600x1200)" test "$(identify -format '%wx%h' "$f")" = "1600x1200"

  # Esc, con la cámara puesta, cierra toda la herramienta.
  sleep 2
  lanzar mac-captura-herramienta-vala
  esperar_ventana '[Mm]ac-captura-herramienta' 30 >/dev/null
  sleep 1
  xdotool key Escape
  for _ in $(seq 50); do pgrep -x mac-captura-her >/dev/null || break; sleep 0.2; done
  ! pgrep -x mac-captura-her >/dev/null || falla "Esc no cerró la herramienta"
}
