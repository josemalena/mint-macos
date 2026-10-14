#!/usr/bin/env bash
# Pantalla de inicio de sesión: saca de la Mac, en SOLO LECTURA y a una
# carpeta local, lo que slick-greeter-mac usa de Apple. Nada va al repo.
#
#   MAC_DATOS=/ruta/al/volumen/de/datos [MAC_USUARIO=nombre] ./desde-mac.sh
#
# Lo llama ../desde-mac.sh --login con el volumen ya montado. Sin MAC_DATOS
# prueba /media/$USER/* buscando uno que tenga Users/ y Library/Caches.
#
# Deja en ~/.local/share/constanza/login/:
#   fondo-claro.jpg, fondo-oscuro.jpg
#               los dos fondos del login: la lista de usuarios sobre el claro
#               y, al elegir a alguien, el oscuro (Catalina.heic, cuadros 0 y 1)
#   avatar.png  la foto de la cuenta (jpegphoto del usuario en dslocal; viene
#               en TIFF aunque se llame así)
#   iconos/     los botones de abajo, de loginwindow.app del volumen de
#               SISTEMA (MAC_SISTEMA): Restart, ShutDown y Sleep en 1x y 2x.
#               Cancel no está en la Mac: lo dibuja el greeter.
#
# Sin sudo: si el plist de la cuenta no se deja leer, lo dice y sigue sin foto.
set -euo pipefail

DESTINO="$HOME/.local/share/constanza/login"
mkdir -p "$DESTINO"

if [ -z "${MAC_DATOS:-}" ]; then
  for d in /media/"$USER"/*; do
    if [ -d "$d/Users" ] && [ -d "$d/Library/Caches" ]; then MAC_DATOS="$d"; break; fi
  done
fi
[ -n "${MAC_DATOS:-}" ] || { echo "  ✗ no encontré el volumen de datos de la Mac (define MAC_DATOS)"; exit 1; }
echo "  volumen de datos: $MAC_DATOS"

# Los fondos: el escritorio dinámico de Catalina (System/Library/Desktop
# Pictures/Catalina.heic, en el volumen de SISTEMA). Trae ocho cuadros; el 0 es
# la Catalina «clara» (el atardecer de la lista de usuarios) y el 1 la de noche
# (la que sale al elegir a alguien). Sin desenfocar: así los muestra el login
# de la Mac (fotos de José, 14-10-2026). A 1920×1200, recortada al centro.
if [ -n "${MAC_SISTEMA:-}" ] && [ -f "$MAC_SISTEMA/System/Library/Desktop Pictures/Catalina.heic" ]; then
  HEIC="$MAC_SISTEMA/System/Library/Desktop Pictures/Catalina.heic"
  for par in "0:claro" "1:oscuro"; do
    convert "$HEIC[${par%%:*}]" -resize 1920x1200^ -gravity center -extent 1920x1200 -quality 92 "$DESTINO/fondo-${par##*:}.jpg"
    echo "  fondo ${par##*:}: $DESTINO/fondo-${par##*:}.jpg"
  done
else
  echo "  sin MAC_SISTEMA o sin Catalina.heic: no hay fondos (corre ../desde-mac.sh --login)"
fi

# Los botones de abajo (Sleep, Restart, Shut Down), del sistema.
if [ -n "${MAC_SISTEMA:-}" ]; then
  RES="$MAC_SISTEMA/System/Library/CoreServices/loginwindow.app/Contents/Resources"
  mkdir -p "$DESTINO/iconos"
  for n in Restart ShutDown Sleep; do
    if [ -f "$RES/$n.tiff" ]; then
      convert "$RES/$n.tiff[0]" "$DESTINO/iconos/$n@1x.png"
      convert "$RES/$n.tiff[1]" "$DESTINO/iconos/$n@2x.png" 2>/dev/null || true
    fi
  done
  echo "  botones: $(ls "$DESTINO/iconos" | wc -l) archivos en $DESTINO/iconos"
else
  echo "  sin MAC_SISTEMA: los botones de abajo quedan dibujados (corre ../desde-mac.sh --login)"
fi

# La foto de la cuenta.
DSLOCAL="$MAC_DATOS/private/var/db/dslocal/nodes/Default/users"
if [ -z "${MAC_USUARIO:-}" ]; then
  MAC_USUARIO="$(ls "$MAC_DATOS/Users" | grep -vE '^(Shared|Guest|\..*)$' | head -1)"
fi
PLIST="$DSLOCAL/$MAC_USUARIO.plist"
if [ -r "$PLIST" ]; then
  python3 - "$PLIST" "$DESTINO/avatar.tiff" <<'PY'
import plistlib, sys
d = plistlib.load(open(sys.argv[1], 'rb'))
foto = d.get('jpegphoto')
if not foto:
    sys.exit("  la cuenta no tiene foto (jpegphoto)")
open(sys.argv[2], 'wb').write(foto[0])
PY
  convert "$DESTINO/avatar.tiff" "$DESTINO/avatar.png" && rm -f "$DESTINO/avatar.tiff"
  echo "  foto de $MAC_USUARIO: $DESTINO/avatar.png"
else
  echo "  ✗ no puedo leer $PLIST (es de root en la Mac): sin foto. Con sudo: sudo cat \"$PLIST\" > /tmp/cuenta.plist"
fi
