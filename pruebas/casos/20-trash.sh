# caso: mandar un archivo a la Trash y verlo en la ventana Trash de Fynder
# límite: 90
prueba() {
  requiere gio fynder
  local f="$HOME/Desktop/para la Trash.txt"
  mkdir -p "$(dirname "$f")"
  echo "se va a la Trash" > "$f"
  gio trash "$f"
  comprobar "el archivo ya no está en Desktop" test ! -e "$f"
  comprobar "está en la Trash del usuario" test -f "$XDG_DATA_HOME/Trash/files/para la Trash.txt"
  comprobar "la Trash recuerda de dónde vino" \
    grep -qx "Path=$(printf '%s' "$f" | sed 's/ /%20/g')" "$XDG_DATA_HOME/Trash/info/para la Trash.txt.trashinfo"

  lanzar fynder trash:///
  local v; v="$(esperar_ventana '[Ff]ynder|[Nn]emo' 30)"
  case "$(titulo "$v")" in
    Trash*|*Papelera*) paso "la ventana es la Trash" ;;
    *) falla "la ventana no es la Trash: «$(titulo "$v")»" ;;
  esac
  esperar_texto "$v" "para la Trash.txt" 20
  captura trash
  cerrar_ventana "$v"
  esperar_sin_ventana "$v" 10
}
