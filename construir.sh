#!/usr/bin/env bash
# Compila e instala en ~/.local, sin sudo, los dos programas propios:
#   - Fynder: el administrador de archivos con la cara del Finder (fork de Nemo)
#   - mint-macos-dock: el Dock de Catalina (fork de zquestz/plank-reloaded), que desde el
#     19-10-2026 se instala como «muelle» (Muelle, el nombre que le dio José). El plank de antes
#     queda como «plank-viejo», con su libplank y sus docklets, para volver atrás.
# Cada uno se clona de su repo público en el hash fijado en versiones.sh: lo
# que se instala es exactamente lo que se probó. Necesita los paquetes de requisitos.sh.
#
#   ./construir.sh               los dos
#   ./construir.sh fynder        solo uno (fynder | plank)
#
# Las fuentes quedan en ~/.cache/mint-macos/src y los builds en
# ~/.cache/mint-macos/build (fuera de /tmp: un reinicio no los borra).
set -euo pipefail

# FYNDER_REPO/_HASH y PLANK_REPO/_HASH: el manifiesto.
source "$(cd "$(dirname "$0")" && pwd)/versiones.sh"

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

# El plank de antes, para volver atrás una semana (Dev-Dock, 19-10-2026): el hash anterior del fork
# (PLANK_VIEJO_HASH) compilado en su propio prefijo, ~/.local/lib/mint-macos/plank-viejo, con su
# libplank, sus docklets y su rpath. No puede compartir nada con Muelle: la libplank nueva cambia el
# tamaño de las clases y Plank carga siempre los docklets de su carpeta compilada.
guardar_plank_viejo() {
  local d="$PREFIJO/lib/mint-macos/plank-viejo"
  [ -n "${PLANK_VIEJO_HASH:-}" ] && [ ! -x "$d/bin/plank" ] || return 0
  paso "El Dock de antes como plank-viejo ($PLANK_VIEJO_HASH)"
  clonar "$PLANK_REPO" "$PLANK_VIEJO_HASH" "$CACHE/src/plank-viejo"
  local bv="$CACHE/build/plank-viejo"
  [ -f "$bv/build.ninja" ] || LDFLAGS="-Wl,-rpath,$d/lib/$ARCH" \
    callado meson setup "$bv" "$CACHE/src/plank-viejo" --prefix="$d" -Denable-apport=false
  callado ninja -C "$bv"
  callado ninja -C "$bv" install
  cat > "$PREFIJO/bin/plank-viejo" <<'EOF'
#!/bin/sh
# El Dock de antes de Muelle, en su propio prefijo (construir.sh, 19-10-2026). Se quita con
# rm -rf ~/.local/lib/mint-macos/plank-viejo ~/.local/bin/plank-viejo.
exec "$HOME/.local/lib/mint-macos/plank-viejo/bin/plank" "$@"
EOF
  chmod 755 "$PREFIJO/bin/plank-viejo"
  echo "  el plank de antes: $PREFIJO/bin/plank-viejo"
}

if [ "$QUE" = todo ] || [ "$QUE" = plank ]; then
  paso "mint-macos-dock ($PLANK_HASH)"
  clonar "$PLANK_REPO" "$PLANK_HASH" "$CACHE/src/plank-reloaded"
  B="$CACHE/build/plank-reloaded"
  guardar_plank_viejo
  # Sin el rpath el binario carga la libplank del sistema y no la del fork.
  [ -f "$B/build.ninja" ] || LDFLAGS="-Wl,-rpath,$PREFIJO/lib/$ARCH" \
    callado meson setup "$B" "$CACHE/src/plank-reloaded" --prefix="$PREFIJO" -Denable-apport=false
  callado ninja -C "$B"
  callado ninja -C "$B" install
  glib-compile-schemas "$PREFIJO/share/glib-2.0/schemas" 2>/dev/null || true
  # «plank» sigue funcionando en la transición: apunta a muelle.
  if [ -x "$PREFIJO/bin/muelle" ]; then
    ln -sfn muelle "$PREFIJO/bin/plank"
    echo "  instalado: $PREFIJO/bin/muelle (plank → muelle)"
  else
    echo "  instalado: $PREFIJO/bin/plank"
  fi
fi

paso "Listo"
echo "  ~/.local/bin tiene que ir antes que /usr/bin en el PATH (lo pone ~/.profile de Mint)."
