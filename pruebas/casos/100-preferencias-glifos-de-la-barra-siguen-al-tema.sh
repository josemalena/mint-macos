# caso: los glifos de la barra de herramientas de System Preferences (Back, Forward y Show All) toman el color del tema: oscuros con un tema
# claro y claros con uno oscuro (antes eran siempre blancos y en claro no se veían)
# límite: 120
muestra_glifos() {   # muestra_glifos VENTANA: cuántos píxeles oscuros y cuántos claros hay en la zona del botón Show All (el que siempre está activo; Back y Forward salen atenuados sin historial)
  local X Y WIDTH HEIGHT
  eval "$(xdotool getwindowgeometry --shell "$1")"
  echo "ventana en $X,$Y ${WIDTH}x${HEIGHT}" >&2
  import -display "$DISPLAY" -window root -crop "44x30+$((X + 230))+$((Y + 25))" +repage "$PRUEBAS_RES/glifos-$modo.png"
  python3 - "$PRUEBAS_RES/glifos-$modo.png" <<'PY'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("L")
px = list(im.getdata())
print(sum(1 for p in px if p < 110), sum(1 for p in px if p > 190))
PY
}
prueba() {
  requiere mac-preferencias xdotool python3 import
  export MP_PYTHON_DIR="$MINT_MACOS_REPO/settings"
  local modo v resultado oscuros claros
  for modo in Adwaita Adwaita:dark; do
    GTK_THEME="$modo" lanzar mac-preferencias
    v="$(esperar_ventana '[Mm]ac-settings' 40)"
    esperar_texto "$v" "Sound" 20
    sleep 3    # el tema claro se aplica unos 250 ms después de leer el tema
    resultado="$(muestra_glifos "$v")"
    oscuros="${resultado% *}"; claros="${resultado#* }"
    paso "con $modo: $oscuros píxeles oscuros y $claros claros en la zona de los glifos"
    captura "barra-$modo"
    kill "$(xdotool getwindowpid "$v")"; sleep 2    # el residente se esconde al cerrar: se acaba el proceso para volver a arrancarlo con el otro tema
    case "$modo" in
      Adwaita) [ "$oscuros" -ge 12 ] || falla "con un tema claro los glifos de la barra no son oscuros (solo $oscuros píxeles oscuros)" ;;
      *) [ "$claros" -ge 12 ] || falla "con un tema oscuro los glifos de la barra no son claros (solo $claros píxeles claros)" ;;
    esac
  done
}
