#!/usr/bin/env bash
# rclone y las nubes en la imagen de mint-macos (lib/destino.sh). En una máquina ya instalada
# no se usa: ahí van ./icloud.sh (iCloud Drive) y ./nube.sh (Google Drive, OneDrive…).
#
#   MINT_MACOS_DESTINO=sistema RCLONE_BINARIO=/ruta/rclone ./instalar.sh
#
# Pone el rclone oficial (v1.75.1 de versiones.sh: el de apt en noble es 1.60.1 y no tiene
# iclouddrive, que existe desde 1.69), ya bajado y verificado por imagen/construir.sh con su
# sha256; el envoltorio en /usr/local/bin/rclone (la clave de rclone.conf sale del llavero de
# cada usuario), y una unidad global por nube, con %h, que solo arranca si el usuario conectó
# ese remoto (~/.config/mint-macos/nubes/REMOTO, que pone «nube.sh activar» o el asistente).
#
# NUNCA van en la imagen el rclone.conf ni sus claves, tampoco en la personal: son de las
# cuentas de cada uno y la clave vive en su llavero, que no viaja. En la máquina nueva el
# usuario conecta sus cuentas (rclone config o el asistente) o copia a mano su rclone.conf cifrado.
set -euo pipefail
AQUI="$(cd "$(dirname "$0")" && pwd)"
source "$AQUI/../lib/destino.sh"
if ! es_sistema; then
  echo "En esta máquina: ./icloud.sh instalar (y alta, montar) y ./nube.sh montar REMOTO CARPETA."; exit 0
fi
[ -x "${RCLONE_BINARIO:-}" ] || { echo "✗ falta RCLONE_BINARIO=… (el rclone oficial que baja imagen/construir.sh)"; exit 1; }

install -D -m 755 "$RCLONE_BINARIO" "$D_LIB/rclone/rclone"
bash "$AQUI/icloud.sh" envoltorio "$D_BIN/rclone"
# iCloud no avisa sus cambios: caché de 1h, como en icloud.sh. Drive y OneDrive sí (168h, nube.sh).
NUBE_DIR_CACHE=1h bash "$AQUI/nube.sh" plantilla icloud "iCloud Drive" rclone-icloud
bash "$AQUI/nube.sh" plantilla GDrive "Google Drive" rclone-gdrive
NUBE_EXCLUIR="/Personal Vault/**" bash "$AQUI/nube.sh" plantilla OneDrive OneDrive rclone-onedrive
# Los guiones, para el asistente del primer arranque y para el usuario.
# Cargan ../lib/destino.sh y ../versiones.sh: van al lado, en /usr/local/lib/mint-macos.
install -d "$D_LIB/icloud" "$D_LIB/lib"
install -m 755 "$AQUI/icloud.sh" "$AQUI/nube.sh" "$AQUI/esperar-icloud.sh" "$AQUI/apps-web.sh" "$D_LIB/icloud/"
install -m 644 "$AQUI/../lib/destino.sh" "$D_LIB/lib/"; install -m 644 "$AQUI/../versiones.sh" "$D_LIB/"
echo "Listo: rclone, su envoltorio y las nubes iCloud Drive, Google Drive y OneDrive (sin cuentas) en ${RAIZ:-la imagen}."
