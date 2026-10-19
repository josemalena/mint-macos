# caso: una app colgada (kill -STOP) sale en Force Quit como «<app> (not responding)» y mac-forcequit --seleccionar PID la deja escogida;
# un segundo --seleccionar no abre otra ventana
# límite: 90
prueba() {
  necesita_teclado
  requiere xed mac-forcequit wmctrl xdotool
  lanzar xed
  local x pid
  x="$(esperar_ventana '^[Xx]ed$' 20)"
  pid="$(xdotool getwindowpid "$x")"
  kill -STOP "$pid"
  trap "kill -KILL $pid 2>/dev/null || true" EXIT   # un xed detenido heredaría el lock del harness
  lanzar mac-forcequit --seleccionar "$pid"
  local fq; fq="$(esperar_ventana '[Mm]ac-forcequit' 20)"
  esperar_texto "$fq" "Xed (not responding)" 20
  captura colgada-escogida
  lanzar mac-forcequit --seleccionar "$pid"
  sleep 2
  local cuantas; cuantas="$(wmctrl -l | grep -c 'Force Quit Applications')"
  [ "$cuantas" -le 1 ] || falla "un segundo --seleccionar abrió otra ventana ($cuantas)"
  # La app escogida es la colgada: Enter la fuerza
  wmctrl -i -a "$fq"; sleep 0.5
  teclas Return
  for _ in $(seq 50); do kill -0 "$pid" 2>/dev/null || break; sleep 0.2; done
  kill -0 "$pid" 2>/dev/null && { kill -KILL "$pid" 2>/dev/null; falla "Enter no forzó la app que --seleccionar dejó escogida"; }
  paso "la app colgada quedó escogida y se forzó con Enter"
}
