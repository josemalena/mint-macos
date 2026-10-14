#!/bin/bash
# Launchpad de Catalina: el programa, el comando mac-launchpad y el lanzador del usuario.
#
#   ./instalar.sh            instala (el lanzador de rofi de este usuario se respalda)
#   ./instalar.sh --quitar   lo deja como estaba: devuelve el lanzador anterior
#
# El atajo es ⌥⌘L. keyd manda ⌘ como Ctrl y la tecla con ⌥ llega a Cinnamon como
# Ctrl+Alt+L (como ⌘⌥F en VS Code), así que el atajo de Cinnamon es <Control><Alt>l.
#
# Solo toca el home del usuario: no escribe en /usr/share ni borra rofi.
set -euo pipefail

AQUI="$(cd "$(dirname "$0")" && pwd)"
LIB="$HOME/.local/lib/mint-macos/launchpad"
BIN="$HOME/.local/bin/mac-launchpad"
LANZADOR="$HOME/.local/share/applications/launchpad.desktop"
RESPALDO="$HOME/.local/share/mint-macos/respaldos/launchpad.desktop.antes"
MARCA="X-MintMacos-Launchpad=1"
CLAVES=org.cinnamon.desktop.keybindings
RUTA=/org/cinnamon/desktop/keybindings/custom-keybindings
ATAJO="<Control><Alt>l"

# El atajo de Cinnamon: una entrada personalizada que corre mac-launchpad.
quitar_atajo() {
  local lista nueva="" k
  lista=$(gsettings get $CLAVES custom-list | tr -d "[]',")
  for k in $lista; do
    if [ "$(gsettings get $CLAVES.custom-keybinding:$RUTA/$k/ command 2>/dev/null)" = "'$BIN'" ]; then
      gsettings reset-recursively $CLAVES.custom-keybinding:$RUTA/$k/ 2>/dev/null || true
    else
      nueva="$nueva'$k', "
    fi
  done
  gsettings set $CLAVES custom-list "[${nueva%, }]"
}
poner_atajo() {
  quitar_atajo
  local lista n=0 k
  lista=$(gsettings get $CLAVES custom-list | tr -d "[]',")
  while echo " $lista " | grep -q " custom$n "; do n=$((n + 1)); done
  k=custom$n
  gsettings set $CLAVES.custom-keybinding:$RUTA/$k/ name "Launchpad (⌥⌘L)"
  gsettings set $CLAVES.custom-keybinding:$RUTA/$k/ command "$BIN"
  gsettings set $CLAVES.custom-keybinding:$RUTA/$k/ binding "['$ATAJO']"
  gsettings set $CLAVES custom-list "[$(for x in $lista $k; do printf "'%s', " "$x"; done | sed 's/, $//')]"
}

if [ "${1:-}" = "--quitar" ]; then
  if [ -f "$RESPALDO" ]; then
    cp "$RESPALDO" "$LANZADOR"
    rm -f "$RESPALDO"
    echo "Lanzador anterior devuelto: $LANZADOR"
  elif grep -q "$MARCA" "$LANZADOR" 2>/dev/null; then
    rm -f "$LANZADOR"
    echo "Lanzador propio quitado."
  fi
  quitar_atajo
  rm -f "$BIN"; rm -rf "$LIB"
  echo "Listo. mac-launchpad ya no está instalado."
  exit 0
fi

mkdir -p "$LIB" "$(dirname "$BIN")" "$(dirname "$RESPALDO")"
install -m 0644 "$AQUI/launchpad.py" "$LIB/launchpad.py"
printf '#!/bin/sh\nexec python3 "%s/launchpad.py" "$@"\n' "$LIB" > "$BIN"
chmod +x "$BIN"

# El lanzador del usuario: el Dock (Plank) apunta a este archivo. Si ya había uno que
# no es nuestro (el de rofi), se guarda una sola vez para poder devolverlo.
if [ -f "$LANZADOR" ] && ! grep -q "$MARCA" "$LANZADOR" && [ ! -f "$RESPALDO" ]; then
  cp "$LANZADOR" "$RESPALDO"
fi
cat > "$LANZADOR" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Launchpad
Comment=Abre las aplicaciones de /Applications
Exec=$BIN
Icon=launchpad
Terminal=false
Categories=Utility;
StartupNotify=false
$MARCA
DESKTOP
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
poner_atajo
echo "Instalado: $BIN"
echo "Atajo:     ⌥⌘L (Cinnamon: $ATAJO)"
echo "Lanzador:  $LANZADOR (el Dock lo usa)"
[ -f "$RESPALDO" ] && echo "El anterior quedó en $RESPALDO; ./instalar.sh --quitar lo devuelve."
