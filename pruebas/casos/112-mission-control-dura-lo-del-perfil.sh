# caso: Mission Control entra en lo que dice el perfil de macOS (250 ms, easeInEaseOut) y no en los 200 ms de Cinnamon, sin tocar los ajustes de José
# límite: 120
# gestor: cinnamon-animaciones
# Una ventana de xed abierta y ⌃↑ (por Main.overview): las ventanas van a su lugar con Overview.ANIMATION_TIME. Un gancho
# anota (en Clutter.Actor.ease) las duraciones con que Cinnamon arma sus animaciones (Xvfb con llvmpipe pinta a pocos cuadros: no se mide el reloj de pared).
eval_js() { gdbus call --session --dest org.Cinnamon --object-path /org/Cinnamon --method org.Cinnamon.Eval "$1"; }
prueba() {
  requiere xed xdotool gdbus
  mkdir -p "$XDG_CONFIG_HOME/mint-macos" "$XDG_DATA_HOME/mint-macos/macos/prueba/apps"
  echo '{"version": "prueba"}' > "$XDG_CONFIG_HOME/mint-macos/macos.json"
  echo '{"id": "animaciones", "comportamiento": {"mission-control-entrar": {"ms": 250, "curva": "easeInEaseOut (0.42,0,0.58,1)"}}}' \
    > "$XDG_DATA_HOME/mint-macos/macos/prueba/apps/animaciones.json"
  # La extensión lee el perfil al encenderse: se apaga y se vuelve a encender (como el arranque de la sesión con el perfil ya puesto)
  eval_js "const EM = imports.ui.extensionSystem; EM.disableExtension ? 0 : 0;" > /dev/null || true
  gsettings set org.cinnamon enabled-extensions "['cmdtab@macos']"; sleep 1
  gsettings set org.cinnamon enabled-extensions "['cmdtab@macos', 'misioncontrol@macos']"; sleep 2
  eval_js "const A = imports.gi.Clutter.Actor.prototype; if (!A.__gancho) { A.__gancho = true; const ini = A.ease;
    A.ease = function (p) { if (p && p.duration !== undefined) global.log('MEDIDA duracion=' + p.duration); return ini.call(this, p); }; }" > /dev/null
  for p in $(pgrep -x xed); do grep -qz "^HOME=$HOME\$" "/proc/$p/environ" 2>/dev/null && kill "$p"; done
  lanzar xed
  local v; v="$(esperar_ventana '^[Xx]ed$' 30)"
  sleep 2
  local n0; n0="$(grep -c 'MEDIDA' "$PRUEBAS_RES/cinnamon.log" || true)"
  eval_js "imports.ui.main.overview.show()" > /dev/null
  sleep 3
  local d; d="$(grep 'MEDIDA' "$PRUEBAS_RES/cinnamon.log" | tail -n +$((n0 + 1)) | sed -n 's/.*duracion=\([0-9.]*\).*/\1/p' | tr '\n' ' ' || true)"
  paso "duraciones al entrar: $d"
  case " $d" in *" 250 "*) ;; *) falla "ninguna animación de 250 ms al entrar a Mission Control: $d" ;; esac
  case " $d" in *" 112.5 "*) ;; *) falla "el fundido del resto de la pantalla (0.45 de la duración) no es de 112.5 ms: $d" ;; esac
  case " $d" in *" 90 "*) falla "quedó el fundido de Cinnamon (90 ms): $d" ;; esac
  # al salir, la de Cinnamon: lo medido es la entrada, la salida no está medida
  n0="$(grep -c 'MEDIDA' "$PRUEBAS_RES/cinnamon.log" || true)"
  eval_js "imports.ui.main.overview.hide()" > /dev/null
  sleep 2
  d="$(grep 'MEDIDA' "$PRUEBAS_RES/cinnamon.log" | tail -n +$((n0 + 1)) | sed -n 's/.*duracion=\([0-9.]*\).*/\1/p' | tr '\n' ' ' || true)"
  paso "duraciones al salir: $d"
  case " $d" in *" 250 "*) falla "la salida usó los 250 ms de la entrada: $d" ;; esac
  # apagada la extensión, Cinnamon recupera la suya
  gsettings set org.cinnamon enabled-extensions "['cmdtab@macos']"; sleep 2
  n0="$(grep -c 'MEDIDA' "$PRUEBAS_RES/cinnamon.log" || true)"
  eval_js "imports.ui.main.overview.show()" > /dev/null; sleep 3
  d="$(grep 'MEDIDA' "$PRUEBAS_RES/cinnamon.log" | tail -n +$((n0 + 1)) | sed -n 's/.*duracion=\([0-9.]*\).*/\1/p' | tr '\n' ' ' || true)"
  paso "con la extensión apagada: $d"
  case " $d" in *" 90 "*) ;; *) falla "apagada la extensión no volvió a la duración de Cinnamon (fundido de 90 ms): $d" ;; esac
  case " $d" in *" 250 "*) falla "apagada la extensión siguió con 250 ms: $d" ;; esac
  eval_js "imports.ui.main.overview.hide()" > /dev/null
  cerrar_ventana "$v"
}
