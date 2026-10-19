# caso: el ícono del Dock rebota sin parar mientras la app abre y se calma cuando sale su ventana; Launchpad no rebota nunca
# límite: 150
# gestor: cinnamon-applets
# Dos lanzadores del Dock de la prueba: «Lento» (abre xed a los 12 s) y «Launchpad» (igual de lento). El rebote se mide en la franja
# de abajo: la altura de lo dibujado cambia cuando el ícono sube.
alto_dibujado() {
  local f="$PRUEBAS_RES/$PRUEBAS_CASO-franja.png"
  import -display "$DISPLAY" -window root -crop "${PRUEBAS_ANCHO}x220+0+$((PRUEBAS_ALTO - 220))" +repage "$f"
  convert "$f" -fuzz 4% -trim -format '%h' info:
}
rango_alto() {   # rango_alto SEGUNDOS: máximo - mínimo de la altura dibujada
  local fin=$((SECONDS + $1)) mn=99999 mx=0 h
  while [ "$SECONDS" -lt "$fin" ]; do
    h="$(alto_dibujado)"; [ -n "$h" ] || continue
    [ "$h" -lt "$mn" ] && mn="$h"; [ "$h" -gt "$mx" ] && mx="$h"
  done
  echo "$((mx - mn))"
}
prueba() {
  requiere plank xed xdotool import convert
  local apps="$XDG_DATA_HOME/applications" lanz="$XDG_CONFIG_HOME/plank/dock1/launchers"
  mkdir -p "$apps" "$lanz"
  for n in lento launchpad; do
    printf '[Desktop Entry]\nType=Application\nName=%s\nExec=sh -c "sleep 12; exec xed"\nIcon=xed\n' "$n" > "$apps/$n.desktop"
    printf '[PlankDockItemPreferences]\nLauncher=file://%s/%s.desktop\n' "$apps" "$n" > "$lanz/$n.dockitem"
  done
  gsettings set net.launchpad.plank.dock.settings:/net/launchpad/plank/docks/dock1/ dock-items "['lento.dockitem', 'launchpad.dockitem']" 2>/dev/null || true
  lanzar plank
  esperar_ventana '^[Pp]lank$' 30 >/dev/null
  sleep 3
  local f="$PRUEBAS_RES/$PRUEBAS_CASO-franja.png" W H
  captura dock-lento-y-launchpad
  import -display "$DISPLAY" -window root -crop "${PRUEBAS_ANCHO}x220+0+$((PRUEBAS_ALTO - 220))" +repage "$f"
  read -r W H < <(convert "$f" -fuzz 4% -trim -format '%w %h\n' info:)
  [ "${W:-0}" -gt 60 ] || falla "el dock no dibujó nada"
  local geo; geo="$(convert "$f" -fuzz 4% -trim -format '%X %Y' info: | tr -d '+' )"
  paso "dock dibujado: ${W}×${H} ($geo)"
  # Primer ícono (Lento) = el de la izquierda del dibujo; el segundo (Launchpad) = el de la derecha.
  local x0 y0; read -r x0 y0 < <(convert "$f" -fuzz 4% -trim -format '%[fx:page.x] %[fx:page.y]\n' info: 2>/dev/null | tr -d '+')
  local y=$((PRUEBAS_ALTO - 220 + ${y0:-100} + H / 2))
  local x_lento=$((x0 + W / 4)) x_lp=$((x0 + 3 * W / 4))
  paso "clic en Lento ($x_lento,$y)"
  xdotool mousemove "$x_lento" "$y"; sleep 0.7; xdotool click 1
  xdotool mousemove 5 5   # la etiqueta que sale al pasar el ratón también cambia la altura dibujada
  local r; r="$(rango_alto 5)"
  paso "mientras abre, la altura dibujada varía $r px"
  [ "$r" -ge 8 ] || falla "Lento no rebotó mientras abría (varió $r px)"
  local x; x="$(esperar_ventana '^[Xx]ed$' 20)"
  sleep 2
  r="$(rango_alto 3)"
  paso "con la ventana abierta varía $r px"
  [ "$r" -le 3 ] || falla "siguió rebotando con la ventana ya abierta ($r px)"
  # (la urgencia —tres saltos cada 2 s— no se prueba aquí: llega por BAMF y esta sesión no la puede provocar; se mira en la pantalla real)
  cerrar_ventana "$x"; esperar_sin_ventana "$x" 10
  sleep 3
  paso "clic en Launchpad ($x_lp,$y)"
  xdotool mousemove "$x_lp" "$y"; sleep 0.7; xdotool click 1
  xdotool mousemove 5 5
  sleep 1
  r="$(rango_alto 6)"
  paso "con Launchpad la altura varía $r px"
  [ "$r" -le 3 ] || falla "Launchpad rebotó ($r px)"
}
