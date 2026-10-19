# caso: una app colgada (kill -STOP) sale en Force Quit como «<app> (not responding)» y mac-forcequit --seleccionar PID la deja escogida;
# un segundo --seleccionar no abre otra ventana
# límite: 90
prueba() {
  despejar_pantalla
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
  # El nombre que muestra depende del .desktop que otra prueba haya dejado para xed («Xed», «xedprueba»…): se busca cualquier fila «(not responding)»
  local pidfq volcado=""; pidfq="$(xdotool getwindowpid "$fq")"
  for _ in $(seq 20); do
    volcado="$(python3 "$(dirname "$PRUEBAS_LIB")/atspi.py" --pid "$pidfq" --volcar 2>&1)"
    echo "$volcado" | grep -q "(not responding)" && break
    sleep 1
  done
  if ! echo "$volcado" | grep -q "(not responding)"; then
    echo "--- lo que muestra Force Quit:" >&2; echo "$volcado" >&2
    echo "--- procesos xed:" >&2; ps -o pid,stat,args -C xed >&2
    falla "Force Quit no marca ninguna app como «(not responding)»"
  fi
  paso "se ve una fila «(not responding)»: $(echo "$volcado" | grep "(not responding)" | head -1 | sed 's/^ *//')"
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
