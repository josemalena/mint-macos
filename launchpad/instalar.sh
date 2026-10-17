#!/bin/bash
# Launchpad de Catalina: el programa, el comando mac-launchpad y el lanzador del usuario.
#
#   ./instalar.sh            instala (el lanzador de rofi de este usuario se respalda)
#   ./instalar.sh --quitar   lo deja como estaba: devuelve el lanzador anterior
#
# El atajo es ⌥⌘L. keyd manda ⌘ como Ctrl y la tecla con ⌥ llega a Cinnamon como
# Ctrl+Alt+L (como ⌘⌥F en VS Code), así que el atajo de Cinnamon es <Control><Alt>l.
# kitty recibe ⌘ y ⌥ sin traducir (keyd/app.conf): ahí llega como Super+Alt+L, y por
# eso el atajo lleva también <Super><Alt>l (comprobado con xinput el 14-10-2026).
#
# Solo toca el home del usuario: no escribe en /usr/share ni borra rofi.
set -euo pipefail

AQUI="$(cd "$(dirname "$0")" && pwd)"
LIB="$HOME/.local/lib/mint-macos/launchpad"
BIN="$HOME/.local/bin/mac-launchpad"
LANZADOR="$HOME/.local/share/applications/launchpad.desktop"
RESPALDO="$HOME/.local/share/mint-macos/respaldos/launchpad.desktop.antes"
MARCA="X-MintMacos-Launchpad=1"
AUTOARRANQUE="$HOME/.config/autostart/mint-macos-launchpad.desktop"
APP_ID=io.github.josemalena.MintMacosLaunchpad
RUTA_DBUS="/$(echo "$APP_ID" | tr . /)"
CLAVES=org.cinnamon.desktop.keybindings
RUTA=/org/cinnamon/desktop/keybindings/custom-keybindings
ATAJO="<Control><Alt>l"
ATAJO_KITTY="<Super><Alt>l"

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
  gsettings set $CLAVES.custom-keybinding:$RUTA/$k/ binding "['$ATAJO', '$ATAJO_KITTY']"
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
  rm -f "$AUTOARRANQUE"
  pkill -f "$LIB/launchpad.py" 2>/dev/null || true      # el residente de esta sesión
  pkill -f "^$HOME/.local/bin/mac-launchpad-vala( |\$)" 2>/dev/null || true     # por ruta: pkill -x trunca a 15 caracteres
  rm -f "$BIN"; rm -rf "$LIB"
  echo "Listo. mac-launchpad ya no está instalado."
  exit 0
fi

mkdir -p "$LIB" "$(dirname "$BIN")" "$(dirname "$RESPALDO")"
install -m 0644 "$AQUI/launchpad.py" "$LIB/launchpad.py"
# El Launchpad es residente: arranca oculto con la sesión y el atajo solo le pide, por
# D-Bus y sin arrancar Python, que se muestre o se esconda. Si el proceso no está (se cayó
# o aún no arrancó), el mismo comando lo levanta y lo muestra.
cat > "$BIN" <<LANZ
#!/bin/sh
if [ "\$#" -eq 0 ]; then
  gdbus call --session --dest $APP_ID --object-path $RUTA_DBUS \\
    --method org.freedesktop.Application.Activate '{}' >/dev/null 2>&1 && exit 0
fi
# El de Vala solo se usa si José lo activó (nativo/activar-launchpad.sh deja el marcador) y el binario está instalado;
# nativo/activar-launchpad.sh --quitar, quitar el binario o MAC_LAUNCHPAD_PYTHON=1 devuelven el de Python.
# Los dos comparten el id de aplicación: solo uno es el residente.
NATIVO="\$HOME/.local/bin/mac-launchpad-vala"
if [ -z "\$MAC_LAUNCHPAD_PYTHON" ] && [ -f "\$HOME/.config/mint-macos/launchpad-vala.activo" ] && [ -x "\$NATIVO" ]; then exec "\$NATIVO" "\$@"; fi
exec python3 "$LIB/launchpad.py" "\$@"
LANZ
chmod +x "$BIN"
mkdir -p "$(dirname "$AUTOARRANQUE")"
cat > "$AUTOARRANQUE" <<AUTO
[Desktop Entry]
Type=Application
Name=Launchpad (residente)
Comment=Deja el Launchpad armado y oculto para que el atajo lo muestre al instante
Exec=$BIN --residente
Terminal=false
X-GNOME-Autostart-enabled=true
$MARCA
AUTO

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
