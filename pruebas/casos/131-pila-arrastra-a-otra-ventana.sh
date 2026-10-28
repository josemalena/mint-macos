# caso: de una Pila del Muelle abierta se arrastra un archivo a otra ventana y llega (text/uri-list); la pila se cierra al soltar
# límite: 150
prueba() {
  local aqui; aqui="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  despejar_pantalla
  requiere muelle xdotool python3
  export MUELLE_SIN_MIGRAR=1
  local esq; esq="$(dirname "$(command -v muelle)")/../esquemas"
  [ -d "$esq" ] && export GSETTINGS_SCHEMA_DIR="$esq"
  # el docklet Stacks que se prueba: el del repo de Muelle, si está compilado (se salta si no)
  local so; so="${PLANK_RELOADED:-$MINT_MACOS_REPO/../plank-reloaded}/build/docklets/Stacks"
  [ -f "$so/libdocklet-stacks.so" ] || saltar "no está compilado el docklet Stacks ($so)"
  export PLANK_DOCKLET_DIRS="$so"
  local pila="$HOME/PilaPrueba" n
  rm -rf "$pila"; mkdir -p "$pila"
  for n in $(seq 1 13); do printf 'archivo %s\n' "$n" > "$pila/archivo$n.txt"; done      # 13 > 12: «Automatic» abre el abanico con «1 More in Files»
  rm -rf "$XDG_CONFIG_HOME/muelle"; dconf reset -f /org/mintmacos/muelle/ 2>/dev/null || true
  mkdir -p "$XDG_CONFIG_HOME/muelle/dock1/launchers"
  printf '[PlankDockItemPreferences]\nLauncher=docklet://stacks\n[DockyStacksPreferences]\nFolder=file://%s\n' "$pila" > "$XDG_CONFIG_HOME/muelle/dock1/launchers/pila.dockitem"
  dconf write /org/mintmacos/muelle/docks/dock1/dock-items "['pila.dockitem']"
  local salida="$PRUEBAS_RES/$PRUEBAS_CASO-recibido.txt"; rm -f "$salida"
  lanzar python3 -I "$aqui/ayudantes/destino-de-arrastre.py" "$salida"
  esperar_ventana '^destino-de-arrastre$' 30 >/dev/null
  lanzar muelle
  local d; d="$(esperar_ventana '^[Mm]uelle$' 30)"
  sleep 3
  local X Y WIDTH HEIGHT; eval "$(xdotool getwindowgeometry --shell "$d")"
  # la cuadrícula es una ventana sin gestor (el único objeto nuevo grande de la raíz tras el clic): se busca por su tamaño
  local popup="" w dy PX PY PW PH
  paso "Muelle en $X,$Y ${WIDTH}x${HEIGHT}"
  # el abanico es una ventana sin gestor, alta y angosta: se busca por su tamaño (xwininfo la lista aunque no tenga clase)
  buscar_cuadricula() {
    xwininfo -root -children 2>/dev/null | awk '/^ +0x[0-9a-f]+ .*[0-9]+x[0-9]+\+-?[0-9]+\+-?[0-9]+/ { if (match($0, /[0-9]+x[0-9]+\+-?[0-9]+\+-?[0-9]+/)) { g=substr($0, RSTART, RLENGTH); split(g, a, /[x+]/); if (a[1] >= 150 && a[1] <= 700 && a[2] >= 500 && a[2] <= 1100) print $1, a[1], a[2], a[3], a[4] } }'
  }
  for dy in 35 25 45 15; do
    xdotool mousemove $((X + WIDTH / 2)) $((PRUEBAS_ALTO - dy)); sleep 0.6
    xdotool mousemove_relative -- 2 0; sleep 0.4
    xdotool click 1; sleep 1.5
    read -r popup PW PH PX PY < <(buscar_cuadricula | head -1) || true
    [ -n "${popup:-}" ] && break
  done
  captura pila-abierta
  [ -n "$popup" ] || falla "no se abrió la cuadrícula de la pila"
  paso "la pila abrió ($popup ${PW}x${PH}+$PX+$PY)"
  # el primer archivo del abanico (archivo1) queda ~100 px sobre el borde de abajo, en el centro del Dock
  xdotool mousemove $((X + WIDTH / 2)) $((PRUEBAS_ALTO - 100)) mousedown 1
  for _ in 1 2 3 4 5 6 7 8 9 10; do xdotool mousemove_relative -- -25 -25; sleep 0.05; done
  xdotool mousemove 120 100; sleep 0.3
  xdotool mouseup 1
  for _ in $(seq 40); do [ -s "$salida" ] && break; sleep 0.25; done
  captura despues-de-soltar
  [ -s "$salida" ] || falla "el archivo arrastrado no llegó a la otra ventana"
  paso "llegó: $(cat "$salida")"
  grep -q "file://$pila/archivo" "$salida" || falla "lo recibido no es un archivo de la pila: $(cat "$salida")"
  sleep 0.5
  [ -z "$(xdotool search --onlyvisible --class '' 2>/dev/null | while read -r w; do [ "$w" = "$popup" ] && echo "$w"; done)" ] || falla "la pila no se cerró al soltar"
  paso "la pila se cerró al soltar"
  rm -rf "$pila"
}
