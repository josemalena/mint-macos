# caso: con menu-flash encendido, el ítem de un menú de Cinnamon parpadea (se apaga y se enciende) antes de ejecutarse; con menu-flash apagado no
# (los números son los provisionales del esquema: 2 parpadeos de 150 ms; el mecanismo es lo que se prueba)
# gestor: cinnamon-colgadas
# límite: 120
parpadeos() {   # parpadeos CLAVE: cuántas veces el rectángulo azul del ítem se apaga y vuelve, según el video de la pantalla
  local video="$PRUEBAS_RES/$PRUEBAS_CASO-$1.mkv" carpeta="$PRUEBAS_RES/$PRUEBAS_CASO-$1-cuadros"
  rm -rf "$carpeta"; mkdir -p "$carpeta"
  ffmpeg -loglevel error -y -f x11grab -framerate 30 -video_size "${PRUEBAS_ANCHO}x${PRUEBAS_ALTO}" -t 2.2 -i "$DISPLAY" "$video" &
  local ff=$!
  sleep 0.6
  xdotool key Return
  wait "$ff"
  ffmpeg -loglevel error -y -i "$video" "$carpeta/%03d.png"
  python3 - "$carpeta" "$2" <<'PY'
import sys, glob
from PIL import Image
carpeta, caja = sys.argv[1], sys.argv[2].split(',')
x0, y0, x1, y1 = [int(v) for v in caja[:4]]
objetivo = tuple(int(v) for v in caja[4:7])
estado = []
for f in sorted(glob.glob(carpeta + '/*.png')):
    im = Image.open(f).convert('RGB').crop((x0, y0, x1, y1))
    cerca = sum(1 for p in im.getdata() if all(abs(p[i] - objetivo[i]) < 12 for i in range(3)))
    estado.append(cerca > 0.5 * (x1 - x0) * (y1 - y0))

cambios = sum(1 for a, b in zip(estado, estado[1:]) if (not a) and b)   # apagado y de vuelta encendido; cerrarse el menú no vuelve
print(cambios)
PY
}
menu_abierto() {   # ¿hay un menú pintado debajo de la manzana? (la zona de 380×280 bajo la barra deja de ser lisa)
  import -display "$DISPLAY" -window root -crop "380x280+0+30" +repage "$PRUEBAS_RES/$PRUEBAS_CASO-zona.png" 2>/dev/null || return 1
  python3 - "$PRUEBAS_RES/$PRUEBAS_CASO-zona.png" <<'PY'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("L")
px = list(im.getdata())
fondo = px[-1]
sys.exit(0 if sum(1 for p in px if abs(p - fondo) > 12) > 0.15 * len(px) else 1)
PY
}
prueba() {
  despejar_pantalla
  necesita_teclado
  requiere xdotool ffmpeg import
  # El esquema de los ajustes, en la carpeta del usuario del sandbox (el applet lo busca ahí)
  mkdir -p "$XDG_DATA_HOME/glib-2.0/schemas"
  cp "$MINT_MACOS_REPO/menus/org.mintmacos.menus.gschema.xml" "$XDG_DATA_HOME/glib-2.0/schemas/"
  glib-compile-schemas "$XDG_DATA_HOME/glib-2.0/schemas"
  export GSETTINGS_SCHEMA_DIR="$XDG_DATA_HOME/glib-2.0/schemas${GSETTINGS_SCHEMA_DIR:+:$GSETTINGS_SCHEMA_DIR}"
  gsettings set org.mintmacos.menus flash-count 2
  gsettings set org.mintmacos.menus flash-duration-ms 150
  # La manzana: el primer applet de la barra
  local resultado
  for modo in true false; do
    gsettings set org.mintmacos.menus menu-flash "$modo"
    # El menú se abre con un clic y a veces tarda en pintarse (en un armado cargado el primer cuadro sale vacío): se espera y, si no salió, se vuelve a clicar
    local intento
    for intento in 1 2 3 4 5 6; do
      xdotool mousemove 22 10 click 1
      for _ in 1 2 3 4 5 6 7 8; do sleep 0.3; menu_abierto && break 2; done
      xdotool key Escape; sleep 0.5      # no salió: se cierra lo que haya y se reintenta
    done
    if ! menu_abierto; then
      # Diagnóstico para el armado completo: la pantalla entera, el estado del salvapantallas y las ventanas
      captura "sin-menu-pantalla-completa"
      { echo "--- xset q:"; xset q 2>&1 | grep -A3 "Screen Saver\|DPMS"; echo "--- ventanas:"; wmctrl -l 2>&1; echo "--- applets de Cinnamon:"; gsettings get org.cinnamon enabled-applets; } >&2
      falla "el menú de la manzana no se abrió en 6 intentos"
    fi
    captura "menu-sin-escoger-$modo"
    xdotool key Down; sleep 0.5
    captura "menu-abierto-$modo"
    # El ítem escogido es lo que cambió entre las dos capturas: su caja y su color (el del tema que haya)
    local caja
    caja="$(python3 - "$PRUEBAS_RES/$PRUEBAS_CASO-menu-sin-escoger-$modo.png" "$PRUEBAS_RES/$PRUEBAS_CASO-menu-abierto-$modo.png" <<'PY'
import sys
from PIL import Image, ImageChops
a = Image.open(sys.argv[1]).convert('RGB'); b = Image.open(sys.argv[2]).convert('RGB')
box = ImageChops.difference(a, b).getbbox()
if not box:
    print("0,0,1,1,0,0,0")
else:
    x0, y0, x1, y1 = box
    c = b.getpixel(((x0 + x1) // 2, y0 + 4))
    print("%d,%d,%d,%d,%d,%d,%d" % (x0 + 6, y0 + 3, x1 - 6, y1 - 3, c[0], c[1], c[2]))
PY
)"
    paso "ítem escogido en $caja (menu-flash=$modo)"
    resultado="$(parpadeos "$modo" "$caja")"
    paso "con menu-flash=$modo el resaltado se apagó $resultado vez/veces"
    if [ "$modo" = true ]; then
      [ "$resultado" -ge 1 ] || falla "con menu-flash encendido el ítem no parpadeó"
    else
      [ "$resultado" -eq 0 ] || falla "con menu-flash apagado el ítem parpadeó ($resultado)"
    fi
    xdotool key Escape; sleep 1
  done
}
