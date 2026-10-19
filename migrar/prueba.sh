#!/bin/bash
# La prueba del migrador de configuración con un disco de Mac de mentira (plists, desktoppicture.db y
# el registro del usuario armados aquí) y una caja con HOME, XDG y bus propios: ni el disco de José
# ni su dconf entran. Comprueba lo que aplica, lo que deja en el informe, que del registro de dslocal
# no salga nada más que la foto, y que --deshacer lo devuelve todo.
set -uo pipefail
AQUI="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fallas=0
mal() { echo "  ✗ $*"; fallas=$((fallas + 1)); }

# El disco de mentira: macOS 12.7.6, oscuro automático, acento verde, resaltado «Other», Dock a la
# izquierda con lupa, una esquina con Launchpad y otra sin equivalente (6, Disable Screen Saver).
python3 -I - "$T/mac" <<'EOF'
import os, plistlib, sqlite3, sys
from PIL import Image
r = sys.argv[1]
def pl(ruta, d):
    os.makedirs(os.path.dirname(ruta), exist_ok=True)
    with open(ruta, "wb") as f:
        plistlib.dump(d, f, fmt=plistlib.FMT_BINARY)
pl(r + "/sistema/System/Library/CoreServices/SystemVersion.plist", {"ProductVersion": "12.7.6"})
os.makedirs(r + "/sistema/System/Library/CoreServices/CoreTypes.bundle", exist_ok=True)  # lo que busca montar_mac_sistema
p = r + "/datos/Users/ana/Library/Preferences/"
pl(p + ".GlobalPreferences.plist", {"AppleInterfaceStyle": "Dark", "AppleInterfaceStyleSwitchesAutomatically": True,
   "AppleAccentColor": 3, "AppleHighlightColor": "1.000000 0.500000 0.000000 Other", "AppleShowScrollBars": "WhenScrolling",
   "AppleActionOnDoubleClick": "Minimize", "com.apple.swipescrolldirection": True, "com.apple.mouse.scaling": 1.0})
pl(p + "com.apple.dock.plist", {"tilesize": 40.0, "magnification": True, "largesize": 80.0, "orientation": "left",
   "autohide": True, "show-recents": False, "wvous-tr-corner": 11, "wvous-bl-corner": 6,
   "persistent-apps": [{"tile-data": {"file-label": "Safari"}}]})
pl(p + "com.apple.finder.plist", {"ShowPathbar": True})
import io
b = io.BytesIO(); Image.new("RGB", (64, 64), (200, 10, 10)).save(b, "TIFF")
pl(r + "/datos/private/var/db/dslocal/nodes/Default/users/ana.plist",
   {"jpegphoto": [b.getvalue()], "realname": ["Ana"], "ShadowHashData": [b"SECRETO-NO-DEBE-SALIR"]})
d = r + "/datos/Users/ana/Library/Application Support/Dock/"
os.makedirs(d, exist_ok=True)
c = sqlite3.connect(d + "desktoppicture.db")
c.executescript("create table data(value); create table preferences(key integer, data_id integer, picture_id integer);")
c.execute("insert into data(rowid, value) values (1, '/Users/ana/Pictures'), (2, 'playa.jpg')")
c.execute("insert into preferences values (10, 1, 1), (16, 2, 1)"); c.commit()
os.makedirs(r + "/datos/Users/ana/Pictures", exist_ok=True)
Image.new("RGB", (32, 32), (0, 0, 255)).save(r + "/datos/Users/ana/Pictures/playa.jpg")
EOF

mkdir -m 700 -p "$T/run" "$T/cfg"
export HOME="$T/home" XDG_CONFIG_HOME="$T/cfg" XDG_RUNTIME_DIR="$T/run" XDG_DATA_HOME="$T/data"
export XDG_DATA_DIRS="/home/$USER/.local/share:/usr/local/share:/usr/share" MAC_DATOS="$T/mac/datos" MAC_SISTEMA="$T/mac/sistema"
mkdir -p "$HOME"
dbus-run-session -- bash -c '
  "'"$AQUI"'/migrar-config.sh" --aplicar --informe "$HOME/informe.md" > "$HOME/salida.txt" 2>&1
  for k in "org.cinnamon hotcorner-layout" "org.cinnamon.desktop.interface gtk-overlay-scrollbars" \
           "org.cinnamon.desktop.wm.preferences action-double-click-titlebar" "org.cinnamon.desktop.peripherals.mouse natural-scroll" \
           "org.cinnamon.desktop.background picture-uri"; do echo "$k = $(gsettings get $k)"; done > "$HOME/despues.txt"
  e="net.launchpad.plank.dock.settings:/net/launchpad/plank/docks/dock1/"
  for k in icon-size zoom-enabled zoom-percent position hide-mode show-recent-apps; do echo "dock $k = $(gsettings get $e $k)"; done >> "$HOME/despues.txt"
  "'"$AQUI"'/migrar-config.sh" --deshacer > /dev/null 2>&1
  for k in "org.cinnamon hotcorner-layout" "org.cinnamon.desktop.interface gtk-overlay-scrollbars"; do echo "$k = $(gsettings get $k)"; done > "$HOME/deshecho.txt"
  echo "dock icon-size = $(gsettings get $e icon-size)" >> "$HOME/deshecho.txt"
  ls "$HOME/.face" >> "$HOME/deshecho.txt" 2>&1
'
D="$HOME/despues.txt"; I="$HOME/informe.md"
grep -q "hotcorner-layout = \['expo:false:0', '$HOME/.local/bin/mac-launchpad:true:0', 'expo:false:0', 'expo:false:0'\]" "$D" \
  || mal "Hot Corners: $(grep hotcorner "$D")"
grep -q "gtk-overlay-scrollbars = true" "$D" || mal "WhenScrolling → overlay"
grep -q "action-double-click-titlebar = 'minimize'" "$D" || mal "doble clic → minimize"
grep -q "natural-scroll = true" "$D" || mal "scroll natural"
grep -q "picture-uri = 'file://$HOME/.local/share/backgrounds/migrado/playa.jpg'" "$D" || mal "fondo: $(grep picture "$D")"
grep -q "dock icon-size = 40" "$D" && grep -q "dock zoom-enabled = true" "$D" && grep -q "dock zoom-percent = 200" "$D" \
  && grep -q "dock position = 'left'" "$D" && grep -q "dock hide-mode = 'auto'" "$D" && grep -q "dock show-recent-apps = false" "$D" \
  || mal "Dock: $(grep dock "$D" | tr '\n' ' ')"
grep -q "apariencia auto, acento Green, resaltado #FF8000" "$I" || mal "apariencia: $(grep apariencia "$I")"
grep -q "Hot Corners .*sin equivalente: bl=6" "$I" || mal "la esquina 6 sin equivalente"
grep -q "perfil monterey-12.7.6" "$I" || mal "versión → perfil de Monterey"
grep -q "velocidad del puntero .*solo informe" "$I" || mal "la velocidad del puntero no se aplica (sin verificar)"
file -b "$HOME/../home/.face" 2>/dev/null | grep -q PNG || true
grep -rq "SECRETO-NO-DEBE-SALIR" "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" 2>/dev/null && mal "salió algo del registro de dslocal que no es la foto"
grep -q "hotcorner-layout = \['expo:false:0', 'scale:false:0', 'scale:false:0', 'desktop:false:0'\]" "$HOME/deshecho.txt" || mal "deshacer las esquinas: $(head -1 "$HOME/deshecho.txt")"
grep -q "dock icon-size = 48" "$HOME/deshecho.txt" || mal "deshacer el Dock"
grep -q "No such file" "$HOME/deshecho.txt" || mal "deshacer ~/.face"
[ $fallas = 0 ] && echo "  ✓ migrador de configuración: bien" || { echo "  ✗ $fallas fallas"; sed 's/^/    /' "$HOME/salida.txt" | tail -25; exit 1; }
