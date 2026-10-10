#!/usr/bin/env bash
# La barra de menús como la de Catalina (entrega 1): 22 px, el reloj
# «Sat Oct 10 12:32 PM» y los íconos de estado en el orden de la Mac.
# Medido contra capturas de la Mac mini a 1x (10-10-2026).
#
# Respalda lo que había antes de tocar nada. No pide sudo.
set -euo pipefail

RESPALDO="$HOME/.local/share/mint-macos/respaldos/barra-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$RESPALDO"
dconf dump /org/cinnamon/ > "$RESPALDO/org-cinnamon.dconf"
cp -a "$HOME/.config/cinnamon/spices/calendar@cinnamon.org" "$RESPALDO/" 2>/dev/null || true
echo "  respaldo del panel en $RESPALDO"

# 22 px: el alto de la barra de la Mac a 1x (Cinnamon venía en 20).
gsettings set org.cinnamon panels-height "['1:22']"

# Izquierda: menú Apple, la app activa y su menú (los tres de mint-macos),
# sin el separador de Cinnamon: la Mac no tiene esa rayita antes de la manzana.
# Derecha, como en la Mac: bandeja (Bluetooth), red, sonido, reloj, usuario y
# la lupa de Spotlight (buscar@macos, abre Ulauncher) y la Notification Center
# (notificaciones@macos, en lugar del applet de Cinnamon). Sin la esquina de
# «mostrar escritorio».
gsettings set org.cinnamon enabled-applets "['panel1:left:1:applemenu@macos:24', 'panel1:left:2:appmenu@macos:23', 'panel1:left:3:globalmenu@macos:25', 'panel1:right:6:systray@cinnamon.org:3', 'panel1:right:7:xapp-status@cinnamon.org:4', 'panel1:right:8:network@cinnamon.org:26', 'panel1:right:9:sound@cinnamon.org:11', 'panel1:right:11:calendar@cinnamon.org:13', 'panel1:right:12:user@cinnamon.org:27', 'panel1:right:13:buscar@macos:29', 'panel1:right:14:notificaciones@macos:30']"

# El reloj: «Sat Oct 10 12:32 PM», sin comas y con PM en mayúscula.
CAL="$HOME/.config/cinnamon/spices/calendar@cinnamon.org/13.json"
if [ -f "$CAL" ]; then
  python3 - "$CAL" <<'PY'
import json, sys
f = sys.argv[1]
d = json.load(open(f))
d['use-custom-format']['value'] = True
d['custom-format']['value'] = '%a %b %-d %-I:%M %p'
json.dump(d, open(f, 'w'), indent=4)
PY
  gdbus call --session --dest org.Cinnamon --object-path /org/Cinnamon \
    --method org.Cinnamon.ReloadXlet 'calendar@cinnamon.org' 'APPLET' >/dev/null || true
else
  echo "  el reloj todavía no tiene configuración: ábrelo una vez y vuelve a correr esto"
fi

# Letras en gris, sin los bordes de color del subpíxel: así las pinta la Mac
# desde Mojave. Es de todo el escritorio (José, 10-10-2026).
gsettings set org.cinnamon.settings-daemon.plugins.xsettings antialiasing 'grayscale'

# Bluetooth en la bandeja, como el ícono de la Mac.
pgrep -x blueman-applet >/dev/null || (setsid nohup blueman-applet >/dev/null 2>&1 &)
echo "  listo"
