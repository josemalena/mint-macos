#!/usr/bin/env bash
# Transforma Linux Mint (Cinnamon) para que se maneje como macOS:
# ⌘ = Super, ⌥ = Alt, en el escritorio, kitty y VS Code, más los applets
# del menú Apple. Antes de tocar un archivo lo respalda en
# ~/.mint-macos-respaldo/<fecha>/, así que se puede deshacer.
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
# instalar.sh le pasa su carpeta de respaldo para que --deshacer la encuentre.
RESPALDO="${MINT_MACOS_RESPALDO:-$HOME/.mint-macos-respaldo/$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$RESPALDO"

paso() { printf '\n▸ %s\n' "$*"; }
respaldar() { [ -e "$1" ] && cp -a "$1" "$RESPALDO/" && echo "  respaldo: $RESPALDO/$(basename "$1")" || true; }

paso "Requisitos (los pone sudo ./requisitos.sh)"
FALTAN=""
for p in python3-gi wmctrl xdotool rsync; do dpkg -s "$p" >/dev/null 2>&1 || FALTAN="$FALTAN $p"; done
command -v keyd >/dev/null || FALTAN="$FALTAN keyd"
[ -z "$FALTAN" ] && echo "  están" || { echo "  ✗ faltan:$FALTAN — corre antes: sudo ./requisitos.sh"; exit 1; }

paso "Cinnamon: atajos y fuentes de entrada"
for ruta in /org/cinnamon/desktop/keybindings/ /org/cinnamon/desktop/input-sources/ /org/gnome/libgnomekbd/keyboard/; do
  nombre="$(echo "$ruta" | tr '/' '_' | sed 's/^_//;s/_$//').dconf"
  dconf dump "$ruta" > "$RESPALDO/$nombre"
done
# Los atajos de capturas y emojis (custom2…custom7) llaman a ~/.local/bin/
# mac-captura y mac-emojis: van antes de cargar los atajos.
"$REPO/capturas/instalar.sh"
# Los atajos propios (Force Quit) llevan la ruta del applet en el $HOME: el
# archivo trae la de la máquina donde se armó y aquí se pone la de este usuario.
sed "s#/home/jmalena#$HOME#g" "$REPO/cinnamon/keybindings.dconf" | dconf load /org/cinnamon/desktop/keybindings/
# Las fuentes de entrada NO se copian de la Mac mini (allí son es y us, con
# español primero): en la iMac, de teclado US, le cambiaban los símbolos
# (15-10-2026). Se queda la que dejó la instalación de Mint, que es la del
# teclado físico. Para escogerlas: MINT_MACOS_TECLADO="us" o "us,es" (la
# primera es la que queda puesta; el orden no se toca si no se pide).
if [ -n "${MINT_MACOS_TECLADO:-}" ]; then
  fuentes=""
  for t in $(echo "$MINT_MACOS_TECLADO" | tr ',' ' '); do
    [[ "$t" =~ ^[a-z]{2,3}(\+[a-z0-9_-]+)?$ ]] || { echo "  ✗ distribución no válida: $t (ej.: us, es, us+intl)"; exit 1; }
    fuentes="${fuentes:+$fuentes, }('xkb', '$t')"
  done
  dconf write /org/cinnamon/desktop/input-sources/sources "[$fuentes]"
  echo "  teclado: $MINT_MACOS_TECLADO (MINT_MACOS_TECLADO)"
else
  echo "  teclado: el de la instalación de Mint, sin cambiar ($(dconf read /org/cinnamon/desktop/input-sources/sources || true) $(sed -n 's/^XKBLAYOUT=//p' /etc/default/keyboard 2>/dev/null | tr -d '"'))"
fi
echo "  respaldo de dconf en $RESPALDO"

paso "keyd: ⌘ y ⌥ como en macOS en todo el sistema"
# keyd, /etc/keyd/default.conf y el grupo keyd los pone requisitos.sh (sudo).
# Aquí solo lo del usuario: las excepciones por aplicación.
keyd --version 2>/dev/null | sed 's/^/  /' || true
id -nG "$USER" | grep -qw keyd || echo "  ojo: $USER todavía no está en el grupo keyd (vale al volver a entrar)"
mkdir -p "$HOME/.config/keyd" "$HOME/.config/autostart"
respaldar "$HOME/.config/keyd/app.conf"
cp "$REPO/keyd/app.conf" "$HOME/.config/keyd/app.conf"
cp "$REPO/keyd/keyd-application-mapper.desktop" "$HOME/.config/autostart/"

paso "kitty: atajos ⌘ y ⌥ (se incluyen, no se reemplaza el kitty.conf)"
KITTY="$HOME/.config/kitty"
mkdir -p "$KITTY"
respaldar "$KITTY/macos-keys.conf"
cp "$REPO/kitty/macos-keys.conf" "$KITTY/macos-keys.conf"
touch "$KITTY/kitty.conf"
if ! grep -q '^include macos-keys.conf' "$KITTY/kitty.conf"; then
  respaldar "$KITTY/kitty.conf"
  printf '\n# Atajos estilo macOS (repo mint-macos)\ninclude macos-keys.conf\n' >> "$KITTY/kitty.conf"
fi

paso "zsh: el ~/.zshrc de la Mac (el shell lo cambia requisitos.sh)"
if [ -e "$HOME/.zshrc" ]; then
  echo "  ya hay un ~/.zshrc: no se toca"
else
  cp "$REPO/zsh/zshrc" "$HOME/.zshrc"
  echo "  ~/.zshrc con el prompt «usuario@equipo carpeta %»"
fi

paso "VS Code: keybindings.json"
VSCODE="$HOME/.config/Code/User"
mkdir -p "$VSCODE"
respaldar "$VSCODE/keybindings.json"
cp "$REPO/vscode/keybindings.json" "$VSCODE/keybindings.json"

paso "Ulauncher: ⌘Espacio, como Spotlight"
UL="$HOME/.config/ulauncher/settings.json"
if [ -f "$UL" ]; then
  respaldar "$UL"
  python3 -c "import json,sys; p=sys.argv[1]; d=json.load(open(p)); d['hotkey-show-app']='<Super>space'; json.dump(d,open(p,'w'),indent=4)" "$UL"
  # ⌘Espacio era del diálogo Run de Cinnamon; se queda con Alt+F2.
  dconf write /org/cinnamon/desktop/keybindings/wm/panel-run-dialog "['<Alt>F2']"
  echo "  reinicia Ulauncher para que tome el atajo"
else
  echo "  Ulauncher no está configurado: se salta"
fi

paso "Applets del menú Apple"
APPLETS="$HOME/.local/share/cinnamon/applets"
mkdir -p "$APPLETS"
for a in "$REPO"/applets/*@macos; do
  n="$(basename "$a")"
  [ -e "$APPLETS/$n" ] && respaldar "$APPLETS/$n"
  rm -rf "${APPLETS:?}/$n"
  # Solo lo que está en git: nada de __pycache__ ni restos locales. En el
  # paquete el repo sale de git archive, sin .git: ahí ya viene limpio.
  if [ -d "$REPO/.git" ]; then
    (cd "$REPO" && git ls-files -z "applets/$n")
  else
    (cd "$REPO" && find "applets/$n" -type f ! -path '*/__pycache__/*' ! -name '*.pyc' -print0)
  fi | while IFS= read -r -d '' f; do
    install -D -m "$( [ -x "$REPO/$f" ] && echo 755 || echo 644 )" "$REPO/$f" "$APPLETS/${f#applets/}"
  done
  echo "  $n"
done
# Cinnamon guarda en caché los módulos de un applet (dbusmenu.js): recargarlo
# no basta, hace falta reiniciar Cinnamon o volver a entrar.

# El lado de las apps del menú global (sesión de Plank/apps): el registrador y
# que las apps publiquen su menú. Va con --sesion porque los applets de
# arriba ya pintan los dos caminos (GTK y DBusMenu): sin ellos, las apps
# esconderían su barra y quedarían sin menús. Respalda y deja volver.sh.
paso "Menú global: que las apps publiquen su menú"
"$REPO/menu-global/instalar.sh" --sesion

# /Applications la crea requisitos.sh (sudo) como carpeta del usuario; si no
# está, se sigue sin ella. La marca le dice a instalar.sh --deshacer que la quite.
paso "/Applications como en la Mac"
if [ -d /Applications ] && [ -w /Applications ] && [ ! -L /Applications ]; then
  "$REPO/aplicaciones/instalar.sh" && touch "$RESPALDO/aplicaciones"
else
  echo "  sin /Applications del usuario: corre antes sudo ./requisitos.sh"
fi

paso "Listo"
echo "  Los applets van al panel con cinnamon/barra.sh (lo corre instalar.sh)."
echo "  El menú global de las apps se activa al cerrar sesión y volver a entrar."
echo "  En kitty: ctrl+shift+F5 recarga la configuración."
echo "  Si el teclado se traba: Backspace+Escape+Enter a la vez detiene keyd."
echo "  Para deshacer: los originales están en $RESPALDO"
