# caso: ⌘I sobre un archivo abre su ventana Info («nombre Info») con el nombre adentro
# límite: 60
prueba() {
  requiere fynder
  necesita_teclado
  local d="$HOME/Documents/Info de prueba"
  mkdir -p "$d"
  echo "para Get Info" > "$d/Ficha.txt"
  lanzar fynder "$d"
  local v; v="$(esperar_ventana '[Ff]ynder' 30)"
  esperar_texto "$v" "Ficha.txt" 20
  # el primer ítem queda escogido al bajar; ⌘I (Fynder toma Ctrl como ⌘)
  teclas Down ctrl+i
  local info=""
  for _ in $(seq 50); do
    info="$(xdotool search --onlyvisible --name '^Ficha\.txt Info$' 2>/dev/null | tail -1 || true)"
    [ -n "$info" ] && break
    sleep 0.2
  done
  [ -n "$info" ] || falla "no salió la ventana «Ficha.txt Info»"
  paso "ventana Info: $info"
  captura info
  cerrar_ventana "$info"
  esperar_sin_ventana "$info" 10
  cerrar_ventana "$v"
  esperar_sin_ventana "$v" 10
}
