# caso: System Preferences ▸ About System Preferences funciona: la app exporta la acción app.about (lo que busca appmenu@macos por D-Bus) y
# al activarla sale la ventana «About System Preferences»
# límite: 90
prueba() {
  requiere mac-preferencias gdbus xdotool python3
  export MP_PYTHON_DIR="$MINT_MACOS_REPO/settings"
  lanzar mac-preferencias --residente
  local ruta="/io/github/josemalena/MintMacosSettings" app="io.github.josemalena.MintMacosSettings" lista=""
  for _ in $(seq 40); do
    lista="$(gdbus call --session --dest "$app" --object-path "$ruta" --method org.gtk.Actions.List 2>/dev/null || true)"
    case "$lista" in *about*) break ;; esac
    sleep 0.5
  done
  case "$lista" in *about*) paso "la app exporta la acción about: $lista" ;; *) falla "la app no exporta app.about: «$lista»" ;; esac
  gdbus call --session --dest "$app" --object-path "$ruta" --method org.gtk.Actions.Activate about '[]' '{}' >/dev/null
  local v; v="$(esperar_ventana 'About System Preferences|[Mm]ac-settings' 30)"
  sleep 1
  captura about
  python3 "$(dirname "$PRUEBAS_LIB")/atspi.py" --pid "$(xdotool getwindowpid "$v")" --texto "System Preferences" --segundos 15 >&2 || falla "el diálogo no muestra «System Preferences»"
  paso "salió el About con el nombre de la app"
}
