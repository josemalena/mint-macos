#!/usr/bin/env bash
# Compila e instala en ~/.local, sin sudo, los dos programas propios:
#   - Fynder: el administrador de archivos con la cara del Finder (fork de Nemo)
#   - plank-reloaded: el Dock de Catalina (fork de zquestz/plank-reloaded)
# Cada uno se clona de su repo público en un hash fijo: lo que se instala es
# exactamente lo que se probó. Necesita los paquetes de requisitos.sh.
#
#   ./construir.sh               los dos
#   ./construir.sh fynder        solo uno (fynder | plank)
#
# Las fuentes quedan en ~/.cache/mint-macos/src y los builds en
# ~/.cache/mint-macos/build (fuera de /tmp: un reinicio no los borra).
set -euo pipefail

FYNDER_REPO=https://github.com/josemalena/fynder.git
FYNDER_HASH=6df603c9598d92bef95cc13bc781a65abe53a043
PLANK_REPO=https://github.com/josemalena/plank-reloaded.git
PLANK_HASH=461786b42a3f4236f38c1f8fb237fa54a6a69076

CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/mint-macos"
PREFIJO="$HOME/.local"
ARCH="$(dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null || echo x86_64-linux-gnu)"
QUE="${1:-todo}"

paso() { printf '\n▸ %s\n' "$*"; }
# corre un paso con su salida a un log; si falla, enseña el final del log.
callado() {
  local log="$CACHE/ultimo.log"
  "$@" > "$log" 2>&1 || { echo "  ✗ falló: $*"; tail -25 "$log" | sed 's/^/    /'; exit 1; }
}

# clonar <repo> <hash> <carpeta>: deja la carpeta en ese hash exacto.
clonar() {
  local repo="$1" hash="$2" dir="$3"
  if [ ! -d "$dir/.git" ]; then
    git clone -q --filter=blob:none "$repo" "$dir"
  fi
  git -C "$dir" fetch -q origin "$hash" 2>/dev/null || git -C "$dir" fetch -q origin
  git -C "$dir" checkout -q --detach "$hash"
  [ "$(git -C "$dir" rev-parse HEAD)" = "$hash" ] || { echo "  ✗ no quedó en $hash"; exit 1; }
  echo "  $(basename "$dir") en $(git -C "$dir" log -1 --format='%h %s')"
}

mkdir -p "$CACHE/src" "$CACHE/build"
# En un usuario nuevo estas carpetas no existen, y el install de Fynder corre
# gtk-update-icon-cache sobre hicolor: sin la carpeta, falla.
mkdir -p "$PREFIJO/bin" "$PREFIJO/share/icons/hicolor" "$PREFIJO/share/applications" "$PREFIJO/share/glib-2.0/schemas" "$PREFIJO/share/mime/packages"

if [ "$QUE" = todo ] || [ "$QUE" = fynder ]; then
  paso "Fynder ($FYNDER_HASH)"
  clonar "$FYNDER_REPO" "$FYNDER_HASH" "$CACHE/src/fynder"
  B="$CACHE/build/fynder"
  # El prefijo va compilado dentro del binario (datos, extensiones): tiene que
  # ser ~/.local, el mismo donde se instala.
  [ -f "$B/build.ninja" ] || callado meson setup "$B" "$CACHE/src/fynder" --prefix="$PREFIJO"
  callado meson configure "$B" -Dprefix="$PREFIJO"
  callado ninja -C "$B"
  # El install corre glib-compile-schemas; con claves nuevas en el esquema,
  # sin recompilarlo GSettings aborta al arrancar.
  callado ninja -C "$B" install
  glib-compile-schemas "$PREFIJO/share/glib-2.0/schemas"
  echo "  instalado: $PREFIJO/bin/fynder"
fi

if [ "$QUE" = todo ] || [ "$QUE" = plank ]; then
  paso "plank-reloaded ($PLANK_HASH)"
  clonar "$PLANK_REPO" "$PLANK_HASH" "$CACHE/src/plank-reloaded"
  B="$CACHE/build/plank-reloaded"
  # Sin el rpath el binario carga la libplank del sistema y no la del fork.
  [ -f "$B/build.ninja" ] || LDFLAGS="-Wl,-rpath,$PREFIJO/lib/$ARCH" \
    callado meson setup "$B" "$CACHE/src/plank-reloaded" --prefix="$PREFIJO" -Denable-apport=false
  callado ninja -C "$B"
  callado ninja -C "$B" install
  glib-compile-schemas "$PREFIJO/share/glib-2.0/schemas" 2>/dev/null || true
  echo "  instalado: $PREFIJO/bin/plank"
fi

paso "Listo"
echo "  ~/.local/bin tiene que ir antes que /usr/bin en el PATH (lo pone ~/.profile de Mint)."
