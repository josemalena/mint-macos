# caso: Force Quit sigue al tema: cuerpo claro (#E9E9E9 de la Catalina clara) con un tema claro y oscuro (#2A2B2D) con uno oscuro
# límite: 90
luz_en() {   # luz_en VENTANA DX DY: la suma R+G+B del punto (X+DX, Y+DY)
  local X Y WIDTH HEIGHT c
  eval "$(xdotool getwindowgeometry --shell "$1")"
  c="$(import -display "$DISPLAY" -window root -crop "1x1+$((X + $2))+$((Y + $3))" +repage -depth 8 txt:- | tail -1 | grep -o '#[0-9A-Fa-f]\{6\}')"
  printf '%d' "$((16#${c:1:2} + 16#${c:3:2} + 16#${c:5:2}))"
}
prueba() {
  requiere mac-forcequit xdotool import
  local modo v luz
  for modo in Adwaita Adwaita:dark; do
    GTK_THEME="$modo" lanzar mac-forcequit
    v="$(esperar_ventana '[Mm]ac-forcequit' 30)"
    sleep 3    # el tema claro se aplica unos 250 ms después de leer el tema
    local X Y WIDTH HEIGHT; eval "$(xdotool getwindowgeometry --shell "$v")"
    luz="$(luz_en "$v" 60 $((HEIGHT - 70)))"
    paso "con $modo el cuerpo de Force Quit suma $luz (R+G+B)"
    captura "forcequit-$modo"
    kill "$(xdotool getwindowpid "$v")"; sleep 1
    case "$modo" in
      Adwaita) [ "$luz" -gt 600 ] || falla "con un tema claro el cuerpo de Force Quit sigue oscuro ($luz)" ;;
      *) [ "$luz" -lt 300 ] || falla "con un tema oscuro el cuerpo de Force Quit no es oscuro ($luz)" ;;
    esac
  done
}
