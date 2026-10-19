# caso: Fynder sigue al tema: con uno claro el lateral y las barras se pintan claros (colores del tema) y con uno oscuro quedan como las capturas
# de Catalina (lateral #27282a)
# límite: 120
# moda VENTANA DY: el color que más se repite en una franja de 180 px desde el borde izquierdo de la ventana, a DY de
# arriba. Un solo punto fallaba: la X de una ventana CSD incluye la sombra y puede ser negativa (fuera de la pantalla),
# y más adentro cae en el texto de una fila (19-10-2026).
moda() {
  local X Y WIDTH HEIGHT x
  eval "$(xdotool getwindowgeometry --shell "$1")"
  x=$(( X < 0 ? 0 : X ))
  import -display "$DISPLAY" -window root -crop "180x1+$x+$((Y + $2))" +repage -depth 8 -format %c histogram:info:- |
    sort -rn | head -1 | grep -o '#[0-9A-Fa-f]\{6\}'
}
luz() { printf '%d' "$((16#${1:1:2} + 16#${1:3:2} + 16#${1:5:2}))"; }
prueba() {
  requiere fynder xdotool import
  gsettings set io.github.josemalena.fynder.preferences global-menu false 2>/dev/null || true
  local d="$HOME/Documents/Carpeta de prueba"
  mkdir -p "$d"
  echo uno > "$d/Primero.txt"
  for modo in "Adwaita" "Adwaita:dark"; do
    GTK_THEME="$modo" lanzar fynder "$d"
    local v; v="$(esperar_ventana '[Ff]ynder' 30)"
    esperar_texto "$v" "Primero.txt" 20
    sleep 3   # el tema claro se aplica 200 ms después de leer el tema
    captura "fynder-$modo"
    local X Y WIDTH HEIGHT
    eval "$(xdotool getwindowgeometry --shell "$v")"
    local lateral; lateral="$(moda "$v" $((HEIGHT / 2)))"
    paso "con $modo el lateral es $lateral (ventana ${WIDTH}x${HEIGHT})"
    if [ "$modo" = "Adwaita" ]; then
      [ "$(luz "$lateral")" -gt 600 ] || falla "con un tema claro el lateral sigue oscuro ($lateral)"
    else
      [ "$lateral" = "#27282A" ] || [ "$lateral" = "#27282a" ] || falla "con un tema oscuro el lateral ya no es el de Catalina #27282a ($lateral)"
    fi
    cerrar_ventana "$v"
    esperar_sin_ventana "$v" 10
  done
}
