# caso: abrir una AppImage la primera vez pregunta como Gatekeeper; Cancel no la abre, Open sí, y no vuelve a preguntar
# límite: 120
prueba() {
  necesita_teclado
  requiere gcc mksquashfs convert python3 gio zenity
  local ai; ai="$(binario_rust mint-macos-appimages)"
  local dest="$HOME/Aplicaciones-$PRUEBAS_CASO" marca="$HOME/appimage-ejecutada" f l
  mkdir -p "$dest"; rm -f "$marca"
  f="$dest/Prueba.AppImage"
  "$MINT_MACOS_REPO/pruebas/fabricar-appimage.sh" "$f"
  "$ai" --destino "$dest"
  l="$XDG_DATA_HOME/applications/mint-macos-appimage-$(md5_uri "$f").desktop"

  # Se abre por su lanzador, como desde el menú o el Launchpad.
  lanzar gio launch "$l"
  local d; d="$(esperar_ventana '[Zz]enity' 20)"
  esperar_texto "$d" "Open" 10
  # Con el nombre de la app (el Name de su lanzador), no el del archivo.
  esperar_texto "$d" "“Prueba de AppImage” is an app downloaded from the Internet. Are you sure you want to open it?"$'\n\n'"Its origin is unknown." 10
  captura pregunta
  wmctrl -i -a "$d"; sleep 0.3
  teclas Escape
  esperar_sin_ventana "$d" 10
  sleep 1
  comprobar "Cancel no la abrió" test ! -e "$marca"

  lanzar gio launch "$l"
  d="$(esperar_ventana '[Zz]enity' 20)"
  esperar_texto "$d" "Open" 10
  wmctrl -i -a "$d"; sleep 0.3
  teclas Return
  esperar_sin_ventana "$d" 10
  for _ in $(seq 25); do [ -e "$marca" ] && break; sleep 0.2; done
  comprobar "Open la abrió" test -e "$marca"

  lanzar gio launch "$l"
  for _ in $(seq 25); do [ "$(wc -l < "$marca")" -ge 2 ] && break; sleep 0.2; done
  comprobar "la segunda vez abre sin preguntar" test "$(wc -l < "$marca")" -ge 2
  if xdotool search --onlyvisible --class '[Zz]enity' >/dev/null 2>&1; then falla "volvió a preguntar"; fi
}
