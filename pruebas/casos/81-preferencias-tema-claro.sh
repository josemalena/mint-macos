# caso: System Preferences sigue al tema: con uno claro la ventana se pinta clara (catalina-claro.css) y con uno oscuro, oscura
# límite: 90
fondo_de() {   # fondo_de VENTANA: el color de un punto del fondo de la ventana (abajo a la izquierda, dentro de la ventana (el cliente trae la sombra))
  local X Y WIDTH HEIGHT
  eval "$(xdotool getwindowgeometry --shell "$1")"
  paso "geometría: ${X},${Y} ${WIDTH}x${HEIGHT}"
  import -display "$DISPLAY" -window root -crop "1x1+$((X + 60))+$((Y + HEIGHT - 70))" +repage -depth 8 txt:- | tail -1 | grep -o '#[0-9A-Fa-f]\{6\}'
}
luz() { printf '%d' "$((16#${1:1:2} + 16#${1:3:2} + 16#${1:5:2}))"; }
# Cierra, por pid, los mac-preferencias de ESTA prueba (los que llevan el HOME de la prueba en su entorno): el de la sesión de José
# tiene otro HOME y no se toca.
soltar_residentes_de_la_prueba() {
  local pid
  for pid in $(pgrep -u "$(id -u)" -x mac-preferencia); do   # comm se corta a 15 letras
    if tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | grep -qx "HOME=$HOME"; then paso "cierro el residente $pid de la prueba"; kill "$pid" 2>/dev/null || true; fi
  done
  sleep 1
}
prueba() {
  requiere mac-preferencias xdotool import
  export MP_PYTHON_DIR="$MINT_MACOS_REPO/settings"
  for modo in "Adwaita" "Adwaita:dark"; do
    soltar_residentes_de_la_prueba
    GTK_THEME="$modo" lanzar mac-preferencias
    local v; v="$(esperar_ventana '[Mm]ac-settings' 40)"
    mac-preferencias general
    for _ in $(seq 50); do [ "$(titulo "$v")" = "General" ] && break; sleep 0.2; done
    sleep 2
    local c; c="$(fondo_de "$v")"
    paso "con $modo el fondo es $c"
    captura "tema-$modo"
    if [ "$modo" = "Adwaita" ]; then
      [ "$(luz "$c")" -gt 600 ] || falla "con un tema claro la ventana sigue oscura ($c)"
    else
      [ "$(luz "$c")" -lt 250 ] || falla "con un tema oscuro la ventana no es oscura ($c)"
    fi
  done
}
