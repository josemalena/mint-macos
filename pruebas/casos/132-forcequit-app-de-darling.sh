# caso: una ventana de una app de Mac en Darling (WM_CLASS «darling-<id>», sin .desktop) sale en Force Quit con su nombre de _DARLING_APP_NAME
# y no como «Darling com.apple.textedit» (27-10-2026)
# límite: 90
prueba() {
  despejar_pantalla
  requiere mac-forcequit wmctrl xdotool python3
  local aqui; aqui="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  lanzar python3 -I "$aqui/ayudantes/ventana-darling.py" TextEdit com.apple.TextEdit
  esperar_ventana '^darling-com.apple.textedit$' 30 >/dev/null
  sleep 1
  lanzar mac-forcequit
  local fq; fq="$(esperar_ventana '[Mm]ac-forcequit' 20)"
  local pidfq volcado=""; pidfq="$(xdotool getwindowpid "$fq")"
  for _ in $(seq 20); do
    volcado="$(python3 "$(dirname "$PRUEBAS_LIB")/atspi.py" --pid "$pidfq" --volcar 2>&1)"
    echo "$volcado" | grep -q "TextEdit" && break
    sleep 1
  done
  echo "$volcado" >&2
  echo "$volcado" | grep -qi "darling" && falla "Force Quit muestra el nombre inventado con la clase («darling…»)"
  echo "$volcado" | grep -q "TextEdit" || falla "Force Quit no muestra «TextEdit»"
  captura force-quit-darling
  paso "la app de Darling sale como «TextEdit», sin .desktop"
}
