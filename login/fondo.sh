#!/usr/bin/env bash
# El fondo de escritorio de esta persona para el login y el bloqueo (slick-greeter-mac).
#
#   ./fondo.sh              instala: el exportador, y un servicio de usuario que lo corre al entrar y al salir
#   ./fondo.sh --quitar     lo deja como estaba (el greeter vuelve al fondo de Catalina de esta cuenta)
#   ./fondo.sh --exportar   copia el fondo actual ahora (lo llaman el servicio y el bloqueo)
#
# El greeter corre como «lightdm» y no lee el $HOME: cada sesión deja una copia en /var/lib/mint-macos/login-fondos
# (la carpeta y un archivo vacío por cuenta los crea `sudo login/instalar.sh`; solo el dueño puede escribir el suyo).
# El greeter enseña el de la última persona que entró en la lista y el de quien bloqueó al desbloquear.
# Sin esa carpeta no hace nada: es inofensivo instalarlo antes que el greeter.
set -euo pipefail

FONDOS="${MINT_MACOS_LOGIN_FONDOS:-/var/lib/mint-macos/login-fondos}"
BIN="$HOME/.local/bin/mint-macos-fondo-login"
UNIDAD="$HOME/.config/systemd/user/mint-macos-fondo-login.service"
ESTADO="${XDG_STATE_HOME:-$HOME/.local/state}/mint-macos"
USUARIO="$(id -un)"

exportar() {
  local destino="$FONDOS/$USUARIO.jpg"
  [ -w "$destino" ] || exit 0                       # sin carpeta o sin archivo de esta cuenta: nada que hacer
  # El fondo del escritorio (dconf se lee sin bus de sesión, así que sirve también al cerrar la sesión).
  local uri
  uri="$(dconf read /org/cinnamon/desktop/background/picture-uri 2>/dev/null | sed "s/^'//; s/'\$//")"
  local ruta
  case "$uri" in
    file://*)       # sin Python: se quita el esquema y se deshacen los %XX
      ruta="$(printf '%s' "${uri#file://}" | sed 's/\\/\\\\/g; s/%\([0-9A-Fa-f][0-9A-Fa-f]\)/\\x\1/g')"
      ruta="$(printf '%b' "$ruta")" ;;
    *) ruta="" ;;
  esac
  if [ -z "$ruta" ] || [ ! -f "$ruta" ]; then : > "$destino"; exit 0; fi   # sin foto (color liso): vuelve el de Catalina
  # Solo se rehace si cambió la foto.
  local sello
  sello="$ruta|$(stat -c '%Y|%s' "$ruta")"
  mkdir -p "$ESTADO"
  if [ -s "$destino" ] && [ "$(cat "$ESTADO/fondo-login.sello" 2>/dev/null || true)" = "$sello" ]; then exit 0; fi
  TMP="$(mktemp --suffix=.jpg)"
  trap 'rm -f "$TMP"' EXIT
  # A lo sumo 3840 px (una pantalla 4K) y sin metadatos: el greeter la escala a su pantalla.
  convert "${ruta}[0]" -auto-orient -resize '3840x3840>' -strip -quality 90 "$TMP"
  cat "$TMP" > "$destino"                           # en el sitio: la carpeta es de root y no deja renombrar
  printf '%s' "$sello" > "$ESTADO/fondo-login.sello"
}

case "${1:-}" in
  --exportar) exportar ;;
  --quitar)
    systemctl --user disable --now mint-macos-fondo-login.service 2>/dev/null || true
    rm -f "$UNIDAD" "$BIN" "$ESTADO/fondo-login.sello"
    systemctl --user daemon-reload 2>/dev/null || true
    [ -w "$FONDOS/$USUARIO.jpg" ] && : > "$FONDOS/$USUARIO.jpg"
    echo "Quitado: el login vuelve al fondo de Catalina para $USUARIO." ;;
  "")
    command -v convert >/dev/null || { echo "✗ Falta ImageMagick (convert): sudo apt install imagemagick" >&2; exit 1; }
    install -Dm755 "$0" "$BIN"
    mkdir -p "$(dirname "$UNIDAD")"
    cat > "$UNIDAD" <<UNI
[Unit]
Description=Fondo de escritorio para la pantalla de inicio (mint-macos)

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$BIN --exportar
ExecStop=$BIN --exportar

[Install]
WantedBy=default.target
UNI
    systemctl --user daemon-reload
    systemctl --user enable --now mint-macos-fondo-login.service
    echo "Instalado: $BIN y el servicio de usuario (corre al entrar y al salir)."
    if [ -d "$FONDOS" ]; then echo "Fondo exportado a $FONDOS/$USUARIO.jpg"
    else echo "Falta la carpeta $FONDOS: corre  sudo login/instalar.sh  (crea la carpeta y un archivo por cuenta)."; fi ;;
  *) echo "uso: $0 [--quitar | --exportar]" >&2; exit 2 ;;
esac
