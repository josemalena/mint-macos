#!/bin/bash
# System Preferences (Settings.app) para Cinnamon, con el diseño de Catalina.
#
#   ./instalar.sh            instala la app, el comando mac-settings y el lanzador
#   ./instalar.sh --quitar   lo deja como estaba: borra lo que instaló
#
# No reemplaza nada: cinnamon-settings sigue igual y el menú Apple, el Dock y los
# atajos siguen abriendo lo que abrían. Para que «System Preferences…» del menú
# Apple abra esta ventana, hay que cambiar ese applet (es de otra sesión).
#
# Los íconos de Apple salen de la Mac con ./desde-mac.sh; sin ellos la app se ve
# igual pero con los íconos del tema.
set -euo pipefail

AQUI="$(cd "$(dirname "$0")" && pwd)"
LIB="$HOME/.local/lib/mint-macos/settings"
BIN="$HOME/.local/bin/mac-settings"
LANZADOR="$HOME/.local/share/applications/mint-macos-settings.desktop"
ICONO="$HOME/.local/share/mint-macos/settings/iconos/sistema.png"

if [ "${1:-}" = "--quitar" ]; then
  rm -rf "$LIB" "$BIN" "$LANZADOR"
  update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
  echo "Listo: System Preferences quitada. Los íconos de Apple en ~/.local/share/mint-macos/settings se quedan (son tuyos)."
  exit 0
fi

for f in /usr/share/cinnamon/cinnamon-settings/cinnamon-settings.py; do
  [ -f "$f" ] || { echo "✗ No encuentro $f: esta app corre sobre cinnamon-settings (Cinnamon 6.x)." >&2; exit 1; }
done
for m in gi; do
  python3 -c "import $m" 2>/dev/null || { echo "✗ Falta python3-gi." >&2; exit 1; }
done
python3 -c "import cairo" 2>/dev/null || { echo "✗ Falta python3-gi-cairo (pycairo)." >&2; exit 1; }

mkdir -p "$LIB/estilo" "$(dirname "$BIN")" "$(dirname "$LANZADOR")"
install -m 755 "$AQUI/preferencias.py" "$LIB/preferencias.py"
install -m 644 "$AQUI/paneles.py" "$LIB/paneles.py"
install -m 644 "$AQUI/estilo/catalina.css" "$LIB/estilo/catalina.css"

cat > "$BIN" <<EOF
#!/bin/sh
exec python3 "$LIB/preferencias.py" "\$@"
EOF
chmod +x "$BIN"

icono="preferences-system"
[ -f "$ICONO" ] && icono="$ICONO"
cat > "$LANZADOR" <<EOF
[Desktop Entry]
Type=Application
Name=System Preferences
Comment=Personalize your computer
Exec=$BIN %U
Icon=$icono
Terminal=false
Categories=Settings;
StartupWMClass=mac-settings
Keywords=settings;preferences;system;control;
EOF
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true

echo "System Preferences instalada: $BIN"
echo "  mac-settings            la cuadrícula"
echo "  mac-settings sound      un panel (por su nombre de Cinnamon o de Catalina)"
echo "  mac-settings --lista    los paneles que hay"
[ -f "$ICONO" ] || echo "  (sin los íconos de la Mac: corre ./desde-mac.sh para que se vea como Catalina)"
echo "Para quitarla: $AQUI/instalar.sh --quitar"
