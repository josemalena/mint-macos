# caso: la salida de emergencia (mac-bloqueo --liberar, desde una consola o ssh) quita el bloqueo: sin estado, sin supervisor y sin pantalla
# límite: 90
vivos() {   # los procesos del bloqueo que no son zombis (un hijo muerto sin recoger todavía aparece en pgrep)
  local p n=0
  for p in $(pgrep -x mac-bloqueo); do
    [ "$(awk '{print $3}' "/proc/$p/stat" 2>/dev/null)" = Z ] || n=$((n + 1))
  done
  echo "$n"
}
prueba() {
  necesita_teclado
  requiere mac-bloqueo
  local estado="$XDG_RUNTIME_DIR/mint-macos/bloqueado"
  rm -f "$estado"
  lanzar mac-bloqueo
  for _ in $(seq 50); do [ -f "$estado" ] && break; sleep 0.2; done
  [ -f "$estado" ] || falla "no escribió el estado «bloqueado»"
  sleep 2
  [ "$(vivos)" -gt 0 ] || falla "el bloqueo no está corriendo"
  mac-bloqueo --liberar > "$PRUEBAS_RES/liberar.txt" || falla "--liberar falló"
  for _ in $(seq 25); do [ "$(vivos)" -eq 0 ] && break; sleep 0.2; done
  [ "$(vivos)" -eq 0 ] || falla "después de --liberar siguen procesos del bloqueo"
  [ ! -f "$estado" ] || falla "después de --liberar el estado «bloqueado» sigue"
  [ "$(mac-bloqueo --estado)" = "libre" ] || falla "--estado no dice «libre»"
  paso "--liberar quitó el estado, al supervisor y a la pantalla"
}
