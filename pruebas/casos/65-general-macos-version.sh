# caso: General trae «macOS version:» bajo Appearance, con las versiones de mint-macos-version --lista y la nota de que vale al volver a
# entrar (texto propio de mint-macos, no de Apple). Con un mint-macos-version de mentira.
# límite: 90
prueba() {
  requiere mac-preferencias xdotool python3
  export MP_PYTHON_DIR="$MINT_MACOS_REPO/settings"
  mkdir -p "$HOME/bin-falso"
  cp "$MINT_MACOS_REPO/pruebas/ayudantes/mint-macos-version-falso.sh" "$HOME/bin-falso/mint-macos-version"
  export PATH="$HOME/bin-falso:$PATH"
  lanzar mac-preferencias
  local v; v="$(esperar_ventana '[Mm]ac-settings' 40)"
  mac-preferencias general
  for _ in $(seq 50); do [ "$(titulo "$v")" = "General" ] && break; sleep 0.2; done
  [ "$(titulo "$v")" = "General" ] || falla "no abrió General: «$(titulo "$v")»"
  esperar_texto "$v" "macOS version:" 20
  esperar_texto "$v" "Takes effect the next time you log in." 10
  esperar_texto "$v" "macOS Prueba 1.0" 10
  captura general-macos-version
}
