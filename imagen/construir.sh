#!/usr/bin/env bash
# imagen/construir.sh — la ISO de mint-macos, remasterizando la oficial de Linux Mint 22.3 Cinnamon.
# SIN PROBAR (27-10-2026): José pidió el guion listo; la ISO, xorriso y qemu se bajan cuando él diga.
#
#   sudo ISO=/ruta/linuxmint-22.3-cinnamon-64bit.iso ./imagen/construir.sh [personal|publica]
#
# Entrada (todo lo que decide el resultado, y nada más):
#   ISO + ISO_SHA256        la oficial; se para si el sha256 no coincide
#   el commit del repo      HEAD, que tiene que estar limpio (FORZAR=1 lo salta, y queda anotado)
#   MINT_MACOS_RECURSOS     solo «personal»: la carpeta con lo de Apple ya convertido (tema de Golden
#                           Gate, íconos, cursores, fondos). Vive en Data y NUNCA va al repo.
#   DARLING_PREFIJO         solo «personal»: un Darling instalado con CMAKE_INSTALL_PREFIX=/opt/darling
# Salida, en TRABAJO (Data):
#   mint-macos-<perfil>-<versión de Mint>-<commit>.iso, su .sha256 y medidas.txt (disco y tiempo por paso)
#
# «publica» no lleva nada de Apple ni Darling: lo de Apple llega en el primer arranque (asistente,
# pendiente). El paso del instalador vive aparte (imagen/instalador-ubiquity.sh), para cambiarlo
# cuando Mint 23 deje Ubiquity.
set -euo pipefail

PERFIL="${1:-personal}"
case "$PERFIL" in personal|publica) ;; *) echo "✗ perfil: personal o publica"; exit 2 ;; esac
AQUI="$(cd "$(dirname "$0")" && pwd)"; REPO="$(cd "$AQUI/.." && pwd)"
ISO="${ISO:?falta ISO=…/linuxmint-22.3-cinnamon-64bit.iso}"
# El de los mirrors el 08-01-2026 (lecrabeinfo.net, a confirmar con sha256sum.txt de linuxmint.com).
ISO_SHA256="${ISO_SHA256:-a081ab202cfda17f6924128dbd2de8b63518ac0531bcfe3f1a1b88097c459bd4}"
TRABAJO="${TRABAJO:-/media/jmalena/Data/mint-macos-imagen}"
MINT_MACOS_RECURSOS="${MINT_MACOS_RECURSOS:-/media/jmalena/Data/mint-macos-referencias/imagen-recursos}"
DARLING_PREFIJO="${DARLING_PREFIJO:-/media/jmalena/Data/darling-opt}"
USUARIO="${SUDO_USER:-}"
MED="$TRABAJO/medidas.txt"

paso() { printf '\n▸ %s\n' "$*"; PASO="$*"; T0=$(date +%s); }
fin_paso() { printf '%-28s %6s s  %s en %s\n' "$PASO" $(( $(date +%s) - T0 )) "$(du -sh "$TRABAJO" 2>/dev/null | cut -f1)" "$TRABAJO" >> "$MED"; }
[ "$(id -u)" = 0 ] || { echo "✗ corre con sudo: unsquashfs, chroot y mksquashfs necesitan root"; exit 1; }
[ -n "$USUARIO" ] || { echo "✗ córrelo con sudo desde tu usuario: los builds no se hacen como root"; exit 1; }
for h in unsquashfs mksquashfs xorriso; do command -v $h >/dev/null || { echo "✗ falta $h (squashfs-tools, xorriso)"; exit 1; }; done

# ---- la entrada ------------------------------------------------------------------------
COMMIT="$(sudo -u "$USUARIO" git -C "$REPO" rev-parse --short=12 HEAD)"
if [ -n "$(sudo -u "$USUARIO" git -C "$REPO" status --porcelain)" ]; then
  [ "${FORZAR:-0}" = 1 ] || { echo "✗ el repo tiene cambios sin commit: la imagen no se podría repetir (FORZAR=1 para seguir)"; exit 1; }
  COMMIT="$COMMIT-sucio"
fi
mkdir -p "$TRABAJO"; : > "$MED"
echo "entrada: ISO=$ISO perfil=$PERFIL commit=$COMMIT recursos=$([ $PERFIL = personal ] && echo "$MINT_MACOS_RECURSOS")" >> "$MED"

paso "sha256 de la ISO"
S="$(sha256sum "$ISO" | cut -d' ' -f1)"
[ "$S" = "$ISO_SHA256" ] || { echo "✗ la ISO no es la esperada: $S (se esperaba $ISO_SHA256)"; exit 1; }
fin_paso

if [ "$PERFIL" = personal ]; then
  [ -d "$MINT_MACOS_RECURSOS" ] || { echo "✗ no está MINT_MACOS_RECURSOS=$MINT_MACOS_RECURSOS (lo de Golden Gate, armado en local)"; exit 1; }
  [ -x "$DARLING_PREFIJO/bin/darling" ] || { echo "✗ no está Darling con prefijo /opt/darling en $DARLING_PREFIJO"; exit 1; }
fi

# ---- desempacar -------------------------------------------------------------------------
RAIZ="$TRABAJO/raiz"; ISOD="$TRABAJO/iso"
desmontar() { for m in run dev/pts dev sys proc; do mountpoint -q "$RAIZ/$m" && umount -l "$RAIZ/$m"; done; true; }
trap desmontar EXIT
paso "sacar el squashfs"
rm -rf -- "${ISOD:?}" "${RAIZ:?}"; mkdir -p "$ISOD"
xorriso -osirrox on -indev "$ISO" -extract /casper/filesystem.squashfs "$ISOD/filesystem.squashfs" >/dev/null 2>&1
fin_paso
paso "unsquashfs"
unsquashfs -q -d "$RAIZ" "$ISOD/filesystem.squashfs"
fin_paso

# ---- lo que se compila (como el usuario, en el host) -------------------------------------
paso "builds en el host"
como() { sudo -u "$USUARIO" -H "$@"; }
como bash -c "cd '$REPO/rust' && nice -n 19 cargo build --release --locked --quiet"
NT="$TRABAJO/nativo"; rm -rf -- "${NT:?}"; mkdir -p "$NT"; chown "$USUARIO" "$NT"
como "$REPO/nativo/compilar-desde-head.sh" "$NT"
fin_paso

# ---- lo que entra al chroot ---------------------------------------------------------------
paso "copiar al chroot"
DENTRO="$RAIZ/tmp/mint-macos"; rm -rf -- "${DENTRO:?}"; mkdir -p "$DENTRO"
como git -C "$REPO" archive HEAD | tar -x -C "$DENTRO"
mkdir -p "$DENTRO/rust/target/release"; cp -a "$REPO/rust/target/release/mint-macos-"* "$DENTRO/rust/target/release/" 2>/dev/null || true
cp -a "$NT" "$DENTRO/nativo-compilado"
if [ "$PERFIL" = personal ]; then
  cp -a "$MINT_MACOS_RECURSOS" "$DENTRO/recursos-apple"
  mkdir -p "$RAIZ/opt"; cp -a "$DARLING_PREFIJO" "$RAIZ/opt/darling"
  chown root:root "$RAIZ/opt/darling/bin/darling"; chmod 4755 "$RAIZ/opt/darling/bin/darling"
fi
fin_paso

paso "en el chroot"
mount --bind /proc "$RAIZ/proc"; mount --bind /sys "$RAIZ/sys"; mount --bind /dev "$RAIZ/dev"
mount --bind /dev/pts "$RAIZ/dev/pts"; mount -t tmpfs tmpfs "$RAIZ/run"
cp --remove-destination /etc/resolv.conf "$RAIZ/etc/resolv.conf"
chroot "$RAIZ" env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin HOME=/root LANG=C.UTF-8 PERFIL="$PERFIL" \
  bash /tmp/mint-macos/imagen/en-chroot.sh
chroot "$RAIZ" bash /tmp/mint-macos/imagen/instalador-ubiquity.sh "$PERFIL"
desmontar
rm -rf -- "${DENTRO:?}"; : > "$RAIZ/etc/resolv.conf"
fin_paso

# ---- empacar ----------------------------------------------------------------------------
paso "mksquashfs"
chroot "$RAIZ" dpkg-query -W --showformat='${Package} ${Version}\n' > "$ISOD/filesystem.manifest"
du -sx --block-size=1 "$RAIZ" | cut -f1 > "$ISOD/filesystem.size"
nice -n 10 mksquashfs "$RAIZ" "$ISOD/filesystem.squashfs.nuevo" -comp xz -b 1M -noappend -quiet
fin_paso

paso "rearmar la ISO"
VER="$(. "$RAIZ/etc/linuxmint/info" 2>/dev/null; echo "${RELEASE:-22.3}")"
SALIDA="$TRABAJO/mint-macos-$PERFIL-$VER-$COMMIT.iso"
# «replay»: el arranque BIOS/EFI (y Secure Boot) de la ISO oficial, tal cual.
xorriso -indev "$ISO" -outdev "$SALIDA" \
  -map "$ISOD/filesystem.squashfs.nuevo" /casper/filesystem.squashfs \
  -map "$ISOD/filesystem.manifest" /casper/filesystem.manifest \
  -map "$ISOD/filesystem.size" /casper/filesystem.size \
  -boot_image any replay
( cd "$TRABAJO" && sha256sum "$(basename "$SALIDA")" > "$(basename "$SALIDA").sha256" )
fin_paso
echo "salida: $SALIDA ($(du -h "$SALIDA" | cut -f1))" | tee -a "$MED"
[ "$PERFIL" = personal ] && echo "OJO: la imagen personal lleva contenido de Apple: no se publica ni se sube a ningún lado." | tee -a "$MED"
chown -R "$USUARIO" "$MED" "$SALIDA" "$SALIDA.sha256"
