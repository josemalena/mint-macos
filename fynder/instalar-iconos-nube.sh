#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Los íconos de Google Drive y OneDrive de la barra lateral de Fynder desde Monterey: el
# símbolo que declara el File Provider de cada uno (CFBundleSymbolName: google_symbols/drive
# y odsymbol), sacado de los instaladores oficiales a referencias/iconos-nube-*/ (Planner,
# 27-10-2026). Son marcas de Google y de Microsoft: NUNCA van a un repo. Se copian de
# referencias a ~/.local/share/icons como íconos -symbolic, que GTK recolorea. Sin ellos,
# Fynder pone la carpeta genérica.
#
#   instalar-iconos-nube.sh            instala (o reemplaza)
#   instalar-iconos-nube.sh --quitar   los quita
#
# Variante: regular (274) en escala mediana (282). Que 27X sea el grosor y 28X la escala del
# símbolo es lo que sugieren los nombres del .car; hipótesis, no está documentado.
set -eu

DEST="$HOME/.local/share/icons/hicolor/scalable/apps"
REF="$HOME/.local/share/mint-macos/referencias"

actualizar_cache () {
	# la caché de este hicolor no tiene index.theme: se regenera igual, o GTK no ve los nuevos
	if [ -f "$HOME/.local/share/icons/hicolor/icon-theme.cache" ]; then
		gtk-update-icon-cache --ignore-theme-index -f -q "$HOME/.local/share/icons/hicolor" || true
	fi
}

if [ "${1:-}" = "--quitar" ]; then
	rm -f "$DEST/mint-macos-nube-gdrive-symbolic.svg" "$DEST/mint-macos-nube-onedrive-symbolic.svg"
	actualizar_cache
	echo "Íconos de las nubes quitados: Fynder vuelve a la carpeta genérica."
	exit 0
fi

# la extracción más nueva
SALIDA=$(ls -d "$REF"/iconos-nube-*/salida 2>/dev/null | sort | tail -n 1)
[ -n "$SALIDA" ] || { echo "No hay referencias/iconos-nube-*/salida: Fynder sigue con la carpeta genérica." >&2; exit 1; }

buscar () {
	find "$SALIDA/$1" -name "$2-*-274-282-*.svg" 2>/dev/null | sort | head -n 1
}
GDRIVE=$(buscar car-google-drive google_symbols__drive)
ONEDRIVE=$(buscar car-onedrive odsymbol)
[ -n "$GDRIVE" ] && [ -n "$ONEDRIVE" ] || { echo "Falta el símbolo de alguna nube en $SALIDA." >&2; exit 1; }

mkdir -p "$DEST"
cp "$GDRIVE" "$DEST/mint-macos-nube-gdrive-symbolic.svg.nuevo"
mv "$DEST/mint-macos-nube-gdrive-symbolic.svg.nuevo" "$DEST/mint-macos-nube-gdrive-symbolic.svg"
cp "$ONEDRIVE" "$DEST/mint-macos-nube-onedrive-symbolic.svg.nuevo"
mv "$DEST/mint-macos-nube-onedrive-symbolic.svg.nuevo" "$DEST/mint-macos-nube-onedrive-symbolic.svg"
actualizar_cache
echo "Íconos de las nubes instalados desde $SALIDA."
echo "Vuelta atrás: sh $0 --quitar"
