# caso: en la ficha de una app, Get la instala con el progreso del motor y el botón pasa a Open; Remove la quita y vuelve Get.
# Contra un motor de mentira (pruebas/ayudantes/tienda-falsa.py): no se instala nada de verdad.
# límite: 120
prueba() {
  requiere mac-tienda xdotool python3
  local reg="$HOME/tienda-falsa.registro"; : > "$reg"
  lanzar python3 "$MINT_MACOS_REPO/pruebas/ayudantes/tienda-falsa.py" "$reg"
  sleep 1
  lanzar mac-tienda --ficha "fake:app"
  local w; w="$(esperar_ventana '[Mm]ac-tienda' 30)"
  esperar_texto "$w" "Fake App" 20
  esperar_texto "$w" "Get" 10
  captura tienda-ficha-get
  pulsar "$w" "Get" 10
  esperar_texto "$w" "Open" 20
  grep -q "Instalar" "$reg" || falla "el motor no recibió Instalar: $(cat "$reg")"
  captura tienda-ficha-open
  pulsar "$w" "Remove" 10
  esperar_texto "$w" "Get" 20
  grep -q "Quitar" "$reg" || falla "el motor no recibió Quitar: $(cat "$reg")"
  captura tienda-ficha-quitada
}
