# caso: KeePassXC (AppImage oficial) soltada en Applications queda como app: lanzador, ícono, Open With y Fynder
# límite: 90
prueba() {
  requiere python3 gio fynder update-desktop-database
  local ai; ai="$(binario_rust mint-macos-appimages)"
  local src="$PRUEBAS_CACHE_REAL/pruebas-appimage/KeePassXC-2.7.12-x86_64.AppImage"
  [ -f "$src" ] || saltar "falta $src (se baja con el sí de José; ver aplicaciones/APPIMAGE.md)"
  local dest="$HOME/Aplicaciones-$PRUEBAS_CASO" f
  mkdir -p "$dest"
  f="$dest/KeePassXC-2.7.12-x86_64.AppImage"
  cp "$src" "$f"; chmod 644 "$f"          # como llega del navegador
  "$ai" --destino "$dest"

  local md5 l ic
  md5="$(md5_uri "$f")"
  l="$XDG_DATA_HOME/applications/mint-macos-appimage-$md5.desktop"
  comprobar "existe el lanzador" test -f "$l"
  comprobar "se llama KeePassXC" grep -qx 'Name=KeePassXC' "$l"
  ic="$(sed -n 's/^Icon=//p' "$l")"
  comprobar "el ícono salió de adentro y es un SVG" grep -q '<svg' "$ic"
  comprobar "quedó ejecutable" test -x "$f"
  comprobar "GIO la ve como app que se muestra" python3 -I -c '
import sys
from gi.repository import Gio
a = Gio.DesktopAppInfo.new(sys.argv[1])
sys.exit(0 if a and a.should_show() and a.get_display_name() == "KeePassXC" else 1)' "mint-macos-appimage-$md5.desktop"
  comprobar "Open With la ofrece para las bases .kdbx" sh -c "gio mime application/x-keepass2 | grep -q 'mint-macos-appimage-$md5.desktop'"

  # Fynder la enseña con su ícono (el miniaturizador de AppImage de xapp).
  lanzar fynder "$dest"
  local v; v="$(esperar_ventana '[Ff]ynder' 30)"
  esperar_texto "$v" "KeePassXC-2.7.12-x86_64.AppImage" 20
  sleep 2
  captura fynder
  cerrar_ventana "$v"
  esperar_sin_ventana "$v" 10
}
