# caso: el módulo libmint-macos-semaforos.so pone en hover los tres semáforos de una barra GTK cuando el puntero está en uno
# límite: 60
prueba() {
  necesita_teclado
  requiere python3 xdotool
  local modulo="${MINT_MACOS_REPO}/nativo/build/gtk-semaforos/libmint-macos-semaforos.so"
  [ -f "$modulo" ] || modulo="$PRUEBAS_PREFIJO/lib/mint-macos/libmint-macos-semaforos.so"
  [ -f "$modulo" ] || saltar "falta libmint-macos-semaforos.so"
  local aqui; aqui="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  local sin con
  sin="$(env -u GTK_MODULES python3 "$aqui/ayudantes/semaforos-hover.py" 2>/dev/null | tail -1)"
  con="$(GTK_MODULES="$modulo" python3 "$aqui/ayudantes/semaforos-hover.py" 2>/dev/null | tail -1)"
  paso "sin el módulo: $sin; con el módulo: $con"
  [ "$sin" = "100" ] || falla "sin el módulo debería estar solo el primero en hover (100): $sin"
  [ "$con" = "111" ] || falla "con el módulo deberían estar los tres en hover (111): $con"
}
