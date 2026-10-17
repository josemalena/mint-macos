# caso: abrir una AppImage la primera vez pregunta como Gatekeeper; Cancel no la abre, Open sí, y no vuelve a preguntar
# límite: 120
prueba() {
  necesita_teclado
  requiere gcc mksquashfs convert python3 gio zenity xprop
  local ai; ai="$(binario_rust mint-macos-appimages)"
  local dest="$HOME/Aplicaciones-$PRUEBAS_CASO" marca="$HOME/appimage-ejecutada" f l
  mkdir -p "$dest"; rm -f "$marca"
  f="$dest/Prueba.AppImage"
  "$MINT_MACOS_REPO/pruebas/fabricar-appimage.sh" "$f"
  "$ai" --destino "$dest"
  l="$XDG_DATA_HOME/applications/mint-macos-appimage-$(md5_uri "$f").desktop"

  # Se abre por su lanzador, como desde el menú o el Launchpad.
  lanzar gio launch "$l"
  # mac-gatekeeper (Vala, la de Catalina) si está; si no, zenity.
  local clase='[Zz]enity|[Mm]ac-gatekeeper'
  local d; d="$(esperar_ventana "$clase" 20)"
  esperar_texto "$d" "Open" 10
  # Con el nombre de la app (el Name de su lanzador), no el del archivo.
  local pregunta="“Prueba de AppImage” is an app downloaded from the Internet. Are you sure you want to open it?"
  paso "la pregunta la hace $(xprop -id "$d" WM_CLASS | cut -d= -f2)"
  if xprop -id "$d" WM_CLASS | grep -qi gatekeeper; then
    esperar_texto "$d" "$pregunta" 10               # mac-gatekeeper: una etiqueta por frase
    esperar_texto "$d" "Its origin is unknown." 10
  else
    esperar_texto "$d" "$pregunta"$'\n\n'"Its origin is unknown." 10   # zenity: las dos en una
  fi
  captura pregunta
  pulsar "$d" Cancel
  esperar_sin_ventana "$d" 10
  sleep 1
  comprobar "Cancel no la abrió" test ! -e "$marca"

  lanzar gio launch "$l"
  d="$(esperar_ventana "$clase" 20)"
  esperar_texto "$d" "Open" 10
  pulsar "$d" Open
  esperar_sin_ventana "$d" 10
  for _ in $(seq 25); do [ -e "$marca" ] && break; sleep 0.2; done
  comprobar "Open la abrió" test -e "$marca"

  lanzar gio launch "$l"
  for _ in $(seq 25); do [ "$(wc -l < "$marca")" -ge 2 ] && break; sleep 0.2; done
  comprobar "la segunda vez abre sin preguntar" test "$(wc -l < "$marca")" -ge 2
  if xdotool search --onlyvisible --class "$clase" >/dev/null 2>&1; then falla "volvió a preguntar"; fi
}
