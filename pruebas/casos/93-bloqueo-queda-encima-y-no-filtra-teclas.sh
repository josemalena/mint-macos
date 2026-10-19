# caso: con Cinnamon real, la pantalla de bloqueo queda encima de todo aunque llegue una notificación, y lo que se teclea con ella puesta
# no llega a la app que estaba al frente (PAM de mentira: LD_PRELOAD de pam-falso.c)
# gestor: cinnamon-colgadas
# límite: 150
prueba() {
  necesita_teclado
  requiere mac-bloqueo xed xdotool gcc notify-send xclip wmctrl
  local aqui; aqui="$(dirname "$PRUEBAS_LIB")"
  gcc -shared -fPIC -o "$PRUEBAS_RES/pam-falso.so" "$aqui/ayudantes/pam-falso.c" || falla "no pude compilar el PAM de mentira"
  local x; lanzar xed; x="$(esperar_ventana '^[Xx]ed$' 20)"
  wmctrl -i -a "$x"; sleep 1
  xdotool type --delay 60 "antes"; sleep 1

  LD_PRELOAD="$PRUEBAS_RES/pam-falso.so" lanzar mac-bloqueo
  local pant=""
  for _ in $(seq 60); do
    for p in $(pgrep -x mac-bloqueo); do tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null | grep -q -- '--pantalla' && pant="$p"; done
    [ -n "$pant" ] && break; sleep 0.2
  done
  [ -n "$pant" ] || falla "no arrancó la pantalla de bloqueo"
  sleep 3

  # Lo que se teclea ahora es de la pantalla de bloqueo, no de xed
  xdotool type --delay 60 "secreto"; xdotool key Return; sleep 1
  paso "tecleé «secreto» con el bloqueo puesto"

  # Una notificación nueva no puede quedar encima
  notify-send "Aviso de prueba" "esto no debe taparse" ; sleep 3
  local arriba; arriba="$(python3 "$aqui/ayudantes/ventana-de-arriba.py")"
  paso "la ventana de más arriba es del pid $arriba (la pantalla es $pant)"
  [ "$arriba" = "$pant" ] || falla "algo quedó encima de la pantalla de bloqueo (pid $arriba)"
  captura bloqueo-con-notificacion

  xdotool type --delay 60 "buena"; xdotool key Return
  for _ in $(seq 50); do pgrep -x mac-bloqueo >/dev/null || break; sleep 0.2; done
  pgrep -x mac-bloqueo >/dev/null && falla "la clave buena no desbloqueó"
  sleep 1
  # xed solo debe tener «antes»: nada de «secreto» ni «buena»
  wmctrl -i -a "$x"; sleep 1
  xdotool key ctrl+a ctrl+c; sleep 1
  local texto; texto="$(xclip -o -selection clipboard 2>/dev/null)"
  [ "$texto" = "antes" ] || falla "xed tiene «$texto» y debía tener solo «antes»: le llegaron teclas con el bloqueo puesto"
  paso "xed no recibió nada de lo tecleado con el bloqueo puesto"
}
