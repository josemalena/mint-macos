# caso: mover una AppImage cambia su lanzador; botarla lo quita; sacarla de la Trash lo trae de vuelta
# límite: 60
prueba() {
  requiere gcc mksquashfs convert python3 gio
  local ai; ai="$(binario_rust mint-macos-appimages)"
  local dest="$HOME/Aplicaciones-$PRUEBAS_CASO" apps="$XDG_DATA_HOME/applications" f g
  mkdir -p "$dest/Utilities"
  f="$dest/Prueba.AppImage"
  "$MINT_MACOS_REPO/pruebas/fabricar-appimage.sh" "$f"
  "$ai" --destino "$dest"
  local l1; l1="$apps/mint-macos-appimage-$(md5_uri "$f").desktop"
  comprobar "integrada en la carpeta de arriba" test -f "$l1"

  g="$dest/Utilities/Prueba con espacios 100%.AppImage"
  mv "$f" "$g"
  "$ai" --destino "$dest"
  local l2; l2="$apps/mint-macos-appimage-$(md5_uri "$g").desktop"
  comprobar "el lanzador viejo se fue" test ! -e "$l1"
  comprobar "el nuevo apunta a Utilities" grep -qF "X-AppImage-Path=$g" "$l2"
  comprobar "GIO lee el Exec con espacios y %" python3 -I -c '
import sys
from gi.repository import Gio
a = Gio.DesktopAppInfo.new_from_filename(sys.argv[1])
sys.exit(0 if a and sys.argv[2] in a.get_commandline().replace("%%", "%") else 1)' "$l2" "$g"

  gio trash "$g"
  "$ai" --destino "$dest"
  comprobar "en la Trash: sin lanzador" test ! -e "$l2"
  local md5g; md5g="$(md5_uri "$g")"
  comprobar "en la Trash: sin ícono" sh -c "! ls '$XDG_DATA_HOME/mint-macos/appimages/' 2>/dev/null | grep -q '^$md5g\.'"

  # El nombre va escapado en la URI (espacios y %), como lo lista gio.
  local en_trash; en_trash="$(gio list -u trash:/// | grep -F "$(python3 -I -c 'import sys
from gi.repository import GLib
print(GLib.uri_escape_string(sys.argv[1], None, False))' "$(basename "$g")")")"
  gio trash --restore "$en_trash"
  comprobar "volvió de la Trash" test -f "$g"
  "$ai" --destino "$dest"
  comprobar "y su lanzador con ella" test -f "$l2"
}
