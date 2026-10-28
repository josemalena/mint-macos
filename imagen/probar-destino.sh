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
  # Lo que el instalador espera encontrar ya instalado por otra pieza (el applet de applemenu)
  # o en la imagen de Mint (adduser.conf, fuse.conf).
  mkdir -p "$T/usr/share/cinnamon/applets/applemenu@macos" "$T/etc"
  printf 'DSHELL=/bin/bash\n#EXTRA_GROUPS="dialout cdrom floppy audio video plugdev users"\n' > "$T/etc/adduser.conf"
  printf '#user_allow_other\n' > "$T/etc/fuse.conf"
  # Lo que construir.sh compila en el host: un árbol de mentira con el mismo dibujo.
  C="$(mktemp -d)"; mkdir -p "$C/usr/local/bin" "$C/usr/local/lib"; : > "$C/usr/local/bin/fsapfsmount"; : > "$C/usr/local/lib/libfsapfs.so.1"
  if ! out="$(MINT_MACOS_DESTINO=sistema MINT_MACOS_RAIZ="$T" FSAPFS_COMPILADO="$C" bash "$REPO/$f" 2>&1)"; then
    echo "✗ $f falló:"; echo "$out" | tail -3 | sed 's/^/    /'; mal=$((mal+1))
  elif g="$(grep -rlF "$T" "$T" 2>/dev/null)" && [ -n "$g" ]; then
    echo "✗ $f: la raíz falsa quedó escrita en:"; echo "$g" | sed "s|$T||; s/^/    /"; mal=$((mal+1))
  else
    echo "✓ $f ($(find "$T" -type f | wc -l | tr -d ' ') archivos)"
  fi
  rm -rf -- "${T:?}" "${C:?}"
done < <(cd "$REPO" && grep -rlF 'lib/destino.sh' --include='instalar*.sh' . | grep -v '^./imagen/' | sed 's|^\./||' | sort)
despues="$(find "${DONDE[@]}" -newer "$MARCA" -type f 2>/dev/null | wc -l)"; rm -f "$MARCA"
[ "$antes" = "$despues" ] || { echo "✗ algo escribió en el home ($antes → $despues archivos nuevos en el home)"; mal=$((mal+1)); }
echo "$n instaladores, $mal con problemas"
[ "$mal" = 0 ]
