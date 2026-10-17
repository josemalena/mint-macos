# caso: mac-ventanas: el residente abre Force Quit al instante, devuelve el JSON de sesión al cliente y rechaza lo que no conoce
# límite: 120
prueba() {
  necesita_teclado
  requiere mac-ventanas wmctrl xdotool
  requiere gdbus
  lanzar mac-ventanas --residente
  local listo=false
  for _ in $(seq 150); do
    if gdbus call --session --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus \
         --method org.freedesktop.DBus.NameHasOwner io.github.josemalena.MintMacosVentanas 2>/dev/null | grep -q true; then
      listo=true; break
    fi
    sleep 0.2
  done
  $listo || falla "el residente no se registró en el bus"
  sleep 3        # que termine de precalentar

  # Una orden desconocida: sale 2 y dice cuál.
  local msg rc=0
  msg="$(mac-ventanas bogus 2>&1)" || rc=$?
  [ "$rc" = 2 ] || falla "una orden desconocida debía salir con 2, salió con $rc"
  case "$msg" in *bogus*) paso "dice cuál orden no conoce" ;; *) falla "el mensaje no nombra la orden: «$msg»" ;; esac

  # Force Quit: sale al instante porque el residente ya tiene GTK cargado.
  local t0 t1; t0=$(date +%s%N)
  mac-ventanas forcequit --prueba
  local fq; fq="$(esperar_ventana '[Mm]ac-ventanas' 10)"
  t1=$(date +%s%N)
  paso "Force Quit visible en $(( (t1 - t0) / 1000000 )) ms"
  [ "$(titulo "$fq")" = "Force Quit Applications" ] || falla "no es Force Quit: «$(titulo "$fq")»"
  [ $(( (t1 - t0) / 1000000 )) -lt 3000 ] || falla "tardó más de 3 s con el residente armado"
  cerrar_ventana "$fq"
  esperar_sin_ventana "$fq" 10

  # El diálogo de sesión: el JSON llega al cliente, que es quien lo imprime.
  local log="$PRUEBAS_RES/$PRUEBAS_CASO-json.log"
  : > "$log"
  setsid mac-ventanas sesion --mode shutdown --prueba --print-json > "$log" 2>&1 < /dev/null &
  local v; v="$(esperar_ventana '[Mm]ac-ventanas' 10)"
  wmctrl -i -a "$v"; sleep 0.5
  teclas Escape
  for _ in $(seq 50); do grep -q '"mode"' "$log" && break; sleep 0.2; done
  grep -q '"mode": "shutdown"' "$log" || falla "el cliente no recibió el JSON de shutdown: «$(cat "$log")»"
  grep -q '"confirmed": false' "$log" || falla "Esc no canceló"
  paso "el cliente recibió: $(head -1 "$log")"
}
