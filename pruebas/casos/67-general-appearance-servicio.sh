# caso: General ▸ Appearance habla con org.mintmacos.Apariencia1: Light/Auto salen del gris y llaman a Poner; los acentos son los que
# da el servicio (aquí uno de mentira que solo anota lo que le ponen).
# límite: 90
prueba() {
  requiere mac-preferencias xdotool python3
  export MP_PYTHON_DIR="$MINT_MACOS_REPO/settings"
  export APARIENCIA_REGISTRO="$HOME/apariencia-registro.txt"
  : > "$APARIENCIA_REGISTRO"
  liberar_nombre_dbus org.mintmacos.Apariencia1
  lanzar python3 "$MINT_MACOS_REPO/pruebas/ayudantes/apariencia-falsa.py"
  # General pide Estado al construirse: el de mentira tiene que tener el nombre antes. NameHasOwner no activa a nadie; llamar a
  # Estado sí podría arrancar el servicio de verdad (tiene activación por D-Bus) y ganarle el nombre al falso.
  for _ in $(seq 50); do
    [ "$(gdbus call --session -d org.freedesktop.DBus -o /org/freedesktop/DBus -m org.freedesktop.DBus.NameHasOwner org.mintmacos.Apariencia1 2>/dev/null)" = "(true,)" ] && break
    sleep 0.2
  done
  lanzar mac-preferencias
  local v; v="$(esperar_ventana '[Mm]ac-settings' 40)"
  mac-preferencias general
  for _ in $(seq 50); do [ "$(titulo "$v")" = "General" ] && break; sleep 0.2; done
  [ "$(titulo "$v")" = "General" ] || falla "no abrió General: «$(titulo "$v")»"
  esperar_texto "$v" "Accent color:" 20
  atspi() { python3 "$(dirname "$PRUEBAS_LIB")/atspi.py" --pid "$(xdotool getwindowpid "$v")" "$@"; }
  for _ in 1 2 3 4 5; do
    atspi --texto "Light" --rol "radio button" --pulsar --segundos 15 >&2 || falla "no se pudo pulsar Light"
    sleep 1
    grep -qx "light||" "$APARIENCIA_REGISTRO" && break
  done
  grep -qx "light||" "$APARIENCIA_REGISTRO" || falla "Light no llamó a Poner(light): $(cat "$APARIENCIA_REGISTRO")"
  paso "Light llamó a Poner"
  for _ in 1 2 3 4 5; do
    atspi --texto "Auto" --rol "radio button" --pulsar --segundos 15 >&2 || falla "no se pudo pulsar Auto"
    sleep 1
    grep -qx "auto||" "$APARIENCIA_REGISTRO" && break
  done
  grep -qx "auto||" "$APARIENCIA_REGISTRO" || falla "Auto no llamó a Poner(auto): $(cat "$APARIENCIA_REGISTRO")"
  paso "Auto llamó a Poner"
  captura general-appearance
}
