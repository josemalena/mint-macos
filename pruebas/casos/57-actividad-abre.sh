# caso: Activity Monitor abre con las seis pestañas, lista procesos (con la columna de CPU) y publica su barra de menús (File, Edit, View, Window, Help)
# límite: 90
prueba() {
  requiere mac-actividad xdotool python3
  # Monitor1 (de Infra): su binario del armado (rust/target/release), o el instalado; el bus de la prueba no lo activa solo.
  local mon=""
  for d in "${PRUEBAS_RUST:-}" "$MINT_MACOS_REPO/rust/target/release" "$HOME/.local/lib/mint-macos"; do
    [ -x "$d/mint-macos-monitor" ] && { mon="$d/mint-macos-monitor"; break; }
  done
  [ -n "$mon" ] || { paso "sin mint-macos-monitor: se salta"; return 0; }
  lanzar "$mon"
  sleep 1
  lanzar mac-actividad
  local w; w="$(esperar_ventana '[Mm]ac-actividad' 30)"
  local pid; pid="$(xdotool getwindowpid "$w")"
  local arbol="" ok=""
  for _ in $(seq 40); do
    arbol="$(python3 "$(dirname "$PRUEBAS_LIB")/atspi.py" --pid "$pid" --volcar 2>/dev/null || true)"
    case "$arbol" in *"% CPU"*) ok=1; break ;; esac
    sleep 1
  done
  captura actividad-cpu
  [ -n "$ok" ] || falla "no se ve la columna «% CPU» ni la lista de procesos"
  for t in CPU Memory Energy Disk Network Resources; do
    case "$arbol" in *"$t"*) ;; *) falla "falta la pestaña $t" ;; esac
  done
  kill -0 "$pid" 2>/dev/null || falla "mac-actividad se cayó"
  # La barra de menús, por org.mintmacos.Menu1 (si mac-menu está en este armado).
  command -v mac-menu >/dev/null || { paso "sin mac-menu: no se revisa la barra de menús"; return 0; }
  lanzar mac-menu
  sleep 2
  llamar() { gdbus call --session --dest org.mintmacos.Menu1 --object-path /org/mintmacos/Menu1 --method "org.mintmacos.Menu1.$1" "${@:2}" 2>&1 || true; }
  local b; b="$(llamar Barra "$w")"
  paso "Barra: ${b:0:300}"
  for m in File Edit View Window Help; do
    case "$b" in *"'$m'"*) ;; *) falla "la barra de menús no trae «$m»: $b" ;; esac
  done
  local f; f="$(llamar Abrir "$w" "0")"
  case "$f" in *"⌘W"*) paso "File ▸ Close con ⌘W" ;; *) falla "File no trae Close con ⌘W: $f" ;; esac
  local v; v="$(llamar Abrir "$w" "2")"
  case "$v" in *"Update Frequency"*"Very often"*|*"Very often"*"Update Frequency"*) paso "View trae Update Frequency" ;; *) falla "View no trae Update Frequency: $v" ;; esac
}
