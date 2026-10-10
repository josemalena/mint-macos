#!/usr/bin/env bash
# Instala mint-macos completo para el usuario que lo corre, sin sudo (lo que
# pide sudo va antes, en requisitos.sh). Orden:
#   1. construir.sh   Fynder y plank-reloaded en ~/.local, en hashes fijos
#   2. desde-mac.sh   lo de Apple, sacado del disco de la Mac (local)
#   3. install.sh     teclado como macOS (keyd, kitty, VS Code), applets y el
#                     lado de las apps del menú global
#   4. tema           Constanza: GTK, Cinnamon, íconos, fuentes, fondo, Plank
#   5. la barra       el panel arriba con los applets en el orden de la Mac
#   6. Fynder         como administrador de archivos, y el dock del fork
#
#   ./instalar.sh [--disco /dev/sdX2] [--volumen-sistema N] [--usuario-mac N]
#                 [--cuadro N] [--sin-mac] [--login]
#   ./instalar.sh --deshacer        vuelve a como estaba antes de la última
#
# Los datos del usuario (Documentos, Fotos…) NO se copian aquí: eso es
# migrar-datos.sh, aparte y con --simular primero.
# Al terminar hay que cerrar sesión y volver a entrar.
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
RESP_BASE="$HOME/.mint-macos-respaldo"
ULTIMO="$RESP_BASE/ultimo-instalar"
ARGS_MAC=(); SIN_MAC=false; LOGIN=false; DESHACER=false
while [ $# -gt 0 ]; do
  case "$1" in
    --disco|--volumen-sistema|--volumen-datos|--usuario-mac|--cuadro) ARGS_MAC+=("$1" "$2"); shift 2 ;;
    --sin-mac) SIN_MAC=true; shift ;;
    --login) LOGIN=true; ARGS_MAC+=("--login"); shift ;;
    --deshacer) DESHACER=true; shift ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "✗ parámetro desconocido: $1 (mira --help)"; exit 2 ;;
  esac
done
paso() { printf '\n■ %s\n' "$*"; }

if $DESHACER; then
  R="$(cat "$ULTIMO" 2>/dev/null)" || { echo "No hay instalación que deshacer."; exit 1; }
  paso "Deshaciendo la instalación de $R"
  # En orden inverso: cada pieza deja lo que había antes de ella.
  if [ -f "$R/barra.ruta" ] && [ -f "$(cat "$R/barra.ruta")/org-cinnamon.dconf" ]; then
    echo "  barra"; dconf load /org/cinnamon/ < "$(cat "$R/barra.ruta")/org-cinnamon.dconf"
  fi
  echo "  tema Constanza"; "$REPO/tema/instalar.sh" --deshacer || true
  for f in "$R"/*.dconf; do
    [ -f "$f" ] || continue
    ruta="/$(basename "$f" .dconf | tr '_' '/')/"
    echo "  dconf $ruta"; dconf reset -f "$ruta"; dconf load "$ruta" < "$f"
  done
  for f in app.conf macos-keys.conf keybindings.json; do
    case "$f" in
      app.conf) d="$HOME/.config/keyd/app.conf" ;;
      macos-keys.conf) d="$HOME/.config/kitty/macos-keys.conf" ;;
      keybindings.json) d="$HOME/.config/Code/User/keybindings.json" ;;
    esac
    [ -f "$R/$f" ] && { echo "  $d"; cp -a "$R/$f" "$d"; }
  done
  [ -f "$R/kitty.conf" ] && cp -a "$R/kitty.conf" "$HOME/.config/kitty/kitty.conf"
  if [ -f "$R/menu-global.ruta" ] && [ -x "$(cat "$R/menu-global.ruta")/volver.sh" ]; then
    echo "  menú global"; "$(cat "$R/menu-global.ruta")/volver.sh" || true
  fi
  [ -f "$R/mimeapps.list" ] && { echo "  administrador de archivos"; cp -a "$R/mimeapps.list" "$HOME/.config/mimeapps.list"; }
  [ -f "$R/sin-mimeapps" ] && rm -f "$HOME/.config/mimeapps.list"
  if [ -f "$R/autostart-plank.desktop" ]; then cp -a "$R/autostart-plank.desktop" "$HOME/.config/autostart/plank.desktop"
  elif [ -f "$R/sin-autostart-plank" ]; then rm -f "$HOME/.config/autostart/plank.desktop"; fi
  echo; echo "Listo. Cierra sesión y vuelve a entrar. Fynder y el Plank del fork quedan"
  echo "instalados en ~/.local, pero ya no son los de por defecto. keyd y lo de"
  echo "requisitos.sh (sudo) no se quitan."
  exit 0
fi

# La carpeta de respaldo de esta corrida; install.sh escribe en ella.
R="$RESP_BASE/$(date +%Y%m%d-%H%M%S)-instalar"
mkdir -p "$R"
export MINT_MACOS_RESPALDO="$R"

paso "0. Requisitos"
FALTA=""
for c in fsapfsmount keyd meson ninja valac sassc convert rsync git; do command -v "$c" >/dev/null || FALTA="$FALTA $c"; done
[ -z "$FALTA" ] && echo "  están" || { echo "  ✗ faltan:$FALTA — corre antes: sudo ./requisitos.sh"; exit 1; }

paso "1. Compilar Fynder y plank-reloaded";  "$REPO/construir.sh"

if $SIN_MAC; then
  paso "2. Disco de la Mac: se salta (--sin-mac); el tema usa sus sustitutos (Inter, Os-Catalina)"
else
  paso "2. Lo de la Mac";                    "$REPO/desde-mac.sh" "${ARGS_MAC[@]}"
fi

paso "3. Teclado, applets y menú global";   "$REPO/install.sh"
# El menú global deja su respaldo y su volver.sh en una carpeta con fecha: la
# más reciente es la de esta corrida.
ls -d "$HOME"/.local/share/respaldos/menu-global-* 2>/dev/null | sort | tail -1 > "$R/menu-global.ruta" || true

paso "4. Tema Constanza";                    "$REPO/tema/instalar.sh"

paso "5. La barra de menús"
"$REPO/cinnamon/barra.sh"
ls -d "$HOME"/.local/share/mint-macos/respaldos/barra-* 2>/dev/null | sort | tail -1 > "$R/barra.ruta" || true

paso "6. Fynder como administrador de archivos, y el dock del fork"
if [ -f "$HOME/.config/mimeapps.list" ]; then cp -a "$HOME/.config/mimeapps.list" "$R/"; else touch "$R/sin-mimeapps"; fi
xdg-mime default fynder.desktop inode/directory application/x-gnome-saved-search
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
echo "  carpetas: $(xdg-mime query default inode/directory)"
# Los ajustes de una instalación anterior con el nombre viejo (nemo-mac).
[ -x "$HOME/.cache/mint-macos/src/fynder/utils/migrar-ajustes-a-fynder.sh" ] && \
  "$HOME/.cache/mint-macos/src/fynder/utils/migrar-ajustes-a-fynder.sh" || true
mkdir -p "$HOME/.config/autostart"
if [ -f "$HOME/.config/autostart/plank.desktop" ]; then cp -a "$HOME/.config/autostart/plank.desktop" "$R/autostart-plank.desktop"; else touch "$R/sin-autostart-plank"; fi
cat > "$HOME/.config/autostart/plank.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Plank
Comment=El dock (plank-reloaded de mint-macos)
Exec=$HOME/.local/bin/plank
X-GNOME-Autostart-enabled=true
EOF
echo "  dock: $HOME/.local/bin/plank al entrar"

if $LOGIN; then
  paso "7. Pantalla de inicio"
  if [ -x "$REPO/login/instalar.sh" ]; then
    echo "  Esto pide sudo y cambia la pantalla de inicio. Córrelo tú:"
    echo "    sudo $REPO/login/instalar.sh"
  else
    echo "  login/instalar.sh todavía no está en el repo"
  fi
fi

paso "El arranque como el de macOS (sudo)"
"$REPO/tema/arranque/instalar.sh" --vista | sed 's/^/  /' || true
echo "  Cambia el arranque y rehace el initramfs. Córrelo tú:"
echo "    sudo $REPO/tema/arranque/instalar.sh        (vuelta atrás: --deshacer)"

echo "$R" > "$ULTIMO"
paso "Listo"
echo "  Cierra sesión y vuelve a entrar: el menú global, keyd por aplicación y el"
echo "  dock nuevo se toman al entrar (Cinnamon también vuelve a leer los applets)."
echo "  Para volver atrás: $0 --deshacer   (respaldos en $R)"
echo "  Los datos de la Mac van aparte:  ./migrar-datos.sh --simular --usuario-mac NOMBRE"
