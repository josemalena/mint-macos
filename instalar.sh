#!/usr/bin/env bash
# Instala mint-macos completo para el usuario que lo corre, sin sudo (lo que
# pide sudo va antes, en requisitos.sh). Orden:
#   1. construir.sh   Fynder y Muelle (el Dock) en ~/.local, en hashes fijos
#   2. desde-mac.sh   lo de Apple, sacado del disco de la Mac (local)
#   3. install.sh     teclado como macOS (keyd, kitty, VS Code), applets y el
#                     lado de las apps del menú global
#   4. tema           Constanza: GTK, Cinnamon, íconos, fuentes, fondo, Plank
#   5. la barra       el panel arriba con los applets en el orden de la Mac
#   6. Fynder         como administrador de archivos, y el dock del fork
#
#   ./instalar.sh [--disco /dev/sdX2] [--volumen-sistema N] [--usuario-mac N]
#                 [--cuadro N] [--sin-mac] [--sin-compilar] [--login]
#
#   --sin-compilar  Fynder y el Dock ya vienen instalados en ~/.local (el
#                   paquete de paquete.sh): no se clonan ni se compilan.
#   ./instalar.sh --deshacer        vuelve a como estaba antes de la última
#
# Los datos del usuario (Documentos, Fotos…) NO se copian aquí: eso es
# migrar-datos.sh, aparte y con --simular primero.
# Al terminar hay que cerrar sesión y volver a entrar.
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
RESP_BASE="$HOME/.mint-macos-respaldo"
ULTIMO="$RESP_BASE/ultimo-instalar"
ARGS_MAC=(); SIN_MAC=false; SIN_COMPILAR=false; LOGIN=false; DESHACER=false
while [ $# -gt 0 ]; do
  case "$1" in
    --disco|--volumen-sistema|--volumen-datos|--usuario-mac|--cuadro) ARGS_MAC+=("$1" "$2"); shift 2 ;;
    --sin-mac) SIN_MAC=true; shift ;;
    --sin-compilar) SIN_COMPILAR=true; shift ;;
    --login) LOGIN=true; ARGS_MAC+=("--login"); shift ;;
    --deshacer) DESHACER=true; shift ;;
    -h|--help) sed -n '2,21p' "$0"; exit 0 ;;
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
  [ -f "$R/aplicaciones" ] && { echo "  /Applications"; "$REPO/aplicaciones/instalar.sh" --quitar || true; }
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
  [ -f "$R/magiclamp" ] && { echo "  efecto genio"; "$REPO/extensions/magiclamp.sh" --deshacer || true; }
  if [ -f "$R/extensiones.ruta" ] && [ -x "$(cat "$R/extensiones.ruta")/volver.sh" ]; then
    echo "  extensiones (⌘Tab)"; "$(cat "$R/extensiones.ruta")/volver.sh" || true
  fi
  if [ -f "$R/menu-global.ruta" ] && [ -x "$(cat "$R/menu-global.ruta")/volver.sh" ]; then
    echo "  menú global"; "$(cat "$R/menu-global.ruta")/volver.sh" || true
  fi
  [ -f "$R/mimeapps.list" ] && { echo "  administrador de archivos"; cp -a "$R/mimeapps.list" "$HOME/.config/mimeapps.list"; }
  [ -f "$R/sin-mimeapps" ] && rm -f "$HOME/.config/mimeapps.list"
  if [ -f "$R/autostart-plank.desktop" ]; then cp -a "$R/autostart-plank.desktop" "$HOME/.config/autostart/plank.desktop"
  elif [ -f "$R/sin-autostart-plank" ]; then rm -f "$HOME/.config/autostart/plank.desktop"; fi
  [ -f "$R/sin-autostart-muelle" ] && rm -f "$HOME/.config/autostart/muelle.desktop"
  if [ -f "$R/nemo-autostart.desktop" ]; then cp -a "$R/nemo-autostart.desktop" "$HOME/.local/share/applications/"
  elif [ -f "$R/sin-nemo-autostart" ]; then rm -f "$HOME/.local/share/applications/nemo-autostart.desktop"; fi
  echo; echo "Listo. Cierra sesión y vuelve a entrar. Fynder y el Dock del fork quedan"
  echo "instalados en ~/.local, pero ya no son los de por defecto. keyd y lo de"
  echo "requisitos.sh (sudo) no se quitan; /Users, /Volumes y /Applications vacía,"
  echo "con sudo ./requisitos.sh --quitar-rutas-mac."
  exit 0
fi

# La carpeta de respaldo de esta corrida; install.sh escribe en ella.
R="$RESP_BASE/$(date +%Y%m%d-%H%M%S)-instalar"
mkdir -p "$R"
export MINT_MACOS_RESPALDO="$R"

paso "0. Requisitos"
FALTA=""
for c in fsapfsmount keyd sassc convert rsync git $($SIN_COMPILAR || echo meson ninja valac); do command -v "$c" >/dev/null || FALTA="$FALTA $c"; done
[ -z "$FALTA" ] && echo "  están" || { echo "  ✗ faltan:$FALTA — corre antes: sudo ./requisitos.sh"; exit 1; }

if $SIN_COMPILAR; then
  paso "1. Fynder y Muelle: ya instalados (--sin-compilar)"
  source "$REPO/tema/dock.sh"
  for b in fynder "$DOCK_BIN"; do [ -x "$HOME/.local/bin/$b" ] || { echo "  ✗ falta ~/.local/bin/$b"; exit 1; }; done
else
  paso "1. Compilar Fynder y Muelle";  "$REPO/construir.sh"
fi

if $SIN_MAC; then
  paso "2. Disco de la Mac: se salta (--sin-mac); el tema usa sus sustitutos (Inter, Adwaita)"
else
  paso "2. Lo de la Mac";                    "$REPO/desde-mac.sh" "${ARGS_MAC[@]}"
fi

paso "3. Teclado, applets y menú global";   "$REPO/install.sh"
# El menú global deja su respaldo y su volver.sh en una carpeta con fecha: la
# más reciente es la de esta corrida.
ls -d "$HOME"/.local/share/respaldos/menu-global-* 2>/dev/null | sort | tail -1 > "$R/menu-global.ruta" || true

paso "3b. ⌘Tab como el de Catalina (extensión de Cinnamon)"
"$REPO/extensions/instalar.sh" --encender
ls -d "$HOME"/.local/share/respaldos/extensiones-* 2>/dev/null | sort | tail -1 > "$R/extensiones.ruta" || true
paso "3c. El efecto genio al minimizar (Magic Lamp, de Cinnamon Spices)"
"$REPO/extensions/magiclamp.sh"
touch "$R/magiclamp"

paso "4. Tema Constanza";                    "$REPO/tema/instalar.sh"

paso "5. La barra de menús"
"$REPO/cinnamon/barra.sh"
ls -d "$HOME"/.local/share/mint-macos/respaldos/barra-* 2>/dev/null | sort | tail -1 > "$R/barra.ruta" || true

paso "6. Fynder como administrador de archivos, y el dock del fork"
if [ -f "$HOME/.config/mimeapps.list" ]; then cp -a "$HOME/.config/mimeapps.list" "$R/"; else touch "$R/sin-mimeapps"; fi
xdg-mime default fynder.desktop inode/directory application/x-gnome-saved-search
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
echo "  carpetas: $(xdg-mime query default inode/directory)"
# El escritorio de Fynder en lugar del de Nemo: Cinnamon arranca el escritorio
# por el nombre «nemo-autostart» (de sus componentes de sesión), y el de
# ~/.local/share/applications le gana al del sistema. Aquí se había hecho a
# mano; en la iMac salía el de Mint, con su menú y sin las etiquetas (15-10-2026).
# Si ya apunta a fynder-desktop (también con esperar-icloud delante), no se toca.
AUTO_ESC="$HOME/.local/share/applications/nemo-autostart.desktop"
if [ -x "$HOME/.local/bin/fynder-desktop" ] && ! grep -q '^Exec=.*fynder-desktop$' "$AUTO_ESC" 2>/dev/null; then
  if [ -f "$AUTO_ESC" ]; then cp -a "$AUTO_ESC" "$R/"; else touch "$R/sin-nemo-autostart"; fi
  cat > "$AUTO_ESC" <<EOF
[Desktop Entry]
Type=Application
Name=Fynder Desktop
Comment=El escritorio de Fynder (mint-macos) en lugar del de Nemo
Exec=$HOME/.local/bin/fynder-desktop
OnlyShowIn=X-Cinnamon;
AutostartCondition=GSettings io.github.josemalena.fynder.desktop show-desktop-icons
X-GNOME-AutoRestart=true
NoDisplay=true
EOF
fi
echo "  escritorio: $(sed -n 's/^Exec=//p' "$AUTO_ESC" | awk '{print $NF}' | xargs basename) al entrar"
# Los ajustes de una instalación anterior con el nombre viejo (nemo-mac).
[ -x "$HOME/.cache/mint-macos/src/fynder/utils/migrar-ajustes-a-fynder.sh" ] && \
  "$HOME/.cache/mint-macos/src/fynder/utils/migrar-ajustes-a-fynder.sh" || true
mkdir -p "$HOME/.config/autostart"
# El Dock al entrar: Muelle (o el Plank de antes si Muelle no está; tema/dock.sh). Un solo
# autoarranque: con Muelle, el de plank se respalda y se quita para que no arranquen los dos.
source "$REPO/tema/dock.sh"
if [ -f "$HOME/.config/autostart/plank.desktop" ]; then cp -a "$HOME/.config/autostart/plank.desktop" "$R/autostart-plank.desktop"; else touch "$R/sin-autostart-plank"; fi
[ -f "$HOME/.config/autostart/muelle.desktop" ] || touch "$R/sin-autostart-muelle"
[ "$DOCK" = muelle ] && rm -f "$HOME/.config/autostart/plank.desktop"
NOMBRE_DOCK=Plank; [ "$DOCK" = muelle ] && NOMBRE_DOCK=Muelle
cat > "$HOME/.config/autostart/$DOCK_BIN.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=$NOMBRE_DOCK
Comment=El Dock (Muelle)
Exec=$HOME/.local/bin/$DOCK_BIN
X-GNOME-Autostart-enabled=true
EOF
echo "  dock: $HOME/.local/bin/$DOCK_BIN al entrar"

if $LOGIN; then
  paso "7. Pantalla de inicio"
  if [ -x "$REPO/login/instalar.sh" ]; then
    echo "  Esto pide sudo y cambia la pantalla de inicio. Córrelo tú:"
    echo "    sudo $REPO/login/instalar.sh"
  else
    echo "  login/instalar.sh todavía no está en el repo"
  fi
fi

paso "Los ayudantes de root de System Preferences (sudo)"
"$REPO/settings/instalar-root.sh" --probar | sed 's/^/  /' || true
echo "  Sin ellos Modifier Keys, Sharing y Startup Disk solo miran. Córrelo tú:"
echo "    sudo $REPO/settings/instalar-root.sh        (vuelta atrás: --volver o --python)"

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
