# caso: la fila de círculos de etiquetas del menú File de la barra global: cada círculo decide por sí solo; un clic en el segundo llama solo a su acción y
# no a la de los demás (Dev arregló lo mismo en el menú contextual de Fynder: el hover no siempre llegaba)
# gestor: cinnamon-applets
# límite: 120
prueba() {
  requiere gdbus xdotool
  ev() { gdbus call --session --dest org.Cinnamon --object-path /org/Cinnamon --method org.Cinnamon.Eval "$1" 2>&1; }
  local mod='imports.ui.appletManager.applets["globalmenu@macos"].applet'
  local r; r="$(ev "typeof $mod.filaEtiquetas")"
  case "$r" in *function*) ;; *) falla "no puedo llegar a filaEtiquetas del applet: $r" ;; esac
  # Un menú propio con la fila de tres círculos y un contador por círculo
  ev "
    const PopupMenu = imports.ui.popupMenu, St = imports.gi.St, Main = imports.ui.main;
    global.__cuentas = [0, 0, 0];
    let ancla = new St.Bin({ width: 20, height: 20, reactive: true });
    Main.uiGroup.add_actor(ancla); ancla.set_position(300, 200);
    let menu = new PopupMenu.PopupMenu(ancla);
    Main.uiGroup.add_actor(menu.actor);
    let fila = $mod.filaEtiquetas(menu, [0, 1, 2].map(i => ({ color: ['#ff3b30', '#ff9500', '#34c759'][i], nombre: 'c' + i, activo: true, activar: () => { global.__cuentas[i]++; } })));
    menu.addMenuItem(fila);
    global.__menu = menu; global.__fila = fila; menu.open(false); 'ok'" >/dev/null
  sleep 1
  # El centro del segundo círculo, en pantalla
  local pos; pos="$(ev "
    let caja = global.__fila.actor.get_children()[0], botones = [];
    let busca = a => { for (let h of a.get_children()) { if (h.style && h.style.indexOf('border-radius: 9px') >= 0) botones.push(h); busca(h); } };
    busca(global.__fila.actor);
    let [x, y] = botones[1].get_transformed_position(); let [w, h] = botones[1].get_size();
    Math.round(x + w / 2) + ' ' + Math.round(y + h / 2) + ' ' + botones.length")"
  paso "centro del segundo círculo y cuántos hay: $pos"
  local nums; nums="$(echo "$pos" | grep -o '[0-9]\+ [0-9]\+ [0-9]\+' | head -1)"
  [ -n "$nums" ] || falla "no pude ubicar los círculos: $pos"
  set -- $nums
  [ "$3" -eq 3 ] || falla "la fila no trae tres círculos ($3)"
  xdotool mousemove "$1" "$2"; sleep 0.5
  xdotool click 1; sleep 1
  local cuentas; cuentas="$(ev "JSON.stringify(global.__cuentas)")"
  paso "cuentas por círculo tras un clic en el segundo: $cuentas"
  case "$cuentas" in *"[0,1,0]"*) paso "solo el segundo círculo hizo su acción" ;; *) falla "el clic en el segundo círculo no llamó solo a su acción: $cuentas" ;; esac
}
