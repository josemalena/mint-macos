# caso: About This Mac/PC (mac-acerca) abre con el equipo real y cambia de pestaña
# límite: 90
prueba() {
  requiere mac-acerca xdotool
  # Un equipo.json de prueba con todos los campos de hardware (los del servicio mint-macos-equipo).
  export MINT_MACOS_EQUIPO="$HOME/equipo-prueba.json"
  cat > "$MINT_MACOS_EQUIPO" <<'JSON'
{"version":1,"tipo":"mac","nombre":"Mac mini (Late 2012)","serie":"C0FAKE000000",
 "sistema":{"id":"linuxmint","nombre":"Linux Mint","version":"22.3 (Zena)","texto":"Linux Mint 22.3"},
 "logo":"/usr/share/icons/hicolor/scalable/apps/linuxmint-logo.svg",
 "procesador":{"modelo":"x","ghz":2.5,"nucleos":2,"texto":"2.5 GHz Dual-Core Intel Core i5"},
 "memoria":{"total":17179869184,"tipo":"DDR3","velocidad":1600,"modulos":2,"texto":"16 GB 1600 MHz DDR3","fuente":"smbios"},
 "graficos":[{"pci":"00:02.0","fabricante":"Intel","modelo":"HD Graphics 4000","texto":"Intel HD Graphics 4000 1536 MB"}]}
JSON
  local txt; txt="$(mac-acerca --texto 2>/dev/null)"
  paso "lo leído:"$'\n'"$txt"
  case "$txt" in *"menu: About This Mac"*|*"menu: About This PC"*) paso "la etiqueta del menú sale del equipo" ;; *) falla "sin etiqueta de menú" ;; esac
  case "$txt" in *"procesador: 2.5 GHz Dual-Core Intel Core i5"*) paso "el procesador sale del json" ;; *) falla "no leyó el procesador del json" ;; esac
  case "$txt" in *"memoria: 16 GB 1600 MHz DDR3"*) paso "la memoria sale del json" ;; *) falla "no leyó la memoria del json" ;; esac
  case "$txt" in *"serie: C0FAKE000000"*) paso "la serie sale del json" ;; *) falla "no leyó la serie del json" ;; esac
  case "$txt" in *"volumen: "?*) paso "hay volúmenes" ;; *) falla "no leyó ningún volumen" ;; esac
  lanzar mac-acerca
  local w; w="$(esperar_ventana '[Mm]ac-acerca' 30)"
  sleep 1
  captura acerca-overview
  local X Y WIDTH HEIGHT
  eval "$(xdotool getwindowgeometry --shell "$w")"
  local alto1=$HEIGHT
  paso "overview: ${WIDTH}x${HEIGHT}"
  mac-acerca --pestana displays >/dev/null 2>&1
  sleep 1
  captura acerca-displays
  eval "$(xdotool getwindowgeometry --shell "$w")"
  paso "displays: ${WIDTH}x${HEIGHT}"
  comprobar "la pestaña Displays cambia el alto de la ventana" test "$HEIGHT" -ne "$alto1"
  mac-acerca --pestana storage >/dev/null 2>&1
  sleep 1
  captura acerca-storage
}
