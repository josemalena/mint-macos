# caso: lo que no es una AppImage legible se rechaza con aviso, sin romper nada ni ejecutarse
# límite: 120
prueba() {
  requiere gcc mksquashfs convert python3
  local ai; ai="$(binario_rust mint-macos-appimages)"
  local dest="$HOME/Aplicaciones-$PRUEBAS_CASO" marca="$HOME/appimage-ejecutada" v
  mkdir -p "$dest"; rm -f "$marca"
  for v in sin-integrar enlace-fuera tipo1 dwarfs elf texto; do
    "$MINT_MACOS_REPO/pruebas/fabricar-appimage.sh" "$dest/$v.AppImage" "$v"
  done
  comprobar "el servicio no se cae" "$ai" --destino "$dest"
  comprobar "ningún lanzador" sh -c "! ls '$XDG_DATA_HOME/applications/' 2>/dev/null | grep -q mint-macos-appimage-"
  comprobar "ninguna se ejecutó" test ! -e "$marca"
  comprobar "ninguna se volvió ejecutable" test ! -x "$dest/texto.AppImage" -a ! -x "$dest/tipo1.AppImage" -a ! -x "$dest/enlace-fuera.AppImage"
  local avisos="$XDG_STATE_HOME/mint-macos/appimages-avisos"
  [ "$(wc -l < "$avisos")" = 5 ] || falla "se esperaban 5 avisos (todas menos sin-integrar); hay $(wc -l < "$avisos")"
  paso "5 avisos, uno por archivo malo"
  "$ai" --destino "$dest"
  [ "$(wc -l < "$avisos")" = 5 ] || falla "la segunda corrida volvió a avisar"
  paso "la segunda corrida no repite los avisos"
}
