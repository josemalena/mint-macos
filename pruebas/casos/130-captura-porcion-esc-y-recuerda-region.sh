# caso: ⇧⌘5 en «Capture Selected Portion»: Esc cancela sin dejar nada (ni archivo ni ventanas) y el último rectángulo se recuerda
# límite: 150
prueba() {
  requiere mac-captura-herramienta-vala xdotool
  [ "$PRUEBAS_REAL" != true ] || saltar "arma la pantalla entera: en la de José no se hace"
  mkdir -p "$HOME/Desktop" "$HOME/.config/mac-captura"
  # no dejar el modo «porción» puesto: los casos 32 y 40 parten del modo por defecto
  trap "rm -f \"\$HOME/.config/mac-captura/config.json\" \"${XDG_STATE_HOME:-$HOME/.local/state}/mac-captura/ultima-region.json\"" RETURN
  rm -f "$HOME/Desktop"/Screen\ Shot* "${XDG_STATE_HOME:-$HOME/.local/state}/mac-captura/ultima-region.json"
  printf '{"modo": "porcion", "guardar_en": "", "destino": "carpeta", "temporizador": 0, "micro": "", "miniatura": false, "recordar": true}' > "$HOME/.config/mac-captura/config.json"

  # 1) Esc con el marco puesto cierra toda la herramienta y no guarda nada
  lanzar mac-captura-herramienta-vala
  esperar_ventana '[Mm]ac-captura-herramienta' 30 >/dev/null
  sleep 1.5
  captura marco-puesto
  xdotool key Escape
  for _ in $(seq 40); do pgrep -x mac-captura-her >/dev/null || break; sleep 0.2; done
  ! pgrep -x mac-captura-her >/dev/null || falla "Esc con el marco de la porción no cerró la herramienta"
  [ -z "$(ls "$HOME/Desktop"/Screen\ Shot* 2>/dev/null)" ] || falla "Esc dejó un archivo en el escritorio"
  paso "Esc cancela con el marco puesto y no deja archivos"

  # 2) el marco se mueve, se cierra con Esc y la vez siguiente vuelve donde quedó
  lanzar mac-captura-herramienta-vala
  esperar_ventana '[Mm]ac-captura-herramienta' 30 >/dev/null
  sleep 1.5
  local cx=$((PRUEBAS_ANCHO / 2)) cy=$((PRUEBAS_ALTO / 2))
  xdotool mousemove $cx $cy mousedown 1
  for _ in 1 2 3 4 5 6; do xdotool mousemove_relative -- 20 10; sleep 0.05; done
  xdotool mouseup 1
  sleep 0.5
  xdotool key Escape
  for _ in $(seq 40); do pgrep -x mac-captura-her >/dev/null || break; sleep 0.2; done
  local f="${XDG_STATE_HOME:-$HOME/.local/state}/mac-captura/ultima-region.json"
  [ -s "$f" ] || falla "no se guardó el último rectángulo ($f)"
  paso "guardado: $(cat "$f")"
  local antes; antes="$(cat "$f")"
  lanzar mac-captura-herramienta-vala
  esperar_ventana '[Mm]ac-captura-herramienta' 30 >/dev/null
  sleep 1.5
  xdotool key Escape
  for _ in $(seq 40); do pgrep -x mac-captura-her >/dev/null || break; sleep 0.2; done
  [ "$(cat "$f")" = "$antes" ] || falla "el rectángulo cambió al abrir y cerrar sin tocarlo: $(cat "$f") (antes $antes)"
  # el marco vuelve a su sitio: la x guardada es la de la vez anterior (la mitad de la pantalla no, porque se movió 120 px)
  local x0; x0="$(grep -o '"x": *[0-9]*' "$f" | head -1 | grep -o '[0-9]*$')"
  [ "$x0" -gt $((PRUEBAS_ANCHO / 4 + 60)) ] || falla "el marco no se movió o no se recordó (x=$x0)"
  paso "el rectángulo se recuerda entre sesiones (x=$x0)"
}
