# caso: sin el servicio org.mintmacos.Menu1 (nadie tiene el nombre) el applet lee el menú de xed por su cuenta, como antes
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

  # Los submenús salen a la derecha del renglón, no hacia abajo en acordeón (como en la Mac).
  local g
  g="$(gdbus call --session --dest org.Cinnamon --object-path /org/Cinnamon --method org.Cinnamon.Eval \
    "const Gio=imports.gi.Gio; let a=imports.ui.appletManager.getRunningInstancesForUuid('globalmenu@macos')[0]; let gm=new Gio.Menu(), sub=new Gio.Menu(); sub.append('Uno',null); sub.append('Dos',null); gm.append('Primero',null); gm.append_submenu('Recientes', sub); let m=a._menus[0]; m.open(false); m.removeAll(); a._raiz=m; a._agregarItems(m, gm, 0); let res='sin-submenu'; for (let it of m.box.get_children()) { let d=it._delegate; if (d && d.menu && d.label) { d.menu.open(false); let o=Cinnamon.util_get_transformed_allocation(it), s=Cinnamon.util_get_transformed_allocation(d.menu.actor); res=[d.label.text, Math.round(o.x2), Math.round(s.x1), Math.round(o.y1), Math.round(s.y1)].join(','); break; } } res" 2>&1)"
  paso "submenú: $g"
  case "$g" in *sin-submenu*) paso "xed no trae submenús en este equipo" ;; *)
    local x2 sx
    g="$(printf '%s' "$g" | tr -d "()'\""| sed 's/^true, //')"
    x2="$(printf '%s' "$g" | cut -d, -f2)"; sx="$(printf '%s' "$g" | cut -d, -f3)"
    [ "$sx" -ge "$((x2 - 6))" ] 2>/dev/null || falla "el submenú no sale a la derecha: $g" ;;
  esac
}
