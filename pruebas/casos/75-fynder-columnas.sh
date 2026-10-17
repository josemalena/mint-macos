# caso: en la vista de columnas se ve la carpeta de arriba con sus hermanas, no
# solo el contenido de la actual
# límite: 60
prueba() {
  requiere fynder
  necesita_teclado
  local base="$HOME/Documents/Columnas"
  mkdir -p "$base/Actual" "$base/Hermana"
  echo x > "$base/Actual/dentro.txt"
  lanzar fynder "$base/Actual"
  local v; v="$(esperar_ventana '[Ff]ynder' 30)"
  esperar_texto "$v" "dentro.txt" 20
  # ⌘3 llega como Super+3 (keyd deja pasar ⌘1…4)
  teclas super+3
  esperar_texto "$v" "Hermana" 15
  captura columnas
  cerrar_ventana "$v"
  esperar_sin_ventana "$v" 10
}
