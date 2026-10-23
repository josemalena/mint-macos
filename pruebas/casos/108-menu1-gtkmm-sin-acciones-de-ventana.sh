# caso: Menu1 con Transmission (gtkmm: el grupo «win» no se exporta): con libmint-macos-acciones.so sus ítems salen activos y Quit funciona
# límite: 120
prueba() {
  requiere mac-menu transmission-gtk gdbus xdotool xprop
  local modulo="${MINT_MACOS_REPO}/nativo/build/gtk-acciones/libmint-macos-acciones.so"
  [ -f "$modulo" ] || modulo="$PRUEBAS_PREFIJO/lib/mint-macos/libmint-macos-acciones.so"
  [ -f "$modulo" ] || saltar "falta libmint-macos-acciones.so"
  # Sin appmenu-gtk-module: la app exporta su propio menubar, como cuando se lanza sin el módulo.
  export GTK_MODULES="$modulo"
  # Como en la sesión de Cinnamon: el shell se encarga de la barra, así que GtkApplication la exporta por D-Bus.
  mkdir -p "$XDG_CONFIG_HOME/gtk-3.0"
  printf '[Settings]\ngtk-shell-shows-menubar=true\n' > "$XDG_CONFIG_HOME/gtk-3.0/settings.ini"
  lanzar mac-menu
  sleep 2
  lanzar transmission-gtk
  esperar_ventana '[Tt]ransmission' 40 >/dev/null
  sleep 4
  llamar() { gdbus call --session --dest org.mintmacos.Menu1 --object-path /org/mintmacos/Menu1 --method "org.mintmacos.Menu1.$1" "${@:2}" 2>&1 || true; }
  local v principal=""
  for v in $(xdotool search --class transmission-gtk 2>/dev/null); do
    xprop -id "$v" _GTK_MENUBAR_OBJECT_PATH 2>/dev/null | grep -q '"' && principal="$v"
  done
  [ -n "$principal" ] || falla "la ventana principal de Transmission no publica _GTK_MENUBAR_OBJECT_PATH"
  local pid; pid="$(xdotool getwindowpid "$principal")"
  local f; f="$(llamar Abrir "$principal" 0)"
  paso "File: ${f:0:700}"
  case "$f" in *"'etiqueta': <'Open'>, 'activo': <true>"*) paso "Open activo" ;; *) falla "Open sigue en gris: ${f:0:700}" ;; esac
  case "$f" in *"'etiqueta': <'Quit'>, 'activo': <true>"*) paso "Quit activo" ;; *) falla "Quit sigue en gris" ;; esac
  local b v1; b="$(llamar Barra "$principal")"
  v1="$(printf '%s' "$b" | grep -o "^(uint32 [0-9]*" | grep -o "[0-9]*$")"
  local ok; ok="$(llamar Activar "$principal" "$v1" "0.7")"
  paso "Activar Quit: $ok"
  for _ in $(seq 50); do kill -0 "$pid" 2>/dev/null || break; sleep 0.2; done
  if kill -0 "$pid" 2>/dev/null; then falla "Transmission (pid $pid) sigue vivo después de Quit por el menú global"; fi
  paso "Transmission salió por Quit del menú global"
}
