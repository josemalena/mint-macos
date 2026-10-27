#!/bin/bash
# Los perfiles de versión de macOS (perfiles/ESQUEMA.md) en esta máquina, sin sudo:
#   - genera ~/.local/share/mint-macos/macos/<versión>/ con lo que haya aquí (disco de la Mac,
#     referencias de extraer-mac); lo que no tenga fuente queda anotado como «falta»;
#   - pone ~/.local/bin/mint-macos-version (escoger la versión: vale al volver a entrar);
#   - y un autoarranque que, al entrar, pasa la escogida a activa.
#
#   perfiles/instalar.sh            instala y genera
#   perfiles/instalar.sh --quitar   la vuelta atrás (no borra la versión escogida)
set -euo pipefail
AQUI=$(cd "$(dirname "$0")" && pwd)
BIN=$HOME/.local/bin/mint-macos-version
AUTO=$HOME/.config/autostart/mint-macos-version.desktop
if [ "${1:-}" = --quitar ]; then
	rm -f "$BIN" "$AUTO"
	echo "Quitado (los perfiles generados siguen en ~/.local/share/mint-macos/macos)."
	exit 0
fi
mkdir -p "$(dirname "$BIN")" "$(dirname "$AUTO")"
cat > "$BIN" <<FIN
#!/bin/sh
# mint-macos: la versión de macOS escogida (perfiles/macos_version.py).
exec python3 -I "$AQUI/macos_version.py" "\$@"
FIN
chmod 755 "$BIN"
cat > "$AUTO" <<FIN
[Desktop Entry]
Type=Application
Name=mint-macos: versión de macOS
Comment=Pasa la versión de macOS escogida a la de esta sesión
Exec=$BIN --aplicar
X-GNOME-Autostart-Phase=Initialization
X-GNOME-Autostart-enabled=true
NoDisplay=true
FIN
nice -n 19 python3 -I "$AQUI/generar.py"
# Los íconos de los módulos de Dock & Menu Bar de Monterey (del .car del panel, en las referencias); sin ellas la fila va sin ícono.
"$AQUI/iconos-modulos-monterey.sh" || true
# Los temas de íconos de Apple (Mint-Macos-<versión>) de las versiones cuyos glifos ya están en las referencias de esta máquina (paso «simbolos»
# de car-mac); se instalan, no se activan.
for d in "${XDG_DATA_HOME:-$HOME/.local/share}"/mint-macos/referencias/simbolos-*/*/; do
	v="$(basename "$d")"
	[ -d "$d" ] && python3 -I "$AQUI/../iconos/construir-tema-macos.py" "$v" || true
done
# La de esta sesión, si todavía no hay (la primera vez no hay que salir y entrar).
[ -f "${XDG_RUNTIME_DIR:-/tmp}/mint-macos/macos.json" ] || "$BIN" --aplicar
echo "Instalado: $BIN (versión activa: $("$BIN" | head -1 | cut -d' ' -f2)); vuelta atrás: $0 --quitar"
