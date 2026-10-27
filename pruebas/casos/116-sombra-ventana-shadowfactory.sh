# caso: Muffin deja ajustar la sombra de las ventanas desde Cinnamon (Meta.ShadowFactory.set_params), sin tocar el CSS del tema
# límite: 90
# gestor: cinnamon-animaciones
prueba() {
  requiere gdbus
  local r
  r="$(eval_js "const F = imports.gi.Meta.ShadowFactory.get_default(); String(typeof F.set_params) + ' ' + JSON.stringify(F.get_params('normal', true))" 2>&1 || true)"
  paso "ShadowFactory: $r"
  case "$r" in *function*) ;; *) falla "no hay Meta.ShadowFactory.set_params: $r" ;; esac
  true
}
