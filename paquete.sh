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
#   cursores-base.tar.gz  McMojave-cursors, la base de los cursores de Constanza
#   spotlyte.tar.gz     Spotlyte (el Spotlight), y spotlyte-config.tar.gz su configuración
#   fynder-ajustes.dconf  los ajustes de Fynder del usuario (etiquetas, menú global…)
#   nativo-binarios.tar.gz  mac-sesion y su lanzador (nativo/, Vala), a ~/.local/bin
#   rust-binarios.tar.gz  los ayudantes de root en Rust (rust/target/release)
#   greeter.tar.gz      el fork de la pantalla de inicio, en el hash de login/instalar.sh
#   instalar-aqui.sh    el que se corre en la otra computadora
#   asistente-root.sh   la parte de root del asistente gráfico (pkexec, una clave)
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

# La pantalla de inicio se compila en la otra computadora, del fork en el hash
# que fija login/instalar.sh. Va en el paquete porque ese hash puede no estar
# en GitHub todavía (en la iMac, 15-10-2026, «not our ref»), y así no hace
# falta internet para eso.
paso "La pantalla de inicio (mint-macos-greeter)"
GH="$(sed -n 's/^GREETER_HASH=//p' "$REPO/login/instalar.sh")"
GF=""
for g in "${GREETER_FUENTE:-}" "$(dirname "$REPO")/slick-greeter" "$HOME/.cache/mint-macos/src/mint-macos-greeter"; do
  [ -n "$g" ] && git -C "$g" cat-file -e "$GH^{commit}" 2>/dev/null && { GF="$g"; break; }
done
[ -n "$GF" ] || { echo "  ✗ ningún repo local tiene $GH (GREETER_FUENTE=<repo del fork>)"; exit 1; }
GT="$(mktemp -d)"
git clone -q "$GF" "$GT/mint-macos-greeter"
git -C "$GT/mint-macos-greeter" checkout -q --detach "$GH"
tar -czf "$DEST/greeter.tar.gz" -C "$GT" mint-macos-greeter
rm -rf "$GT"
echo "  ${GH:0:7} de $GF, $(du -h "$DEST/greeter.tar.gz" | cut -f1)"

# El tema base de los cursores (McMojave-cursors, de vinceliuice, GPL): de
# él salen la flecha, la I de texto y la espera, que Catalina no trae como
# archivo. No viene en Mint; tema/iconos/cursores.py lo busca también en ~/.local.
paso "Cursores base (McMojave-cursors)"
if [ -d /usr/share/icons/McMojave-cursors/cursors ]; then
  tar -czf "$DEST/cursores-base.tar.gz" -C /usr/share/icons McMojave-cursors
  echo "  $(du -h "$DEST/cursores-base.tar.gz" | cut -f1)"
else
  echo "  ✗ no está /usr/share/icons/McMojave-cursors: sin él faltan la flecha y la espera"; exit 1
fi

# Spotlyte, el Spotlight (fork de Ulauncher en ../spotlyte): el código tal
# como está commiteado y su configuración (atajo ⌘Espacio y el tema).
paso "Spotlyte"
SPOT="${SPOTLYTE_REPO:-$(dirname "$REPO")/spotlyte}"
[ -d "$SPOT/.git" ] || { echo "  ✗ no está el repo de Spotlyte en $SPOT (SPOTLYTE_REPO)"; exit 1; }
git -C "$SPOT" archive --prefix=app/ HEAD | gzip > "$DEST/spotlyte.tar.gz"
UL_CONF=()
for f in .config/ulauncher/settings.json .config/ulauncher/user-themes; do [ -e "$HOME/$f" ] && UL_CONF+=("$f"); done
[ ${#UL_CONF[@]} -gt 0 ] && tar -czf "$DEST/spotlyte-config.tar.gz" -C "$HOME" "${UL_CONF[@]}"
echo "  $(git -C "$SPOT" rev-parse --short HEAD), $(du -h "$DEST/spotlyte.tar.gz" | cut -f1)"

# Los ajustes de Fynder de este usuario (las etiquetas, la barra de ruta, dónde
# abre una ventana nueva, la letra del escritorio, el menú global), sin
# tamaños de ventana ni pestañas guardadas.
paso "Ajustes de Fynder"
dconf dump /io/github/josemalena/fynder/ | python3 -c '
import sys
quiero = {"preferences": {"finder-new-window-location", "finder-show-path-bar", "toolbar-finder-layout",
                          "show-hidden-files", "finder-tags", "global-menu"},
          "desktop": {"font", "finder-desktop-optical-disks"}}
grupo = None
for l in sys.stdin:
    l = l.rstrip("\n")
    if l.startswith("["):
        grupo = l.strip("[]"); print(l) if grupo in quiero else None; continue
    if grupo in quiero and l.split("=", 1)[0] in quiero[grupo]:
        print(l)
' > "$DEST/fynder-ajustes.dconf"
echo "  $(grep -c = "$DEST/fynder-ajustes.dconf") ajustes"

# BINARIOS_DESDE: un «home» de montaje (meson install --destdir) con Fynder y el
# Dock compilados del HEAD commiteado, para no llevar lo que haya instalado aquí
# a medias (16-10-2026). Por defecto, lo instalado en este ~/.local.
ORIGEN_BIN="${BINARIOS_DESDE:-$HOME}"
# Los binarios de Rust (rust/: los ayudantes de root), compilados del HEAD
# commiteado en una carpeta aparte; van a ~/mint-macos/rust/target/release, donde
# los buscan los instalar-root.sh. En la otra computadora no hace falta Rust.
paso "Binarios de Rust"
if command -v cargo >/dev/null && [ -f "$REPO/rust/Cargo.toml" ]; then
  RT="$(mktemp -d)"
  git -C "$REPO" archive HEAD rust | tar -x -C "$RT"
  ( cd "$RT/rust" && CARGO_TARGET_DIR="$RT/rust/target" cargo build --release --locked --quiet )
  ( cd "$RT" && tar -czf "$DEST/rust-binarios.tar.gz" $(cd "$RT" && find rust/target/release -maxdepth 1 -type f -name 'mint-macos-*' -perm -u+x) )
  echo "  $(tar -tzf "$DEST/rust-binarios.tar.gz" | xargs -n1 basename | tr '\n' ' ')"
  rm -rf "$RT"
else
  echo "  sin cargo o sin rust/: el paquete va sin binarios de Rust (los instalar-root usan el Python)"
fi

# Los diálogos de sesión en Vala (nativo/), compilados del HEAD; van a ~/.local/bin.
paso "mac-sesion (Vala)"
if command -v valac >/dev/null && command -v meson >/dev/null && [ -f "$REPO/nativo/meson.build" ]; then
  NT="$(mktemp -d)"
  "$REPO/nativo/compilar-desde-head.sh" "$NT"
  tar -czf "$DEST/nativo-binarios.tar.gz" -C "$NT" .local/bin
  rm -rf "$NT"
else
  echo "  sin valac o meson: el paquete va sin mac-sesion (los diálogos usan applemenu.py)"
fi

paso "Fynder y el Dock instalados${BINARIOS_DESDE:+ (de $BINARIOS_DESDE)}"
LISTA="$(mktemp)"
for b in "$BUILD_FYNDER" "$BUILD_DOCK"; do
  [ -f "$b/build.ninja" ] || { echo "  ✗ no hay build de meson en $b (BUILD_FYNDER / BUILD_DOCK)"; exit 1; }
  meson introspect --installed "$b" | python3 -c '
import json, os, sys
home = os.path.expanduser("~") + "/"
origen = sys.argv[1].rstrip("/") + "/"
for destino in json.load(sys.stdin).values():
    if not destino.startswith(home + ".local/"):
        sys.exit(f"  ✗ {destino} no está en ~/.local")
    if os.path.lexists(origen + destino[len(home):]):
        print(destino[len(home):])
' "$ORIGEN_BIN" >> "$LISTA"
done
tar -czf "$DEST/binarios.tar.gz" -C "$ORIGEN_BIN" -T "$LISTA"
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
         "System/Library/Fonts" "Library/Fonts" "System/Library/Sounds" \
         "System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds"; do
  [ -d "$d" ] || continue
  rsync -a --prune-empty-dirs -R \
    --include='en.lproj/' --include='English.lproj/' --include='Base.lproj/' --exclude='*.lproj/' \
    --exclude='MacOS/' --exclude='_CodeSignature/' --include='*/' \
    --include='*.icns' --include='*.car' --include='*.pdf' --include='*.png' --include='*.tif' \
    --include='*.tiff' --include='*.plist' --include='*.strings' --include='*.json' \
    --include='*.ttf' --include='*.otf' --include='*.ttc' --include='*.aiff' --include='*.caf' \
    --include='*.xml' --exclude='*' \
    "$d" "$STAGE/"
done
# Todos los fondos de Desktop & Screen Saver (los .heic, Solid Colors y el
# orden), no solo Catalina.heic: settings/fondos.py los lee (15-10-2026).
[ -d "System/Library/Desktop Pictures" ] && rsync -a -R "System/Library/Desktop Pictures" "$STAGE/"
cd "$REPO"
desmontar_mac
tar -cf "$DEST/mac-sistema.tar" -C "$STAGE" .
rm -rf "$STAGE"
echo "  $(du -h "$DEST/mac-sistema.tar" | cut -f1)"
# La memoria TRANSPORTE es FAT32 (nada de más de 4 GB): con todos los Desktop
# Pictures el tar pasa de 4.4 GB (16-10-2026). Se parte en trozos de 3.9 GB que
# instalar-aqui.sh vuelve a juntar.
if [ "$(stat -c %s "$DEST/mac-sistema.tar")" -gt 3900000000 ]; then
  rm -f "$DEST"/mac-sistema.tar.parte-*
  split -b 3900m -d "$DEST/mac-sistema.tar" "$DEST/mac-sistema.tar.parte-"
  rm -f "$DEST/mac-sistema.tar"
  echo "  partido para FAT32: $(ls "$DEST"/mac-sistema.tar.parte-* | xargs -n1 basename | tr '\n' ' ')"
fi

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

cp "$REPO/paquete/instalar-aqui.sh" "$REPO/paquete/asistente-root.sh" "$DEST/"
chmod +x "$DEST/instalar-aqui.sh" "$DEST/asistente-root.sh"
cat > "$DEST/origen.txt" <<EOF
usuario=$USER
home=$HOME
mint=$(. /etc/os-release && echo "$VERSION_ID")
repo=$(git -C "$REPO" rev-parse HEAD)
fecha=$(date -Iseconds)
EOF

paso "Listo: $DEST ($(du -sh "$DEST" | cut -f1))"
echo "  En la otra computadora, entrando como $USER:  ./instalar-aqui.sh"
