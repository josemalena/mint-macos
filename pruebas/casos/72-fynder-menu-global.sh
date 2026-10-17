# caso: con el menú global, Fynder publica por D-Bus la barra del Finder: el menú
# de la app y File, Edit, View, Go, Window, Help, con los ítems de Catalina
# límite: 60
prueba() {
  requiere fynder gdbus xprop
  gsettings set io.github.josemalena.fynder.preferences global-menu true
  local d="$HOME/Documents"
  mkdir -p "$d"
  lanzar fynder "$d"
  local v; v="$(esperar_ventana '[Ff]ynder' 30)"
  local bus ruta todo=""
  for _ in $(seq 50); do
    bus="$(xprop -id "$v" _GTK_UNIQUE_BUS_NAME 2>/dev/null | sed -n 's/.*= "\(.*\)"/\1/p')"
    ruta="$(xprop -id "$v" _GTK_MENUBAR_OBJECT_PATH 2>/dev/null | sed -n 's/.*= "\(.*\)"/\1/p')"
    if [ -n "$bus" ] && [ -n "$ruta" ]; then
      # los grupos 0 a 40 alcanzan para la barra y sus menús; sin los «_» de los mnemónicos
      todo="$(gdbus call --session --dest "$bus" --object-path "$ruta" --method org.gtk.Menus.Start \
               "[$(seq -s, 0 40)]" 2>/dev/null | tr -d '_' || true)"
      case "$todo" in *"'Window'"*) break ;; esac
    fi
    sleep 0.2
  done
  [ -n "$todo" ] || falla "la ventana no publica su barra (_GTK_MENUBAR_OBJECT_PATH)"
  local m
  for m in File Edit View Go Window Help "Show Clipboard" "Bring All to Front" "Customize Toolbar…" \
           "Merge All Windows" "Show View Options"; do
    case "$todo" in *"'$m'"*) paso "está «$m»" ;; *) falla "falta «$m» en el menú global" ;; esac
  done
  for m in "Select Items Matching..." "Invert Selection" "Extra Pane"; do
    case "$todo" in *"'$m'"*) falla "sobra «$m» (es de Nemo, no del Finder)" ;; *) paso "no está «$m»" ;; esac
  done
  cerrar_ventana "$v"
  esperar_sin_ventana "$v" 10
}
