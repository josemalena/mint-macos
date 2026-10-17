#!/usr/bin/env bash
# Compila nativo/ del HEAD commiteado (no del árbol de trabajo, que puede estar a medias) y
# deja mac-sesion y mac-sesion-lanzar en RAIZ/.local/bin. Lo usan instalar.sh y paquete.sh.
#   compilar-desde-head.sh RAIZ
set -euo pipefail
RAIZ="${1:?uso: compilar-desde-head.sh RAIZ}"
REPO="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
for c in meson ninja valac; do command -v "$c" >/dev/null || { echo "falta $c" >&2; exit 1; }; done
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
git -C "$REPO" archive HEAD nativo | tar -x -C "$T"
meson setup "$T/nativo/build" "$T/nativo" --buildtype=release --prefix=/usr >/dev/null
ninja -C "$T/nativo/build" >/dev/null
install -d "$RAIZ/.local/bin"
install -m 755 "$T/nativo/build/sesion/mac-sesion" "$T/nativo/mac-sesion-lanzar" "$RAIZ/.local/bin/"
echo "compilado del HEAD $(git -C "$REPO" rev-parse --short HEAD)"
