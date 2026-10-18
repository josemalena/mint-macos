# caso: en el Launchpad, mantener pulsado un ícono y soltarlo sobre otro arma una carpeta «Untitled»; se renombra y se guarda
# (launchpad.json); llevar un ícono a otro lugar lo reordena y sacarlo de la carpeta lo devuelve a la rejilla
# límite: 120
prueba() {
  requiere mac-launchpad-vala xdotool python3
  local apps="$HOME/lp-apps" diseno="$HOME/lp-diseno.json"
  mkdir -p "$apps"
  for n in Alfa Beta Gamma Delta Epsilon; do
    printf '[Desktop Entry]\nType=Application\nName=%s\nExec=true\nIcon=application-x-executable\n' "$n" > "$apps/$n.desktop"
  done
  rm -f "$diseno"
  export LAUNCHPAD_DESTINO="$apps" LAUNCHPAD_DISENO="$diseno" LAUNCHPAD_TAM=1920x1200
  lanzar mac-launchpad-vala
  local w; w="$(esperar_ventana '[Ll]aunchpad' 30)"
  # Sin gestor de ventanas el foco no es de nadie: se le da, y se sube y se pone en el origen (en un armado completo hay ventanas
  # de casos anteriores, y el teclado y el ratón iban a parar a otra).
  xdotool windowmove "$w" 0 0 2>/dev/null || true
  xdotool windowraise "$w" 2>/dev/null || true
  xdotool windowfocus --sync "$w" 2>/dev/null || true
  sleep 2
  captura launchpad-inicial
  # Rejilla de 1920×1200: la primera celda en (312, 98+56), paso 215; Alfa, Beta, Delta, Epsilon, Gamma por orden alfabético.
  local x0=312 y0=154 paso=215
  mover() { xdotool mousemove "$1" "$2"; }
  arrastrar() {   # de la celda $1 a la celda $2, manteniendo pulsado
    mover "$((x0 + $1 * paso))" "$y0"
    xdotool mousedown 1
    sleep 1.0
    mover "$((x0 + $1 * paso + 20))" "$y0"
    sleep 0.2
    mover "$((x0 + $2 * paso))" "$y0"
    sleep 0.6
    xdotool mouseup 1
    sleep 0.6
  }
  # 1. Beta (celda 1) encima de Alfa (celda 0): carpeta «Untitled», con el nombre listo para escribir.
  arrastrar 1 0
  captura launchpad-carpeta-creada
  [ -f "$diseno" ] || falla "no se guardó el diseño"
  grep -q '"Untitled"' "$diseno" || falla "la carpeta Untitled no está en el diseño: $(cat "$diseno")"
  # 2. Se renombra: se escribe y Enter.
  xdotool windowfocus --sync "$w" 2>/dev/null || true
  xdotool type --delay 80 "Trabajo"
  xdotool key Return
  for _ in $(seq 20); do grep -q '"Trabajo"' "$diseno" && break; sleep 0.25; done
  grep -q '"Trabajo"' "$diseno" || falla "el nombre no se guardó: $(cat "$diseno")"
  captura launchpad-carpeta-renombrada
  # 3. Se cierra la carpeta (Esc) y se reordena: Epsilon (celda 2 ahora: Trabajo, Gamma?…) se lleva a la primera celda.
  xdotool windowfocus --sync "$w" 2>/dev/null || true
  xdotool key Escape
  sleep 0.5
  local antes; antes="$(python3 -c "import json;print(json.load(open('$diseno'))['orden'])")"
  paso "orden antes: $antes"
  arrastrar 3 0
  # Con la máquina cargada (un armado completo) el soltar tarda en guardarse: se espera el cambio en vez de un tiempo fijo.
  local despues="$antes"
  for _ in $(seq 40); do
    despues="$(python3 -c "import json;print(json.load(open('$diseno'))['orden'])")"
    [ "$antes" != "$despues" ] && break
    sleep 0.25
  done
  paso "orden después: $despues"
  captura launchpad-reordenado
  [ "$antes" != "$despues" ] || falla "llevar un ícono a otro lugar no cambió el orden: $(cat "$diseno")"
}
