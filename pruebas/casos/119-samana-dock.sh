# caso: el Dock con el tema Samaná (Monterey) tiene una placa de ~79 px de alto con esquinas de 20 y el aro de 1 px (dock/INFORME.md)
# límite: 240
# Se genera Samaná en la prueba (nunca en ~/.local), se arranca Muelle con ese tema y 64 px de ícono, y se mide la placa en la captura.
prueba() {
  despejar_pantalla
  requiere muelle import convert python3
  export MUELLE_SIN_MIGRAR=1
  local aqui; aqui="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  local car="$PRUEBAS_HOME_REAL/.local/share/mint-macos/referencias/monterey-20261026/recursos/car"
  [ -d "$car" ] || saltar "no están los .car de Monterey (referencias/monterey-20261026)"
  local esq; esq="$(dirname "$(command -v muelle)")/../esquemas"
  [ -d "$esq" ] && export GSETTINGS_SCHEMA_DIR="$esq"
  mkdir -p "$XDG_DATA_HOME/themes" "$XDG_DATA_HOME/muelle/themes"
  CATALOGOS_TEMA="$car" CONSTANZA_TEMAS="$XDG_DATA_HOME/themes" CONSTANZA_PLANK="$XDG_DATA_HOME/muelle/themes" TEMA_BASE=Samana CONSTANZA_VARIANTES="Oscuro Claro" \
    "$aqui/../tema/gtk/construir.sh" > "$PRUEBAS_RES/construir-samana.log" 2>&1 || falla "no se generó Samaná (construir-samana.log)"
  local apps="$XDG_DATA_HOME/applications" lanz="$XDG_CONFIG_HOME/muelle/dock1/launchers" n lista=""
  rm -rf "$XDG_CONFIG_HOME/muelle"; dconf reset -f /org/mintmacos/muelle/ 2>/dev/null || true
  mkdir -p "$apps" "$lanz"
  for n in 1 2 3 4 5 6; do
    printf '[Desktop Entry]\nType=Application\nName=Ap%s\nExec=true\nIcon=xed\n' "$n" > "$apps/ap$n.desktop"
    printf '[PlankDockItemPreferences]\nLauncher=file://%s/ap%s.desktop\n' "$apps" "$n" > "$lanz/ap$n.dockitem"
    lista="$lista'ap$n.dockitem', "
  done
  dconf write /org/mintmacos/muelle/docks/dock1/dock-items "[${lista%, }]"
  dconf write /org/mintmacos/muelle/docks/dock1/icon-size 64
  local variante
  for variante in Oscuro Claro; do
    dconf write /org/mintmacos/muelle/docks/dock1/theme "'Samana-$variante'"
    for p in $(pgrep -x muelle); do grep -qz "^HOME=$HOME\$" "/proc/$p/environ" 2>/dev/null && kill "$p"; done
    sleep 2; lanzar muelle; esperar_ventana '^[Mm]uelle$' 30 >/dev/null; sleep 3
    xdotool mousemove 5 5 2>/dev/null; sleep 1
    captura "dock-$variante"
  done
  local f="$PRUEBAS_RES/$PRUEBAS_CASO-dock-Oscuro.png" alto
  # la placa: la caja de lo dibujado en la franja de abajo (el fondo de la prueba es liso)
  alto="$(convert "$f" -crop "${PRUEBAS_ANCHO}x200+0+$((PRUEBAS_ALTO - 200))" +repage -fuzz 3% -trim -format '%h' info:)"
  paso "alto de lo dibujado en el Dock oscuro: $alto px (placa de 79 + aro y sombra)"
  [ "$alto" -ge 70 ] || falla "la placa del Dock no se dibujó ($alto px)"
  true
}
