# caso: una .app de Mac (sin .desktop) que empieza a abrir sale ya en el Muelle con su ícono saltando; al salir su ventana el ícono deja de saltar (el ítem de la ventana real lo reemplaza)
# límite: 150
# gestor: cinnamon-applets
# mint-macos-arranque manda el aviso de startup-notification («new:» con NAME, ICON y WMCLASS darling-…) que el Muelle muestra como un ítem que
# rebota; ventana-darling.py hace de la ventana de la app. Se mide en la franja de abajo: el ancho dibujado crece con el ítem nuevo y la altura
# cambia mientras rebota.
dibujado() {   # dibujado ANCHOxALTO de lo dibujado en la franja del Dock
  local f="$PRUEBAS_RES/$PRUEBAS_CASO-franja.png"
  import -display "$DISPLAY" -window root -crop "${PRUEBAS_ANCHO}x220+0+$((PRUEBAS_ALTO - 220))" +repage "$f"
  convert "$f" -fuzz 4% -trim -format '%w %h' info:
}
rango_alto() {   # rango_alto SEGUNDOS: máximo - mínimo de la altura dibujada
  local fin=$((SECONDS + $1)) mn=99999 mx=0 w h
  while [ "$SECONDS" -lt "$fin" ]; do
    read -r w h < <(dibujado) || true; [ -n "${h:-}" ] || continue
    [ "$h" -lt "$mn" ] && mn="$h"; [ "$h" -gt "$mx" ] && mx="$h"
  done
  echo "$((mx - mn))"
}
prueba() {
  local aqui; aqui="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  despejar_pantalla
  requiere muelle mint-macos-arranque xdotool convert import python3
  export MUELLE_SIN_MIGRAR=1
  local esq; esq="$(dirname "$(command -v muelle)")/../esquemas"
  [ -d "$esq" ] && export GSETTINGS_SCHEMA_DIR="$esq"
  local apps="$XDG_DATA_HOME/applications" lanz="$XDG_CONFIG_HOME/muelle/dock1/launchers"
  rm -rf "$XDG_CONFIG_HOME/muelle"; dconf reset -f /org/mintmacos/muelle/ 2>/dev/null || true
  mkdir -p "$apps" "$lanz"
  printf '[Desktop Entry]\nType=Application\nName=Fijo\nExec=true\nIcon=xed\n' > "$apps/fijo.desktop"
  printf '[PlankDockItemPreferences]\nLauncher=file://%s/fijo.desktop\n' "$apps" > "$lanz/fijo.dockitem"
  dconf write /org/mintmacos/muelle/docks/dock1/dock-items "['fijo.dockitem']"
  dconf write /org/mintmacos/muelle/docks/dock1/zoom-enabled false
  convert -size 64x64 xc:'#cc2222' "$PRUEBAS_RES/icono-app.png"
  lanzar muelle
  esperar_ventana '^[Mm]uelle$' 30 >/dev/null
  sleep 3
  xdotool mousemove 5 5; sleep 1
  local w0 h0 w1 h1 w2 h2 reposo bota
  read -r w0 h0 < <(dibujado) || true
  paso "Dock en reposo: ${w0}x${h0}"
  reposo="$(rango_alto 3)"
  [ "$reposo" -le 4 ] || falla "el Dock se mueve en reposo ($reposo px)"

  # empieza a abrir una app de Mac: el aviso sale ya, la ventana tarda
  lanzar mint-macos-arranque --nombre TextEdit --clase darling-com.apple.textedit --icono "$PRUEBAS_RES/icono-app.png" --max-segundos 100
  sleep 1.5
  read -r w1 h1 < <(dibujado) || true
  paso "con el aviso de arranque: ${w1}x${h1}"
  captura app-abriendo
  bota="$(rango_alto 4)"
  paso "mientras abre, la altura dibujada varía $bota px"
  [ "$bota" -ge 10 ] || falla "el ícono no salta mientras abre ($bota px)"

  # sale su ventana: el rebote y el ítem del aviso se van
  lanzar python3 -I "$aqui/ayudantes/ventana-darling.py" TextEdit com.apple.TextEdit
  esperar_ventana '^darling-com.apple.textedit$' 30 >/dev/null
  sleep 2
  xdotool mousemove 5 5; sleep 1
  local reposo2; reposo2="$(rango_alto 3)"
  captura app-abierta
  read -r w2 h2 < <(dibujado) || true
  paso "ya abierta: ${w2}x${h2}; la altura varía $reposo2 px"
  [ "$reposo2" -le 6 ] || falla "el ícono sigue saltando con la ventana ya abierta ($reposo2 px)"
}
