# caso: una app GTK3 con menú exportado (xed) que se abre con otra app al frente trae sus menús en la barra global
# límite: 150
# gestor: cinnamon-applets
prueba() {
  requiere xed gdbus xdotool mac-acerca
  gsettings set io.github.josemalena.fynder.preferences global-menu true 2>/dev/null || true
  export GTK_MODULES="${GTK_MODULES:-appmenu-gtk-module}"
  lanzar mac-acerca
  esperar_ventana '[Mm]ac-acerca' 30 >/dev/null
  sleep 2
  lanzar xed
  local w; w="$(esperar_ventana '[Xx]ed' 30)"
  xdotool windowfocus "$w" 2>/dev/null || true
  local r="" n=0
  for _ in $(seq 20); do
    sleep 1
    r="$(gdbus call --session --dest org.Cinnamon --object-path /org/Cinnamon --method org.Cinnamon.Eval \
      "let g=imports.ui.appletManager.getRunningInstancesForUuid('globalmenu@macos'); g.length ? String(g[0]._caja.get_n_children()) : '-1'" 2>&1)"
    n="$(printf '%s' "$r" | grep -o "[0-9-]\+'\|\"[0-9-]\+" | tr -dc '0-9-' || true)"
    [ "${n:-0}" -gt 0 ] 2>/dev/null && break
  done
  paso "botones en la barra global: ${n:-?} ($r)"
  captura menu-global-xed
  [ "${n:-0}" -gt 0 ] 2>/dev/null || falla "xed no trajo sus menús a la barra global: $r"
}
