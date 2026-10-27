# caso: Force Quit lista una app que se abrió y, al forzarla, la app se cierra
# límite: 90
prueba() {
  necesita_teclado
  requiere xed mac-forcequit wmctrl xdotool
  lanzar xed
  local x pid
  x="$(esperar_ventana '^[Xx]ed$' 20)"
  pid="$(xdotool getwindowpid "$x")"
  comprobar "xed está vivo antes de forzarlo" kill -0 "$pid"

  lanzar mac-forcequit
  local fq; fq="$(esperar_ventana '[Mm]ac-forcequit' 20)"
  case "$(titulo "$fq")" in
    "Force Quit Applications") paso "la ventana se llama como en Catalina" ;;
    *) falla "el título no es el de Catalina: «$(titulo "$fq")»" ;;
  esac
  esperar_texto "$fq" "Xed" 20       # la fila de la app que se abrió (el nombre que da el gestor de ventanas)
  captura lista

  # Sin selección al abrir (como en Catalina): flecha abajo escoge la primera fila y Enter fuerza su salida.
  wmctrl -i -a "$fq"
  sleep 0.5
  teclas Down
  teclas Return
  sleep 1; teclas Return        # la confirmación («Do you want to force … to quit?»): Return acepta el botón por defecto
  for _ in $(seq 50); do kill -0 "$pid" 2>/dev/null || break; sleep 0.2; done
  if kill -0 "$pid" 2>/dev/null; then falla "xed (pid $pid) sigue vivo después de Force Quit"; fi
  paso "xed ya no corre"
  esperar_sin_ventana "$x" 10
}
