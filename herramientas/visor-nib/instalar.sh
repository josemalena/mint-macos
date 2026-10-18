#!/bin/sh
# El visor de nib como programa del usuario (sin sudo): ~/.local/bin/mac-visor-nib y su
# .desktop «Mac App Viewer». Fynder lo abre al hacer doble clic en una .app de la Mac.
#
#   sh herramientas/visor-nib/instalar.sh            instala
#   sh herramientas/visor-nib/instalar.sh --quitar   la vuelta atrás
set -eu
AQUI=$(cd "$(dirname "$0")" && pwd)
BIN=$HOME/.local/bin/mac-visor-nib
DESK=$HOME/.local/share/applications/mint-macos-visor-nib.desktop
if [ "${1:-}" = --quitar ]; then
	rm -f "$BIN" "$DESK"
	update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
	echo "Quitado."
	exit 0
fi
mkdir -p "$(dirname "$BIN")" "$(dirname "$DESK")"
cat > "$BIN" <<EOF
#!/bin/sh
# mint-macos: el visor de nib (herramientas/visor-nib). Lo que pinta va a ~/.local/share/mint-macos/visor-nib.
exec nice -n 10 python3 -I "$AQUI/visor.py" "\$@"
EOF
chmod 755 "$BIN"
cat > "$DESK" <<EOF
[Desktop Entry]
Type=Application
Name=Mac App Viewer
Comment=Pinta las ventanas y los menús de una app de la Mac desde sus nib
Exec=$BIN %f
Icon=applications-system
NoDisplay=true
Terminal=false
EOF
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
echo "Instalado: $BIN (vuelta atrás: sh $0 --quitar)"
