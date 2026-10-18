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
}
