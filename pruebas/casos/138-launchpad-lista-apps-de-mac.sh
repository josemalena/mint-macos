# caso: el Launchpad lista las .app de Mac (las que da org.mintmacos.AppsMac1.Listar(), sin .desktop) junto con las demás, por nombre; si un lanzador de Linux se llama igual, sale aclarado («(GNOME)»)
# límite: 90
prueba() {
  requiere mac-launchpad-vala mint-macos-apps-mac identify gdbus
  local app="$HOME/Applications/Zeta Prueba.app"
  mkdir -p "$app/Contents/MacOS"
  cat > "$app/Contents/Info.plist" <<'P'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.prueba.zeta</string>
<key>CFBundleName</key><string>Zeta Prueba</string>
<key>CFBundleExecutable</key><string>zeta</string>
</dict></plist>
P
  printf '#!/bin/sh\n' > "$app/Contents/MacOS/zeta"; chmod +x "$app/Contents/MacOS/zeta"
  lanzar mint-macos-apps-mac
  for _ in $(seq 20); do gdbus introspect --session -d org.mintmacos.AppsMac1 -o /org/mintmacos/AppsMac1 >/dev/null 2>&1 && break; sleep 0.5; done
  local apps="$HOME/lp-apps"; mkdir -p "$apps"
  printf '[Desktop Entry]\nType=Application\nName=Alfa\nExec=true\nIcon=application-x-executable\n' > "$apps/Alfa.desktop"
  printf '[Desktop Entry]\nType=Application\nName=Zeta Prueba\nExec=true\nIcon=application-x-executable\n' > "$apps/org.gnome.ZetaPrueba.desktop"
  local lista="$PRUEBAS_RES/$PRUEBAS_CASO-lista.txt"
  LAUNCHPAD_DESTINO="$apps" mac-launchpad-vala --lista > "$lista" 2>&1 || falla "--lista terminó con error"
  paso "$(wc -l < "$lista") líneas: $(tr '\n' '|' < "$lista" | cut -c1-200)"
  grep -q "Zeta Prueba" "$lista" || falla "la lista no trae la .app de Mac «Zeta Prueba»"
  grep -qx "Zeta Prueba" "$lista" || falla "la .app de Mac debe salir con su nombre a secas: $(tr '\n' '|' < "$lista")"
  grep -qx "Zeta Prueba (GNOME)" "$lista" || falla "el lanzador de GNOME con el mismo nombre debe salir como «Zeta Prueba (GNOME)»: $(tr '\n' '|' < "$lista")"
  grep -q "Alfa" "$lista" || falla "la lista perdió los lanzadores normales"
  local png="$PRUEBAS_RES/$PRUEBAS_CASO-pagina.png"
  LAUNCHPAD_DESTINO="$apps" LAUNCHPAD_DISENO="$HOME/lp-diseno.json" mac-launchpad-vala --png "$png" || falla "--png terminó con error"
  comprobar "es un PNG de 1920x1200" test "$(identify -format '%wx%h' "$png")" = "1920x1200"
}
