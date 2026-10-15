#!/bin/bash
# El agente de polkit estilo Catalina (mint-macos). Todo es del home: no pide root.
#
#   ./instalar.sh             copia el agente y su supervisor, y deja el arranque con la sesión
#                             (mientras Cinnamon tenga su agente, el nuestro sale sin hacer nada)
#   ./instalar.sh --activar   apaga el agente de Cinnamon (org.cinnamon enable-polkit-agent=false):
#                             surte efecto en el próximo arranque de Cinnamon, y hace falta el sí de José
#   ./instalar.sh --quitar    lo deja como estaba: para el agente, quita el arranque, vuelve a encender
#                             el de Cinnamon y lo registra en caliente si no quedó ninguno
set -euo pipefail

AQUI="$(cd "$(dirname "$0")" && pwd)"
LIB="$HOME/.local/lib/mint-macos/polkit"
BIN="$HOME/.local/bin/mint-macos-polkit"
AUTOARRANQUE="$HOME/.config/autostart/mint-macos-polkit.desktop"

case "${1:-}" in
  --quitar)
    rm -f "$AUTOARRANQUE"
    for p in $(pgrep -x mint-macos-polkit 2>/dev/null || true); do kill "$p" 2>/dev/null || true; done   # el supervisor
    for p in $(pgrep -f "^python3 $LIB/agente.py" 2>/dev/null || true); do kill "$p" 2>/dev/null || true; done
    gsettings set org.cinnamon enable-polkit-agent true
    sleep 1
    # Sin agente en la sesión, se registra el de Cinnamon sin reiniciar nada.
    gdbus call --session --dest org.Cinnamon --object-path /org/Cinnamon --method org.Cinnamon.Eval \
      "imports.ui.polkitAuthenticationAgent.init()" >/dev/null 2>&1 || true
    rm -rf "${LIB:?}" "$BIN"
    echo "Listo: el agente de Cinnamon vuelve a ser el de la sesión."
    exit 0 ;;
  --activar)
    gsettings set org.cinnamon enable-polkit-agent false
    echo "Cinnamon ya no registrará su agente en el próximo arranque. Reinicia Cinnamon (o cierra sesión)"
    echo "para que el agente de mint-macos sea el único; hasta entonces el de Cinnamon sigue en pie."
    exit 0 ;;
esac

python3 -c "import gi; gi.require_version('PolkitAgent', '1.0')" 2>/dev/null \
  || { echo "✗ Falta gir1.2-polkit-1.0 (PolkitAgent)." >&2; exit 1; }
mkdir -p "$LIB" "$(dirname "$BIN")" "$(dirname "$AUTOARRANQUE")"
install -m 755 "$AQUI/agente.py" "$LIB/agente.py"
install -m 755 "$AQUI/mint-macos-polkit" "$LIB/mint-macos-polkit"
ln -sf "$LIB/mint-macos-polkit" "$BIN"
cat > "$AUTOARRANQUE" <<EOT
[Desktop Entry]
Type=Application
Name=mint-macos-polkit
Comment=El diálogo de clave de administrador estilo Catalina
Exec=$LIB/mint-macos-polkit
Terminal=false
X-GNOME-Autostart-enabled=true
EOT
echo "Instalado: $LIB y el arranque con la sesión."
echo "Para que sea el agente de verdad: ./instalar.sh --activar y reiniciar Cinnamon (con el sí de José)."
echo "Para deshacerlo todo: ./instalar.sh --quitar"
