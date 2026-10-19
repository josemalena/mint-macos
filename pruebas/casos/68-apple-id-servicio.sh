# caso: la franja de System Preferences y la hoja de Sign In hablan con org.mintmacos.AppleID1 (uno de mentira): cuenta y clave,
# código de verificación, Mail y Calendar, y el final con los calendarios. Los secretos no se anotan en ningún lado.
# límite: 120
prueba() {
  requiere mac-preferencias xdotool python3
  export MP_PYTHON_DIR="$MINT_MACOS_REPO/settings"
  export APPLEID_REGISTRO="$HOME/appleid-registro.txt"
  : > "$APPLEID_REGISTRO"
  liberar_nombre_dbus org.mintmacos.AppleID1
  lanzar python3 "$MINT_MACOS_REPO/pruebas/ayudantes/appleid-falso.py"
  # Estado activaría el servicio de verdad (tiene activación por D-Bus): se espera el nombre sin llamarlo.
  for _ in $(seq 50); do
    [ "$(gdbus call --session -d org.freedesktop.DBus -o /org/freedesktop/DBus -m org.freedesktop.DBus.NameHasOwner org.mintmacos.AppleID1 2>/dev/null)" = "(true,)" ] && break
    sleep 0.2
  done
  lanzar mac-preferencias
  local v; v="$(esperar_ventana '[Mm]ac-settings' 40)"
  esperar_texto "$v" "Sign in to your Apple ID" 20
  pulsar "$v" "Sign In" 15
  esperar_texto "$v" "Sign in with your Apple ID" 15
  sleep 2
  xdotool type --delay 40 "prueba@example.com"; xdotool key Tab; xdotool type --delay 40 "password"; xdotool key Return
  esperar_texto "$v" "Verification Code" 15
  sleep 2
  xdotool type --delay 40 "123456"; xdotool key Return
  esperar_texto "$v" "Open appleid.apple.com" 15
  sleep 2
  captura apple-id-mail
  xdotool type --delay 40 "abcd-efgh-ijkl-mnop"; xdotool key Return
  esperar_texto "$v" "You’re all set" 15
  captura apple-id-listo
  esperar_texto "$v" "iCloud Drive is mounted. Mail and 2 calendar(s) are set up: open Thunderbird and, if it asks, choose the saved password." 5
  grep -q "IniciarSesion prueba@example.com" "$APPLEID_REGISTRO" || falla "no llamó a IniciarSesion: $(cat "$APPLEID_REGISTRO")"
  grep -q "EnviarCodigo" "$APPLEID_REGISTRO" || falla "no llamó a EnviarCodigo"
  grep -q "ConfigurarMail" "$APPLEID_REGISTRO" || falla "no llamó a ConfigurarMail"
  ! grep -q "password\|123456\|abcd-efgh" "$APPLEID_REGISTRO" || falla "un secreto quedó en el registro"
}
