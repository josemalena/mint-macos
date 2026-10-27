# caso: la lupa del Muelle crece en lo que dice el perfil de macOS (entrada ~140 ms casi lineal, 2.0×, campana de ±6 anchos de ícono)
# límite: 200
# Se graba la franja del Dock a 60 cuadros por segundo mientras el puntero entra en el Dock, y se mide el alto del ícono de abajo del
# puntero por cuadro (ayudantes/medir-lupa.py); la medida se compara con el perfil de la prueba (los números del de Monterey).
prueba() {
  local aqui; aqui="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  despejar_pantalla
  requiere muelle xdotool ffmpeg convert
  export MUELLE_SIN_MIGRAR=1
  local esq; esq="$(dirname "$(command -v muelle)")/../esquemas"
  [ -d "$esq" ] && export GSETTINGS_SCHEMA_DIR="$esq"
  # El perfil de la prueba: lo medido en Monterey (referencias/animaciones-medidas/dock-lupa/INDICE.md)
  mkdir -p "$XDG_CONFIG_HOME/mint-macos" "$XDG_DATA_HOME/mint-macos/macos/prueba/apps"
  echo '{"version": "prueba"}' > "$XDG_CONFIG_HOME/mint-macos/macos.json"
  perfil_lupa() {   # perfil_lupa MS
    echo '{"id": "animaciones", "comportamiento": {"dock-lupa": {"rango_ms": "133-150", "factor_maximo": 2.0, "alcance_anchos": 6, "curva": "casi lineal", "ms": '"$1"'}}}' \
      > "$XDG_DATA_HOME/mint-macos/macos/prueba/apps/animaciones.json"
  }
  local apps="$XDG_DATA_HOME/applications" lanz="$XDG_CONFIG_HOME/muelle/dock1/launchers" n lista=""
  rm -rf "$XDG_CONFIG_HOME/muelle"; dconf reset -f /org/mintmacos/muelle/ 2>/dev/null || true
  mkdir -p "$apps" "$lanz"
  for n in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    printf '[Desktop Entry]\nType=Application\nName=Ap%s\nExec=true\nIcon=xed\n' "$n" > "$apps/ap$n.desktop"
    printf '[PlankDockItemPreferences]\nLauncher=file://%s/ap%s.desktop\n' "$apps" "$n" > "$lanz/ap$n.dockitem"
    lista="$lista'ap$n.dockitem', "
  done
  dconf write /org/mintmacos/muelle/docks/dock1/dock-items "[${lista%, }]"
  dconf write /org/mintmacos/muelle/docks/dock1/zoom-enabled true
  dconf write /org/mintmacos/muelle/docks/dock1/zoom-percent 200
  local franja_alto=400 W H X Y cx cy video ms dur geo
  for ms in 142 400; do
    perfil_lupa "$ms"
    # Muelle lee el perfil al arrancar: uno nuevo por cada duración
    for p in $(pgrep -x muelle); do grep -qz "^HOME=$HOME\$" "/proc/$p/environ" 2>/dev/null && kill "$p"; done
    sleep 1
    lanzar muelle
    esperar_ventana '^[Mm]uelle$' 30 >/dev/null
    sleep 3
    xdotool mousemove 5 5; sleep 1
    local f="$PRUEBAS_RES/$PRUEBAS_CASO-reposo.png"
    import -display "$DISPLAY" -window root -crop "${PRUEBAS_ANCHO}x${franja_alto}+0+$((PRUEBAS_ALTO - franja_alto))" +repage "$f"
    read -r W H X Y < <(convert "$f" -fuzz 4% -trim -format '%w %h %X %Y\n' info: | tr -d '+')
    [ "${W:-0}" -gt 200 ] || falla "el Dock no dibujó nada"
    cx=$((X + W / 2)); cy=$((PRUEBAS_ALTO - franja_alto + Y + H - 8)); video="$PRUEBAS_RES/$PRUEBAS_CASO-$ms.mkv"
    ffmpeg -loglevel error -y -f x11grab -framerate 60 -video_size "${PRUEBAS_ANCHO}x${franja_alto}" \
      -i "$DISPLAY+0,$((PRUEBAS_ALTO - franja_alto))" -c:v ffv1 -t 2.5 "$video" &
    local ff=$!
    sleep 0.8
    xdotool mousemove "$cx" "$cy"
    wait "$ff" || true
    dur="$(python3 -I "$aqui/ayudantes/medir-lupa.py" "$video" "$cx" | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["ms_hasta_98"])')"
    paso "perfil con $ms ms: el ícono tardó $dur ms en llegar al máximo"
    if [ "$ms" = 142 ]; then
      captura lupa-completa
      geo="$dur"
      # entre lo del perfil (142) y lo de antes (200 ms, easeOutCubic llega al 98 % a los ~146): un cuadro de error a cada lado
      [ "$dur" -ge 90 ] && [ "$dur" -le 190 ] || falla "con 142 ms en el perfil la lupa tardó $dur ms"
      # la campana: los íconos de las puntas (a 7 pasos del puntero) quedan en reposo y el del centro, al doble
      python3 -I "$aqui/ayudantes/medir-campana.py" "$PRUEBAS_RES/$PRUEBAS_CASO-lupa-completa.png" "$cx" || falla "la campana no es la medida"
    else
      [ "$dur" -ge $((geo + 150)) ] || falla "con 400 ms en el perfil la lupa tardó $dur ms: el perfil no manda"
    fi
    xdotool mousemove 5 5
  done
}
