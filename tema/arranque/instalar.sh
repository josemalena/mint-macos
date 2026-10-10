#!/usr/bin/env bash
# El arranque como el de macOS: tema de Plymouth «catalina» (la manzana y la
# barra de progreso). Pide sudo: va a /usr/share/plymouth y rehace el
# initramfs.
#
#   ./instalar.sh --vista      solo genera las imágenes y una vista previa
#                              (~/.local/share/constanza/arranque/vista.png), sin sudo
#   sudo ./instalar.sh         lo instala y lo deja de tema por defecto
#   sudo ./instalar.sh --deshacer   vuelve al tema que había
#
# La manzana sale de la SF de la Mac del usuario (~/.local/share/fonts/
# san-francisco/SFNS.ttf, que pone desde-mac.sh): es de Apple, así que se
# genera en cada máquina y no va al repo.
set -euo pipefail

AQUI="$(cd "$(dirname "$0")" && pwd)"
USUARIO="${SUDO_USER:-${USER:-$(id -un)}}"
HOME_USUARIO="$(getent passwd "$USUARIO" | cut -d: -f6)"
LOCAL="$HOME_USUARIO/.local/share/constanza/arranque"
TEMAS=/usr/share/plymouth/themes
DESTINO="$TEMAS/catalina"
ANTERIOR="$LOCAL/tema-anterior.txt"
MODO="${1:-instalar}"

paso() { printf '\n▸ %s\n' "$*"; }

if [ "$MODO" = --deshacer ]; then
  [ "$(id -u)" = 0 ] || { echo "✗ con sudo"; exit 1; }
  T="$(cat "$ANTERIOR" 2>/dev/null || echo mint-logo)"
  paso "Volviendo al tema de arranque «$T»"
  plymouth-set-default-theme "$T"
  update-initramfs -u
  echo "  listo (el de Catalina queda en $DESTINO, sin usarse)"
  exit 0
fi

paso "Imágenes, a la medida de la pantalla"
# La pantalla más chica que esté conectada (el arranque sale en todas).
# De cada salida conectada, su modo preferido (el primero de la lista).
ALTO="$(for c in /sys/class/drm/card*-*; do
          if [ "$(cat "$c/status" 2>/dev/null)" = connected ]; then head -1 "$c/modes"; fi
        done 2>/dev/null | awk -Fx '{print $2+0}' | sort -n | head -1 || true)"
[ -n "$ALTO" ] || ALTO=1080
# En la Mac la manzana mide ~1/12 del alto de la pantalla y la barra el doble
# de ancho que la manzana, con 6 px de grueso (a 1x).
python3 - "$HOME_USUARIO/.local/share/fonts/san-francisco/SFNS.ttf" "$LOCAL" "$ALTO" <<'PY'
import os, sys
from PIL import Image, ImageDraw, ImageFont
fuente, salida, alto = sys.argv[1], sys.argv[2], int(sys.argv[3])
os.makedirs(salida, exist_ok=True)
if not os.path.exists(fuente):
    sys.exit("  ✗ falta SFNS.ttf: corre antes ./desde-mac.sh (la manzana sale de esa fuente)")
h = max(48, round(alto / 12))
grande = Image.new('L', (h * 6, h * 6), 0)
ImageDraw.Draw(grande).text((h, h), '', font=ImageFont.truetype(fuente, h * 4), fill=255)
mascara = grande.crop(grande.getbbox())
w = round(mascara.width * h / mascara.height)
manzana = Image.new('RGBA', (w, h), (255, 255, 255, 0))
manzana.putalpha(mascara.resize((w, h), Image.LANCZOS))
manzana.save(os.path.join(salida, 'manzana.png'))
bw, bh = round(h * 2.0), max(4, round(h / 16))
for nombre, color in (('barra-fondo.png', (90, 90, 90, 255)), ('barra-lleno.png', (255, 255, 255, 255))):
    barra = Image.new('RGBA', (bw * 4, bh * 4), (0, 0, 0, 0))
    ImageDraw.Draw(barra).rounded_rectangle((0, 0, bw * 4 - 1, bh * 4 - 1), radius=bh * 2, fill=color)
    barra.resize((bw, bh), Image.LANCZOS).save(os.path.join(salida, nombre))
print(f"  manzana {w}×{h}, barra {bw}×{bh} (pantalla de {alto} px de alto)")
PY

# Vista previa: lo que se vería a mitad de arranque.
python3 - "$LOCAL" "$ALTO" <<'PY'
import os, sys
from PIL import Image
d, alto = sys.argv[1], int(sys.argv[2]); ancho = round(alto * 16 / 10)
v = Image.new('RGB', (ancho, alto), (0, 0, 0))
m = Image.open(os.path.join(d, 'manzana.png')); f = Image.open(os.path.join(d, 'barra-fondo.png')); l = Image.open(os.path.join(d, 'barra-lleno.png'))
mx, my = ancho // 2 - m.width // 2, round(alto / 2 - m.height * 0.62)
v.paste(m, (mx, my), m)
px, py = ancho // 2 - f.width // 2, round(my + m.height + m.height * 0.72)
v.paste(f, (px, py), f)
mitad = l.crop((0, 0, l.width // 2, l.height)); v.paste(mitad, (px, py), mitad)
v.save(os.path.join(d, 'vista.png'))
PY
echo "  vista previa: $LOCAL/vista.png"
[ "$MODO" = --vista ] && exit 0

[ "$(id -u)" = 0 ] || { echo "✗ para instalarlo hace falta sudo: sudo $0"; exit 1; }
paso "Tema de Plymouth «catalina»"
command -v plymouth-set-default-theme >/dev/null || { echo "  ✗ falta plymouth"; exit 1; }
plymouth-set-default-theme > "$ANTERIOR" 2>/dev/null || echo mint-logo > "$ANTERIOR"
chown "$USUARIO": "$ANTERIOR"
echo "  el de ahora: $(cat "$ANTERIOR") (se guarda para --deshacer)"
install -d "$DESTINO"
install -m 644 "$AQUI/catalina.script" "$DESTINO/catalina.script"
install -m 644 "$LOCAL/manzana.png" "$LOCAL/barra-fondo.png" "$LOCAL/barra-lleno.png" "$DESTINO/"
cat > "$DESTINO/catalina.plymouth" <<EOF
[Plymouth Theme]
Name=Catalina
Description=El arranque de macOS: la manzana y la barra de progreso (mint-macos)
ModuleName=script

[script]
ImageDir=$DESTINO
ScriptFile=$DESTINO/catalina.script
EOF
plymouth-set-default-theme catalina
paso "initramfs (el arranque lo lee de ahí)"
update-initramfs -u
echo
echo "Listo: se ve en el próximo arranque. Para volver: sudo $0 --deshacer"
