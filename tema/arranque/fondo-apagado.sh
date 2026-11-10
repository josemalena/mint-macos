#!/usr/bin/env bash
# mac-fondo-apagado: deja el fondo de pantalla del usuario listo para la pantalla de
# apagado (Plymouth, tema catalina), como la Mac (José, 10-11-2026). Lo instala
# silencio.sh en ~/.local/bin, con su autoarranque.
#
#   mac-fondo-apagado            lo prepara una vez
#   mac-fondo-apagado --vigilar  lo prepara y lo rehace cada vez que cambia el fondo
#
# Escribe /var/lib/mint-macos/apagado/fondo.png (la carpeta es de este usuario: la crea
# silencio.sh). Plymouth solo lee PNG y al apagar no hay tiempo de escalar una foto
# de 6K: aquí se recorta a la medida de la pantalla, como el «zoom» de Cinnamon.
# Corre como el usuario, sin sudo. APAGADO_DIR cambia la carpeta (para pruebas).
set -euo pipefail
DIR="${APAGADO_DIR:-/var/lib/mint-macos/apagado}"
SALIDA="$DIR/fondo.png"

preparar() {
  local uri ruta ancho="" alto=""
  uri="$(gsettings get org.cinnamon.desktop.background picture-uri)"
  uri="${uri#\'}"; uri="${uri%\'}"
  ruta="$(python3 -c 'import sys, urllib.parse as u; p = u.urlparse(sys.argv[1]); print(u.unquote(p.path) if p.scheme == "file" else "")' "$uri")"
  if [ ! -f "$ruta" ]; then
    rm -f "$SALIDA"
    echo "  sin fondo de imagen (${uri:-vacío}): el apagado queda negro"
    return 0
  fi
  # La pantalla más grande que esté conectada: Plymouth la escala para las otras.
  read -r ancho alto < <(for c in /sys/class/drm/card*-*; do
      if [ "$(cat "$c/status" 2>/dev/null)" = connected ]; then head -1 "$c/modes"; fi
    done 2>/dev/null | awk -Fx '{print $1+0, $2+0}' | sort -n -k2 | tail -1) || true
  [ -n "$alto" ] || { ancho=1920; alto=1080; }
  [ -d "$DIR" ] || { echo "  ✗ falta $DIR: corre antes sudo silencio.sh" >&2; return 1; }
  convert "$ruta" -resize "${ancho}x${alto}^" -gravity center -extent "${ancho}x${alto}" "png:$SALIDA.nuevo"
  mv -f "$SALIDA.nuevo" "$SALIDA"
  echo "  fondo de apagado: $(basename "$ruta") a ${ancho}×${alto} en $SALIDA"
}

case "${1:-}" in
  "") preparar ;;
  --vigilar)
    # Al pararlo (silencio.sh --deshacer, o al cerrar sesión) se va todo el grupo:
    # también el gsettings monitor y el ciclo, que si no quedarían huérfanos.
    trap 'trap - TERM; kill 0' TERM
    preparar || true
    # Cada cambio del fondo (System Preferences, Cinnamon o los fondos dinámicos) lo rehace.
    # En segundo plano y con wait: mientras espera una tubería en primer plano, bash no
    # atiende la señal, y el vigilante no se dejaba parar (probado el 10-11-2026).
    gsettings monitor org.cinnamon.desktop.background picture-uri | while read -r _; do preparar || true; done &
    wait ;;
  *) echo "uso: $0 [--vigilar]" >&2; exit 2 ;;
esac
