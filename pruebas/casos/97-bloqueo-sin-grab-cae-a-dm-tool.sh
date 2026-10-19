# caso: si el grab no se logra en ~2 s (aquí otro programa lo tiene y no lo suelta, y no hay Cinnamon que lo suelte), el bloqueo no se queda
# «medio puesto»: llama a dm-tool lock (de mentira en la caja) y lo anota en su log
# límite: 90
prueba() {
  necesita_teclado
  requiere mac-bloqueo
  local aqui; aqui="$(dirname "$PRUEBAS_LIB")"
  local falso; falso="$(mktemp -d)"
  printf '#!/bin/sh\necho "$@" >> "%s/dm-tool-llamado.txt"\n' "$PRUEBAS_RES" > "$falso/dm-tool"
  chmod +x "$falso/dm-tool"
  rm -f "$PRUEBAS_RES/dm-tool-llamado.txt"
  export PATH="$falso:$PATH"
  # Un programa ajeno agarra el teclado y no lo suelta en 25 s
  lanzar python3 "$aqui/ayudantes/agarrar-teclado.py" 25
  sleep 2
  local log="${XDG_STATE_HOME:-$HOME/.local/state}/mint-macos/bloqueo.log"
  rm -f "$log"
  local estado="$XDG_RUNTIME_DIR/mint-macos/bloqueado"
  rm -f "$estado"
  lanzar mac-bloqueo
  for _ in $(seq 40); do [ -s "$PRUEBAS_RES/dm-tool-llamado.txt" ] && break; sleep 0.5; done
  [ -s "$PRUEBAS_RES/dm-tool-llamado.txt" ] || falla "con el grab ocupado el bloqueo no llamó a dm-tool lock"
  [ "$(head -1 "$PRUEBAS_RES/dm-tool-llamado.txt")" = "lock" ] || falla "llamó a dm-tool con «$(head -1 "$PRUEBAS_RES/dm-tool-llamado.txt")» y debía ser «lock»"
  paso "con el grab ocupado cayó a dm-tool lock"
  grep -q "último recurso" "$log" || falla "no anotó el último recurso en el log ($log)"
  paso "lo anotó en el log: $(tail -1 "$log")"
  [ -f "$estado" ] || falla "el estado «bloqueado» no sigue puesto"
  mac-bloqueo --liberar >/dev/null
}
