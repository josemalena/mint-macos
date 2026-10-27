# caso: el panel del Notification Center entra deslizándose (240 ms, easeInEaseOut) y sale en 190 ms, sin fundido, con el ancho de 360 pt del perfil de Monterey
# límite: 120
# gestor: cinnamon-animaciones
# Un gancho en Clutter.Actor.ease anota con qué propiedades y duración se anima cada cosa (Xvfb con llvmpipe pinta a pocos cuadros: no se mide
# el reloj de pared). El perfil de Monterey del repo lo pone el gestor antes de arrancar Cinnamon.
anotadas() {   # anotadas N: las animaciones anotadas desde la N-ésima, una por línea
  grep 'MEDIDA' "$PRUEBAS_RES/cinnamon.log" | tail -n +$(($1 + 1)) | sed 's/.*MEDIDA duracion=//; s/ claves=/ /' || true
}
prueba() {
  requiere gdbus
  gancho_ease
  # el panel está armado desde el arranque; se espera a que pase el calentamiento (8 s)
  sleep 10
  local n0 a
  n0="$(grep -c 'MEDIDA' "$PRUEBAS_RES/cinnamon.log" || true)"
  eval_js "global.mintMacosNotificationCenter()" > /dev/null
  sleep 2
  a="$(anotadas "$n0")"
  paso "al abrir: $(echo "$a" | tr '\n' ';')"
  echo "$a" | grep -qx '240 x' || falla "no entró deslizándose en 240 ms (solo x): $a"
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
  echo "$a" | grep -qx '190 x' || falla "no salió deslizándose en 190 ms (solo x): $a"
  echo "$a" | grep -q 'opacity' && falla "el panel se fundió al salir: $a"
  # sin las medidas (sin macos.json, archivo ausente, JSON roto) el applet lee null y no se desliza: la función que lee el perfil, sola, con cjs
  local aqui; aqui="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  local d="$PRUEBAS_RES/perfil-roto" variante r
  for variante in ausente roto sin-macos-json; do
    rm -rf "$d"; mkdir -p "$d/c/mint-macos" "$d/d/mint-macos/macos/m/apps"
    case "$variante" in
      ausente) echo '{"version":"m"}' > "$d/c/mint-macos/macos.json" ;;
      roto) echo '{"version":"m"}' > "$d/c/mint-macos/macos.json"; echo '{"comportamiento": {' > "$d/d/mint-macos/macos/m/apps/animaciones.json" ;;
    esac
    r="$(XDG_RUNTIME_DIR="$d/none" XDG_CONFIG_HOME="$d/c" XDG_DATA_HOME="$d/d" cjs -c "const GLib = imports.gi.GLib;
      $(sed -n '/^function delPerfil/,/^}/p' "$aqui/../applets/notificaciones@macos/applet.js"); print(String(delPerfil('notification-center-entrar', 'ms')))" 2>&1)"
    [ "$r" = null ] || falla "perfil $variante: delPerfil dio «$r» y debía ser null"
    paso "perfil $variante: el applet lee null (queda el menú de Cinnamon, ancho 345)"
  done
  true
}
