# caso: «mac-ventanas acerca» le pide About This Mac/PC al residente y cambia de pestaña sin abrir otra ventana
# límite: 90
prueba() {
  requiere mac-ventanas xdotool
  lanzar mac-ventanas --residente
  sleep 2
  mac-ventanas acerca >/dev/null 2>&1
  local w; w="$(esperar_ventana '[Mm]ac-ventanas' 30)"
  sleep 1
  paso "ventana: «$(titulo "$w")»"
  case "$(titulo "$w")" in "About This Mac"|"About This PC") ;; *) falla "el título no es About This Mac/PC: «$(titulo "$w")»" ;; esac
  local X Y WIDTH HEIGHT
  eval "$(xdotool getwindowgeometry --shell "$w")"; local alto1=$HEIGHT
  mac-ventanas acerca --pestana storage >/dev/null 2>&1
  sleep 1
  eval "$(xdotool getwindowgeometry --shell "$w")"
  comprobar "la pestaña Storage cambia el alto de la ventana" test "$HEIGHT" -ne "$alto1"
  [ "$(xdotool search --onlyvisible --class '[Mm]ac-ventanas' | wc -l)" = 1 ] || falla "salió más de una ventana"
  captura acerca-residente
}
