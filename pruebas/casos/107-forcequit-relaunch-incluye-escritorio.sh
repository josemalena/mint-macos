# caso: Relaunch de Fynder también mata fynder-desktop (clase nemo-desktop), por PID
# límite: 90
prueba() {
  necesita_teclado
  requiere mac-forcequit wmctrl xdotool python3
  local aqui; aqui="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  python3 "$aqui/ayudantes/ventana-con-clase.py" fynder & local pf=$!
  python3 "$aqui/ayudantes/ventana-con-clase.py" nemo-desktop desktop & local pd=$!
  trap "kill $pf $pd 2>/dev/null || true" EXIT
  sleep 2
  comprobar "el escritorio está vivo antes" kill -0 "$pd"

  lanzar mac-forcequit
  local fq; fq="$(esperar_ventana '[Mm]ac-forcequit' 20)"
  esperar_texto "$fq" "Fynder" 20
  wmctrl -i -a "$fq"; sleep 0.5
  teclas Down
  teclas Return
  sleep 1; teclas Return        # la confirmación («Do you want to force … to quit?»): Return acepta el botón por defecto
  for _ in $(seq 60); do kill -0 "$pf" 2>/dev/null || kill -0 "$pd" 2>/dev/null || break; sleep 0.2; done
  if kill -0 "$pf" 2>/dev/null; then falla "Fynder (pid $pf) sigue vivo"; fi
  if kill -0 "$pd" 2>/dev/null; then falla "el escritorio de Fynder (pid $pd) sigue vivo tras Relaunch"; fi
  paso "Relaunch mató Fynder y su escritorio"
}
