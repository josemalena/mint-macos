#!/bin/bash
# Capturas de pantalla como en macOS Catalina, con gnome-screenshot.
#
#   captura.sh pantalla           ⇧⌘3   la pantalla entera, al escritorio
#   captura.sh area               ⇧⌘4   un área, al escritorio
#   captura.sh herramienta        ⇧⌘5   la herramienta de captura
#   captura.sh pantalla --clip    ⌃⇧⌘3  al portapapeles, sin archivo
#   captura.sh area --clip        ⌃⇧⌘4  al portapapeles, sin archivo
#
# El archivo se llama como en la Mac: «Screen Shot 2026-10-10 at 7.10.14 PM.png»
# (en inglés, como todo el entorno de José). Si ya existe uno con ese nombre,
# no se pisa: « (2)», « (3)»… antes del .png, como hace macOS.
set -u

modo="${1:-pantalla}"
clip=false
[ "${2:-}" = "--clip" ] && clip=true

# El escritorio según XDG; en esta máquina varias XDG apuntan a $HOME, y ahí
# la Mac nunca guarda.
escritorio="$(xdg-user-dir DESKTOP 2>/dev/null || true)"
if [ -z "$escritorio" ] || [ "$escritorio" = "$HOME" ] || [ "$escritorio" = "$HOME/" ]; then
  escritorio="$HOME/Desktop"
fi
mkdir -p "$escritorio"

nombre_libre() {
  local base
  base="$(LC_ALL=C date +'Screen Shot %Y-%m-%d at %-I.%M.%S %p')"
  local f="$escritorio/$base.png" n=2
  while [ -e "$f" ]; do f="$escritorio/$base ($n).png"; n=$((n + 1)); done
  printf '%s' "$f"
}

case "$modo" in
  pantalla) args=() ;;
  area)     args=(-a) ;;
  ventana)  args=(-w) ;;
  herramienta) exec gnome-screenshot -i ;;
  *) echo "uso: $0 pantalla|area|ventana|herramienta [--clip]" >&2; exit 2 ;;
esac

if $clip; then
  exec gnome-screenshot "${args[@]}" -c
else
  exec gnome-screenshot "${args[@]}" -f "$(nombre_libre)"
fi
