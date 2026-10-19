# caso: Plank arranca como dock abajo y, al abrirse una app, su dock crece con el ícono nuevo
# límite: 120
# El dock de Plank es una ventana del ancho de la pantalla, transparente: lo que crece es lo que dibuja. Se mide
# recortando la franja de abajo de la pantalla y quitándole el fondo (-trim); xed abre arriba, lejos de esa franja.
ancho_dibujado() {
  local f="$PRUEBAS_RES/$PRUEBAS_CASO-franja.png"
  import -display "$DISPLAY" -window root -crop "${PRUEBAS_ANCHO}x200+0+$((PRUEBAS_ALTO - 200))" +repage "$f"
  convert "$f" -fuzz 4% -trim -format '%w' info:
}
prueba() {
  requiere muelle xed xdotool import convert
  lanzar muelle
  local d; d="$(esperar_ventana '^[Mm]uelle$' 30)"
  local X Y WIDTH HEIGHT
  eval "$(xdotool getwindowgeometry --shell "$d")"
  [ "$Y" -gt 600 ] || falla "el dock no está abajo de la pantalla (y=$Y)"
  sleep 3        # que arme sus lanzadores
  local antes; antes="$(ancho_dibujado)"
  paso "el dock dibuja ${antes}px de ancho"
  [ "$antes" -gt 100 ] || falla "el dock no dibujó nada (${antes}px)"
  captura dock-solo

  lanzar xed
  local x; x="$(esperar_ventana '^[Xx]ed$' 20)"
  local despues="$antes"
  for _ in $(seq 100); do
    despues="$(ancho_dibujado)"
    [ "$despues" -gt "$antes" ] && break
    sleep 0.2
  done
  captura dock-con-xed
  [ "$despues" -gt "$antes" ] || falla "el dock no creció al abrir xed (sigue en ${antes}px)"
  paso "el dock creció: ${antes} → ${despues}px"
  cerrar_ventana "$x"
  esperar_sin_ventana "$x" 10
}
