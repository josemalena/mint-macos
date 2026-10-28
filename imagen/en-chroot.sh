#!/usr/bin/env bash
# imagen/en-chroot.sh — corre DENTRO del chroot de la imagen, como root (lo llama construir.sh).
# El repo está en /tmp/mint-macos, con rust/target/release y nativo-compilado ya hechos en el host.
# Instala cada pieza en modo sistema (lib/destino.sh): /usr/local, /etc/xdg, /etc/skel, esquemas.
# SIN PROBAR (27-10-2026).
set -euo pipefail
M=/tmp/mint-macos
export MINT_MACOS_DESTINO=sistema MINT_MACOS_RAIZ=""
PERFIL="${PERFIL:-personal}"
paso() { printf '\n▸ (chroot) %s\n' "$*"; }

# Las piezas que ya saben instalarse en modo sistema: las que cargan lib/destino.sh. El resto
# queda en la lista de pendientes, para no meter en la imagen algo instalado a medias.
paso "piezas de mint-macos"
LISTOS=(); PENDIENTES=()
while IFS= read -r f; do
  if grep -q 'lib/destino.sh' "$M/$f"; then LISTOS+=("$f"); else PENDIENTES+=("$f"); fi
done < <(cd "$M" && find . -name 'instalar*.sh' -not -path './imagen/*' -not -path './paquete/*' | sed 's|^\./||' | sort)
for f in "${LISTOS[@]}"; do echo "  · $f"; bash "$M/$f"; done
printf '  pendientes de modo sistema (%d):\n' "${#PENDIENTES[@]}"; printf '    %s\n' "${PENDIENTES[@]}"

# /etc/skel: ~/Library vacía (requisitos.sh la crea para un usuario que ya existe; aquí es para los
# que nazcan) y las rutas de macOS (/Users, /Volumes, /Applications) del sistema.
paso "rutas de macOS"
install -d -m 700 /etc/skel/Library
MINT_MACOS_RAIZ="" bash "$M/requisitos.sh" --solo-rutas-mac 2>/dev/null \
  || echo "  requisitos.sh todavía no tiene --solo-rutas-mac: las rutas se ponen en el primer arranque"

if [ "$PERFIL" = personal ]; then
  # Lo de Apple (solo la imagen personal de José): el tema, los íconos, los cursores y los fondos
  # ya convertidos en Data. Se ponen como del sistema; el usuario los escoge con su sesión.
  paso "recursos de Apple (personal)"
  R="$M/recursos-apple"
  [ -d "$R/themes" ] && cp -a "$R/themes/." /usr/share/themes/
  [ -d "$R/icons" ] && cp -a "$R/icons/." /usr/share/icons/
  [ -d "$R/fondos" ] && { mkdir -p /usr/share/backgrounds/mint-macos; cp -a "$R/fondos/." /usr/share/backgrounds/mint-macos/; }
  [ -d "$R/mint-macos" ] && { mkdir -p /usr/local/share/mint-macos; cp -a "$R/mint-macos/." /usr/local/share/mint-macos/; }
  # Darling vino copiado a /opt/darling (setuid). El DPREFIX de cada usuario se crea al primer
  # «darling shell»; aquí solo el enlace para tenerlo en el PATH.
  ln -sf /opt/darling/bin/darling /usr/local/bin/darling
fi

paso "esquemas y dconf"
glib-compile-schemas /usr/share/glib-2.0/schemas/
[ -d /etc/dconf/db ] && dconf update || true
