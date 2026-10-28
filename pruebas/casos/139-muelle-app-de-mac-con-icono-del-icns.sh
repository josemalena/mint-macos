# caso: el ítem del Muelle de una app de Mac en Darling (sin .desktop) toma el ícono grande del .icns que da org.mintmacos.AppsMac1, no el _NET_WM_ICON de su ventana (64 px)
# límite: 150
# gestor: cinnamon-applets
# La ventana de prueba trae un ícono ROJO de 48 px; el .icns de la .app, uno AZUL de 256 px. En la franja del Dock debe haber azul y nada de rojo.
cuenta() {   # cuenta COLOR → fracción de la franja del Dock cerca de ese color
  local f="$PRUEBAS_RES/$PRUEBAS_CASO-franja.png"
  import -display "$DISPLAY" -window root -crop "${PRUEBAS_ANCHO}x220+0+$((PRUEBAS_ALTO - 220))" +repage "$f"
  convert "$f" -fuzz 12% -fill white -opaque "$1" -fill black +opaque white -format '%[fx:mean]' info:
}
prueba() {
  local aqui; aqui="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  despejar_pantalla
  requiere muelle mint-macos-apps-mac xdotool convert import python3 gdbus
  export MUELLE_SIN_MIGRAR=1
  local esq; esq="$(dirname "$(command -v muelle)")/../esquemas"
  [ -d "$esq" ] && export GSETTINGS_SCHEMA_DIR="$esq"
  local apps="$XDG_DATA_HOME/applications" lanz="$XDG_CONFIG_HOME/muelle/dock1/launchers"
  rm -rf "$XDG_CONFIG_HOME/muelle"; dconf reset -f /org/mintmacos/muelle/ 2>/dev/null || true
  mkdir -p "$apps" "$lanz"
  printf '[Desktop Entry]\nType=Application\nName=Fijo\nExec=true\nIcon=xed\n' > "$apps/fijo.desktop"
  printf '[PlankDockItemPreferences]\nLauncher=file://%s/fijo.desktop\n' "$apps" > "$lanz/fijo.dockitem"
  dconf write /org/mintmacos/muelle/docks/dock1/dock-items "['fijo.dockitem']"
  dconf write /org/mintmacos/muelle/docks/dock1/zoom-enabled false
  # la .app con su .icns (un PNG de 256 px, entrada «ic08»)
  local app="$HOME/Applications/Zeta Prueba.app"
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
  cat > "$app/Contents/Info.plist" <<'P'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.prueba.zeta</string>
<key>CFBundleName</key><string>Zeta Prueba</string>
<key>CFBundleExecutable</key><string>zeta</string>
<key>CFBundleIconFile</key><string>zeta</string>
</dict></plist>
P
  printf '#!/bin/sh\n' > "$app/Contents/MacOS/zeta"; chmod +x "$app/Contents/MacOS/zeta"
  convert -size 256x256 xc:'#2244cc' "$PRUEBAS_RES/azul.png"
  python3 -I - "$PRUEBAS_RES/azul.png" "$app/Contents/Resources/zeta.icns" <<'P'
import struct, sys
png = open(sys.argv[1], "rb").read()
cuerpo = b"ic08" + struct.pack(">I", 8 + len(png)) + png
open(sys.argv[2], "wb").write(b"icns" + struct.pack(">I", 8 + len(cuerpo)) + cuerpo)
P
  lanzar mint-macos-apps-mac
  for _ in $(seq 20); do gdbus introspect --session -d org.mintmacos.AppsMac1 -o /org/mintmacos/AppsMac1 >/dev/null 2>&1 && break; sleep 0.5; done
  gdbus call --session -d org.mintmacos.AppsMac1 -o /org/mintmacos/AppsMac1 -m org.mintmacos.AppsMac1.Resolver darling-com.prueba.zeta >/dev/null
  local cache="${XDG_CACHE_HOME:-$HOME/.cache}/mint-macos/apps-mac"
  for _ in $(seq 30); do ls "$cache"/com.prueba.zeta-*.png >/dev/null 2>&1 && break; sleep 0.5; done
  ls "$cache"/com.prueba.zeta-*.png >/dev/null 2>&1 || falla "el servicio no hizo los PNG del .icns en $cache"
  lanzar muelle
  esperar_ventana '^[Mm]uelle$' 30 >/dev/null
  sleep 3
  lanzar python3 -I "$aqui/ayudantes/ventana-darling.py" "Zeta Prueba" com.prueba.zeta
  esperar_ventana '^darling-com.prueba.zeta$' 30 >/dev/null
  sleep 5      # el Muelle pide el ícono a AppsMac1 y cambia el de la ventana
  xdotool mousemove 5 5; sleep 1
  local azul rojo
  azul="$(cuenta '#2244cc')"; rojo="$(cuenta '#cc2222')"
  captura muelle-icono-icns
  paso "en el Dock: azul $azul, rojo $rojo"
  awk -v a="$azul" 'BEGIN { exit !(a > 0.002) }' || falla "el Dock no usa el ícono del .icns (azul $azul)"
  awk -v r="$rojo" 'BEGIN { exit !(r < 0.0002) }' || falla "el Dock sigue mostrando el ícono de la ventana (rojo $rojo)"
}
