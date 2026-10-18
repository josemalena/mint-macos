# caso: ⌘Q (Quit de appmenu@macos) busca el ítem Quit del menú de xed por org.mintmacos.Menu1 y lo activa: xed sale
# límite: 120
# gestor: cinnamon-applets
prueba() {
  requiere xed gdbus xdotool mac-menu
  export GTK_MODULES="${GTK_MODULES:-appmenu-gtk-module}"
  lanzar mac-menu
  sleep 1
  lanzar xed
  local w; w="$(esperar_ventana '[Xx]ed' 30)"
  local pid; pid="$(xdotool getwindowpid "$w")"
  xdotool windowfocus "$w" 2>/dev/null || true
  sleep 2
  paso "xed pid $pid, foco: $(xdotool getwindowfocus getwindowname 2>/dev/null)"
  gdbus call --session --dest org.Cinnamon --object-path /org/Cinnamon --method org.Cinnamon.Eval \
    "imports.ui.appletManager.getRunningInstancesForUuid('appmenu@macos')[0]._salirDeApp(); 'ok'" >/dev/null 2>&1 || true
  local sale=""
  for _ in $(seq 40); do kill -0 "$pid" 2>/dev/null || { sale=1; break; }; sleep 0.5; done
  captura appmenu-salir
  [ -n "$sale" ] || falla "xed no salió con ⌘Q (el Quit no se activó por el servicio)"
}
