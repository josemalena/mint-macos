#!/usr/bin/env bash
# imagen/instalador-ubiquity.sh — lo del instalador, aislado: Mint 22.x usa Ubiquity; Mint 23
# (hipótesis: Navidad de 2026) pasaría al live-installer de LMDE, y esto se reemplaza entero.
# Corre dentro del chroot, después de en-chroot.sh. SIN PROBAR (27-10-2026).
#   instalador-ubiquity.sh personal|publica
set -euo pipefail
PERFIL="${1:-personal}"
if [ "$PERFIL" = publica ]; then
  # La imagen pública no puede llevar la marca de Mint en el arranque ni en el instalador
  # (blog.linuxmint.com/?p=209): las diapositivas de Ubiquity, el plymouth y os-release van con la
  # marca propia. Pendiente hasta que José decida el nombre del producto.
  echo "  publica: la marca del instalador está pendiente (falta el nombre del producto)"
  exit 0
fi
# Personal: Ubiquity tal cual; solo se anota de dónde viene la imagen.
mkdir -p /etc/mint-macos
printf 'imagen=personal\nconstruida=%s\n' "$(date -u +%FT%TZ)" > /etc/mint-macos/imagen
