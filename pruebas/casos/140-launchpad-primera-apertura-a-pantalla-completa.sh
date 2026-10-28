# caso: la primera apertura de un residente recién arrancado ya sale a pantalla completa (no pequeña, ni en otro tamaño que luego crece)
# límite: 90
# gestor: muffin
prueba() {
  requiere mac-launchpad-vala xdotool xwininfo
  export LAUNCHPAD_DEBUG=1
  local log="$PRUEBAS_RES/$PRUEBAS_CASO.log" tam="$PRUEBAS_RES/$PRUEBAS_CASO-tamanos.txt"
  setsid mac-launchpad-vala --residente > "$log" 2>&1 < /dev/null &
  sleep 8
  mac-launchpad-vala &
  : > "$tam"
  local fin=$((SECONDS + 3)) w
  while [ "$SECONDS" -lt "$fin" ]; do
    for w in $(xdotool search --onlyvisible --class launchpad 2>/dev/null); do
      echo "$(date +%s.%N) $(xwininfo -id "$w" | awk '/Width:/ {a=$2} /Height:/ {h=$2} END {print a "x" h}')" >> "$tam"
    done
    sleep 0.05
  done
  for p in $(pgrep -x mac-launchpad-v); do grep -qz "^HOME=$HOME\$" "/proc/$p/environ" 2>/dev/null && kill "$p"; done
  paso "tamaños vistos: $(awk '{print $2}' "$tam" | sort | uniq -c | tr '\n' ' ')"
  [ -s "$tam" ] || falla "no apareció la ventana del Launchpad"
  local malos; malos="$(awk -v ok="${PRUEBAS_ANCHO}x${PRUEBAS_ALTO}" '$2 != ok' "$tam" | wc -l)"
  [ "$malos" -eq 0 ] || falla "$malos muestras con un tamaño distinto de ${PRUEBAS_ANCHO}x${PRUEBAS_ALTO}: $(awk -v ok="${PRUEBAS_ANCHO}x${PRUEBAS_ALTO}" '$2 != ok {print $2}' "$tam" | sort | uniq -c | tr '\n' ' ')"
}
