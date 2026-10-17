# caso: ⌘1 a ⌘4 pasan por las cuatro vistas sin que la ventana se caiga
# límite: 60
prueba() {
  requiere fynder
  necesita_teclado
  local d="$HOME/Documents/Vistas"
  mkdir -p "$d"
  echo x > "$d/Archivo de vistas.txt"
  lanzar fynder "$d"
  local v; v="$(esperar_ventana '[Ff]ynder' 30)"
  esperar_texto "$v" "Archivo de vistas.txt" 20
  local n
  for n in 2 3 4 1; do
    teclas "super+$n"
    sleep 1
    xdotool getwindowname "$v" >/dev/null 2>&1 || falla "la ventana se cayó en la vista $n"
    paso "vista $n viva"
  done
  esperar_texto "$v" "Archivo de vistas.txt" 10
  captura vistas
  cerrar_ventana "$v"
  esperar_sin_ventana "$v" 10
}
