# caso: el diálogo de Restart (mac-sesion --prueba) devuelve su JSON: Esc cancela, Enter confirma, y nada se ejecuta
# límite: 120
prueba() {
  necesita_teclado
  requiere mac-sesion wmctrl xdotool
  local log="$PRUEBAS_RES/$PRUEBAS_CASO-mac-sesion.log"
  for tecla in Escape Return; do
    : > "$log"
    lanzar mac-sesion --mode restart --prueba --print-json
    local v; v="$(esperar_ventana '[Mm]ac-sesion' 20)"
    wmctrl -i -a "$v"
    sleep 0.5
    teclas "$tecla"
    esperar_sin_ventana "$v" 10
    for _ in $(seq 25); do grep -q '"mode"' "$log" && break; sleep 0.2; done
    paso "$tecla → $(grep '"mode"' "$log" | head -1)"
    grep -q '"mode": "restart"' "$log" || falla "el JSON no dice mode restart"
    grep -q '"prueba": true' "$log" || falla "el JSON no dice prueba true"
    grep -q '"executed": false' "$log" || falla "se ejecutó algo en modo prueba"
    if [ "$tecla" = Escape ]; then
      grep -q '"confirmed": false' "$log" || falla "Esc no canceló"
    else
      grep -q '"confirmed": true' "$log" || falla "Enter no confirmó"
    fi
  done
}
