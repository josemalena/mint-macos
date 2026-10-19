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

  # Un menú de Cinnamon abierto justo antes de bloquear (el de la manzana, si el gestor lo trae): no puede quedar a la vista
  xdotool mousemove 22 10 click 1; sleep 1
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
  # Nada de la sesión se ve: ni la barra de arriba, ni el menú que estaba abierto, ni la notificación (esquina superior derecha).
  # Se compara cada zona con el fondo de la pantalla de bloqueo, que es liso en esas esquinas.
  python3 - "$PRUEBAS_RES/$PRUEBAS_CASO-bloqueo-con-notificacion.png" <<'PY' || falla "se ve algo de la sesión por encima del bloqueo"
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGB")
w, h = im.size
fondo = im.getpixel((w // 2, h - 20))
def liso(x0, y0, x1, y1):
    for y in range(y0, y1, 4):
        for x in range(x0, x1, 4):
            p = im.getpixel((x, y))
            if max(abs(p[i] - fondo[i]) for i in range(3)) > 14:
                return False
    return True
zonas = {"la barra de arriba": (0, 0, w, 30), "el menú abierto": (0, 30, 400, 330), "las notificaciones": (w - 420, 30, w, 330)}
malas = [n for n, z in zonas.items() if not liso(*z)]
if malas:
    print("se ve algo en: " + ", ".join(malas))
    sys.exit(1)
PY
  paso "ni la barra, ni el menú abierto, ni la notificación se ven"

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
