#!/usr/bin/env bash
# Instala fsapfsinfo y fsapfsmount (libfsapfs, de libyal) para leer discos
# APFS de una Mac desde Linux, por FUSE y en SOLO LECTURA. No viene en los
# repositorios de Mint: se compila desde la versión publicada, comprobando su sha256
# (versiones.sh).
#
#   ./instalar-fsapfs.sh                         en esta máquina (pide sudo)
#   FSAPFS_SOLO_COMPILAR=/carpeta ./instalar-fsapfs.sh
#                                                solo compila, sin root ni apt, y deja el árbol
#                                                instalado en esa carpeta (make install DESTDIR=…):
#                                                así lo hace install-sapos/imagen/construir.sh en el host
#   MINT_MACOS_DESTINO=sistema FSAPFS_COMPILADO=/carpeta ./instalar-fsapfs.sh
#                                                la imagen (lib/destino.sh): copia ese árbol, el
#                                                ayudante de mount, fuse.conf, el vigilante y el
#                                                grupo disk para los usuarios nuevos; nada se compila
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
# La versión sale del manifiesto; LIBFSAPFS_VERSION=… la cambia para una prueba (sin sha256).
PEDIDA="${LIBFSAPFS_VERSION:-}"
source "$(dirname "$REPO")/versiones.sh"
source "$(dirname "$REPO")/lib/destino.sh"
VERSION="${PEDIDA:-$LIBFSAPFS_VERSION}"
SHA=""; { [ -z "$PEDIDA" ] || [ "$PEDIDA" = "$LIBFSAPFS_VERSION" ]; } && SHA="$LIBFSAPFS_SHA256"

compilar() { # destdir (vacío: make install de verdad, con sudo)
  local TMP; TMP="$(mktemp -d)"
  echo "▸ libfsapfs $VERSION"
  curl -fsSL -o "$TMP/libfsapfs.tar.gz" \
    "https://github.com/libyal/libfsapfs/releases/download/$VERSION/libfsapfs-experimental-$VERSION.tar.gz"
  if [ -n "$SHA" ]; then
    echo "$SHA  $TMP/libfsapfs.tar.gz" | sha256sum -c --quiet || { echo "  ✗ el sha256 de libfsapfs no es el del manifiesto"; exit 1; }
  else echo "  (versión de prueba $VERSION: sin sha256 en el manifiesto)"; fi
  tar xzf "$TMP/libfsapfs.tar.gz" -C "$TMP"
  cd "$TMP/libfsapfs-$VERSION"
  ./configure --prefix=/usr/local --enable-python=no
  make -j"$(nproc)"
  # Sin libfuse3-dev, configure sigue adelante pero no construye fsapfsmount.
  test -x fsapfstools/fsapfsmount || { echo "  ✗ no se construyó fsapfsmount: falta FUSE 3"; exit 1; }
  if [ -n "$1" ]; then make install DESTDIR="$1"; else sudo make install; sudo ldconfig; fi
  cd /; rm -rf -- "$TMP"
}

if [ -n "${FSAPFS_SOLO_COMPILAR:-}" ]; then
  mkdir -p "$FSAPFS_SOLO_COMPILAR"; compilar "$(cd "$FSAPFS_SOLO_COMPILAR" && pwd)"
  echo "Compilado en $FSAPFS_SOLO_COMPILAR (usr/local/…)."; exit 0
fi

if es_sistema; then
  [ -d "${FSAPFS_COMPILADO:-}/usr/local" ] || { echo "✗ falta FSAPFS_COMPILADO=… (el árbol de FSAPFS_SOLO_COMPILAR)"; exit 1; }
  echo "▸ libfsapfs $VERSION (compilado en el host)"
  mkdir -p "$RAIZ/usr/local"; cp -a "$FSAPFS_COMPILADO/usr/local/." "$RAIZ/usr/local/"
  # FUSE 3 viene en Mint; si faltara, dentro del chroot se pone (desde fuera no hay apt).
  if [ -z "$RAIZ" ]; then
    ldconfig -p | grep -q 'libfuse3.so.3' || apt-get install -y fuse3
    ldconfig
  fi
else
  echo "▸ Requisitos de compilación y FUSE 3"
  sudo apt install -y build-essential autoconf automake autopoint libtool \
    pkg-config libssl-dev libfuse3-dev fuse3 curl
  compilar ""
fi

echo "▸ Helper de mount(8): fstype=fsapfs en el fstab"
$COMO_ROOT install -D -m 755 "$REPO/mount.fsapfs" "$RAIZ/sbin/mount.fsapfs"

# Al montar desde Nemo el montaje corre como el usuario, no como root, y el
# helper pide allow_other: sin esto falla con «option allow_other only
# allowed if 'user_allow_other' is set in /etc/fuse.conf».
echo "▸ /etc/fuse.conf: user_allow_other"
FUSE_CONF="$RAIZ/etc/fuse.conf"
[ -f "$FUSE_CONF" ] || { $COMO_ROOT mkdir -p "$RAIZ/etc"; $COMO_ROOT touch "$FUSE_CONF"; }
$COMO_ROOT sed -i 's/^#\s*user_allow_other/user_allow_other/' "$FUSE_CONF"
grep -q '^user_allow_other' "$FUSE_CONF" || echo user_allow_other | $COMO_ROOT tee -a "$FUSE_CONF" >/dev/null

if es_sistema; then
  # Las piezas para el asistente del primer arranque (leer el disco de la Mac del usuario):
  # los guiones de apfs/, sin los discos de nadie (montajes-usuario.sh los crea por UUID
  # en la máquina; discos-root.sh y el fstab de José no van).
  install -d "$D_LIB/apfs"
  install -m 755 "$REPO/montajes-usuario.sh" "$REPO/recuperar.sh" "$REPO/vigilar.sh" "$D_LIB/apfs/"
  install -m 644 "$REPO/fstab.ejemplo" "$REPO/README.md" "$D_LIB/apfs/"
  MINT_MACOS_RAIZ="$RAIZ" bash "$REPO/vigilar.sh" --instalar
  # Leer /dev/sdXN sin sudo: los usuarios que se creen entran al grupo disk. Hipótesis: Ubiquity
  # (user-setup) y adduser leen EXTRA_GROUPS de /etc/adduser.conf; falta comprobarlo al instalar.
  AC="$RAIZ/etc/adduser.conf"
  if [ -f "$AC" ]; then
    grep -q '^ADD_EXTRA_GROUPS=1' "$AC" || echo 'ADD_EXTRA_GROUPS=1' >> "$AC"
    if grep -q '^EXTRA_GROUPS=' "$AC"; then grep -qE '^EXTRA_GROUPS=.*\bdisk\b' "$AC" || sed -i 's/^EXTRA_GROUPS="\(.*\)"/EXTRA_GROUPS="\1 disk"/' "$AC"
    else echo 'EXTRA_GROUPS="disk"' >> "$AC"; fi
  fi
  echo "Listo: libfsapfs, mount.fsapfs, fuse.conf, fsapfs-vigilar y el grupo disk en ${RAIZ:-la imagen}."
  exit 0
fi

# Leer /dev/sdXN sin sudo (montar a mano en una carpeta propia). Con sudo
# (o en un contenedor como root) $USER puede no estar: va SUDO_USER o id -un.
USUARIO="${SUDO_USER:-${USER:-$(id -un)}}"
if ! id -nG "$USUARIO" | grep -qw disk; then
  sudo usermod -aG disk "$USUARIO"
  echo "  $USUARIO entra al grupo disk: vale desde la próxima sesión"
fi

fsapfsmount -V | head -1
echo "Listo. Mira los volúmenes con: fsapfsinfo /dev/sdXN"
