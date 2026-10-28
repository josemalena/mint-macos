# caso: el About de un programa nuestro sale modal y centrado sobre la ventana del programa, no suelto en otro monitor (José, 27-10-2026)
# límite: 90
prueba() {
  despejar_pantalla
  requiere mac-forcequit xdotool gdbus
  lanzar mac-forcequit
  local fq; fq="$(esperar_ventana '[Mm]ac-forcequit' 20)"
  sleep 1
  gdbus call --session --dest io.github.josemalena.MintMacosForceQuit --object-path /io/github/josemalena/MintMacosForceQuit \
    --method org.gtk.Actions.Activate about '[]' '{}' >/dev/null || falla "no pude pedir app.about"
  local ab=""
  for _ in $(seq 40); do
    ab="$(xdotool search --onlyvisible --name '^About Force Quit' 2>/dev/null | head -1)"
    [ -n "$ab" ] && break; sleep 0.25
  done
  [ -n "$ab" ] || falla "no salió la ventana About"
  sleep 0.7
  local X Y WIDTH HEIGHT PX PY PW PH
  eval "$(xdotool getwindowgeometry --shell "$fq")"; PX=$X; PY=$Y; PW=$WIDTH; PH=$HEIGHT
  eval "$(xdotool getwindowgeometry --shell "$ab")"
  local dx=$(( (X + WIDTH / 2) - (PX + PW / 2) )) dy=$(( (Y + HEIGHT / 2) - (PY + PH / 2) ))
  paso "madre ${PW}x${PH}+$PX+$PY; About ${WIDTH}x${HEIGHT}+$X+$Y; descentrado ($dx,$dy)"
  captura about-sobre-la-ventana
  [ "${dx#-}" -le 40 ] && [ "${dy#-}" -le 40 ] || falla "el About no quedó centrado sobre la ventana del programa ($dx,$dy)"
  xprop -id "$ab" WM_TRANSIENT_FOR 2>/dev/null | grep -q "window id" || falla "el About no es transient de la ventana del programa"
  paso "el About sale centrado sobre su ventana y es transient de ella"
}
