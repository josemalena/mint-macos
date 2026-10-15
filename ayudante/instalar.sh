#!/bin/bash
# mint-macos-ayudante: un solo proceso residente para Force Quit y la barra de ⇧⌘5.
#
#   ./instalar.sh            lo instala y lo arranca oculto
#   ./instalar.sh --quitar   quita el arranque y el proceso; Force Quit y ⇧⌘5 siguen
#                            funcionando como antes (cada uno arranca su propio Python)
#
# Arranca con la sesión (~/.config/autostart) y se queda vivo con GTK cargado. Force Quit
# (applemenu@macos/forcekill.py) y mac-captura (⇧⌘5) le piden la ventana por D-Bus, sin
# arrancar Python; si el proceso no está, cada uno sigue de largo y abre la suya.
#
# Solo toca el home. Copia aquí lo que el ayudante carga, para que lo instalado y lo del repo
# sean lo mismo: forcekill.py al applet, captura.sh y herramienta.py a ~/.local/bin.
set -euo pipefail

AQUI="$(cd "$(dirname "$0")" && pwd)"
REPO="$(dirname "$AQUI")"
LIB="$HOME/.local/lib/mint-macos/ayudante"
BIN="$HOME/.local/bin/mint-macos-ayudante"
AUTOARRANQUE="$HOME/.config/autostart/mint-macos-ayudante.desktop"
APPLET="$HOME/.local/share/cinnamon/applets/applemenu@macos"
APP_ID=io.github.josemalena.MintMacosAyudante
RUTA_DBUS="/$(echo "$APP_ID" | tr . /)"

if [ "${1:-}" = "--quitar" ]; then
  rm -f "$AUTOARRANQUE"
  pkill -f "$LIB/ayudante.py" 2>/dev/null || true      # el residente de esta sesión
  rm -rf "$LIB" "$BIN"
  echo "Listo: mint-macos-ayudante quitado. Force Quit y ⇧⌘5 abren su propio Python, como antes."
  exit 0
fi

python3 -c "import gi" 2>/dev/null || { echo "✗ Falta python3-gi." >&2; exit 1; }

mkdir -p "$LIB" "$(dirname "$BIN")" "$(dirname "$AUTOARRANQUE")" "$HOME/.local/bin"
install -m 644 "$AQUI/ayudante.py" "$LIB/ayudante.py"
install -m 755 "$REPO/capturas/captura.sh" "$HOME/.local/bin/mac-captura"
install -m 755 "$REPO/capturas/herramienta.py" "$HOME/.local/bin/mac-captura-herramienta"
if [ -d "$APPLET" ]; then
  install -m 755 "$REPO/applets/applemenu@macos/forcekill.py" "$APPLET/forcekill.py"
else
  echo "  (no encuentro el applet applemenu@macos instalado: Force Quit no se pedirá al ayudante)"
fi

cat > "$BIN" <<EOF
#!/bin/sh
# mint-macos-ayudante forcequit|captura: pide la ventana al residente; si no está, lo levanta.
[ "\$#" -eq 1 ] || { echo "uso: \$0 forcequit|captura" >&2; exit 2; }
gdbus call --session --dest $APP_ID --object-path $RUTA_DBUS \\
  --method org.gtk.Actions.Activate "\$1" '[]' '{}' >/dev/null 2>&1 && exit 0
exec python3 "$LIB/ayudante.py" --accion "\$1"
EOF
chmod +x "$BIN"

cat > "$AUTOARRANQUE" <<EOF
[Desktop Entry]
Type=Application
Name=mint-macos-ayudante
Comment=Deja Force Quit y la barra de capturas listos para abrirse al instante
Exec=python3 $LIB/ayudante.py --residente
Terminal=false
X-GNOME-Autostart-enabled=true
EOF

echo "Instalado: $BIN"
echo "Arranque:  $AUTOARRANQUE"
echo "Para arrancarlo ahora sin cerrar sesión: setsid python3 $LIB/ayudante.py --residente &"
