# caso: mac-bloqueo bloquea dentro de la sesión: pide la clave, con una mala sigue bloqueado, si matan la pantalla vuelve en menos de
# un segundo (fail-closed) y con la buena se desbloquea (PAM de mentira: LD_PRELOAD de pam-falso.c, la buena es «buena»)
# límite: 120
pantalla_pid() {   # el pid del hijo que dibuja (el supervisor no lleva --pantalla)
  local p
  for p in $(pgrep -x mac-bloqueo); do
    tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null | grep -q -- '--pantalla' && { echo "$p"; return; }
  done
}
prueba() {
  necesita_teclado
  requiere mac-bloqueo xdotool gcc
  local aqui; aqui="$(dirname "$PRUEBAS_LIB")"
  gcc -shared -fPIC -o "$PRUEBAS_RES/pam-falso.so" "$aqui/ayudantes/pam-falso.c" || falla "no pude compilar el PAM de mentira"
  export LD_PRELOAD="$PRUEBAS_RES/pam-falso.so"
  local estado="$XDG_RUNTIME_DIR/mint-macos/bloqueado"
  rm -f "$estado"
  lanzar mac-bloqueo
  for _ in $(seq 50); do [ -f "$estado" ] && break; sleep 0.2; done
  [ -f "$estado" ] || falla "no escribió el estado «bloqueado»"
  paso "el estado «bloqueado» existe"
  local pant
  for _ in $(seq 50); do pant="$(pantalla_pid)"; [ -n "$pant" ] && break; sleep 0.2; done
  [ -n "$pant" ] || falla "no arrancó la pantalla"
  sleep 3   # (la ventana es override-redirect: no sale en el bus de accesibilidad; se mira la captura y que siga viva)
  kill -0 "$pant" 2>/dev/null || falla "la pantalla de bloqueo se cayó al arrancar"
  paso "la pantalla está viva"
  captura bloqueada

  # Una clave mala: sigue bloqueado
  xdotool type --delay 80 "mala"; xdotool key Return
  sleep 2
  kill -0 "$pant" 2>/dev/null || falla "con una clave mala la pantalla se cerró"
  [ -f "$estado" ] || falla "con una clave mala se borró el estado"
  paso "la clave mala no desbloquea"

  # Matan la pantalla: tiene que volver antes de 1 s y el estado se queda
  local t0 t1 nueva; t0="$(date +%s%N)"
  kill -9 "$pant"
  for _ in $(seq 100); do nueva="$(pantalla_pid)"; [ -n "$nueva" ] && [ "$nueva" != "$pant" ] && break; sleep 0.01; done
  t1="$(date +%s%N)"
  [ -n "$nueva" ] && [ "$nueva" != "$pant" ] || falla "al matar la pantalla no volvió"
  local ms=$(( (t1 - t0) / 1000000 ))
  paso "la pantalla volvió en $ms ms"
  [ "$ms" -lt 1000 ] || falla "tardó $ms ms en volver (más de 1 s)"
  [ -f "$estado" ] || falla "al caerse la pantalla se borró el estado"
  sleep 3
  kill -0 "$nueva" 2>/dev/null || falla "la pantalla nueva se cayó"

  # La buena: se desbloquea y todo termina
  xdotool type --delay 80 "buena"; xdotool key Return
  for _ in $(seq 50); do pgrep -x mac-bloqueo >/dev/null || break; sleep 0.2; done
  pgrep -x mac-bloqueo >/dev/null && falla "con la clave buena el bloqueo sigue vivo"
  [ ! -f "$estado" ] || falla "con la clave buena el estado «bloqueado» no se borró"
  paso "la clave buena desbloquea y borra el estado"
}
