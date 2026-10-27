#!/bin/bash
# Los íconos de 24 px (48 a 2x) de los módulos de Dock & Menu Bar de Monterey (Wi-Fi, Bluetooth, Sound…), del .car del panel Dock de esa Mac
# (car-sacado de referencias/monterey-*/), a ~/.local/share/mint-macos/iconos-monterey/Dock/<Nombre>.png. Son de Apple: se quedan en la máquina,
# nunca en el repo ni en el paquete. Sin referencias no hace nada y la fila de la barra lateral sale sin ícono.
#
#   perfiles/iconos-modulos-monterey.sh        (lo llama perfiles/instalar.sh)
set -u
DATOS="${XDG_DATA_HOME:-$HOME/.local/share}/mint-macos"
CAR=""
for d in "$DATOS"/referencias/monterey-*/car-sacado/iconos__prefpanes__Dock__Assets.car; do [ -d "$d" ] && CAR="$d"; done
[ -n "$CAR" ] || exit 0
DEST="$DATOS/iconos-monterey/Dock"
mkdir -p "$DEST"
n=0
for nombre in DockAndMenuBar WiFi Bluetooth AirDrop FocusModes ScreenMirroring Display Sound NowPlaying AccessibilityShortcuts Battery UserSwitcher Hearing Clock Spotlight Siri TimeMachine DoNotDisturb KeyboardBrightness; do
  f="$(ls "$CAR" 2>/dev/null | grep "^$nombre-48x48.*@2x\.png$" | head -1)"
  [ -n "$f" ] && cp -f "$CAR/$f" "$DEST/$nombre.png" && n=$((n + 1))
done
echo "íconos de los módulos de Monterey: $n en $DEST"
