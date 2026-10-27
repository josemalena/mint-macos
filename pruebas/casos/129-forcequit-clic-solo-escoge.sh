# caso: en Force Quit un clic en la fila solo la escoge; el botón pide confirmar; Cancel no mata nada; Force Quit mata solo la escogida
# límite: 120
prueba() {
  necesita_teclado
  requiere xed mac-forcequit wmctrl xdotool
  lanzar xed
  local x pid
  x="$(esperar_ventana '^[Xx]ed$' 20)"
  pid="$(xdotool getwindowpid "$x")"
  lanzar mac-forcequit
  local fq; fq="$(esperar_ventana '[Mm]ac-forcequit' 20)"
  esperar_texto "$fq" "Xed" 20
  wmctrl -i -a "$fq"; sleep 0.5
  local X Y _; read -r _ _ X Y _ < <(wmctrl -lG | awk -v id="$(printf '0x%08x' "$fq")" 'tolower($1)==id')
  # wmctrl da la esquina del cuerpo de la ventana: la fila de xed (única app abierta) queda en (X+100, Y+34) y el botón en (X+273, Y+216) (medido en la captura)
  xdotool mousemove $((X + 100)) $((Y + 34)) click 1; sleep 0.8
  kill -0 "$pid" 2>/dev/null || falla "un clic en la fila mató la app (regresión del 27-10-2026)"
  paso "el clic solo escogió: xed sigue vivo"
  # el botón (233, 244) pide confirmar; Cancel (Escape) no mata
  xdotool mousemove $((X + 273)) $((Y + 216)) click 1; sleep 1
  captura confirmacion
  kill -0 "$pid" 2>/dev/null || falla "el botón mató la app sin confirmar"
  teclas Escape; sleep 1
  kill -0 "$pid" 2>/dev/null || falla "Cancel mató la app"
  paso "el botón pide confirmar y Cancel no mata nada"
  # otra vez el botón y aceptar
  wmctrl -i -a "$fq"; sleep 0.5
  xdotool mousemove $((X + 273)) $((Y + 216)) click 1; sleep 1
  teclas Return
  for _ in $(seq 50); do kill -0 "$pid" 2>/dev/null || break; sleep 0.2; done
  kill -0 "$pid" 2>/dev/null && { kill -KILL "$pid" 2>/dev/null; falla "aceptar la confirmación no forzó la app escogida"; }
  paso "aceptar la confirmación fuerza solo la app escogida"
}
