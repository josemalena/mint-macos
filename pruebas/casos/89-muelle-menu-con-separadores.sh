# caso: el clic secundario en un ítem del Dock muestra las acciones de X-Muelle-Actions (los menús de Finder y System Preferences de la Mac),
# con separadores donde la acción se llama «-»; y una acción que solo está en X-Muelle-Actions corre su Exec al escogerla
# límite: 90
prueba() {
  despejar_pantalla
  requiere muelle xdotool import convert
  export MUELLE_SIN_MIGRAR=1
  local esq; esq="$(dirname "$(command -v muelle)")/../esquemas"
  [ -d "$esq" ] && export GSETTINGS_SCHEMA_DIR="$esq"
  local apps="$XDG_DATA_HOME/applications" lanz="$XDG_CONFIG_HOME/muelle/dock1/launchers"
  # Partir de cero: lo que otro caso de la corrida dejó (lanzadores de 69, el dconf de Muelle) haría salir íconos «?» y otro menú
  rm -rf "$XDG_CONFIG_HOME/muelle"; dconf reset -f /org/mintmacos/muelle/ 2>/dev/null || true
  mkdir -p "$apps" "$lanz"
  cat > "$apps/menu.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Menu
Exec=true
Icon=xed
Actions=solo-esta;
X-Muelle-Actions=alfa;separa1;beta;gamma;separa2;delta;

[Desktop Action solo-esta]
Name=Solo la lista normal
Exec=true

[Desktop Action alfa]
Name=Alfa
Exec=touch $PRUEBAS_RES/alfa-corrio

[Desktop Action separa1]
Name=-

[Desktop Action beta]
Name=Beta
Exec=true

[Desktop Action gamma]
Name=Gamma
Exec=true

[Desktop Action separa2]
Name=-

[Desktop Action delta]
Name=Delta
Exec=true
EOF
  printf '[PlankDockItemPreferences]\nLauncher=file://%s/menu.desktop\n' "$apps" > "$lanz/menu.dockitem"
  dconf write /org/mintmacos/muelle/docks/dock1/dock-items "['menu.dockitem']"   # (dconf directo: no depende de dónde esté el esquema)
  lanzar muelle
  local v; v="$(esperar_ventana '^[Mm]uelle$' 30)"
  sleep 3
  local f="$PRUEBAS_RES/$PRUEBAS_CASO-franja.png" W H
  import -display "$DISPLAY" -window root -crop "${PRUEBAS_ANCHO}x220+0+$((PRUEBAS_ALTO - 220))" +repage "$f"
  read -r W H < <(convert "$f" -fuzz 4% -trim -format '%w %h\n' info:)
  [ "${W:-0}" -gt 30 ] || falla "el dock no dibujó nada"
  local x0 y0; read -r x0 y0 < <(convert "$f" -fuzz 4% -trim -format '%[fx:page.x] %[fx:page.y]\n' info: | tr -d '+')
  xdotool mousemove $((x0 + W / 2)) $((PRUEBAS_ALTO - 220 + ${y0:-100} + H / 2)); sleep 0.7; xdotool click 3
  captura menu-del-dock
  esperar_texto "$v" "Alfa" 15
  esperar_texto "$v" "Delta" 5
  local pid volcado; pid="$(xdotool getwindowpid "$v")"
  volcado="$(python3 "$(dirname "$PRUEBAS_LIB")/atspi.py" --pid "$pid" --volcar 2>&1)"
  echo "$volcado" | grep -q "Solo la lista normal" && falla "mostró la lista normal en vez de X-Muelle-Actions"
  local seps; seps="$(echo "$volcado" | grep -ci 'separator')"
  paso "separadores en el menú: $seps"
  [ "$seps" -ge 2 ] || falla "faltan los separadores (vi $seps)"
  echo "$volcado" | grep -q '«-»\|"-"' && falla "dibujó la acción «-» como un ítem"
  # Alfa solo está en X-Muelle-Actions (no en Actions=): al escogerla tiene que correr su Exec
  rm -f "$PRUEBAS_RES/alfa-corrio"
  xdotool key Down; sleep 0.3; xdotool key Return
  for _ in $(seq 30); do [ -f "$PRUEBAS_RES/alfa-corrio" ] && break; sleep 0.2; done
  [ -f "$PRUEBAS_RES/alfa-corrio" ] || falla "escoger una acción de X-Muelle-Actions no ejecutó su Exec"
  paso "la acción de X-Muelle-Actions corrió su Exec"
}
