#!/usr/bin/env bash
# Tema GTK «Constanza-Oscuro» en ~/.themes: ventanas (GTK 2, 3 y 4), panel y
# menús de Cinnamon, bordes con semáforos (metacity-1 para Muffin) y Plank.
# Parte de Mojave-gtk-theme (vinceliuice, GPL-3.0) en una versión fijada: se
# clona y se compila con su propio instalador, sin copiar su CSS al repo, y
# encima se le agrega _constanza.scss.
set -euo pipefail
AQUI="$(cd "$(dirname "$0")" && pwd)"
MOJAVE_COMMIT=eff1025
NOMBRE=Constanza-Oscuro
DEST="$HOME/.themes"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

for p in sassc glib-compile-resources; do
  command -v "$p" >/dev/null || sudo apt install -y sassc libglib2.0-dev-bin
done

echo "  Mojave-gtk-theme $MOJAVE_COMMIT"
git clone -q https://github.com/vinceliuice/Mojave-gtk-theme.git "$TMP/mojave"
git -C "$TMP/mojave" checkout -q "$MOJAVE_COMMIT"
mkdir -p "$TMP/salida"
"$TMP/mojave/install.sh" -d "$TMP/salida" -n Constanza -c dark -o standard -a standard -s standard >/dev/null 2>&1
BASE="$TMP/salida/Constanza-Dark"
[ -f "$BASE/gtk-3.0/gtk.gresource" ] || { echo "  ✗ no se compiló el tema base"; exit 1; }

# Lo propio encima, en GTK 3 (es lo que usan Nemo y casi todo en Cinnamon).
sassc "$AQUI/_constanza.scss" "$BASE/gtk-3.0/constanza.css"
# sassc antepone @charset si hay acentos en los comentarios, y GTK no lo
# acepta («unknown @ rule»).
sed -i '/^@charset/d' "$BASE/gtk-3.0/constanza.css"
for css in gtk.css gtk-dark.css; do
  echo '@import url("constanza.css");' >> "$BASE/gtk-3.0/$css"
done

# Nombre propio y metatema.
sed -i -e "s/^Name=.*/Name=$NOMBRE/" -e "s/^GtkTheme=.*/GtkTheme=$NOMBRE/" \
       -e "s/^MetacityTheme=.*/MetacityTheme=$NOMBRE/" -e "s/^IconTheme=.*/IconTheme=Constanza/" \
       -e "s/^CursorTheme=.*/CursorTheme=McMojave-cursors/" \
       -e "s/^Comment=.*/Comment=Constanza oscuro: Mojave-gtk-theme (GPL-3.0) con retoques propios/" \
       "$BASE/index.theme"
cp "$AQUI/../CREDITOS.md" "$BASE/CREDITOS.md"

rm -rf "$DEST/$NOMBRE"; mkdir -p "$DEST"
mv "$BASE" "$DEST/$NOMBRE"

# Dock: el tema de Plank oscuro de Mojave con el nombre de Constanza.
PLANK="$HOME/.local/share/plank/themes/$NOMBRE"
rm -rf "$PLANK"; mkdir -p "$PLANK"
cp "$TMP/mojave/src/other/plank/Theme-Dark/"* "$PLANK/"
echo "  tema: $DEST/$NOMBRE"
