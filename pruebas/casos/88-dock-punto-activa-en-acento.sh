# caso: en el Dock, el punto de la app activa va en el color de acento del tema (azul de Adwaita) y el de una abierta que no está activa sigue blanco
# límite: 120
# gestor: cinnamon-applets
# Un lanzador (xed) en el Dock; al abrirlo y activarlo, el punto de su ícono cambia del blanco al acento.
prueba() {
  despejar_pantalla
  requiere muelle xed xdotool import convert
  export GTK_THEME=Adwaita
  local apps="$XDG_DATA_HOME/applications" lanz="$XDG_CONFIG_HOME/muelle/dock1/launchers"
  mkdir -p "$apps" "$lanz"
  printf '[Desktop Entry]\nType=Application\nName=xedprueba\nExec=xed\nIcon=xed\nStartupWMClass=Xed\n' > "$apps/xedprueba.desktop"
  printf '[PlankDockItemPreferences]\nLauncher=file://%s/xedprueba.desktop\n' "$apps" > "$lanz/xedprueba.dockitem"
  local esq; esq="$(dirname "$(command -v muelle)")/../esquemas"
  [ -d "$esq" ] && export GSETTINGS_SCHEMA_DIR="$esq"
  dconf write /org/mintmacos/muelle/docks/dock1/dock-items "['xedprueba.dockitem']"   # (dconf directo: no depende de dónde esté el esquema)
  lanzar muelle
  esperar_ventana '^[Mm]uelle$' 30 >/dev/null
  lanzar xed
  local x; x="$(esperar_ventana '^[Xx]ed$' 30)"
  xdotool windowactivate "$x" 2>/dev/null || true
  sleep 4
  local f="$PRUEBAS_RES/$PRUEBAS_CASO-franja.png"
  import -display "$DISPLAY" -window root -crop "${PRUEBAS_ANCHO}x120+0+$((PRUEBAS_ALTO - 120))" +repage "$f"
  captura dock-con-xed-activo
  # el píxel más saturado de la franja: el punto de la app activa (el resto del dock es gris y blanco)
  local pt; pt="$(convert "$f" -colorspace HSB -channel G -separate +channel -format '%[fx:maxima]' info:)"
  local azul; azul="$(convert "$f" -fill black +opaque 'srgb(53,132,228)' -fuzz 12% -fill white -opaque 'srgb(53,132,228)' -format '%[fx:mean]' info: 2>/dev/null || true)"
  local n; n="$(convert "$f" -fuzz 18% -fill white -opaque 'srgb(53,132,228)' -fill black +opaque white -format '%[fx:mean*w*h]' info:)"
  paso "píxeles cercanos al acento azul: ${n%.*}"
  [ "${n%.*}" -ge 8 ] || falla "no se ve el punto en el color de acento (${n%.*} píxeles azules)"
}
