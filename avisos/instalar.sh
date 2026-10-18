#!/bin/bash
# Los informes de System Reports de Mint como notificaciones, sin el ícono de
# mintreport-tray en la barra (José, 18-10-2026). Sin sudo: todo es del usuario.
#
#   ./instalar.sh            instala mint-macos-avisos (avisos.service) y esconde
#                            mintreport-tray
#   ./instalar.sh --quitar   la vuelta atrás: quita el servicio y devuelve la bandeja
#
# Cómo decide qué avisar: la cabecera de rust/avisos/src/main.rs. Su prueba:
# rust/avisos/prueba.sh (bus aparte; no toca la sesión).
set -euo pipefail
AQUI="$(cd "$(dirname "$0")" && pwd)"
LIB="$HOME/.local/lib/mint-macos"
UNIDADES="$HOME/.config/systemd/user"
AUTOSTART="$HOME/.config/autostart/mintreport.desktop"

if [ "${1:-}" = "--quitar" ]; then
  systemctl --user disable --now avisos.service 2>/dev/null || true
  rm -f "$UNIDADES/avisos.service" "$LIB/mint-macos-avisos"
  systemctl --user daemon-reload
  # Solo si la copia es nuestra: una de José se queda.
  if grep -q '^# mint-macos: avisos' "$AUTOSTART" 2>/dev/null; then
    rm -f "$AUTOSTART"
    pgrep -u "$USER" -x mintreport-tray >/dev/null || (setsid mintreport-tray >/dev/null 2>&1 < /dev/null &)
  fi
  echo "Quitado: mintreport-tray vuelve a la barra. El estado ($HOME/.local/state/mint-macos/avisos-mint) se queda."
  exit 0
fi

RUST="$AQUI/../rust/target/release/mint-macos-avisos"
[ -x "$RUST" ] || { echo "✗ falta compilar $RUST (cd rust && cargo build --release -p mint-macos-avisos)"; exit 1; }
mkdir -p "$LIB" "$UNIDADES" "$(dirname "$AUTOSTART")"
install -m 755 "$RUST" "$LIB/mint-macos-avisos"
cat > "$UNIDADES/avisos.service" <<EOF
[Unit]
Description=Los informes de System Reports como notificaciones (mint-macos)

[Service]
ExecStart=%h/.local/lib/mint-macos/mint-macos-avisos
Restart=on-failure
RestartSec=30

[Install]
WantedBy=default.target
EOF
systemctl --user daemon-reload
systemctl --user enable --now avisos.service >/dev/null 2>&1
echo "  avisos.service: $(systemctl --user is-active avisos.service)"

# El ícono de la bandeja: una copia en ~/.config/autostart tapa la de /etc/xdg sin
# tocarla.
if [ ! -e "$AUTOSTART" ]; then
  cat > "$AUTOSTART" <<'EOF'
[Desktop Entry]
# mint-macos: avisos. Los informes van por notificaciones (mint-macos-avisos);
# vuelta atrás: avisos/instalar.sh --quitar, o borrar este archivo.
Type=Application
Name=System Reports
Exec=mintreport-tray
Hidden=true
X-GNOME-Autostart-enabled=false
EOF
fi
pkill -u "$USER" -x mintreport-tray 2>/dev/null || true
echo "  mintreport-tray: fuera de la barra"
