# caso: con el tema Samaná el menú Apple de Cinnamon sale con lo medido en Monterey (fondo #323232 / #ECECEC, esquinas de 6, fila de 22)
# límite: 240
# gestor: cinnamon-colgadas
# Se genera Samaná en una carpeta de la prueba (nunca en ~/.themes), se activa en el Cinnamon de la prueba y se abre el menú Apple con un clic.
prueba() {
  necesita_teclado
  requiere xdotool import convert python3 gsettings
  AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  local car="$PRUEBAS_HOME_REAL/.local/share/mint-macos/referencias/monterey-20261026/recursos/car"
  [ -d "$car" ] || saltar "no están los .car de Monterey (referencias/monterey-20261026)"
  local t="$XDG_DATA_HOME/themes"; mkdir -p "$t" "$XDG_DATA_HOME/plank-t"
  CATALOGOS_TEMA="$car" CONSTANZA_TEMAS="$t" CONSTANZA_PLANK="$XDG_DATA_HOME/plank-t" TEMA_BASE=Samana CONSTANZA_VARIANTES="Oscuro Claro" \
    "$AQUI/../tema/gtk/construir.sh" > "$PRUEBAS_RES/construir-samana.log" 2>&1 || falla "no se generó Samaná (construir-samana.log)"
  local variante
  for variante in Oscuro Claro; do
    gsettings set org.cinnamon.theme name "Samana-$variante"; sleep 4
    # los applets arman sus menús (y el separador, que depende del tema) al cargarse: se quitan y se vuelven a poner
    local aplets; aplets="$(gsettings get org.cinnamon enabled-applets)"
    gsettings set org.cinnamon enabled-applets "[]"; sleep 2
    gsettings set org.cinnamon enabled-applets "$aplets"; sleep 5
    xdotool mousemove 14 12; sleep 0.5; xdotool click 1; sleep 1.5
    captura "menu-apple-$variante"
    xdotool key Escape; sleep 1
  done
  # el fondo del menú: un píxel dentro de la caja, a la izquierda de los textos (la barra mide 22-25 px de alto)
  local f="$PRUEBAS_RES/$PRUEBAS_CASO-menu-apple-Oscuro.png" px
  px="$(convert "$f" -format '%[hex:p{12,60}]' info:)"
  paso "Oscuro: píxel del menú $px (esperado 323232)"
  [ "$px" = 323232 ] || falla "el menú oscuro no tiene el fondo #323232 de Monterey: $px"
  f="$PRUEBAS_RES/$PRUEBAS_CASO-menu-apple-Claro.png"
  px="$(convert "$f" -format '%[hex:p{12,60}]' info:)"
  paso "Claro: píxel del menú $px (esperado ECECEC)"
  [ "$px" = ECECEC ] || falla "el menú claro no tiene el fondo #ECECEC de Monterey: $px"
  true
}
