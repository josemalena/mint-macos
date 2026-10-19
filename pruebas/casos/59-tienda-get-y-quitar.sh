# caso: en la ficha de una app, Get la instala con el progreso del motor y el botón pasa a Open; Remove la quita y vuelve Get.
# Contra un motor de mentira (pruebas/ayudantes/tienda-falsa.py): no se instala nada de verdad.
# límite: 120
prueba() {
  requiere mac-tienda xdotool python3
  local reg="$HOME/tienda-falsa.registro"; : > "$reg"
  # Con la máquina cargada (un armado mientras otra sesión compila) el motor de mentira tardaba más
  # que el «sleep 1» y la ficha se pedía a nadie (18-10-2026): se espera a que tenga el nombre. Antes,
  # que no lo tenga el motor de verdad por activación.
  liberar_nombre_dbus org.mintmacos.Tienda1
  lanzar python3 "$MINT_MACOS_REPO/pruebas/ayudantes/tienda-falsa.py" "$reg"
  local i
  for i in $(seq 1 100); do
    [ "$(gdbus call --session -d org.freedesktop.DBus -o /org/freedesktop/DBus -m org.freedesktop.DBus.NameHasOwner org.mintmacos.Tienda1 2>/dev/null)" = "(true,)" ] && break
    sleep 0.2
  done
  [ "$i" -lt 100 ] || falla "el motor de mentira no tomó org.mintmacos.Tienda1"
  lanzar mac-tienda --ficha "fake:app"
  local w; w="$(esperar_ventana '[Mm]ac-tienda' 30)"
  esperar_texto "$w" "Fake App" 40
  esperar_texto "$w" "Get" 10
  captura tienda-ficha-get
  pulsar "$w" "Get" 10
  esperar_texto "$w" "Open" 20
  grep -q "Instalar" "$reg" || falla "el motor no recibió Instalar: $(cat "$reg")"
  captura tienda-ficha-open
  pulsar "$w" "Remove" 10
  esperar_texto "$w" "Get" 20
  grep -q "Quitar" "$reg" || falla "el motor no recibió Quitar: $(cat "$reg")"
  captura tienda-ficha-quitada
}
