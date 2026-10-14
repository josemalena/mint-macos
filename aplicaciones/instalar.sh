#!/bin/bash
# /Applications como en la Mac: una carpeta con una entrada por app instalada y
# la subcarpeta Utilities. Se mantiene sola: cuando se instala o se quita una
# app, systemd lo ve y la vuelve a armar.
#
#   ./instalar.sh            instala el generador y el servicio que lo vigila
#   ./instalar.sh --quitar   deja todo como estaba: para el servicio, borra lo
#                            generado en /Applications y quita los archivos
#
# /Applications tiene que existir y ser del usuario; crearla pide sudo y se
# hace una sola vez (requisitos.sh lo hace al instalar el paquete):
#   sudo install -d -o "$USER" -g "$(id -gn)" /Applications
#
# Qué entra, qué va en Utilities y cómo ajustarlo: aplicaciones.py --help
set -euo pipefail

AQUI="$(cd "$(dirname "$0")" && pwd)"
LIB="$HOME/.local/lib/mint-macos"
UNIDADES="$HOME/.config/systemd/user"
DESTINO="${APLICACIONES_DESTINO:-/Applications}"

if [ "${1:-}" = "--quitar" ]; then
  systemctl --user disable --now aplicaciones.path aplicaciones.service 2>/dev/null || true
  if [ -x "$LIB/aplicaciones.py" ] && [ -d "$DESTINO" ]; then
    python3 "$LIB/aplicaciones.py" --destino "$DESTINO" --quitar
  fi
  rm -f "$UNIDADES/aplicaciones.path" "$UNIDADES/aplicaciones.service" "$LIB/aplicaciones.py"
  systemctl --user daemon-reload
  echo "Listo. La carpeta $DESTINO no se borra (es del sistema); si ya no la quieres: sudo rmdir $DESTINO"
  exit 0
fi

if [ ! -d "$DESTINO" ] || [ ! -w "$DESTINO" ]; then
  echo "Falta $DESTINO (o no es tuya). Créala una vez con:" >&2
  echo "  sudo install -d -o \"\$USER\" -g \"\$(id -gn)\" $DESTINO" >&2
  echo "y vuelve a correr este guion." >&2
  exit 1
fi

mkdir -p "$LIB" "$UNIDADES"
install -m 755 "$AQUI/aplicaciones.py" "$LIB/aplicaciones.py"

cat > "$UNIDADES/aplicaciones.service" <<EOF
[Unit]
Description=Arma $DESTINO con las apps instaladas (mint-macos)

[Service]
Type=oneshot
ExecStart=/usr/bin/python3 %h/.local/lib/mint-macos/aplicaciones.py --destino $DESTINO

[Install]
WantedBy=default.target
EOF

# Las carpetas de lanzadores que existen en esta máquina. Una que aparezca
# después (Flatpak instalado más tarde) entra con el próximo inicio de sesión.
{
  echo "[Unit]"
  echo "Description=Vigila los lanzadores para $DESTINO"
  echo
  echo "[Path]"
  for d in /usr/share/applications /usr/local/share/applications \
           "$HOME/.local/share/applications" \
           /var/lib/flatpak/exports/share/applications \
           "$HOME/.local/share/flatpak/exports/share/applications" \
           /var/lib/snapd/desktop/applications; do
    [ -d "$d" ] && echo "PathChanged=${d/#$HOME/%h}"
  done
  echo "Unit=aplicaciones.service"
  echo
  echo "[Install]"
  echo "WantedBy=default.target"
} > "$UNIDADES/aplicaciones.path"

systemctl --user daemon-reload
systemctl --user enable aplicaciones.service >/dev/null 2>&1
systemctl --user enable --now aplicaciones.path >/dev/null
systemctl --user start aplicaciones.service
echo "$DESTINO armada ($(find "$DESTINO" -maxdepth 2 -name '*.desktop' | wc -l) apps). Se mantiene sola."
echo "Para deshacerlo: $AQUI/instalar.sh --quitar"
