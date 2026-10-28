#!/usr/bin/env bash
# imagen/probar-destino.sh — corre en modo sistema, sobre una raíz falsa y sin root, cada instalar.sh
# que ya carga lib/destino.sh, y comprueba tres cosas:
#   1) termina bien;
#   2) no escribió nada fuera de la raíz (el home no cambia);
#   3) ningún archivo instalado lleva la raíz falsa adentro: una D_* escrita donde iba una R_*
#      dejaría en la imagen un Exec= que apunta al chroot.
# Lo de Rust necesita el binario compilado (cd rust && cargo build --release).
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
mal=0; n=0
# Solo donde instalan las piezas: ~/.local entero trae las referencias (cientos de miles de archivos).
DONDE=("$HOME/.local/bin" "$HOME/.local/lib/mint-macos" "$HOME/.local/share/dbus-1" "$HOME/.local/share/applications"
       "$HOME/.local/share/cinnamon" "$HOME/.config/autostart" "$HOME/.config/systemd/user")
MARCA="$(mktemp)"
antes=0
while IFS= read -r f; do
  n=$((n+1)); T="$(mktemp -d)"
  # Lo que el instalador espera encontrar ya instalado por otra pieza (el applet de applemenu).
  mkdir -p "$T/usr/share/cinnamon/applets/applemenu@macos"
  if ! out="$(MINT_MACOS_DESTINO=sistema MINT_MACOS_RAIZ="$T" bash "$REPO/$f" 2>&1)"; then
    echo "✗ $f falló:"; echo "$out" | tail -3 | sed 's/^/    /'; mal=$((mal+1))
  elif g="$(grep -rlF "$T" "$T" 2>/dev/null)" && [ -n "$g" ]; then
    echo "✗ $f: la raíz falsa quedó escrita en:"; echo "$g" | sed "s|$T||; s/^/    /"; mal=$((mal+1))
  else
    echo "✓ $f ($(find "$T" -type f | wc -l | tr -d ' ') archivos)"
  fi
  rm -rf -- "${T:?}"
done < <(cd "$REPO" && grep -rlF 'lib/destino.sh' --include='instalar*.sh' . | grep -v '^./imagen/' | sed 's|^\./||' | sort)
despues="$(find "${DONDE[@]}" -newer "$MARCA" -type f 2>/dev/null | wc -l)"; rm -f "$MARCA"
[ "$antes" = "$despues" ] || { echo "✗ algo escribió en el home ($antes → $despues archivos nuevos en el home)"; mal=$((mal+1)); }
echo "$n instaladores, $mal con problemas"
[ "$mal" = 0 ]
