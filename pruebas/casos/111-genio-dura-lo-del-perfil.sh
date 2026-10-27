# caso: el genio (Magic Lamp) dura lo que dice el perfil de macOS al minimizar y al restaurar (Monterey: 433 y 450 ms), no los 350 ms del ajuste
# límite: 200
# gestor: cinnamon-animaciones
# Una ventana de xed se minimiza y se restaura; el perfil de la prueba trae las medidas de Monterey.
eval_js() {   # eval_js CÓDIGO: lo corre dentro de Cinnamon (org.Cinnamon.Eval)
  gdbus call --session --dest org.Cinnamon --object-path /org/Cinnamon --method org.Cinnamon.Eval "$1"
}
prueba() {
  requiere xed xdotool wmctrl gdbus
  mkdir -p "$XDG_CONFIG_HOME/mint-macos" "$XDG_DATA_HOME/mint-macos/macos/prueba/apps"
  echo '{"version": "prueba"}' > "$XDG_CONFIG_HOME/mint-macos/macos.json"
  echo '{"id": "animaciones", "comportamiento": {"genio-minimizar": {"ms": 433}, "genio-restaurar": {"ms": 450}}}' \
    > "$XDG_DATA_HOME/mint-macos/macos/prueba/apps/animaciones.json"
  # Cinnamon leyó el perfil al hacer la animación (no al arrancar), así que basta con que exista
  grep -q 'Loaded extension CinnamonMagicLamp' "$PRUEBAS_RES/cinnamon.log" || saltar "Magic Lamp no está instalada en esta máquina"
  # Xvfb con llvmpipe pinta la deformación a 1-2 cuadros por segundo: la grabación no sirve para medir el tiempo. Se mide dentro de Cinnamon: un
  # gancho en Clutter.Timeline.start anota la duración con la que se arma y lo que tardó en completarse (reloj monótono).
  eval_js "const T = imports.gi.Clutter.Timeline; if (!T.prototype.__gancho) { T.prototype.__gancho = true; const ini = T.prototype.start;
    T.prototype.start = function () { const t0 = GLib.get_monotonic_time(), d = this.duration;
      this.connect('completed', () => global.log('MEDIDA duracion=' + d + ' real=' + Math.round((GLib.get_monotonic_time() - t0) / 1000)));
      return ini.call(this); }; }" > /dev/null
  for p in $(pgrep -x xed); do grep -qz "^HOME=$HOME\$" "/proc/$p/environ" 2>/dev/null && kill "$p"; done
  lanzar xed
  local v; v="$(esperar_ventana '^[Xx]ed$' 30)"
  sleep 2
  xdotool mousemove 5 5
  local n0 d; n0="$(grep -c 'MEDIDA' "$PRUEBAS_RES/cinnamon.log" || true)"
  xdotool windowminimize "$v"
  sleep 2
  d="$(grep 'MEDIDA' "$PRUEBAS_RES/cinnamon.log" | tail -n +$((n0 + 1)) | sed -n 's/.*duracion=\([0-9.]*\) real=\([0-9]*\).*/\1 \2/p' | head -1)"
  paso "minimizar: duración de la animación y lo que tardó de verdad (ms): ${d:-ninguna} (perfil 433; ajuste de la extensión 350)"
  [ -n "$d" ] || falla "el genio no corrió al minimizar"
  [ "${d%% *}" -eq 433 ] || falla "minimizar armó una animación de ${d%% *} ms, no los 433 del perfil"
  n0="$(grep -c 'MEDIDA' "$PRUEBAS_RES/cinnamon.log" || true)"
  wmctrl -i -a "$v"
  sleep 2
  d="$(grep 'MEDIDA' "$PRUEBAS_RES/cinnamon.log" | tail -n +$((n0 + 1)) | sed -n 's/.*duracion=\([0-9.]*\) real=\([0-9]*\).*/\1 \2/p' | head -1)"
  paso "restaurar: ${d:-ninguna} (perfil 450)"
  [ -n "$d" ] || falla "el genio no corrió al restaurar"
  [ "${d%% *}" -eq 450 ] || falla "restaurar armó una animación de ${d%% *} ms, no los 450 del perfil"
  cerrar_ventana "$v"
}
