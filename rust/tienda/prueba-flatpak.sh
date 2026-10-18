#!/usr/bin/env bash
# La FFI de libflatpak contra un repo de juguete: un runtime y una app de 3 MB,
# en carpetas aparte. FLATPAK_USER_DIR y FLATPAK_SYSTEM_DIR apuntan a la prueba,
# así que ni la instalación de usuario ni la de sistema de José se tocan.
#
#   rust/tienda/prueba-flatpak.sh
set -euo pipefail
AQUI="$(cd "$(dirname "$0")" && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export FLATPAK_USER_DIR="$T/inst" FLATPAK_SYSTEM_DIR="$T/sys"
mkdir -p "$T/rt/usr/bin" "$T/rt/files" "$T/app/files/bin" "$T/app/export" "$T/inst" "$T/sys"
printf '[Runtime]\nname=org.mintmacos.Juguete.Platform\nruntime=org.mintmacos.Juguete.Platform/x86_64/1\nsdk=org.mintmacos.Juguete.Platform/x86_64/1\n' > "$T/rt/metadata"
echo hola > "$T/rt/usr/bin/hola"
printf '[Application]\nname=org.mintmacos.Juguete\nruntime=org.mintmacos.Juguete.Platform/x86_64/1\nsdk=org.mintmacos.Juguete.Platform/x86_64/1\ncommand=hola\n' > "$T/app/metadata"
printf '#!/bin/sh\necho juguete\n' > "$T/app/files/bin/hola"; chmod +x "$T/app/files/bin/hola"
echo 1 > "$T/app/files/version"
head -c $((3 << 20)) /dev/urandom > "$T/app/files/relleno"
flatpak build-export --runtime "$T/repo" "$T/rt" 1 >/dev/null
flatpak build-export "$T/repo" "$T/app" stable >/dev/null
flatpak --user remote-add --no-gpg-verify juguete "file://$T/repo"
cd "$AQUI/.."
TIENDA_FLATPAK_PRUEBA="$T" cargo test -q -p mint-macos-tienda transaccion_de_juguete -- --ignored 2>&1 | grep -E 'test result|panicked|assert|FAILED' || true
TIENDA_FLATPAK_PRUEBA="$T" cargo test -q -p mint-macos-tienda transaccion_de_juguete -- --ignored >/dev/null 2>&1 && echo "  ✓ libflatpak: instalar, progreso, tamaño, actualizar, cancelar y quitar" || { echo "  ✗ libflatpak"; exit 1; }
