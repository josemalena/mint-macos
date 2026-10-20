# caso: Fynder etiqueta sin escribir: en «Tags…» sale la lista, se filtra al escribir y Delete quita la cápsula; cada círculo del menú pone o quita solo su color
# límite: 120
# Pedido de José (19-10-2026, por Planner): había que escribir la etiqueta a
# mano en todas partes y no se podía escoger un color solo. El 56 no lo veía
# (prueba la fila de la barra global, no Fynder).

# Las etiquetas del archivo, una por línea («Purple», «Red»…), del xattr de la Mac.
etiquetas() {
  python3 -I -c 'import os, plistlib, sys
try:
    v = plistlib.loads(os.getxattr(sys.argv[1], "user.com.apple.metadata:_kMDItemUserTags"))
except OSError:
    v = []
for t in v:
    print(t.split("\n")[0])' "$1"
}

# Espera hasta que las etiquetas sean exactamente $2 (separadas por espacios, en orden).
esperar_etiquetas() {
  local f="$1" quiero="$2" hay=""
  for _ in $(seq 25); do
    hay="$(etiquetas "$f" | tr '\n' ' ' | sed 's/ $//')"
    [ "$hay" = "$quiero" ] && { paso "etiquetas: «$hay»"; return 0; }
    sleep 0.2
  done
  falla "$3: las etiquetas son «$hay», no «$quiero»"
}

# «x y ancho alto» de un elemento de un menú de la app, por accesibilidad
# (el nombre se repite en la barra lateral: solo cuenta dentro de un menú).
caja_en_menu() {
  python3 -I - "$1" "$2" <<'EOF'
import sys, time
import gi
gi.require_version("Atspi", "2.0")
from gi.repository import Atspi
pid, nombre = int(sys.argv[1]), sys.argv[2]

def en_menu(n):
    while n is not None:
        try:
            if n.get_role_name() in ("menu", "popup menu"):
                return True
            n = n.get_parent()
        except Exception:
            return False
    return False

def buscar(n, prof=0):
    if n is None or prof > 40:
        return None
    try:
        if n.get_name() == nombre and en_menu(n.get_parent()):
            st = n.get_state_set()
            if st.contains(Atspi.StateType.SHOWING):
                return n
        for i in range(n.get_child_count()):
            r = buscar(n.get_child_at_index(i), prof + 1)
            if r is not None:
                return r
    except Exception:
        return None
    return None

for _ in range(50):
    d = Atspi.get_desktop(0)
    for i in range(d.get_child_count()):
        a = d.get_child_at_index(i)
        try:
            if a is None or a.get_process_id() != pid:
                continue
        except Exception:
            continue
        n = buscar(a)
        if n is not None:
            e = n.get_extents(Atspi.CoordType.SCREEN)
            print(e.x, e.y, e.width, e.height)
            sys.exit(0)
    time.sleep(0.2)
sys.exit(1)
EOF
}

clic_en_menu() {
  local c; c="$(caja_en_menu "$1" "$2")" || falla "no se ve «$2» en el menú"
  # shellcheck disable=SC2086
  set -- $c
  paso "clic en el menú ($1 $2 $3 $4)"
  xdotool mousemove $(($1 + $3 / 2)) $(($2 + $4 / 2)) sleep 0.2 click 1
}

# Los círculos no salen por accesibilidad (GTK no expone los hijos de un ítem
# de menú): se busca el color en la franja de 30 px encima de «Tags…».
clic_en_circulo() {
  local pid="$1" hex="$2" c xy
  c="$(caja_en_menu "$pid" "Tags…")" || falla "no se ve «Tags…» en el menú"
  # shellcheck disable=SC2086
  set -- $c
  import -display "$DISPLAY" -window root -crop "${3}x30+${1}+$(($2 - 30))" +repage "$PRUEBAS_RES/franja.png"
  xy="$(python3 -I - "$PRUEBAS_RES/franja.png" "$hex" "$1" "$(($2 - 30))" <<'EOF'
import sys
import numpy
from PIL import Image
img = numpy.asarray(Image.open(sys.argv[1]).convert("RGB")).astype(int)
h = sys.argv[2].lstrip("#")
color = numpy.array([int(h[i:i + 2], 16) for i in (0, 2, 4)])
cerca = numpy.abs(img - color).sum(axis=2) < 40
ys, xs = numpy.nonzero(cerca)
if len(xs) < 20:
    sys.exit(1)
print(int(xs.mean()) + int(sys.argv[3]), int(ys.mean()) + int(sys.argv[4]))
EOF
)" || falla "no se ve el círculo $hex encima de «Tags…»"
  paso "clic en el círculo $hex ($xy)"
  # shellcheck disable=SC2086
  xdotool mousemove $xy sleep 0.2 click 1
}

prueba() {
  requiere fynder python3 xdotool
  necesita_teclado
  local d="$HOME/Documents/Lista de etiquetas" f
  mkdir -p "$d"
  f="$d/Etiquetado.txt"
  echo x > "$f"
  lanzar fynder "$d"
  local v; v="$(esperar_ventana '[Ff]ynder' 30)"
  esperar_texto "$v" "Etiquetado.txt" 20
  local pid; pid="$(xdotool getwindowpid "$v")"
  teclas Down

  # 1. Control-clic ▸ Tags…: el campo con su lista abierta
  teclas shift+F10
  clic_en_menu "$pid" "Tags…"
  sleep 1
  captura lista-abierta
  # escribir filtra; Enter pone la primera coincidencia
  teclas p u r
  sleep 0.5
  teclas Return
  esperar_etiquetas "$f" "Purple" "escribir «pur» y Enter"
  # sin escribir: ↓ marca la primera de la lista y Enter la pone
  teclas Down Return
  esperar_etiquetas "$f" "Purple Red" "↓ y Enter en la lista"
  captura capsulas
  # Delete marca la última cápsula y otro Delete la quita
  teclas BackSpace
  sleep 0.3
  teclas BackSpace
  esperar_etiquetas "$f" "Purple" "Delete dos veces"
  teclas Escape Escape
  sleep 0.5

  # 2. los círculos del menú: cada uno pone o quita solo su color
  # verde de Fynder (nemo_mac_tag_color_hex)
  teclas shift+F10
  sleep 0.5
  clic_en_circulo "$pid" "#34c759"
  esperar_etiquetas "$f" "Purple Green" "el círculo verde"
  teclas shift+F10
  sleep 0.5
  captura circulos
  clic_en_circulo "$pid" "#34c759"
  esperar_etiquetas "$f" "Purple" "el círculo verde otra vez (quita solo Green)"

  cerrar_ventana "$v"
  esperar_sin_ventana "$v" 10
}
