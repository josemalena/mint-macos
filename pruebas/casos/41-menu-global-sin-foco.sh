# caso: al entrar, sin ninguna ventana con foco, la barra de menús dice Fynder (no «Finder») y trae los menús del escritorio
# límite: 120
# gestor: cinnamon-applets
prueba() {
  requiere fynder-desktop gdbus xdotool
  gsettings set io.github.josemalena.fynder.preferences global-menu true
  # Como al entrar: nada con foco y el escritorio de Fynder saliendo después de la barra.
  lanzar fynder-desktop
  sleep 6
  local v; v="$(xdotool search --class nemo-desktop | head -1 || true)"
  paso "ventana del escritorio de Fynder: ${v:-ninguna}"
  local r
  consulta() {
    gdbus call --session --dest org.Cinnamon --object-path /org/Cinnamon --method org.Cinnamon.Eval \
      "let g=imports.ui.appletManager.getRunningInstancesForUuid('globalmenu@macos'); let a=imports.ui.appletManager.getRunningInstancesForUuid('appmenu@macos'); [String(global.display.focus_window), a.length ? a[0]._applet_label.get_text() : 'sin-applet', g.length ? g[0]._caja.get_n_children() : -1].join('|')" 2>&1
  }
  # Sin ventana con foco, como al entrar (o al cerrar la última).
  gdbus call --session --dest org.Cinnamon --object-path /org/Cinnamon --method org.Cinnamon.Eval \
    "global.display.unset_input_focus(global.get_current_time()); 'ok'" >/dev/null 2>&1 || true
  sleep 2
  r="$(consulta)"
  paso "estado: $r"
  captura menu-global-sin-foco
  case "$r" in *"|Fynder|"*) paso "la barra dice Fynder" ;; *) falla "la barra no dice Fynder: $r" ;; esac
  case "$r" in *"|0'"*|*"|-1'"*) falla "la barra de menús está vacía: $r" ;; *) paso "hay menús" ;; esac

  # El menú de la app Fynder es el del Finder (Catalina 12.31.32 PM): con Services ▸ y sin Quit.
  local m
  m="$(gdbus call --session --dest org.Cinnamon --object-path /org/Cinnamon --method org.Cinnamon.Eval \
    "let a=imports.ui.appletManager.getRunningInstancesForUuid('appmenu@macos')[0]; a._updateMenuLabels(true); [a.servicesItem ? a.servicesItem.label.text : 'sin-services', a.quitItem.actor.visible].join('|')" 2>&1)"
  paso "menú de la app: $m"
  case "$m" in *"Services|false"*) paso "tiene Services y no tiene Quit" ;; *) falla "el menú de Fynder debe tener Services y no Quit: $m" ;; esac
  # About (y los demás programas internos de mint-macos) no tienen menú: la barra sigue con la app anterior (Fynder).
  if command -v mac-acerca >/dev/null; then
    lanzar mac-acerca
    local w; w="$(esperar_ventana '[Mm]ac-acerca' 30)"
    xdotool windowfocus "$w" 2>/dev/null || true
    sleep 2
    r="$(consulta)"
    paso "con About al frente: $r"
    case "$r" in *"|Fynder|"*) paso "la barra sigue en Fynder" ;; *) falla "con About al frente la barra no sigue con la app anterior: $r" ;; esac
  fi
}
