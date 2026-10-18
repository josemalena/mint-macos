#!/bin/bash
# Los íconos de las apps de APT en el App Store (18-10-2026). Ubuntu publica los
# íconos de DEP-11 en tarballs al lado del catálogo (icons-64x64 y icons-128x128),
# pero APT no los baja por defecto (DefaultEnabled "false" en 50appstream). Sin ellos
# casi la mitad de las apps de APT llega sin ícono: el que trae la ficha por URL
# (appstream.ubuntu.com) no siempre responde. REQUIERE ROOT:
#
#   sudo tienda/iconos-apt-root.sh            los activa y corre apt update
#   sudo tienda/iconos-apt-root.sh --quitar   la vuelta atrás
#
# appstreamcli los desempaca en /var/lib/swcatalog/icons/<origen>/<tamaño>, que es
# donde los busca mint-macos-tienda.
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "✗ Corre esto con sudo."; exit 1; }
CONF=/etc/apt/apt.conf.d/60mint-macos-dep11-iconos
if [ "${1:-}" = --quitar ]; then
  rm -f "$CONF"
  echo "Quitado. Los íconos ya bajados se van con el próximo apt update."
  exit 0
fi
cat > "$CONF" <<'EOF'
// mint-macos: los íconos de DEP-11 para el App Store (tienda/iconos-apt-root.sh).
Acquire::IndexTargets::deb::DEP-11-icons::DefaultEnabled "true";
Acquire::IndexTargets::deb::DEP-11-icons-large::DefaultEnabled "true";
EOF
apt-get update -qq
appstreamcli refresh --source=os --force >/dev/null 2>&1 || true
n=$(find /var/lib/swcatalog/icons -name '*.png' 2>/dev/null | wc -l)
echo "Listo: $n íconos en /var/lib/swcatalog/icons. Vuelta atrás: sudo $0 --quitar"
