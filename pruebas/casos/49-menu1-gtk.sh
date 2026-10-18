# caso: org.mintmacos.Menu1 lee el menú de xed (GTK con appmenu-gtk-module, barra en dos secciones), lo aplana y ejecuta un ítem
# límite: 120
prueba() {
  requiere mac-menu xed gdbus xdotool
  export GTK_MODULES="${GTK_MODULES:-appmenu-gtk-module}"
  lanzar mac-menu
  sleep 2
  lanzar xed
  local w; w="$(esperar_ventana '[Xx]ed' 30)"
  sleep 2
  local xid="$w"
  llamar() { gdbus call --session --dest org.mintmacos.Menu1 --object-path /org/mintmacos/Menu1 --method "org.mintmacos.Menu1.$1" "${@:2}" 2>&1 || true; }
  local f b
  f="$(llamar Fuente "$xid")"
  paso "Fuente: $f"
  case "$f" in *gtk*) ;; *) falla "Fuente no dice gtk: $f" ;; esac
  b="$(llamar Barra "$xid")"
  paso "Barra: ${b:0:300}"
  for m in File Edit View Search; do
    case "$b" in *"'$m'"*) ;; *) falla "la barra no trae «$m»: $b" ;; esac
  done
  local v; v="$(printf '%s' "$b" | grep -o "^(uint32 [0-9]*" | grep -o "[0-9]*$")"
  # Abrir «Edit» (el segundo menú de arriba, id «1»): trae Undo, Cut, Copy, Paste y sus atajos de la Mac.
  local e; e="$(llamar Abrir "$xid" "1")"
  paso "Edit: ${e:0:400}"
  case "$e" in *Undo*) ;; *) falla "Edit no trae Undo: $e" ;; esac
  case "$e" in *"⌘Z"*) paso "atajo de la Mac: ⌘Z" ;; *) falla "Undo sin ⌘Z: $e" ;; esac
  # Activar con la versión vieja da Vencido y no ejecuta nada.
  local bad; bad="$(llamar Activar "$xid" 9999 "1.0")"
  case "$bad" in *Vencido*) paso "versión vieja → Vencido" ;; *) falla "Activar con versión vieja no dio Vencido: $bad" ;; esac
  # Activar con la versión vigente ejecuta: «Select All» (1.9) da true.
  local ok; ok="$(llamar Activar "$xid" "$v" "1.9")"
  case "$ok" in *true*) paso "Activar vigente: true" ;; *) falla "Activar con la versión vigente no dio true: $ok" ;; esac
  # Buscar «Find» devuelve rutas.
  local q; q="$(llamar Buscar "$xid" "find")"
  paso "Buscar: ${q:0:300}"
  case "$q" in *"▸"*) ;; *) falla "Buscar no trae rutas: $q" ;; esac
}
