# caso: sombras@macos pone la sombra medida de las ventanas (sigma 17 px, 0.32 de opacidad, ventana activa) y sin ella queda la de Cinnamon
# límite: 150
# gestor: cinnamon-animaciones
# Fondo blanco, una ventana de xed, captura de la pantalla compuesta y medida de la sombra a la izquierda de la ventana (ayudantes/medir-sombra.py).
medir() {   # medir ETIQUETA: deja BORDE y SIGMA de la ventana activa
  local v="$1" g x y
  g="$(xdotool getwindowgeometry --shell "$v")"; eval "$g"     # X Y WIDTH HEIGHT: del cliente
  # el borde de la ventana con su marco: la x del marco (decoración); wmctrl -lG da la del marco
  read -r x y < <(wmctrl -lG | awk -v id="$(printf '0x%08x' "$v")" '$1 == id {print $3, $4 + $6 / 2}')
  captura "sombra-$2"
  read -r BORDE SIGMA < <(python3 -I "$AQUI/ayudantes/medir-sombra.py" "$PRUEBAS_RES/$PRUEBAS_CASO-sombra-$2.png" "$x" "$y")
  paso "$2: oscuridad en el borde $BORDE, sigma $SIGMA px"
}
prueba() {
  requiere python3 xdotool wmctrl import
  AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  # fondo blanco: una ventana de tipo escritorio (Cinnamon pinta el suyo y no deja cambiarlo con xsetroot)
  lanzar python3 "$AQUI/ayudantes/fondo-blanco.py"
  esperar_ventana '^fondo-blanco$' 30 > /dev/null; sleep 1
  lanzar python3 "$AQUI/ayudantes/ventana-con-marco.py" 300 200
  local v; v="$(esperar_ventana '^marco-de-prueba$' 30)"
  sleep 2
  xdotool mousemove 5 5; sleep 1
  medir "$v" con-perfil
  # la oscuridad en el borde es A/2 (opacidad 0.32 → 0.16) y sigma 17 px: tolerancias anchas (un ajuste visual sobre pixeles enteros)
  python3 -I -c "import sys; b, s = $BORDE, $SIGMA; sys.exit(0 if 0.10 <= b <= 0.22 and 12 <= s <= 24 else 1)" \
    || falla "la sombra medida (borde $BORDE, sigma $SIGMA) no es la del perfil (borde ~0.16, sigma ~17)"
  # sin la extensión: la de Cinnamon (radio 10, opacidad 0.5): más chica
  gsettings set org.cinnamon enabled-extensions "['cmdtab@macos', 'misioncontrol@macos', 'CinnamonMagicLamp@klangman']"; sleep 2
  medir "$v" sin-extension
  python3 -I -c "import sys; b, s = $BORDE, $SIGMA; sys.exit(0 if s < 12 else 1)" || falla "apagada la extensión no volvió la sombra de Cinnamon (sigma $SIGMA)"
  # sin la sombra medida (archivo ausente, JSON roto): queda la de Cinnamon, sin fallar
  local variante perfil="$XDG_DATA_HOME/mint-macos/macos/monterey-12.7.6/apps/efectos.json"
  for variante in ausente roto; do
    if [ "$variante" = ausente ]; then rm -f "$perfil"; else echo '{"ventana": {"sombra": {' > "$perfil"; fi
    gsettings set org.cinnamon enabled-extensions "['cmdtab@macos', 'misioncontrol@macos', 'CinnamonMagicLamp@klangman']"; sleep 1
    gsettings set org.cinnamon enabled-extensions "['cmdtab@macos', 'misioncontrol@macos', 'sombras@macos', 'CinnamonMagicLamp@klangman']"; sleep 2
    grep -q "Loaded extension sombras@macos" "$PRUEBAS_RES/cinnamon.log" || falla "perfil $variante: la extensión no cargó"
    medir "$v" "perfil-$variante"
    python3 -I -c "import sys; sys.exit(0 if $SIGMA < 12 else 1)" || falla "perfil $variante: sigma $SIGMA, debía quedar la de Cinnamon (~10)"
  done
  cerrar_ventana "$v"
  true
}
