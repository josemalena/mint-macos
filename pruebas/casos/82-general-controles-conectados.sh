# caso: en General, ocultar la barra de menús, Click in the scroll bar to y font smoothing escriben las claves de perfiles/adaptaciones.json
# límite: 120
# esperar_clave CMD ESPERADO: la escritura a dconf tarda un poco; se mira hasta 8 s
esperar_valor() {
  local esperado="$1"; shift
  for _ in $(seq 40); do
    "$@" 2>/dev/null | grep -q -- "$esperado" && return 0
    sleep 0.2
  done
  return 1
}
prueba() {
  requiere mac-preferencias xdotool python3 gsettings
  export MP_PYTHON_DIR="$MINT_MACOS_REPO/settings"
  gsettings set org.cinnamon panels-enabled "['1:0:top']"
  gsettings set org.cinnamon panels-autohide "['1:false']"
  gsettings set org.cinnamon.settings-daemon.plugins.xsettings antialiasing grayscale
  local spice="$HOME/.config/cinnamon/spices/applemenu@macos"
  mkdir -p "$spice"
  printf '{"recent-items": {"type": "generic", "default": 10, "value": 10}}' > "$spice/applemenu@macos.json"
  lanzar mac-preferencias
  local v; v="$(esperar_ventana '[Mm]ac-settings' 40)"
  mac-preferencias general
  for _ in $(seq 50); do [ "$(titulo "$v")" = "General" ] && break; sleep 0.2; done
  esperar_texto "$v" "Accent color:" 20
  atspi() { python3 "$(dirname "$PRUEBAS_LIB")/atspi.py" --pid "$(xdotool getwindowpid "$v")" "$@"; }
  sleep 1

  atspi --texto "Automatically hide and show the menu bar" --rol "check box" --pulsar --segundos 15 >&2 || falla "no se pudo pulsar «Automatically hide…»"
  esperar_valor "1:true" gsettings get org.cinnamon panels-autohide || falla "ocultar la barra no escribió panels-autohide: $(gsettings get org.cinnamon panels-autohide)"
  paso "panels-autohide quedó en 1:true"

  atspi --texto "Jump to the spot that’s clicked" --rol "radio button" --pulsar --segundos 15 >&2 || falla "no se pudo pulsar «Jump to the spot…»"
  esperar_valor "Gtk/PrimaryButtonWarpsSlider.*1" gsettings get org.cinnamon.settings-daemon.plugins.xsettings overrides \
    || falla "no escribió Gtk/PrimaryButtonWarpsSlider=1: $(gsettings get org.cinnamon.settings-daemon.plugins.xsettings overrides)"
  paso "PrimaryButtonWarpsSlider quedó en 1"

  atspi --texto "Use font smoothing when available" --rol "check box" --pulsar --segundos 15 >&2 || falla "no se pudo pulsar «Use font smoothing…»"
  esperar_valor "none" gsettings get org.cinnamon.settings-daemon.plugins.xsettings antialiasing \
    || falla "font smoothing no escribió antialiasing=none: $(gsettings get org.cinnamon.settings-daemon.plugins.xsettings antialiasing)"
  paso "antialiasing quedó en none"
  captura general-controles
}
