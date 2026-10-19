# caso: un atajo de App Shortcuts (~/.config/mint-macos/atajos-apps.json) activa el comando de menú de la app con ese nombre, por
# org.mintmacos.Menu1, y el atajo solo se agarra mientras esa app tiene el foco
# límite: 120
# gestor: cinnamon-applets
prueba() {
  requiere xed gdbus xdotool mac-menu python3
  export GTK_MODULES="${GTK_MODULES:-appmenu-gtk-module}"
  lanzar mac-menu
  sleep 1
  lanzar xed
  local w; w="$(esperar_ventana '[Xx]ed' 30)"
  xdotool windowfocus "$w" 2>/dev/null || true
  sleep 2
  ev() { gdbus call --session --dest org.Cinnamon --object-path /org/Cinnamon --method org.Cinnamon.Eval "$1" 2>&1; }
  llamar() { gdbus call --session --dest org.mintmacos.Menu1 --object-path /org/mintmacos/Menu1 --method "org.mintmacos.Menu1.$1" "${@:2}" 2>&1 || true; }
  local a="imports.ui.appletManager.getRunningInstancesForUuid('appmenu@macos')[0]"
  # «Word wrap» está en View de xed: casilla con estado. Se lee antes.
  local antes; antes="$(llamar Buscar "$w" "Word wrap" | grep -o "'marcado': <[a-z]*>" | head -1)"
  paso "Word wrap antes: ${antes:-sin marca}"
  mkdir -p "$XDG_CONFIG_HOME/mint-macos"
  printf '{"version":1,"atajos":[{"app":"*","titulo":"Word wrap","atajo":"⌥⌘9"}]}' > "$XDG_CONFIG_HOME/mint-macos/atajos-apps.json"
  sleep 2
  local r; r="$(ev "[$a._hotkeysApp.size, [...$a._hotkeysApp.keys()].join(',')].join('|')")"
  paso "atajos agarrados: $r"
  case "$r" in *"1|<Super><Alt>9"*) ;; *) falla "no se agarró <Super><Alt>9 para ⌥⌘9: $r" ;; esac
  # Se pulsa: el comando de menú se activa y la casilla cambia.
  ev "$a._dispararAtajoApp('<Super><Alt>9'); 'ok'" >/dev/null
  sleep 3
  local despues; despues="$(llamar Buscar "$w" "Word wrap" | grep -o "'marcado': <[a-z]*>" | head -1)"
  paso "Word wrap después: ${despues:-sin marca}"
  [ -n "$despues" ] && [ "$antes" != "$despues" ] || falla "el atajo no activó «Word wrap» ($antes → $despues)"
  # Sin el archivo, no queda ningún atajo agarrado.
  rm -f "$XDG_CONFIG_HOME/mint-macos/atajos-apps.json"
  sleep 2
  r="$(ev "String($a._hotkeysApp.size)")"
  case "$r" in *'"0"'*) paso "sin archivo, sin atajos" ;; *) falla "quedaron atajos agarrados sin el archivo: $r" ;; esac
}
