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
  pkg-config libfuse3-dev fuse3 curl

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

fsapfsmount -V | head -1
echo "Listo. Mira los volúmenes con: fsapfsinfo /dev/sdXN"
