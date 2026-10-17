# caso: Fynder abre una carpeta: la ventana lleva su nombre y se ven sus archivos
# límite: 60
prueba() {
  requiere fynder
  local d="$HOME/Documents/Carpeta de prueba"
  mkdir -p "$d"
  echo uno > "$d/Primero.txt"
  echo dos > "$d/Segundo.md"
  lanzar fynder "$d"
  local v; v="$(esperar_ventana '[Ff]ynder' 30)"
  case "$(titulo "$v")" in
    "Carpeta de prueba"*) paso "el título es la carpeta" ;;
    *) falla "el título no es la carpeta: «$(titulo "$v")»" ;;
  esac
  esperar_texto "$v" "Primero.txt" 20
  esperar_texto "$v" "Segundo.md" 10
  captura abierta
  cerrar_ventana "$v"
  esperar_sin_ventana "$v" 10
}
