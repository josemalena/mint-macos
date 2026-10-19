# caso: el panel de terceros Solaar sale en System Preferences y enseña los dispositivos Logitech con su batería y ajustes
# (con un solaar de mentira: el real solo ve el teclado si está conectado, y en el armado no lo está)
# límite: 120
prueba() {
  requiere mac-preferencias xdotool
  local falso; falso="$(mktemp -d)"
  cat > "$falso/solaar" <<'FALSO'
#!/bin/sh
case "$1" in
  show) printf 'Bolt Receiver\n  Device path  : /dev/hidraw0\n\n  1: Wave Keys\n     Battery: 80%%, discharging.\n' ;;
  config) printf '# Swap Fx function\n# When off, F1 is F1\n# possible values: on/true/t/yes/y/1 or off/false/f/no/n/0\nfn-swap = True\n\n' ;;
esac
FALSO
  chmod +x "$falso/solaar"
  export PATH="$falso:$PATH"
  export MP_PYTHON_DIR="$MINT_MACOS_REPO/settings"
  lanzar mac-preferencias
  local v; v="$(esperar_ventana '[Mm]ac-settings' 40)"
  esperar_texto "$v" "Solaar" 30
  captura cuadricula-con-solaar
  mac-preferencias solaar
  for _ in $(seq 50); do [ "$(titulo "$v")" = "Solaar" ] && break; sleep 0.2; done
  [ "$(titulo "$v")" = "Solaar" ] || falla "no abrió el panel Solaar: «$(titulo "$v")»"
  esperar_texto "$v" "Wave Keys" 60
  captura panel-solaar
  cerrar_ventana "$v"
}
