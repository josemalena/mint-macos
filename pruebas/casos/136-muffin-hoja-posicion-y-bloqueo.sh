# caso: Muffin coloca la hoja (DIALOG + MODAL + transient, role «mint-macos-hoja», de otro proceso) según el perfil —colgada de la barra de título
# hasta Catalina, centrada desde Monterey— y la madre no recibe clics en su contenido mientras la hoja está abierta (la barra de título sí)
# límite: 150
# gestor: muffin
geometria() {   # geometria ID → X Y ANCHO ALTO del cliente en la pantalla (xwininfo; xdotool getwindowgeometry suma mal las extensiones del marco)
  xwininfo -id "$1" | awk '/Absolute upper-left X/ {x=$4} /Absolute upper-left Y/ {y=$4} /Width:/ {w=$2} /Height:/ {h=$2} END {print x, y, w, h}'
}
poner_perfil() { mkdir -p "$XDG_RUNTIME_DIR/mint-macos"; printf '{"version":"%s"}' "$1" > "$XDG_RUNTIME_DIR/mint-macos/macos.json"; }
prueba() {
  local aqui; aqui="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  requiere xdotool python3 gsettings
  gsettings set org.cinnamon.muffin attach-modal-dialogs true || falla "no pude encender attach-modal-dialogs"
  local reg="$PRUEBAS_RES/$PRUEBAS_CASO-madre.log"; rm -f "$reg"
  lanzar python3 -I "$aqui/ayudantes/madre-y-hoja.py" madre "$reg"
  local m; m="$(esperar_ventana '^madre-hoja$' 20)"
  sleep 1
  local PX PY PW PH HX HY HW HH
  read -r PX PY PW PH < <(geometria "$m")
  # control: sin hoja, un clic en el contenido llega a la madre
  xdotool mousemove $((PX + 60)) $((PY + 60)) click 1; sleep 0.5
  [ -s "$reg" ] || falla "control: sin hoja, la madre no recibió el clic"
  : > "$reg"
  local perfil
  for perfil in catalina-10.15 monterey-12.7.6; do
    poner_perfil "$perfil"
    lanzar python3 -I "$aqui/ayudantes/madre-y-hoja.py" hoja "$m"
    local h; h="$(esperar_ventana '^hoja-de-prueba$' 20)"
    sleep 1.5
    read -r HX HY HW HH < <(geometria "$h")
    paso "$perfil: madre ${PW}x${PH}+$PX+$PY; hoja ${HW}x${HH}+$HX+$HY"
    captura "hoja-$perfil"
    # Monterey centra sobre el marco completo de la madre (con su barra de título): el centro en Y es el del marco, no el del contenido
    local barra; barra="$(xprop -id "$m" _NET_FRAME_EXTENTS | awk -F'[=, ]+' '{print $4}')"
    local dcx=$(( (HX + HW / 2) - (PX + PW / 2) )) dcy=$(( (HY + HH / 2) - (PY - barra + (PH + barra) / 2) ))
    [ "${dcx#-}" -le 8 ] || falla "$perfil: la hoja no está centrada en X ($dcx)"
    case "$perfil" in
      catalina*) [ "$(( HY - PY ))" -le 4 ] && [ "$(( HY - PY ))" -ge -4 ] || falla "catalina: la hoja no cuelga de la barra de título (arriba de la hoja a $(( HY - PY )) px del contenido de la madre)" ;;
      monterey*) [ "${dcy#-}" -le 8 ] || falla "monterey: la hoja no está centrada en Y ($dcy)" ;;
    esac
    # la madre no recibe clics en su contenido; el que cae en la hoja no cuenta
    : > "$reg"
    xdotool mousemove $((PX + 30)) $((PY + PH - 30)) click 1; sleep 0.7
    [ ! -s "$reg" ] || falla "$perfil: la madre recibió un clic con la hoja abierta"
    paso "$perfil: la madre no recibe clics con la hoja abierta"
    xdotool windowclose "$h" 2>/dev/null || xdotool key --window "$h" Escape
    for _ in $(seq 25); do xdotool getwindowname "$h" >/dev/null 2>&1 || break; sleep 0.2; done
    for p in $(pgrep -f "madre-y-hoja.py hoja"); do grep -qz "^HOME=$HOME\$" "/proc/$p/environ" 2>/dev/null && kill "$p"; done
    sleep 0.5
  done
  # al cerrarse la hoja la madre vuelve a recibir clics
  : > "$reg"; xdotool mousemove $((PX + 30)) $((PY + PH - 30)) click 1; sleep 0.5
  [ -s "$reg" ] || falla "con la hoja cerrada la madre sigue sin recibir clics"
  paso "sin hoja, la madre vuelve a recibir clics"
  # la alerta (panel de confirmación, rol «mint-macos-alerta», la que pone Cocotron/Fynder): conserva MODAL y también bloquea a la madre
  poner_perfil monterey-12.7.6
  lanzar python3 -I "$aqui/ayudantes/madre-y-hoja.py" hoja "$m" mint-macos-alerta
  local a; a="$(esperar_ventana '^hoja-de-prueba$' 20)"
  sleep 1.5
  paso "alerta: _NET_WM_STATE = $(xprop -id "$a" _NET_WM_STATE | cut -d= -f2)"
  xprop -id "$a" _NET_WM_STATE | grep -q MODAL || falla "la alerta perdió _NET_WM_STATE_MODAL"
  : > "$reg"; xdotool mousemove $((PX + 30)) $((PY + PH - 30)) click 1; sleep 0.7
  [ ! -s "$reg" ] || falla "la madre recibió un clic con la alerta abierta"
  paso "la alerta conserva MODAL y la madre no recibe clics"
}
