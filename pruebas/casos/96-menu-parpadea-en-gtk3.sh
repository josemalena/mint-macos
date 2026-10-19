# caso: con el módulo GTK3 (GTK_MODULES) un menú de una app GTK3 cualquiera parpadea al escoger un ítem, con el teclado y con el ratón; el ítem
# se activa después del parpadeo y no antes; un ítem con submenú no parpadea; apagado no cambia nada
# límite: 150
parpadeos() {   # parpadeos NOMBRE CAJA TECLA_O_CLIC: graba la pantalla, escoge y cuenta
  local video="$PRUEBAS_RES/$PRUEBAS_CASO-$1.mkv" carpeta="$PRUEBAS_RES/$PRUEBAS_CASO-$1-cuadros" aqui; aqui="$(dirname "$PRUEBAS_LIB")"
  rm -rf "$carpeta"; mkdir -p "$carpeta"
  ffmpeg -loglevel error -y -f x11grab -framerate 30 -video_size "${PRUEBAS_ANCHO}x${PRUEBAS_ALTO}" -t 2.2 -i "$DISPLAY" "$video" &
  local ff=$!
  sleep 0.6
  date +%s.%N > "$PRUEBAS_RES/$PRUEBAS_CASO-pulsado.txt"
  if [ "$3" = tecla ]; then xdotool key Return; else xdotool click 1; fi
  wait "$ff"
  ffmpeg -loglevel error -y -i "$video" "$carpeta/%03d.png"
  python3 "$aqui/ayudantes/contar-parpadeos.py" "$carpeta" "$2"
}
prueba() {
  necesita_teclado
  requiere xdotool ffmpeg import python3
  local aqui; aqui="$(dirname "$PRUEBAS_LIB")"
  local modulo="${MINT_MACOS_MODULO_MENU:-}"
  [ -n "$modulo" ] || modulo="$(command -v libmint-macos-menu-flash.so 2>/dev/null || true)"
  [ -n "$modulo" ] && [ -f "$modulo" ] || modulo="$MINT_MACOS_REPO/nativo/build/gtkmenu-flash/libmint-macos-menu-flash.so"
  [ -f "$modulo" ] || salta "no está compilado el módulo del parpadeo"
  mkdir -p "$XDG_DATA_HOME/glib-2.0/schemas"
  cp "$MINT_MACOS_REPO/menus/org.mintmacos.menus.gschema.xml" "$XDG_DATA_HOME/glib-2.0/schemas/"
  glib-compile-schemas "$XDG_DATA_HOME/glib-2.0/schemas"
  export GSETTINGS_SCHEMA_DIR="$XDG_DATA_HOME/glib-2.0/schemas${GSETTINGS_SCHEMA_DIR:+:$GSETTINGS_SCHEMA_DIR}"
  gsettings set org.mintmacos.menus flash-count 2
  gsettings set org.mintmacos.menus flash-duration-ms 150
  local salida="$PRUEBAS_RES/$PRUEBAS_CASO-activaciones.txt"
  rm -f "$salida"
  GTK_MODULES="$modulo" lanzar python3 "$aqui/ayudantes/app-menu-prueba.py" "$salida"
  local v; v="$(esperar_ventana 'menu-prueba|python3' 20)"
  sleep 1
  xdotool mousemove 160 120; sleep 0.3

  local modo caja n t0
  for modo in true false; do
    gsettings set org.mintmacos.menus menu-flash "$modo"
    for via in tecla clic; do
      xdotool mousemove 160 100; xdotool click 1; sleep 1          # abre el menú con el botón
      xdotool key Down; sleep 0.3
      captura "menu-$modo-$via-sin"
      xdotool key Down; sleep 0.5
      captura "menu-$modo-$via-con"
      caja="$(python3 "$aqui/ayudantes/item-resaltado.py" "$PRUEBAS_RES/$PRUEBAS_CASO-menu-$modo-$via-sin.png" "$PRUEBAS_RES/$PRUEBAS_CASO-menu-$modo-$via-con.png")"
      paso "con menu-flash=$modo y $via: ítem en $caja"
      if [ "$via" = clic ]; then
        # El ratón sobre el ítem escogido
        local cx cy; cx="$(echo "$caja" | cut -d, -f1)"; cy="$(echo "$caja" | cut -d, -f2)"
        xdotool mousemove $((cx + 20)) $((cy + 6)); sleep 0.4
      fi
      rm -f "$salida"
      n="$(parpadeos "$modo-$via" "$caja" "$via")"
      paso "con menu-flash=$modo y $via el resaltado se apagó $n vez/veces"
      if [ "$modo" = true ]; then
        [ "$n" -ge 1 ] || falla "con menu-flash encendido ($via) el ítem no parpadeó"
      else
        [ "$n" -eq 0 ] || falla "con menu-flash apagado ($via) el ítem parpadeó ($n)"
      fi
      sleep 1
      [ -s "$salida" ] || falla "el ítem no se activó ($modo, $via)"
      paso "el ítem se activó: $(head -1 "$salida")"
      # Con parpadeo la acción llega después de 2 parpadeos de 150 ms (≥ 0.5 s); sin él, enseguida
      local demora; demora="$(python3 -c "
import sys
p = float(open('$PRUEBAS_RES/$PRUEBAS_CASO-pulsado.txt').read())
a = float(open('$salida').read().split()[1])
print('%.2f' % (a - p))")"
      paso "la acción llegó $demora s después de escoger"
      if [ "$modo" = true ]; then
        python3 -c "import sys; sys.exit(0 if $demora >= 0.5 else 1)" || falla "con menu-flash encendido la acción llegó demasiado pronto ($demora s): no esperó al parpadeo"
      else
        python3 -c "import sys; sys.exit(0 if $demora < 0.3 else 1)" || falla "con menu-flash apagado la acción tardó $demora s"
      fi
      xdotool key Escape; sleep 0.5
    done
  done
}
