# caso: los menús File y Go del menú global salen como en el Finder de Catalina
# (capturas 02-barra-menu-file-submenu y 02-barra-menu-go-abierto)
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
  for m in "New Finder Window" "New Folder with Selection" "New Smart Folder" "Print" "Close Window" \
           "Make Alias" "Show Original" "Add to Sidebar" "Eject" "Find" "Tags…" \
           "Enclosing Folder" "Recents" "iCloud Drive" "Recent Folders" "Go to Folder…" "Connect to Server…"; do
    case "$todo" in *"'$m'"*) paso "está «$m»" ;; *) falla "falta «$m»" ;; esac
  done
  for m in "Add Bookmark" "Close All Windows" "Create New Document" "Same Location as Other Pane" "Templates"; do
    case "$todo" in *"'$m'"*) falla "sobra «$m» (es de Nemo)" ;; *) paso "no está «$m»" ;; esac
  done
  cerrar_ventana "$v"
  esperar_sin_ventana "$v" 10
}
