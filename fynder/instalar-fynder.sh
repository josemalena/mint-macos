#!/bin/sh
# Instala Fynder desde el HEAD del repo (nunca del árbol sucio) en ~/.local/bin,
# con respaldo de los binarios y del esquema actuales y su volver.sh. No reinicia nada.
set -eu

# El repo de Fynder: FYNDER_REPO, o el de al lado de mint-macos (repos/fynder).
REPO=${FYNDER_REPO:-$(cd "$(dirname "$0")/../../fynder" && pwd)}
FECHA=$(date +%Y%m%d-%H%M)
RESPALDO="$HOME/.mint-macos-respaldo/$FECHA-fynder-antes"
ESQ="$HOME/.local/share/glib-2.0/schemas"
XML=io.github.josemalena.fynder.gschema.xml
# el módulo de GTK del selector Open/Save (fynder/gtk-module, portal/instalar-selector.sh)
MOD="$HOME/.local/lib/fynder/libfynder-chooser-module.so"
# el .desktop lleva las acciones del menú del Finder en el Dock (X-Muelle-Actions)
APPS="$HOME/.local/share/applications"
TMP=$(mktemp -d)
trap 'rm -rf "${TMP:?}"' EXIT

HASH=$(git -C "$REPO" rev-parse --short HEAD)
# la versión del About sale de los commits desde el fork (src/gen-build-number.sh);
# el archivo de git no trae .git, así que se calcula aquí
FYNDER_VERSION="1.0.$(git -C "$REPO" rev-list --count 66eabf45..HEAD)"
export FYNDER_VERSION
echo "Compilando Fynder $HASH desde HEAD (puede tardar unos minutos)..."
mkdir "$TMP/src"
git -C "$REPO" archive HEAD | tar -x -C "$TMP/src"
meson setup "$TMP/build" "$TMP/src" >"$TMP/setup.log" 2>&1 || { tail -20 "$TMP/setup.log"; exit 1; }
# con prioridad baja y dos trabajos: José trabaja en la computadora mientras compila (18-10-2026)
nice -n 19 ionice -c3 meson compile -j 2 -C "$TMP/build" >"$TMP/compile.log" 2>&1 || { tail -30 "$TMP/compile.log"; exit 1; }

echo "Respaldo en $RESPALDO"
mkdir -p "$RESPALDO"
cp "$HOME/.local/bin/fynder" "$HOME/.local/bin/fynder-desktop" "$RESPALDO/"
cp "$ESQ/$XML" "$RESPALDO/"
[ -f "$MOD" ] && cp "$MOD" "$RESPALDO/"
[ -f "$APPS/fynder.desktop" ] && cp "$APPS/fynder.desktop" "$RESPALDO/"
cat >"$RESPALDO/volver.sh" <<'EOF'
#!/bin/sh
# Vuelve a los binarios y al esquema de Fynder que había antes de esta instalación.
d=$(dirname "$0")
cp "$d/fynder" "$HOME/.local/bin/fynder.nuevo" && mv "$HOME/.local/bin/fynder.nuevo" "$HOME/.local/bin/fynder"
cp "$d/fynder-desktop" "$HOME/.local/bin/fynder-desktop.nuevo" && mv "$HOME/.local/bin/fynder-desktop.nuevo" "$HOME/.local/bin/fynder-desktop"
cp "$d/io.github.josemalena.fynder.gschema.xml" "$HOME/.local/share/glib-2.0/schemas/" && glib-compile-schemas "$HOME/.local/share/glib-2.0/schemas"
if [ -f "$d/libfynder-chooser-module.so" ]; then
  cp "$d/libfynder-chooser-module.so" "$HOME/.local/lib/fynder/libfynder-chooser-module.so.nuevo" &&
    mv "$HOME/.local/lib/fynder/libfynder-chooser-module.so.nuevo" "$HOME/.local/lib/fynder/libfynder-chooser-module.so"
fi
if [ -f "$d/fynder.desktop" ]; then
  cp "$d/fynder.desktop" "$HOME/.local/share/applications/fynder.desktop.nuevo" &&
    mv "$HOME/.local/share/applications/fynder.desktop.nuevo" "$HOME/.local/share/applications/fynder.desktop"
fi
EOF
chmod +x "$RESPALDO/volver.sh"

# primero el esquema: los binarios nuevos leen claves que el viejo no tiene
if ! cmp -s "$TMP/src/libnemo-private/$XML" "$ESQ/$XML"; then
  cp "$TMP/src/libnemo-private/$XML" "$ESQ/$XML.nuevo"
  mv "$ESQ/$XML.nuevo" "$ESQ/$XML"
  glib-compile-schemas "$ESQ"
  echo "Esquema actualizado y compilado."
fi

for b in fynder fynder-desktop; do
  cp "$TMP/build/src/$b" "$HOME/.local/bin/$b.nuevo"
  mv "$HOME/.local/bin/$b.nuevo" "$HOME/.local/bin/$b"
  cmp "$TMP/build/src/$b" "$HOME/.local/bin/$b"
done

# el módulo solo si el selector está instalado (instalar-selector.sh lo puso ahí)
if [ -f "$MOD" ] && [ -f "$TMP/build/gtk-module/libfynder-chooser-module.so" ]; then
  cp "$TMP/build/gtk-module/libfynder-chooser-module.so" "$MOD.nuevo"
  mv "$MOD.nuevo" "$MOD"
  echo "Módulo del selector actualizado (los programas GTK abiertos siguen con el viejo)."
fi

if ! cmp -s "$TMP/src/data/fynder.desktop" "$APPS/fynder.desktop"; then
  mkdir -p "$APPS"
  cp "$TMP/src/data/fynder.desktop" "$APPS/fynder.desktop.nuevo"
  mv "$APPS/fynder.desktop.nuevo" "$APPS/fynder.desktop"
  update-desktop-database "$APPS" 2>/dev/null || true
  echo "fynder.desktop actualizado."
fi

echo "Instalado Fynder $HASH. Los programas ya abiertos siguen con el binario viejo hasta reiniciarlos."
echo "Vuelta atrás: sh $RESPALDO/volver.sh"
