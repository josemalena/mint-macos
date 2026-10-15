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
AUTOARRANQUE="$HOME/.config/autostart/mint-macos-settings.desktop"
APP_ID=io.github.josemalena.MintMacosSettings
RUTA_DBUS="/$(echo "$APP_ID" | tr . /)"

if [ "${1:-}" = "--quitar" ]; then
  rm -f "$AUTOARRANQUE"
  pkill -f "$LIB/preferencias.py" 2>/dev/null || true      # el residente de esta sesión
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
install -m 644 "$AQUI/apple_id.py" "$LIB/apple_id.py"
install -m 644 "$AQUI/propios.py" "$LIB/propios.py"
install -m 644 "$AQUI/teclado.py" "$LIB/teclado.py"
install -m 644 "$AQUI/raton.py" "$LIB/raton.py"
install -m 644 "$AQUI/general.py" "$LIB/general.py"
install -m 644 "$AQUI/sonido.py" "$LIB/sonido.py"
install -m 644 "$AQUI/pantallas.py" "$LIB/pantallas.py"
install -m 644 "$AQUI/avisos.py" "$LIB/avisos.py"
install -m 644 "$AQUI/fecha.py" "$LIB/fecha.py"
install -m 644 "$AQUI/energia.py" "$LIB/energia.py"
install -m 644 "$AQUI/bt.py" "$LIB/bt.py"
install -m 644 "$AQUI/compartir.py" "$LIB/compartir.py"
install -m 644 "$AQUI/actualizaciones.py" "$LIB/actualizaciones.py"
install -m 644 "$AQUI/estilo/catalina.css" "$LIB/estilo/catalina.css"

# System Preferences es residente: arranca escondida con la sesión y mac-settings solo le
# pide, por D-Bus y sin arrancar Python, que se muestre (con el panel pedido). Si el
# proceso no está (se cayó o aún no arrancó), el mismo comando lo levanta.
cat > "$BIN" <<EOF
#!/bin/sh
case "\${1:-}" in
  -*) ;;                                   # --lista y demás van al programa
  *) if [ "\$#" -le 1 ]; then
       gdbus call --session --dest $APP_ID --object-path $RUTA_DBUS \\
         --method org.gtk.Actions.Activate abrir "[<'\${1:-}'>]" '{}' >/dev/null 2>&1 && exit 0
     fi ;;
esac
exec python3 "$LIB/preferencias.py" "\$@"
EOF
chmod +x "$BIN"
mkdir -p "$(dirname "$AUTOARRANQUE")"
cat > "$AUTOARRANQUE" <<EOF
[Desktop Entry]
Type=Application
Name=System Preferences (residente)
Comment=Deja System Preferences armada y escondida para que se abra al instante
Exec=python3 $LIB/preferencias.py --residente
Terminal=false
X-GNOME-Autostart-enabled=true
EOF

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
