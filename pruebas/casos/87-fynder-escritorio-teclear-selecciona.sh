# caso: en el escritorio de Fynder, teclear selecciona el icono que empieza con lo escrito (como el Finder), sin abrir el cuadro de búsqueda de Nemo
# límite: 120
# gestor: cinnamon-applets
prueba() {
  requiere fynder-desktop xdotool import compare identify
  gsettings set io.github.josemalena.fynder.preferences global-menu false 2>/dev/null || true
  mkdir -p "$HOME/Desktop"
  for n in Alfa Beta Bravo Zeta; do echo x > "$HOME/Desktop/$n.txt"; done
  lanzar fynder-desktop
  sleep 8
  # foco en el escritorio, sin tocar ningún icono: el clic va abajo, a la izquierda de la columna de iconos, y antes se le da
  # el foco a la ventana del escritorio (el 19-10-2026 una ventana de otro caso tapaba (300,400) y «br» se tecleó en ella)
  local SW SH; read -r SW SH < <(xdotool getdisplaygeometry)
  # con set -e y pipefail, un search sin resultado o un foco rechazado cortaban el caso sin motivo (19-10-2026)
  local esc; esc="$(xdotool search --class nemo-desktop 2>/dev/null | head -1 || true)"
  if [ -n "$esc" ]; then xdotool windowfocus --sync "$esc" 2>/dev/null || true; fi
  xdotool mousemove $((SW - 400)) $((SH - 100)) click 1; sleep 1
  local antes="$PRUEBAS_RES/$PRUEBAS_CASO-antes.png" despues="$PRUEBAS_RES/$PRUEBAS_CASO-despues.png"
  import -display "$DISPLAY" -window root "$antes"
  xdotool type --delay 150 "br"; sleep 1.5
  import -display "$DISPLAY" -window root "$despues"
  captura escritorio-con-br
  local cambio; cambio="$(compare -metric AE "$antes" "$despues" null: 2>&1 || true)"
  # el cuadro de búsqueda de Nemo salía abajo a la derecha: esa esquina no debe cambiar
  local W H; read -r W H < <(identify -format '%w %h\n' "$antes")
  local esquina; esquina="$(compare -metric AE -extract "300x80+$((W - 300))+$((H - 80))" "$antes" "$despues" null: 2>&1 || true)"
  paso "píxeles distintos tras teclear «br»: ${cambio%% *}; en la esquina del cuadro de búsqueda: ${esquina%% *}"
  [ "${cambio%% *}" -gt 200 ] || falla "teclear no seleccionó ningún icono (cambiaron ${cambio%% *} píxeles)"
  [ "${esquina%% *}" -eq 0 ] || falla "apareció el cuadro de búsqueda de Nemo (cambiaron ${esquina%% *} píxeles en su esquina)"
}
