#!/usr/bin/env bash
# Cuando el proceso FUSE muere, systemd no se entera: la unidad sigue
# «active (mounted)» y el punto responde «Transport endpoint is not
# connected». El automount no lo rehace solo; esto lo desmonta y lo vuelve
# a montar.
set -euo pipefail
PUNTO="${1:-/media/$USER/MacMini}"
UNIDAD="$(systemd-escape -p --suffix=mount "$PUNTO")"
sudo umount -l "$PUNTO" || true
sudo systemctl restart "$UNIDAD"
ls "$PUNTO" >/dev/null && echo "✓ $PUNTO responde"
