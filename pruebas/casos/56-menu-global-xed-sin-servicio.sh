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

  # Los submenús se despliegan hacia abajo, en acordeón, con sangría para que se vea que son de un submenú.
  local g
  g="$(gdbus call --session --dest org.Cinnamon --object-path /org/Cinnamon --method org.Cinnamon.Eval \
    "const Gio=imports.gi.Gio; let a=imports.ui.appletManager.getRunningInstancesForUuid('globalmenu@macos')[0]; let gm=new Gio.Menu(), sub=new Gio.Menu(); sub.append('Uno',null); sub.append('Dos',null); gm.append('Primero',null); gm.append_submenu('Recientes', sub); let m=a._menus[0]; m.open(false); m.removeAll(); a._raiz=m; a._agregarItems(m, gm, 0); let res='sin-submenu'; for (let it of m.box.get_children()) { let d=it._delegate; if (d && d.menu && d.label) { d.menu.open(false); let o=Cinnamon.util_get_transformed_allocation(it), h=d.menu.box.get_children()[0], s=Cinnamon.util_get_transformed_allocation(h.actor||h); res=[d.label.text, Math.round(o.x1), Math.round(s.x1), Math.round(o.y2), Math.round(s.y1)].join(','); break; } } res" 2>&1)"
  paso "submenú: $g"
  case "$g" in *sin-submenu*) paso "xed no trae submenús en este equipo" ;; *)
    local ox sx oy2 sy
    g="$(printf '%s' "$g" | tr -d "()'\""| sed 's/^true, //')"
    ox="$(printf '%s' "$g" | cut -d, -f2)"; sx="$(printf '%s' "$g" | cut -d, -f3)"; oy2="$(printf '%s' "$g" | cut -d, -f4)"; sy="$(printf '%s' "$g" | cut -d, -f5)"
    [ "$sx" -ge "$((ox + 12))" ] 2>/dev/null || falla "el submenú no lleva sangría: $g"
    [ "$sy" -ge "$((oy2 - 2))" ] 2>/dev/null || falla "el submenú no se despliega hacia abajo: $g" ;;
  esac

  # Ítems alternos (x-constanza-alternate): el alterno va escondido y toma el lugar de su base mientras ⌥ está apretado.
  local alt
  alt="$(gdbus call --session --dest org.Cinnamon --object-path /org/Cinnamon --method org.Cinnamon.Eval \
    "const Gio=imports.gi.Gio, GLib=imports.gi.GLib; let a=imports.ui.appletManager.getRunningInstancesForUuid('globalmenu@macos')[0]; let gm=new Gio.Menu(); gm.append('Move to Trash',null); let it=Gio.MenuItem.new('Delete Immediately…',null); it.set_attribute_value('x-constanza-alternate', GLib.Variant.new_boolean(true)); it.set_attribute_value('x-constanza-accel', GLib.Variant.new_string('⌥⌘⌫')); gm.append_item(it); let m=a._menus[0]; m.open(false); m.removeAll(); m._pares=[]; a._raiz=m; a._agregarItems(m, gm, 0); let vis=()=>m.box.get_children().map(c=>c.visible?1:0).join(''); let antes=vis(); a._sincAlt(m, true); let con=vis(); a._sincAlt(m, false); [antes,con,vis()].join('/')" 2>&1)"
  paso "alternos (sin ⌥ / con ⌥ / suelto): $alt"
  case "$alt" in *"10/01/10"*) ;; *) falla "el ítem alterno no cambia con ⌥: $alt" ;; esac

  # Etiquetas del Finder (x-constanza-tag-color): los ítems seguidos van en UNA fila de círculos, y «Tags…» sigue como ítem normal.
  local et
  et="$(gdbus call --session --dest org.Cinnamon --object-path /org/Cinnamon --method org.Cinnamon.Eval \
    "const Gio=imports.gi.Gio, GLib=imports.gi.GLib; let a=imports.ui.appletManager.getRunningInstancesForUuid('globalmenu@macos')[0]; let gm=new Gio.Menu(); for (let [n,c] of [['Red','#ff453a'],['Green','#34c759'],['None','']]) { let it=Gio.MenuItem.new(n,null); it.set_attribute_value('x-constanza-tag-color', GLib.Variant.new_string(c)); gm.append_item(it); } gm.append('Tags…',null); try { let m=a._menus[0]; m.open(false); m.removeAll(); m._pares=[]; a._raiz=m; a._agregarItems(m, gm, 0); let hijos=m.box.get_children(); let fila=hijos[0]; let circulos=0; let buscar=(x)=>{ for (let h of x.get_children()) { if (h.style && h.style.indexOf('border-radius: 9px')>=0) circulos++; buscar(h); } }; buscar(fila); [hijos.length, circulos].join('/') } catch (e) { 'ERR ' + e + ' ' + e.stack }" 2>&1)"
  paso "etiquetas (ítems / círculos): $et"
  case "$et" in *"2/3"*) ;; *) falla "las etiquetas no salieron en una fila de círculos más «Tags…»: $et" ;; esac
  captura etiquetas-fila
}
