#!/usr/bin/env bash
# Saca del disco de la Mac, en SOLO LECTURA y a carpetas locales del usuario,
# lo que el tema Constanza usa de Apple. Nada de esto va al repo: son
# archivos de Apple y cada quien los saca de su propia Mac.
#
#   ./desde-mac.sh [--disco /dev/sdX2] [--volumen-sistema N] [--volumen-datos N]
#                  [--usuario-mac NOMBRE] [--cuadro N] [--login]
#
#   --disco            el contenedor APFS (lsblk -f lo marca «apfs»). Sin él,
#                      el primero que haya.
#   --volumen-sistema  índice del volumen de sistema (fsapfsinfo /dev/sdX2 los
#                      lista). Sin él, el que no es «- Data», Preboot,
#                      Recovery, VM ni Update.
#   --volumen-datos    índice del volumen de datos. Sin él, «<nombre> - Data».
#   --usuario-mac      el usuario de la Mac (carpeta en /Users). Solo hace falta
#                      para --login. Sin él, el único que haya.
#   --cuadro           el cuadro de Catalina.heic para el fondo (7 = atardecer,
#                      el de José; 1 = la noche, el «oscuro» de Apple).
#   --login            además, lo de la pantalla de inicio (login/desde-mac.sh).
#
# Qué deja (todo en el $HOME del usuario de Linux):
#   ~/.local/share/fonts/san-francisco/   las SF (y SF Mono) de la Mac
#   ~/.local/share/constanza/manzana/     la manzana del menú Apple (de la SF)
#   ~/.local/share/icons/Constanza/       los íconos de color, de discos y del
#                                         lateral del Finder (los construye
#                                         tema/iconos/construir.sh)
#   ~/.local/share/backgrounds/constanza/ el fondo de Catalina
#
# Lo que NO se puede sacar desde Linux: los glifos de la barra del Finder
# (atrás, vistas, compartir…). Están en un catálogo que solo desempaca macOS.
# Se sacan una vez en la Mac (ver LEEME.md, «Glifos de la barra») y se dejan
# en ~/.local/share/constanza/glifos-finder; este guion los usa si están.
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
LOGIN=false
while [ $# -gt 0 ]; do
  case "$1" in
    --disco) export MAC_DISCO="$2"; shift 2 ;;
    --volumen-sistema) export MAC_VOL_SISTEMA="$2"; shift 2 ;;
    --volumen-datos) export MAC_VOL_DATOS="$2"; shift 2 ;;
    --usuario-mac) export MAC_USUARIO="$2"; shift 2 ;;
    --cuadro) export CUADRO="$2"; shift 2 ;;
    --login) LOGIN=true; shift ;;
    -h|--help) sed -n '2,32p' "$0"; exit 0 ;;
    *) echo "✗ parámetro desconocido: $1 (mira --help)"; exit 2 ;;
  esac
done

paso() { printf '\n▸ %s\n' "$*"; }
source "$REPO/tema/comun.sh"
trap desmontar_mac EXIT

paso "El disco de la Mac"
command -v fsapfsmount >/dev/null || { echo "  ✗ falta fsapfsmount: corre antes sudo ./requisitos.sh"; exit 1; }
for d in $(discos_apfs); do
  echo "  $d:"; volumenes_apfs "$d" | sed 's/^/    /'
done
montar_mac_sistema || { echo "  ✗ no encontré el volumen de sistema (prueba --disco y --volumen-sistema)"; exit 1; }
export MAC_SISTEMA
echo "  sistema montado en $MAC_SISTEMA (solo lectura)"
VERSION="$(grep -A1 ProductVersion "$MAC_SISTEMA/System/Library/CoreServices/SystemVersion.plist" 2>/dev/null | grep -o '[0-9.]\+' | head -1)"
echo "  macOS ${VERSION:-?}"
case "$VERSION" in 10.15*) ;; *) echo "  ojo: el tema se midió contra Catalina (10.15); otra versión puede no traer los mismos archivos" ;; esac

paso "Fuentes San Francisco";        "$REPO/tema/fuentes/desde-mac.sh" || echo "  (sin fuentes)"
paso "Manzana del menú Apple";       python3 "$REPO/tema/manzana/desde-fuente.py" || echo "  (sin manzana)"
paso "Íconos del Finder y del Dock"; "$REPO/tema/iconos/construir.sh" || echo "  (sin íconos)"
paso "Fondo de Catalina";            "$REPO/tema/fondo/desde-mac.sh" --forzar || echo "  (sin fondo)"

paso "Glifos de la barra del Finder"
if [ -f "$HOME/.local/share/constanza/glifos-finder/GoBack@1x.png" ]; then
  echo "  están en ~/.local/share/constanza/glifos-finder ($(ls "$HOME/.local/share/constanza/glifos-finder" | wc -l) archivos)"
else
  echo "  no están: hay que sacarlos una vez en la Mac (LEEME.md, «Glifos de la barra»)."
  echo "  Sin ellos la barra de Fynder usa los de Os-Catalina."
fi

if $LOGIN; then
  paso "Pantalla de inicio (login/desde-mac.sh)"
  if [ -x "$REPO/login/desde-mac.sh" ]; then
    montar_mac_datos || { echo "  ✗ no encontré el volumen de datos (prueba --volumen-datos)"; exit 1; }
    export MAC_DATOS
    "$REPO/login/desde-mac.sh"
  else
    echo "  login/desde-mac.sh todavía no está en el repo"
  fi
fi

paso "Listo"
echo "  Nada de lo que se sacó está en el repo. El disco de la Mac no se tocó."
