# caso: la barra de ⇧⌘5 (Vala): su botón Capture deja el archivo de Catalina en Desktop con la pantalla entera
# límite: 90
prueba() {
  requiere mac-captura-herramienta-vala xdotool identify
  [ "$PRUEBAS_REAL" != true ] || saltar "captura la pantalla entera: en la de José no se hace"
  mkdir -p "$HOME/Desktop"
  rm -f "$HOME/Desktop"/Screen\ Shot*
  # El HOME de prueba está vacío: modo «pantalla entera», destino Desktop, sin temporizador.
  lanzar mac-captura-herramienta-vala
  local b; b="$(esperar_ventana '[Mm]ac-captura-herramienta' 30)"
  [ "$(titulo "$b")" = "Screenshot" ] || falla "la barra no se llama Screenshot: «$(titulo "$b")»"
  sleep 1
  captura barra
  # El botón Capture es el último de la barra: se pulsa con el ratón (la barra es un dock y no toma el teclado).
  local X Y WIDTH HEIGHT
  eval "$(xdotool getwindowgeometry --shell "$b")"
  paso "barra: ${WIDTH}x${HEIGHT} en $X,$Y"
  xdotool mousemove $((X + WIDTH - 62)) $((Y + HEIGHT / 2)) click 1
  local f=""
  for _ in $(seq 100); do
    f="$(ls "$HOME/Desktop"/Screen\ Shot*.png 2>/dev/null | head -1 || true)"
    [ -n "$f" ] && break
    sleep 0.2
  done
  [ -n "$f" ] || falla "no salió ningún archivo «Screen Shot …png» en $HOME/Desktop"
  paso "archivo: $(basename "$f")"
  for _ in $(seq 50); do identify "$f" >/dev/null 2>&1 && break; sleep 0.2; done     # hasta que termine de escribirse
  comprobar "el nombre es el de la Mac" bash -c \
    '[[ "$(basename "$1")" =~ ^Screen\ Shot\ [0-9]{4}-[0-9]{2}-[0-9]{2}\ at\ [0-9]{1,2}\.[0-9]{2}\.[0-9]{2}\ (AM|PM)\.png$ ]]' _ "$f"
  comprobar "es la pantalla entera (1600x1200)" test "$(identify -format '%wx%h' "$f")" = "1600x1200"
}
