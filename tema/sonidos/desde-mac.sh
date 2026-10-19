#!/usr/bin/env bash
# Los sonidos de sistema de la Mac para Muelle y Fynder (Planner y Dev-Dock, 19-10-2026): los del Dock
# (arrastrar a la papelera, el «poof» al sacar un ícono), los del Finder (mover a la papelera, vaciarla)
# y los de montar y desmontar un volumen y de captura. Se sacan del volumen de sistema montado
# (MAC_SISTEMA, lo monta desde-mac.sh), se pasan a WAV porque libcanberra no lee AIFF, y quedan en
# ~/.local/share/sounds/mint-macos/ con el MISMO nombre que en la Mac («drag to trash.wav»): así los
# busca Muelle. Nunca van al repo. Cada versión de macOS puede traer otros: se copia lo que haya.
set -euo pipefail
[ -n "${MAC_SISTEMA:-}" ] || { echo "  ✗ falta MAC_SISTEMA (córrelo desde desde-mac.sh)"; exit 1; }
command -v ffmpeg >/dev/null || { echo "  ✗ falta ffmpeg"; exit 1; }
D="$MAC_SISTEMA/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds"
[ -d "$D" ] || { echo "  ✗ esta Mac no tiene $D"; exit 1; }
DEST="$HOME/.local/share/sounds/mint-macos"
mkdir -p "$DEST"
n=0
for f in "$D/dock/"*.aif "$D/finder/"*.aif "$D/system/Volume Mount.aif" "$D/system/Volume Unmount.aif" \
         "$D/system/Grab.aif" "$D/system/Shutter.aif"; do
  [ -f "$f" ] || continue
  ffmpeg -loglevel error -y -i "$f" "$DEST/$(basename "$f" .aif).wav" && n=$((n + 1))
done
echo "  $n sonidos en $DEST"
