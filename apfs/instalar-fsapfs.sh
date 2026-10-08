#!/usr/bin/env bash
# Instala fsapfsinfo y fsapfsmount (libfsapfs, de libyal) para leer discos
# APFS de una Mac desde Linux, por FUSE y en SOLO LECTURA. No viene en los
# repositorios de Mint: se compila desde la versión publicada.
set -euo pipefail

VERSION="${LIBFSAPFS_VERSION:-20260921}"
REPO="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)"

echo "▸ Requisitos de compilación y FUSE 3"
sudo apt install -y build-essential autoconf automake autopoint libtool \
  pkg-config libssl-dev libfuse3-dev fuse3 curl

echo "▸ libfsapfs $VERSION"
curl -fsSL -o "$TMP/libfsapfs.tar.gz" \
  "https://github.com/libyal/libfsapfs/releases/download/$VERSION/libfsapfs-experimental-$VERSION.tar.gz"
tar xzf "$TMP/libfsapfs.tar.gz" -C "$TMP"
cd "$TMP/libfsapfs-$VERSION"
./configure --prefix=/usr/local --enable-python=no
make -j"$(nproc)"
# Sin libfuse3-dev, configure sigue adelante pero no construye fsapfsmount.
test -x fsapfstools/fsapfsmount || { echo "  ✗ no se construyó fsapfsmount: falta FUSE 3"; exit 1; }
sudo make install
sudo ldconfig

echo "▸ Helper de mount(8): fstype=fsapfs en el fstab"
sudo install -m 755 "$REPO/mount.fsapfs" /sbin/mount.fsapfs

# Al montar desde Nemo el montaje corre como el usuario, no como root, y el
# helper pide allow_other: sin esto falla con «option allow_other only
# allowed if 'user_allow_other' is set in /etc/fuse.conf».
echo "▸ /etc/fuse.conf: user_allow_other"
sudo sed -i 's/^#\s*user_allow_other/user_allow_other/' /etc/fuse.conf
grep -q '^user_allow_other' /etc/fuse.conf || echo user_allow_other | sudo tee -a /etc/fuse.conf >/dev/null

# Leer /dev/sdXN sin sudo (montar a mano en una carpeta propia).
if ! id -nG "$USER" | grep -qw disk; then
  sudo usermod -aG disk "$USER"
  echo "  $USER entra al grupo disk: vale desde la próxima sesión"
fi

fsapfsmount -V | head -1
echo "Listo. Mira los volúmenes con: fsapfsinfo /dev/sdXN"
