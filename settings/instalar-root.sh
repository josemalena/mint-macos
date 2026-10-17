#!/bin/bash
# Instala de una vez todos los ayudantes de root de System Preferences: corre el
# instalar-root.sh de cada panel que lo tenga (hoy equipo, modifier-keys, sharing y
# startup-disk; uno nuevo entra solo). Cada uno copia su ayudante a
# /usr/libexec/mint-macos con dueño root y pone su acción de polkit.
#
#   sudo ./instalar-root.sh            todos: el de Rust donde esté compilado, si no el de Python
#   sudo ./instalar-root.sh --python   todos con el de Python (vuelta atrás al viejo)
#   sudo ./instalar-root.sh --volver   repone lo que había antes de la última corrida
#   sudo ./instalar-root.sh --quitar   los quita todos
#   ./instalar-root.sh --probar        sin root: qué instalaría cada panel, sin tocar nada
#
# Los de Rust se compilan antes, como tu usuario y NO con sudo:
#   cd rust && cargo build --release
# (el paquete de otra computadora ya los trae compilados en rust-binarios.tar.gz).
#
# Antes de instalar o quitar guarda lo que hay en /var/backups/mint-macos/ayudantes-<fecha>/,
# que es lo que repone --volver.
set -euo pipefail

AQUI="$(cd "$(dirname "$0")" && pwd)"
RUST="$AQUI/../rust/target/release"
LIBEXEC=/usr/libexec/mint-macos
POLKIT=/usr/share/polkit-1/actions
RESPALDOS=/var/backups/mint-macos

MODO="${1:-}"
case "$MODO" in
  ""|--python|--volver|--quitar|--probar) ;;
  *) echo "uso: sudo $0 [--python | --volver | --quitar]   ($0 --probar sin root)" >&2; exit 2 ;;
esac
[ $# -le 1 ] || { echo "uso: sudo $0 [--python | --volver | --quitar]" >&2; exit 2; }
if [ "$MODO" != --probar ]; then
  [ "$(id -u)" = 0 ] || { echo "✗ Corre esto con sudo (o --probar para ver qué haría)."; exit 1; }
fi

PANELES=()
for f in "$AQUI"/*/instalar-root.sh; do
  [ -f "$f" ] && PANELES+=("$(basename "$(dirname "$f")")")
done
[ ${#PANELES[@]} -gt 0 ] || { echo "✗ no hay ningún panel con instalar-root.sh en $AQUI"; exit 1; }

# Lo que se puede reponer: los ayudantes y las acciones de polkit de mint-macos.
respaldar() {
  # Con nanosegundos: dos corridas en el mismo segundo no comparten carpeta.
  local r; r="$RESPALDOS/ayudantes-$(date +%Y%m%d-%H%M%S-%N)"
  install -d -m 0755 "$RESPALDOS"
  mkdir -m 0700 "$r"
  install -d "$r/libexec" "$r/polkit"
  [ -d "$LIBEXEC" ] && cp -a "$LIBEXEC/." "$r/libexec/"
  find "$POLKIT" -maxdepth 1 -name 'org.mintmacos.*.policy' -exec cp -a {} "$r/polkit/" \;
  echo "  respaldo: $r"
}

if [ "$MODO" = --volver ]; then
  ULTIMO="$(ls -1d "$RESPALDOS"/ayudantes-* 2>/dev/null | tail -1 || true)"
  [ -n "$ULTIMO" ] || { echo "✗ no hay respaldo en $RESPALDOS"; exit 1; }
  echo "Reponiendo $ULTIMO"
  # Lo que se instaló después del respaldo se quita; lo que había vuelve con dueño root.
  for p in "${PANELES[@]}"; do rm -f "$LIBEXEC/$p"; done
  find "$POLKIT" -maxdepth 1 -name 'org.mintmacos.*.policy' -delete
  for f in "$ULTIMO"/libexec/*; do
    if [ -f "$f" ]; then install -d -m 0755 "$LIBEXEC"; install -m 0755 -o root -g root "$f" "$LIBEXEC/"; fi
  done
  rmdir "$LIBEXEC" 2>/dev/null || true
  for f in "$ULTIMO"/polkit/*.policy; do
    if [ -f "$f" ]; then install -m 0644 -o root -g root "$f" "$POLKIT/"; fi
  done
  if [ -d "$LIBEXEC" ]; then ls -l "$LIBEXEC" | sed 's/^/  /'
  else echo "  antes no había ningún ayudante: quedan quitados"; fi
  exit 0
fi

if [ "$MODO" = --probar ]; then
  for p in "${PANELES[@]}"; do
    if [ -x "$RUST/mint-macos-$p" ]; then echo "  $p: Rust ($RUST/mint-macos-$p)"
    else echo "  $p: Python (falta el de Rust)"; fi
  done
  exit 0
fi

respaldar
FALTA_RUST=()
FALLARON=()
for p in "${PANELES[@]}"; do
  echo "■ $p"
  [ "$MODO" = "" ] && [ ! -x "$RUST/mint-macos-$p" ] && FALTA_RUST+=("$p")
  # Uno que falle no deja a los otros sin instalar.
  if ! "$AQUI/$p/instalar-root.sh" $MODO; then FALLARON+=("$p"); fi
done

if [ ${#FALTA_RUST[@]} -gt 0 ]; then
  echo
  echo "Ojo: ${FALTA_RUST[*]} quedó con el de Python porque falta compilar el de Rust."
  echo "  Como tu usuario, NO con sudo:  cd $(cd "$AQUI/.." && pwd)/rust && cargo build --release"
  echo "  y vuelve a correr:  sudo $0"
fi
if [ ${#FALLARON[@]} -gt 0 ]; then
  echo "✗ fallaron: ${FALLARON[*]}   (lo de antes: sudo $0 --volver)"
  exit 1
fi
echo "Listo: ${PANELES[*]}.   Vuelta atrás: sudo $0 --volver  (o --python)"
