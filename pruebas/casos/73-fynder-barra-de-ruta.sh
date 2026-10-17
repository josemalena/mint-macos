# caso: con la barra de ruta encendida, se ven las carpetas de arriba de la actual
# límite: 60
prueba() {
  requiere fynder
  gsettings set io.github.josemalena.fynder.preferences finder-show-path-bar true
  local d="$HOME/Documents/Nivel uno/Nivel dos"
  mkdir -p "$d"
  echo x > "$d/aqui.txt"
  lanzar fynder "$d"
  local v; v="$(esperar_ventana '[Ff]ynder' 30)"
  esperar_texto "$v" "Nivel uno" 20
  esperar_texto "$v" "Nivel dos" 10
  captura ruta
  cerrar_ventana "$v"
  esperar_sin_ventana "$v" 10
}
