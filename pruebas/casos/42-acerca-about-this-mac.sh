# caso: About This Mac/PC (mac-acerca) abre con el equipo real y cambia de pestaña
# límite: 90
prueba() {
  requiere mac-acerca xdotool
  local txt; txt="$(mac-acerca --texto 2>/dev/null)"
  paso "lo leído:"$'\n'"$txt"
  case "$txt" in *"menu: About This Mac"*|*"menu: About This PC"*) paso "la etiqueta del menú sale del equipo" ;; *) falla "sin etiqueta de menú" ;; esac
  case "$txt" in *"procesador: "?*) paso "hay procesador" ;; *) falla "no leyó el procesador" ;; esac
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
