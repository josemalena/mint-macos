# caso: el panel del Notification Center entra deslizándose (230 ms, easeInEaseOut) y sale en 158 ms, sin fundido, con el ancho de 360 pt del perfil de Monterey
# límite: 120
# gestor: cinnamon-animaciones
# Un gancho en Clutter.Actor.ease anota con qué propiedades y duración se anima cada cosa (Xvfb con llvmpipe pinta a pocos cuadros: no se mide
# el reloj de pared). El perfil de Monterey del repo lo pone el gestor antes de arrancar Cinnamon.
eval_js() { gdbus call --session --dest org.Cinnamon --object-path /org/Cinnamon --method org.Cinnamon.Eval "$1"; }
anotadas() {   # anotadas N: las animaciones anotadas desde la N-ésima, una por línea
  grep 'MEDIDA' "$PRUEBAS_RES/cinnamon.log" | tail -n +$(($1 + 1)) | sed 's/.*MEDIDA //' || true
}
prueba() {
  requiere gdbus
  eval_js "const A = imports.gi.Clutter.Actor.prototype; if (!A.__gancho) { A.__gancho = true; const ini = A.ease;
    A.ease = function (p) { if (p && p.duration !== undefined) global.log('MEDIDA ' + p.duration + ' ' + Object.keys(p).filter(k => k != 'duration' && k != 'mode' && k != 'onComplete').join(',')); return ini.call(this, p); }; }" > /dev/null
  # el panel está armado desde el arranque; se espera a que pase el calentamiento (8 s)
  sleep 10
  local n0 a
  n0="$(grep -c 'MEDIDA' "$PRUEBAS_RES/cinnamon.log" || true)"
  eval_js "global.mintMacosNotificationCenter()" > /dev/null
  sleep 2
  a="$(anotadas "$n0")"
  paso "al abrir: $(echo "$a" | tr '\n' ';')"
  echo "$a" | grep -qx '230 x' || falla "no entró deslizándose en 230 ms (solo x): $a"
  echo "$a" | grep -q 'opacity' && falla "el panel se fundió al entrar: $a"
  captura nc-abierto
  # el ancho del panel: 360 pt (Monterey)
  local ancho; ancho="$(eval_js "String(imports.ui.appletManager.getRunningInstancesForUuid('notificaciones@macos')[0].menu.box.width)")"
  paso "ancho del panel: $ancho"
  case "$ancho" in *\"360\"*) ;; *) falla "el panel no mide 360: $ancho" ;; esac
  n0="$(grep -c 'MEDIDA' "$PRUEBAS_RES/cinnamon.log" || true)"
  eval_js "global.mintMacosNotificationCenter()" > /dev/null
  sleep 2
  a="$(anotadas "$n0")"
  paso "al cerrar: $(echo "$a" | tr '\n' ';')"
  echo "$a" | grep -qx '158 x' || falla "no salió deslizándose en 158 ms (solo x): $a"
  echo "$a" | grep -q 'opacity' && falla "el panel se fundió al salir: $a"
  true
}
