# caso: con Constanza-Claro el aviso de notificación (el banner de arriba a la derecha) es claro, también con acciones y un cuerpo largo
# (se instala en el sandbox el tema Constanza-Claro de la sesión con los CSS claros del repo encima)
# gestor: cinnamon-notificaciones
# límite: 150
prueba() {
  requiere notify-send python3 import
  local casa tema="$XDG_DATA_HOME/themes/Constanza-Claro"
  casa="$(getent passwd "$(id -un)" | cut -d: -f6)"
  [ -f "$casa/.themes/Constanza-Claro/cinnamon/cinnamon.css" ] || saltar "no está construido Constanza-Claro"
  mkdir -p "$XDG_DATA_HOME/themes"
  rm -rf "$tema"; cp -r "$casa/.themes/Constanza-Claro" "$tema"
  # El CSS claro del repo encima del que ya trae el tema (gana el último)
  cat "$MINT_MACOS_REPO/tema/gtk/_constanza-cinnamon-claro.css" >> "$tema/cinnamon/cinnamon.css"
  # El sandbox sobrevive entre corridas: el tema se deshace al terminar (con el tema claro puesto, los casos de Cinnamon que siguen cambiarían)
  trap 'gsettings reset org.cinnamon.theme name 2>/dev/null; rm -rf "$XDG_DATA_HOME/themes/Constanza-Claro"' EXIT
  gsettings set org.cinnamon.theme name "'Constanza-Claro'"
  sleep 4
  # (con -A notify-send se queda esperando la respuesta: va al fondo y con tope)
  timeout 25 notify-send -t 15000 -A "mostrar=Show" -A "responder=Reply" "Mensaje de prueba" "Este es un cuerpo bastante largo para que la notificación tenga varias líneas y se vea cómo queda el aviso completo con todo su texto, sus botones y su ícono en claro." > /dev/null 2>&1 &
  sleep 1
  captura aviso-claro   # (a los pocos segundos el aviso se esconde solo: se mira al segundo)
  python3 - "$PRUEBAS_RES/$PRUEBAS_CASO-aviso-claro.png" <<'PY' || falla "el aviso de notificación no es claro con Constanza-Claro"
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("L")
w, h = im.size
# La zona de arriba a la derecha donde sale el aviso (debajo de la barra): su fondo tiene que ser claro
caja = im.crop((w - 340, 60, w - 30, 140))
px = list(caja.getdata())
claros = sum(1 for p in px if p > 190)
print("píxeles claros en la zona del aviso: %d de %d" % (claros, len(px)))
sys.exit(0 if claros > 0.35 * len(px) else 1)
PY
  paso "el aviso es claro"
}
