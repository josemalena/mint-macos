# caso: el selector de emojis (⌃⌘Espacio) abre junto al puntero y Esc lo cierra sin hacer nada
# límite: 60
prueba() {
  local w
  requiere mac-emojis-vala xdotool
  lanzar mac-emojis-vala --destino ""
  w="$(esperar_ventana '[Mm]ac-emojis' 20)"
  sleep 1.5
  captura emojis-abierto
  xdotool key Escape
  for _ in $(seq 40); do pgrep -f "mac-emojis-vala" >/dev/null || break; sleep 0.2; done
  ! pgrep -f "mac-emojis-vala" >/dev/null || falla "Esc no cerró el selector"

  # Lo mismo pidiéndoselo al residente.
  requiere mac-ventanas
  lanzar mac-ventanas --residente
  sleep 4
  (mac-ventanas emojis --destino "" >/dev/null 2>&1 || true) &
  w=""
  for _ in $(seq 50); do w="$(xdotool search --onlyvisible --class '[Mm]ac-ventanas' | tail -1 || true)"; [ -n "$w" ] && break; sleep 0.2; done
  [ -n "$w" ] || falla "el residente no abrió el selector"
  sleep 1.5
  xdotool key Escape
  sleep 1
  [ -z "$(xdotool search --onlyvisible --class '[Mm]ac-ventanas' | tail -1 || true)" ] || falla "Esc no cerró el selector del residente"
}
