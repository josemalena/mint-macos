# caso: con una app colgada, Cinnamon no muestra su diálogo «no responde»: abre Force Quit Applications con esa app escogida
# y marcada «(not responding)»
# gestor: cinnamon-colgadas
# límite: 120
prueba() {
  despejar_pantalla
  necesita_teclado
  requiere xed mac-forcequit mac-forcequit-lanzar wmctrl xdotool
  gsettings set org.cinnamon.muffin check-alive-timeout 2000 2>/dev/null || true
  lanzar xed
  local x pid
  x="$(esperar_ventana '^[Xx]ed$' 20)"
  pid="$(xdotool getwindowpid "$x")"
  kill -STOP "$pid"
  trap "kill -KILL $pid 2>/dev/null || true" EXIT
  # Cerrar una ventana que no contesta es lo que hace que Muffin pregunte si está viva
  python3 "$(dirname "$PRUEBAS_LIB")/ayudantes/cerrar-ventana.py" "$x"
  local fq; fq="$(esperar_ventana '[Mm]ac-forcequit' 30)"
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
  captura force-quit-con-xed-colgado
  # Y sin el diálogo de Cinnamon (se llama «… is not responding» y trae Wait)
  if python3 "$(dirname "$PRUEBAS_LIB")/atspi.py" --pid "$(pgrep -x -n cinnamon)" --texto "Wait" --segundos 2 >/dev/null 2>&1; then
    falla "salió el diálogo de Cinnamon con el botón Wait"
  fi
  paso "sin el diálogo de Cinnamon"
  kill -KILL "$pid" 2>/dev/null || true
}
