# caso: mac-launchpad-vala lista las apps instaladas (con Text Editor) y dibuja su cuadro a PNG de 1920×1200
# límite: 90
prueba() {
  requiere mac-launchpad-vala identify
  local lista="$PRUEBAS_RES/$PRUEBAS_CASO-lista.txt"
  mac-launchpad-vala --lista > "$lista" 2>&1 || falla "--lista terminó con error"
  paso "$(wc -l < "$lista") líneas"
  grep -qi "Text Editor" "$lista" || falla "la lista no trae Text Editor (xed): $(head -3 "$lista")"
  local png="$PRUEBAS_RES/$PRUEBAS_CASO-pagina.png"
  mac-launchpad-vala --png "$png" || falla "--png terminó con error"
  comprobar "es un PNG de 1920x1200" test "$(identify -format '%wx%h' "$png")" = "1920x1200"
}
