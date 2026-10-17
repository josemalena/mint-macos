# caso: integrar una AppImage no la ejecuta (una de mentira que deja marca si alguien la corre)
# límite: 60
prueba() {
  requiere gcc mksquashfs convert python3
  local ai; ai="$(binario_rust mint-macos-appimages)"
  local dest="$HOME/Aplicaciones-$PRUEBAS_CASO" f marca="$HOME/appimage-ejecutada"
  mkdir -p "$dest"; rm -f "$marca"
  f="$dest/Prueba.AppImage"
  "$MINT_MACOS_REPO/pruebas/fabricar-appimage.sh" "$f"
  comprobar "llega sin +x, como del navegador" test ! -x "$f"
  "$ai" --destino "$dest"
  "$ai" --destino "$dest"
  comprobar "existe el lanzador" test -f "$XDG_DATA_HOME/applications/mint-macos-appimage-$(md5_uri "$f").desktop"
  comprobar "no se ejecutó al integrarla" test ! -e "$marca"
  # La marca funciona: corriéndola a propósito sí aparece (si no, este caso no
  # podría fallar nunca).
  "$f" a-proposito
  comprobar "corriéndola a propósito deja la marca" grep -q 'a-proposito' "$marca"
}
