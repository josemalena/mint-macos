#!/usr/bin/env bash
# Las apps web de iCloud (Mail, Calendar, Notes…), Apple Music y Podcasts como
# aplicaciones: cada una en su ventana del navegador, sin barra de direcciones,
# con su lanzador en el menú, el Dock y /Applications.
#
#   ./apps-web.sh            crea los lanzadores y los íconos
#   ./apps-web.sh --quitar   borra lo que creó
#
# No son PWA: icloud.com no publica un manifest. Se abren con --app=URL del
# navegador (Edge por defecto; NAVEGADOR=google-chrome para Chrome). La sesión
# es la del perfil normal del navegador.
#
# Íconos: los de las apps de Catalina salen del disco de la Mac (macos_apps.py);
# Pages, Numbers y Keynote no vienen en el sistema y se bajan del App Store
# (José, 14-10-2026: los actuales, aunque sean de otro estilo). Nada de esto va
# al repo; se genera aquí. Si no hay disco de Mac, la app queda con el ícono
# genérico y un aviso.
set -euo pipefail

AQUI="$(cd "$(dirname "$0")" && pwd)"
# Edge si está; si no, el primer Chromium que haya. Firefox no sirve: no tiene --app.
if [ -z "${NAVEGADOR:-}" ]; then
  for n in microsoft-edge-stable google-chrome-stable chromium chromium-browser brave-browser; do
    command -v "$n" >/dev/null && { NAVEGADOR="$n"; break; }
  done
fi
NAVEGADOR="${NAVEGADOR:-microsoft-edge-stable}"
APPS="$HOME/.local/share/applications"
ICONOS="$HOME/.local/share/icons/hicolor/256x256/apps"
PREFIJO="mint-macos-web"

# id | nombre | URL | origen del ícono: mac:<ruta en el sistema> o tienda:<id del App Store>
LISTA=(
  "mail|Mail|https://www.icloud.com/mail|mac:System/Applications/Mail.app"
  "calendar|Calendar|https://www.icloud.com/calendar|mac:System/Applications/Calendar.app"
  "contacts|Contacts|https://www.icloud.com/contacts|mac:System/Applications/Contacts.app"
  "photos|Photos|https://www.icloud.com/photos|mac:System/Applications/Photos.app"
  "notes|Notes|https://www.icloud.com/notes|mac:System/Applications/Notes.app"
  "reminders|Reminders|https://www.icloud.com/reminders|mac:System/Applications/Reminders.app"
  "iclouddrive|iCloud Drive|https://www.icloud.com/iclouddrive|mac:System/Library/CoreServices/Finder.app/Contents/Applications/iCloud Drive.app"
  "findmy|Find My|https://www.icloud.com/find|mac:System/Applications/FindMy.app"
  "pages|Pages|https://www.icloud.com/pages|tienda:361309726"
  "numbers|Numbers|https://www.icloud.com/numbers|tienda:361304891"
  "keynote|Keynote|https://www.icloud.com/keynote|tienda:361285480"
  "music|Music|https://music.apple.com|mac:System/Applications/Music.app"
  "podcasts|Podcasts|https://podcasts.apple.com|mac:System/Applications/Podcasts.app"
)

if [ "${1:-}" = "--quitar" ]; then
  rm -f "$APPS/$PREFIJO-"*.desktop "$ICONOS/$PREFIJO-"*.png
  update-desktop-database "$APPS" 2>/dev/null || true
  gtk-update-icon-cache -q -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
  echo "Listo: apps web de Apple quitadas."
  exit 0
fi

# Sin navegador que sirva no se corta la instalación (iMac, 15-10-2026: sin Edge,
# el paquete se detenía aquí): avisa y sale bien; se corre otra vez al instalarlo.
command -v "$NAVEGADOR" >/dev/null || {
  echo "  ⚠ sin Edge ni Chrome/Chromium: las apps web de iCloud no se crean."
  echo "    Instala uno y corre otra vez: $0"
  exit 0
}
mkdir -p "$APPS" "$ICONOS"

# La clase de ventana que pone Chromium con --app: «host__ruta», con las barras
# de la ruta como «_»; sin ruta, el host solo. Es lo que el Dock usa para
# juntar la ventana con su lanzador.
clase_de() {
  local sin="${1#*://}" host ruta
  host="${sin%%/*}"; ruta="${sin#"$host"}"
  if [ -z "$ruta" ] || [ "$ruta" = "/" ]; then echo "$host"; else echo "${host}_${ruta//\//_}"; fi
}

# El ícono de la tienda: la página del App Store (vista Mac) trae la URL del
# ícono de macOS; se pide a 1024 y se baja a 256.
icono_tienda() {
  local id="$1" destino="$2" pagina url tmp
  pagina=$(curl -fsSL -m 20 -A "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Safari/605.1.15" \
    "https://apps.apple.com/us/app/id$id?platform=mac") || return 1
  # La vista Mac trae dos: el de iPad (…-4-…sRGB…) y el de macOS (…-6-…); va el segundo.
  url=$(grep -oE 'https://is[0-9]-ssl\.mzstatic\.com/image/thumb/[^" ,{]+AppIcon[^" ,{/]+-6-[^" ,{/]+\.png' <<<"$pagina" | head -1)
  [ -n "$url" ] || return 1
  tmp=$(mktemp --suffix=.png)
  curl -fsS -m 20 -o "$tmp" "$url/1024x1024bb.png" || { rm -f "$tmp"; return 1; }
  python3 -c "from PIL import Image; import sys; Image.open(sys.argv[1]).convert('RGBA').resize((256,256), Image.LANCZOS).save(sys.argv[2])" "$tmp" "$destino"
  rm -f "$tmp"
}

# shellcheck source=../tema/comun.sh
source "$AQUI/../tema/comun.sh"
MAC=""
montar_mac_sistema && MAC="$MAC_SISTEMA" || echo "⚠ Sin disco de Mac: los íconos de Catalina quedan genéricos."

hechos=0
for fila in "${LISTA[@]}"; do
  IFS='|' read -r id nombre url origen <<<"$fila"
  icono="$ICONOS/$PREFIJO-$id.png"
  case "$origen" in
    mac:*)
      if [ -n "$MAC" ] && [ -d "$MAC/${origen#mac:}" ]; then
        PYTHONPATH="$AQUI/../tema/iconos" python3 -c "
import sys; from macos_apps import icns_de, png_256
i = icns_de(sys.argv[1]); i and png_256(i, sys.argv[2])" "$MAC/${origen#mac:}" "$icono" \
          || echo "⚠ $nombre: no salió el ícono de la Mac."
      fi ;;
    tienda:*)
      icono_tienda "${origen#tienda:}" "$icono" || echo "⚠ $nombre: no pude bajar el ícono del App Store." ;;
  esac
  [ -f "$icono" ] && ic="$PREFIJO-$id" || ic="web-browser"
  cat > "$APPS/$PREFIJO-$id.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=$nombre
Comment=$nombre en la web de Apple
Exec=$NAVEGADOR --app=$url
Icon=$ic
Terminal=false
Categories=Network;Office;
StartupWMClass=$(clase_de "$url")
EOF
  hechos=$((hechos + 1))
done
[ -n "$MAC" ] && desmontar_mac

update-desktop-database "$APPS" 2>/dev/null || true
gtk-update-icon-cache -q -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
echo "Listo: $hechos apps web de Apple con $NAVEGADOR. Para quitarlas: $0 --quitar"
