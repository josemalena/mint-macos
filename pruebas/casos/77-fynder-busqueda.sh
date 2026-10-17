# caso: ⌘F y escribir: «Searching "carpeta"», la barra This Mac | carpeta y el resultado
# límite: 90
prueba() {
  requiere fynder
  necesita_teclado
  local d="$HOME/Documents/Para buscar"
  mkdir -p "$d/sub"
  echo x > "$d/sub/Encontrame.txt"
  echo y > "$d/Otro.txt"
  lanzar fynder "$d"
  local v; v="$(esperar_ventana '[Ff]ynder' 30)"
  esperar_texto "$v" "Otro.txt" 20
  teclas ctrl+f
  xdotool type --delay 60 "Encontrame"
  local t=""
  for _ in $(seq 50); do
    t="$(titulo "$v")"
    case "$t" in "Searching"*"Para buscar"*) break ;; esac
    sleep 0.2
  done
  case "$t" in "Searching"*"Para buscar"*) paso "título de búsqueda" ;; *) falla "el título quedó «$t»" ;; esac
  esperar_texto "$v" "This Mac" 10
  esperar_texto "$v" "Encontrame.txt" 30
  captura busqueda
  cerrar_ventana "$v"
  esperar_sin_ventana "$v" 10
}
