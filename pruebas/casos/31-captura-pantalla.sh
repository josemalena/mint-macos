# caso: mac-captura pantalla deja «Screen Shot AAAA-MM-DD at H.MM.SS AM.png» en Desktop con la pantalla entera
# límite: 60
prueba() {
  requiere mac-captura gnome-screenshot identify
  mkdir -p "$HOME/Desktop"
  rm -f "$HOME/Desktop"/Screen\ Shot*
  lanzar mac-captura pantalla
  local f=""
  for _ in $(seq 100); do
    f="$(ls "$HOME/Desktop"/Screen\ Shot*.png 2>/dev/null | head -1 || true)"
    [ -n "$f" ] && break
    sleep 0.2
  done
  [ -n "$f" ] || falla "no salió ningún archivo «Screen Shot …png» en $HOME/Desktop"
  paso "archivo: $(basename "$f")"
  comprobar "el nombre es el de la Mac" bash -c \
    '[[ "$(basename "$1")" =~ ^Screen\ Shot\ [0-9]{4}-[0-9]{2}-[0-9]{2}\ at\ [0-9]{1,2}\.[0-9]{2}\.[0-9]{2}\ (AM|PM)\.png$ ]]' _ "$f"
  sleep 0.5       # que gnome-screenshot termine de escribirlo
  comprobar "es la pantalla entera (${PRUEBAS_ANCHO}x${PRUEBAS_ALTO})" test "$(identify -format '%wx%h' "$f")" = "${PRUEBAS_ANCHO}x${PRUEBAS_ALTO}"
}
