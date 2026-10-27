# caso: General con el perfil de Monterey trae «Allow wallpaper tinting in windows» y «Prefer tabs» y no trae «Automatically hide…» ni «font smoothing»; con Catalina, al revés
# límite: 120
# (INFORME-A de trabajo-samana-20261026/preferencias: las diferencias de General entre Catalina y Monterey, de las capturas 08-pref-general--Main)
matar_preferencias() {   # la app es de instancia única: hasta que se vaya de verdad, o la siguiente solo activaría la vieja con su perfil
  local p vivo i
  for i in $(seq 40); do
    vivo=false
    for p in $(pgrep -x mac-preferencia); do
      if grep -qz "^HOME=$HOME\$" "/proc/$p/environ" 2>/dev/null; then vivo=true; kill $([ "$i" -gt 12 ] && echo -KILL) "$p" 2>/dev/null; fi
    done
    $vivo || break; sleep 0.25
  done
  sleep 1
}
volcar() {   # volcar VERSION: abre General con esa versión activa y deja el texto de la ventana en $VOLCADO
  mkdir -p "$XDG_RUNTIME_DIR/mint-macos"
  printf '{"version":"%s"}' "$1" > "$XDG_RUNTIME_DIR/mint-macos/macos.json"
  lanzar mac-preferencias com.apple.preference.general
  local v; v="$(esperar_ventana '[Mm]ac-settings' 40)"
  esperar_texto "$v" "Recent items:" 30
  VOLCADO="$(python3 "$(dirname "$PRUEBAS_LIB")/atspi.py" --pid "$(xdotool getwindowpid "$v")" --volcar 2>&1)"
  captura "general-$1"
  # (la app sigue viva con la ventana cerrada: se mata la de esta prueba por el HOME)
  matar_preferencias
}
prueba() {
  requiere mac-preferencias xdotool python3
  export MP_PYTHON_DIR="$MINT_MACOS_REPO/settings"
  volcar monterey-12.7.6
  case "$VOLCADO" in *"Allow wallpaper tinting in windows"*) ;; *) falla "Monterey: falta «Allow wallpaper tinting in windows»" ;; esac
  case "$VOLCADO" in *"Prefer tabs:"*) ;; *) falla "Monterey: falta «Prefer tabs:»" ;; esac
  case "$VOLCADO" in *"Automatically hide and show the menu bar"*) falla "Monterey: «Automatically hide and show the menu bar» sigue en General" ;; esac
  case "$VOLCADO" in *"Use font smoothing"*) falla "Monterey: «Use font smoothing» sigue en General" ;; esac
  paso "Monterey: tinting y Prefer tabs sí; menu bar y font smoothing no"
  matar_preferencias
  volcar catalina-10.15
  case "$VOLCADO" in *"Automatically hide and show the menu bar"*) ;; *) falla "Catalina: falta «Automatically hide and show the menu bar»" ;; esac
  case "$VOLCADO" in *"Use font smoothing"*) ;; *) falla "Catalina: falta «Use font smoothing»" ;; esac
  case "$VOLCADO" in *"Allow wallpaper tinting"*) falla "Catalina: salió «Allow wallpaper tinting» (es de Monterey)" ;; esac
  paso "Catalina: como estaba"
  true
}
