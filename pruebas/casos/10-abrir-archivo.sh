# caso: abrir un archivo de texto: sale su ventana con el nombre en el título, y se cierra
# límite: 60
prueba() {
  requiere xed
  local f="$HOME/Documents/Notas de prueba.txt"
  mkdir -p "$(dirname "$f")"
  echo "hola desde la prueba" > "$f"
  lanzar xed "$f"
  local v; v="$(esperar_ventana '^[Xx]ed$' 20)"
  case "$(titulo "$v")" in
    *"Notas de prueba.txt"*) paso "el título nombra el archivo" ;;
    *) falla "el título no nombra el archivo: «$(titulo "$v")»" ;;
  esac
  captura abierto
  cerrar_ventana "$v"
  esperar_sin_ventana "$v" 10
}
