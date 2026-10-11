#!/usr/bin/env bash
# iCloud Drive (y, si se quiere, Fotos) en Linux con rclone, montado como una
# carpeta y en el lateral de Fynder, como en el Finder. Sin sudo.
#
#   ./icloud.sh instalar     el rclone oficial (versión fija, checksum) en ~/.local/bin
#   ./icloud.sh alta         guía el alta del remoto «icloud» con rclone config:
#                            el Apple ID, la contraseña y el código los escribe
#                            el usuario; este guion no los ve ni los guarda
#   ./icloud.sh montar       el servicio de usuario que monta ~/iCloud Drive, el
#                            aviso de vencimiento y la entrada en Fynder
#   ./icloud.sh fotos        además, Fotos en solo lectura (~/Pictures/iCloud Photos)
#   ./icloud.sh estado       qué hay y cuándo vence la sesión
#   ./icloud.sh renovar      rclone reconnect (cada 30 días lo pide Apple)
#   ./icloud.sh deshacer     quita servicios, aviso y la entrada de Fynder
#                            (el remoto queda en rclone.conf; se borra con
#                            «rclone config delete icloud»)
#
# OJO: el backend iclouddrive de rclone es experimental («Tier 4»). Requisitos
# del lado de Apple: en el iPhone, Ajustes → [nombre] → iCloud → «Access
# iCloud Data on the Web» encendido; la contraseña normal del Apple ID (no una
# de aplicación) y el código de 2FA. La sesión dura 30 días.
#
# Variables para probar sin la cuenta: ICLOUD_REMOTO (icloud), ICLOUD_CARPETA
# (~/iCloud Drive), ICLOUD_SERVICIO (rclone-icloud), RCLONE_CONFIG, y
# ICLOUD_SIN_FYNDER=1 para no tocar el lateral de Fynder.
set -euo pipefail

RCLONE_VERSION=v1.75.1                     # 04-09-2026; iclouddrive desde v1.69
declare -A RCLONE_SHA256=(
  [amd64]=982b5aa772841168f8e380f139e9e787b2a105403e32b94da8676a0e1c0a13ab
  [arm64]=03f2504174034b6d004152ed7369251c9a9ec1f7e0836eda420f5c7a5ec0dff9
)
YO="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
BIN="$HOME/.local/bin/rclone"
REMOTO="${ICLOUD_REMOTO:-icloud}"
CARPETA="${ICLOUD_CARPETA:-$HOME/iCloud Drive}"
FOTOS_REMOTO="${REMOTO}-fotos"
FOTOS_CARPETA="${ICLOUD_FOTOS:-$HOME/Pictures/iCloud Photos}"
SERVICIO="${ICLOUD_SERVICIO:-rclone-icloud}"
UNIDADES="$HOME/.config/systemd/user"
ESTADO="$HOME/.local/state/mint-macos"
ALTA="$ESTADO/$REMOTO-alta"                # fecha del alta o de la última renovación
CACHE_MAX="${ICLOUD_CACHE_MAX:-10G}"
paso() { printf '\n▸ %s\n' "$*"; }

arquitectura() { case "$(uname -m)" in x86_64) echo amd64 ;; aarch64) echo arm64 ;; *) echo "✗ arquitectura $(uname -m) sin binario fijado" >&2; exit 1 ;; esac; }

instalar() {
  paso "rclone $RCLONE_VERSION en ~/.local/bin (el del sistema no se toca)"
  if [ -x "$BIN" ] && "$BIN" version 2>/dev/null | head -1 | grep -q "rclone $RCLONE_VERSION$"; then
    echo "  ya está"; return
  fi
  local a tmp; a="$(arquitectura)"; tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/r.zip" "https://downloads.rclone.org/$RCLONE_VERSION/rclone-$RCLONE_VERSION-linux-$a.zip"
  echo "${RCLONE_SHA256[$a]}  $tmp/r.zip" | sha256sum -c --quiet - || { echo "  ✗ el checksum no cuadra: no se instala"; exit 1; }
  unzip -q -j "$tmp/r.zip" "rclone-$RCLONE_VERSION-linux-$a/rclone" -d "$tmp"
  install -D -m 755 "$tmp/rclone" "$BIN"
  echo "  $("$BIN" version | head -1) (checksum verificado)"
}

alta() {
  instalar
  paso "Alta del remoto «$REMOTO» (iCloud Drive)"
  if "$BIN" listremotes 2>/dev/null | grep -qx "$REMOTO:"; then
    echo "  ya existe «$REMOTO:». Si la sesión venció: $0 renovar"; return
  fi
  cat <<EOF
  Antes, en el iPhone: Ajustes → [tu nombre] → iCloud → «Access iCloud Data
  on the Web» encendido. Ten el iPhone a mano: llega un código de 6 dígitos.

  Solo se piden tres cosas: el Apple ID, su contraseña NORMAL (no una de
  aplicación) y el código. Quedan solo en ${RCLONE_CONFIG:-~/.config/rclone/rclone.conf},
  en tu \$HOME; la contraseña no sale en pantalla, y en la lista de procesos
  solo aparece oscurecida (lo mismo que guarda rclone.conf).
EOF
  local id clave oscura
  read -r -p "  Apple ID (correo): " id
  [ -n "$id" ] || { echo "  no se hizo nada"; return; }
  read -r -s -p "  Contraseña del Apple ID: " clave; echo
  [ -n "$clave" ] || { echo "  no se hizo nada"; return; }
  # Se oscurece por stdin («rclone obscure -») para que la clave en claro no
  # vaya en la línea de comandos (ps la mostraría); a create va ya oscurecida.
  oscura="$(printf '%s' "$clave" | "$BIN" obscure -)"; clave=""
  echo "  Conectando con Apple; cuando lo pida, escribe el código que llegó al iPhone."
  # create sin --non-interactive pregunta en la terminal lo que falte: el 2FA.
  "$BIN" config create "$REMOTO" iclouddrive apple_id="$id" password="$oscura" --no-obscure
  "$BIN" listremotes | grep -qx "$REMOTO:" || { echo "  ✗ no quedó el remoto «$REMOTO»"; exit 1; }
  mkdir -p "$ESTADO"; date +%F > "$ALTA"
  if grep -q '^RCLONE_ENCRYPT_V0' "${RCLONE_CONFIG:-$HOME/.config/rclone/rclone.conf}" 2>/dev/null; then
    if command -v secret-tool >/dev/null; then
      echo "  La configuración está cifrada: escribe su clave para guardarla en el llavero (secret-tool)."
      secret-tool store --label="rclone (mint-macos)" rclone config
    else
      echo "  ✗ la configuración está cifrada y falta secret-tool (sudo ./requisitos.sh): el montaje automático no podrá abrirla"
    fi
  fi
  echo "  listo. Ahora: $0 montar"
}

unidad_montaje() { # nombre remoto carpeta extra
  local nombre="$1" remoto="$2" carpeta="$3" extra="$4" clave=""
  grep -q '^RCLONE_ENCRYPT_V0' "${RCLONE_CONFIG:-$HOME/.config/rclone/rclone.conf}" 2>/dev/null && \
    clave='--password-command "secret-tool lookup rclone config"'
  mkdir -p "$UNIDADES" "$carpeta"
  # --rc en un socket Unix ($XDG_RUNTIME_DIR, 0700): Fynder lee de ahí el
  # progreso de subidas y bajadas (vfs/queue, core/stats). Sin clave porque
  # solo el usuario llega al socket.
  cat > "$UNIDADES/$nombre.service" <<EOF
[Unit]
Description=$remoto montado en $carpeta (rclone, mint-macos)
After=network-online.target

[Service]
Type=notify
${RCLONE_CONFIG:+Environment=RCLONE_CONFIG=$RCLONE_CONFIG}
ExecStart=$BIN mount "$remoto:" "$carpeta" $clave --vfs-cache-mode full --vfs-cache-max-size $CACHE_MAX --cache-dir "%h/.cache/rclone/$nombre" --dir-cache-time 1m --rc --rc-addr "unix://%t/$nombre.sock" --rc-no-auth $extra
ExecStop=/bin/fusermount -u "$carpeta"
Restart=on-failure
RestartSec=30

[Install]
WantedBy=default.target
EOF
}

montar() {
  instalar
  "$BIN" listremotes 2>/dev/null | grep -qx "$REMOTO:" || { echo "✗ no hay remoto «$REMOTO»: corre antes $0 alta"; exit 1; }
  paso "Servicio $SERVICIO: «$REMOTO:» en $CARPETA"
  unidad_montaje "$SERVICIO" "$REMOTO" "$CARPETA" ""
  # El aviso de vencimiento: cada día; avisa desde el día 26 de los 30.
  install -D -m 755 /dev/stdin "$HOME/.local/libexec/mint-macos/icloud-vence" <<EOF
#!/bin/bash
alta="\$(cat "$ALTA" 2>/dev/null)" || exit 0
dias=\$(( ( \$(date +%s) - \$(date -d "\$alta" +%s) ) / 86400 ))
[ "\$dias" -ge 26 ] || exit 0
notify-send -i folder-remote "iCloud Drive vence en \$(( 30 - dias )) días" \\
  "Apple pide renovar la sesión cada 30 días. En una terminal: $YO renovar"
EOF
  cat > "$UNIDADES/$SERVICIO-vence.service" <<EOF
[Unit]
Description=Aviso de vencimiento de la sesión de iCloud (mint-macos)
[Service]
Type=oneshot
ExecStart=%h/.local/libexec/mint-macos/icloud-vence
EOF
  cat > "$UNIDADES/$SERVICIO-vence.timer" <<EOF
[Unit]
Description=Revisa cada día si vence la sesión de iCloud (mint-macos)
[Timer]
OnCalendar=daily
Persistent=true
[Install]
WantedBy=timers.target
EOF
  systemctl --user daemon-reload
  systemctl --user enable --now "$SERVICIO.service" "$SERVICIO-vence.timer"
  # enable --now no reinicia una unidad que ya corre: sin esto, una unidad
  # regenerada (opciones nuevas) seguiría con el rclone viejo.
  systemctl --user restart "$SERVICIO.service"
  [ -f "$ALTA" ] || { mkdir -p "$ESTADO"; date +%F > "$ALTA"; }
  paso "En el lateral de Fynder (iCloud → iCloud Drive)"
  if [ -n "${ICLOUD_SIN_FYNDER:-}" ]; then
    echo "  se salta (ICLOUD_SIN_FYNDER)"
  elif gsettings list-keys io.github.josemalena.fynder.preferences 2>/dev/null | grep -qx sidebar-icloud-path; then
    gsettings get io.github.josemalena.fynder.preferences sidebar-icloud-path > "$ESTADO/$SERVICIO-fynder-antes.txt"
    gsettings set io.github.josemalena.fynder.preferences sidebar-icloud-path "$CARPETA"
    echo "  sidebar-icloud-path = $CARPETA"
  else
    echo "  Fynder no está (o no trae la clave): se salta"
  fi
  estado
}

fotos() {
  "$BIN" listremotes 2>/dev/null | grep -qx "$FOTOS_REMOTO:" || {
    paso "Remoto «$FOTOS_REMOTO» (Fotos, solo lectura)"
    echo "  Es el mismo Apple ID con service = photos. En «rclone config»: n, name> $FOTOS_REMOTO,"
    echo "  Storage> iclouddrive, y en la configuración avanzada (y) service> photos."
    echo "  La primera lista de una fototeca grande puede tardar minutos."
    read -r -p "  ¿Abro rclone config? [s/N] " r; [[ "$r" =~ ^[sS] ]] || return 0
    "$BIN" config
  }
  "$BIN" listremotes | grep -qx "$FOTOS_REMOTO:" || { echo "  ✗ no quedó «$FOTOS_REMOTO»"; exit 1; }
  unidad_montaje "$SERVICIO-fotos" "$FOTOS_REMOTO" "$FOTOS_CARPETA" "--read-only"
  systemctl --user daemon-reload
  systemctl --user enable --now "$SERVICIO-fotos.service"
  echo "  Fotos en $FOTOS_CARPETA (solo lectura)"
}

estado() {
  paso "Estado"
  echo "  rclone: $("$BIN" version 2>/dev/null | sed -n 1p || echo 'no está')"
  echo "  remotos: $("$BIN" listremotes 2>/dev/null | tr '\n' ' ')"
  for u in "$SERVICIO.service" "$SERVICIO-fotos.service" "$SERVICIO-vence.timer"; do
    [ -f "$UNIDADES/$u" ] && echo "  $u: $(systemctl --user is-active "$u" 2>/dev/null || true)"
  done
  if [ -f "$ALTA" ]; then
    d=$(( ( $(date +%s) - $(date -d "$(cat "$ALTA")" +%s) ) / 86400 ))
    echo "  sesión: alta o renovación el $(cat "$ALTA"); vence en $(( 30 - d )) días"
  fi
  mountpoint -q "$CARPETA" && echo "  montado: $CARPETA" || echo "  sin montar: $CARPETA"
}

renovar() {
  paso "Renovar la sesión de «$REMOTO» (pide un código nuevo en el iPhone)"
  "$BIN" config reconnect "$REMOTO:"
  mkdir -p "$ESTADO"; date +%F > "$ALTA"
  systemctl --user restart "$SERVICIO.service" 2>/dev/null || true
  echo "  renovada el $(date +%F)"
}

deshacer() {
  paso "Quitando el montaje de iCloud"
  for u in "$SERVICIO-fotos.service" "$SERVICIO.service" "$SERVICIO-vence.timer"; do
    systemctl --user disable --now "$u" 2>/dev/null || true
    rm -f "$UNIDADES/$u"
  done
  rm -f "$UNIDADES/$SERVICIO-vence.service"
  systemctl --user daemon-reload
  if [ -f "$ESTADO/$SERVICIO-fynder-antes.txt" ]; then
    gsettings set io.github.josemalena.fynder.preferences sidebar-icloud-path "$(tr -d "'" < "$ESTADO/$SERVICIO-fynder-antes.txt")" 2>/dev/null || true
  fi
  echo "  listo. Quedan: el remoto en rclone.conf («rclone config delete $REMOTO» lo borra),"
  echo "  la caché en ~/.cache/rclone/$SERVICIO y la carpeta vacía $CARPETA."
}

case "${1:-}" in
  instalar) instalar ;; alta) alta ;; montar) montar ;; fotos) fotos ;;
  estado) estado ;; renovar) renovar ;; deshacer) deshacer ;;
  *) sed -n '2,25p' "$0"; exit 2 ;;
esac
