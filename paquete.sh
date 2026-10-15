#!/usr/bin/env bash
# Arma un paquete para instalar mint-macos en OTRA computadora con Linux Mint
# que no tiene el disco de la Mac ni red con esta: se lleva en un USB o por
# otra Mac. Corre en la computadora que ya tiene mint-macos funcionando.
#
#   ./paquete.sh [carpeta]     por defecto ~/.local/share/mint-macos/paquetes/<fecha>
#
# Qué lleva:
#   mint-macos.tar.gz   el repo tal como está commiteado (git archive HEAD)
#   binarios.tar.gz     Fynder y el Dock tal como están instalados aquí en
#                       ~/.local (los archivos que dicen sus builds de meson)
#   mac-sistema.tar     lo que el tema lee del disco de la Mac: íconos,
#                       Assets.car, PDFs, plists, fuentes, cursores y el fondo
#                       de Catalina. Sin binarios ni idiomas que no son inglés.
#   apple-extra.tar.gz  lo de Apple que se sacó en la Mac misma (glifos-finder)
#                       y lo de la pantalla de inicio (constanza/login)
#   instalar-aqui.sh    el que se corre en la otra computadora
#
# Lo de Apple es para las máquinas de quien tiene la Mac: el paquete no se
# publica ni va a ningún repo.
#
# Los binarios llevan compilada la ruta ~/.local de ESTE usuario: en la otra
# computadora hay que entrar con el mismo nombre de usuario y la misma versión
# de Mint. instalar-aqui.sh lo revisa.
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
DEST="${1:-$HOME/.local/share/mint-macos/paquetes/$(date +%Y%m%d)}"
# Los builds de meson de donde salen los binarios instalados.
BUILD_FYNDER="${BUILD_FYNDER:-$HOME/.cache/mint-macos/build/fynder}"
BUILD_DOCK="${BUILD_DOCK:-$HOME/.cache/mint-macos/build/plank-reloaded}"
[ -f "$BUILD_DOCK/build.ninja" ] || BUILD_DOCK="$(dirname "$REPO")/plank-reloaded/build"

paso() { printf '\n▸ %s\n' "$*"; }
mkdir -p "$DEST"

paso "mint-macos (HEAD $(git -C "$REPO" rev-parse --short HEAD))"
[ -z "$(git -C "$REPO" status --porcelain --untracked-files=no)" ] \
  || echo "  ojo: hay cambios sin commitear en el repo; el paquete lleva solo lo commiteado"
git -C "$REPO" archive --prefix=mint-macos/ HEAD | gzip > "$DEST/mint-macos.tar.gz"
echo "  $(du -h "$DEST/mint-macos.tar.gz" | cut -f1)"

paso "Fynder y el Dock instalados"
LISTA="$(mktemp)"
for b in "$BUILD_FYNDER" "$BUILD_DOCK"; do
  [ -f "$b/build.ninja" ] || { echo "  ✗ no hay build de meson en $b (BUILD_FYNDER / BUILD_DOCK)"; exit 1; }
  meson introspect --installed "$b" | python3 -c '
import json, os, sys
home = os.path.expanduser("~") + "/"
for destino in json.load(sys.stdin).values():
    if not destino.startswith(home + ".local/"):
        sys.exit(f"  ✗ {destino} no está en ~/.local")
    if os.path.lexists(destino):
        print(destino[len(home):])
' >> "$LISTA"
done
tar -czf "$DEST/binarios.tar.gz" -C "$HOME" -T "$LISTA"
echo "  $(wc -l < "$LISTA") archivos, $(du -h "$DEST/binarios.tar.gz" | cut -f1)"
rm -f "$LISTA"

paso "Lo de Apple, del disco de la Mac (solo lectura)"
source "$REPO/tema/comun.sh"
trap desmontar_mac EXIT
montar_mac_sistema || { echo "  ✗ no encuentro el disco de la Mac"; exit 1; }
STAGE="$(mktemp -d)"
cd "$MAC_SISTEMA"
for d in "System/Applications" "System/Library/CoreServices" "System/Library/PreferencePanes" \
         "System/Library/Extensions" "System/Library/Frameworks" "System/Library/PrivateFrameworks" \
         "System/Library/Fonts" "Library/Fonts"; do
  [ -d "$d" ] || continue
  rsync -a --prune-empty-dirs -R \
    --include='en.lproj/' --include='English.lproj/' --include='Base.lproj/' --exclude='*.lproj/' \
    --exclude='MacOS/' --exclude='_CodeSignature/' --include='*/' \
    --include='*.icns' --include='*.car' --include='*.pdf' --include='*.png' --include='*.tif' \
    --include='*.tiff' --include='*.plist' --include='*.strings' --include='*.json' \
    --include='*.ttf' --include='*.otf' --include='*.ttc' --exclude='*' \
    "$d" "$STAGE/"
done
mkdir -p "$STAGE/System/Library/Desktop Pictures"
cp -a "System/Library/Desktop Pictures/Catalina.heic" "$STAGE/System/Library/Desktop Pictures/" 2>/dev/null || true
cd "$REPO"
desmontar_mac
tar -cf "$DEST/mac-sistema.tar" -C "$STAGE" .
rm -rf "$STAGE"
echo "  $(du -h "$DEST/mac-sistema.tar" | cut -f1)"

paso "Lo de Apple sacado en la Mac misma"
EXTRA=()
[ -d "$HOME/.local/share/constanza/glifos-finder" ] && EXTRA+=(.local/share/constanza/glifos-finder)
# La pantalla de inicio: fondos, foto de la cuenta y botones (login/desde-mac.sh
# los saca del volumen de DATOS, que el paquete no lleva).
[ -d "$HOME/.local/share/constanza/login" ] && EXTRA+=(.local/share/constanza/login)
if [ ${#EXTRA[@]} -gt 0 ]; then
  tar -czf "$DEST/apple-extra.tar.gz" -C "$HOME" "${EXTRA[@]}"; echo "  ${EXTRA[*]}"
else
  echo "  nada (no hay glifos-finder)"
fi

cp "$REPO/paquete/instalar-aqui.sh" "$DEST/"
chmod +x "$DEST/instalar-aqui.sh"
cat > "$DEST/origen.txt" <<EOF
usuario=$USER
home=$HOME
mint=$(. /etc/os-release && echo "$VERSION_ID")
repo=$(git -C "$REPO" rev-parse HEAD)
fecha=$(date -Iseconds)
EOF

paso "Listo: $DEST ($(du -sh "$DEST" | cut -f1))"
echo "  En la otra computadora, entrando como $USER:  ./instalar-aqui.sh"
