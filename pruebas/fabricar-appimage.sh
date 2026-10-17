#!/usr/bin/env bash
# Fabrica AppImages de mentira para las pruebas de mint-macos-appimages: un ELF
# estático con «AI\x02» en el byte 8 y un squashfs pegado detrás, como una de
# verdad. Si alguien la ejecuta, deja una línea en $HOME/appimage-ejecutada con
# sus argumentos: así se ve que integrarla no la corre.
#
#   pruebas/fabricar-appimage.sh SALIDA [variante]
#
# Variantes: buena (por defecto), sin-integrar (X-AppImage-Integrate=false),
# enlace-fuera (el .desktop es un enlace a ../../etc/passwd), tipo1 (AI\x01),
# dwarfs (DWARFS en vez de squashfs), elf (un ELF sin firma de AppImage) y
# texto (un archivo de texto con el nombre .AppImage).
set -euo pipefail

SALIDA="$1"
VARIANTE="${2:-buena}"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

if [ "$VARIANTE" = texto ]; then
  echo "no soy una AppImage" > "$SALIDA"
  exit 0
fi

cat > "$T/runtime.c" <<'C'
#include <stdio.h>
#include <stdlib.h>
int main(int argc, char **argv) {
    const char *h = getenv("HOME");
    char p[4096];
    snprintf(p, sizeof p, "%s/appimage-ejecutada", h ? h : "/tmp");
    FILE *f = fopen(p, "a");
    if (f) {
        for (int i = 0; i < argc; i++) fprintf(f, "%s%c", argv[i], i + 1 < argc ? ' ' : '\n');
        fclose(f);
    }
    return 0;
}
C
gcc -static -O2 -o "$T/runtime" "$T/runtime.c"

# El final del ELF tiene que ser el final de su tabla de secciones (es lo que
# lee el servicio para saber dónde empieza el squashfs).
fin=$(python3 -I -c '
import struct, sys
h = open(sys.argv[1], "rb").read(64)
print(struct.unpack_from("<Q", h, 0x28)[0] + struct.unpack_from("<H", h, 0x3A)[0] * struct.unpack_from("<H", h, 0x3C)[0])' "$T/runtime")
[ "$fin" = "$(stat -c %s "$T/runtime")" ] || { echo "el ELF no termina en su tabla de secciones" >&2; exit 1; }

case "$VARIANTE" in
  elf) cp "$T/runtime" "$SALIDA"; exit 0 ;;
  tipo1) firma='AI\x01' ;;
  *) firma='AI\x02' ;;
esac
printf "$firma" | dd of="$T/runtime" bs=1 seek=8 conv=notrunc status=none

mkdir -p "$T/raiz/usr/share/icons/hicolor/256x256/apps"
integrar=""
[ "$VARIANTE" = sin-integrar ] && integrar="X-AppImage-Integrate=false"
cat > "$T/raiz/prueba-appimage.desktop" <<D
[Desktop Entry]
Type=Application
Name=Prueba de AppImage
Name[es]=Prueba de AppImage en español
Comment=Una AppImage de mentira para las pruebas
Exec=AppRun %F
Icon=prueba-appimage
Categories=Utility;
MimeType=application/x-mint-macos-prueba;
StartupWMClass=prueba-appimage
$integrar
D
convert -size 256x256 xc:'#3478f6' -fill white -draw 'circle 128,128 128,40' \
  "$T/raiz/usr/share/icons/hicolor/256x256/apps/prueba-appimage.png"
ln -s usr/share/icons/hicolor/256x256/apps/prueba-appimage.png "$T/raiz/.DirIcon"
printf '#!/bin/sh\nexit 0\n' > "$T/raiz/AppRun"; chmod +x "$T/raiz/AppRun"
if [ "$VARIANTE" = enlace-fuera ]; then
  rm "$T/raiz/prueba-appimage.desktop"
  ln -s ../../etc/passwd "$T/raiz/prueba-appimage.desktop"
fi

if [ "$VARIANTE" = dwarfs ]; then
  { cat "$T/runtime"; printf 'DWARFS\x02\x05'; head -c 4096 /dev/zero; } > "$SALIDA"
  exit 0
fi
mksquashfs "$T/raiz" "$T/raiz.sqfs" -quiet -no-progress -all-root -comp gzip >/dev/null
cat "$T/runtime" "$T/raiz.sqfs" > "$SALIDA"
chmod 644 "$SALIDA"   # como llega del navegador: sin +x
