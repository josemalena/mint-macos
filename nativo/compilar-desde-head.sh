#!/usr/bin/env bash
# Compila nativo/ del HEAD commiteado (no del árbol de trabajo, que puede estar a medias) y
# deja mac-sesion, mac-gatekeeper, mac-forcequit, mac-launchpad-vala, mac-captura-herramienta-vala, mac-ventanas, mac-preferencias, mac-sesion-lanzar y mac-forcequit-lanzar en RAIZ/.local/bin. Lo usan instalar.sh y paquete.sh.
#   compilar-desde-head.sh RAIZ
set -euo pipefail
RAIZ="${1:?uso: compilar-desde-head.sh RAIZ}"
REPO="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
for c in meson ninja valac; do command -v "$c" >/dev/null || { echo "falta $c" >&2; exit 1; }; done
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
git -C "$REPO" archive HEAD nativo | tar -x -C "$T"
meson setup "$T/nativo/build" "$T/nativo" --buildtype=release --prefix=/usr >/dev/null
ninja -C "$T/nativo/build" >/dev/null
install -d "$RAIZ/.local/bin"
install -m 755 "$T/nativo/build/sesion/mac-sesion" "$T/nativo/build/gatekeeper/mac-gatekeeper" "$T/nativo/build/forcequit/mac-forcequit" "$T/nativo/build/launchpad/mac-launchpad-vala" "$T/nativo/build/captura/mac-captura-herramienta-vala" "$T/nativo/build/ventanas/mac-ventanas" "$T/nativo/build/preferencias/mac-preferencias" "$T/nativo/mac-sesion-lanzar" "$T/nativo/mac-forcequit-lanzar" "$RAIZ/.local/bin/"
# El agente de polkit solo sale si hay libpolkit-agent-1-dev; sin él se compila lo demás.
if [ -x "$T/nativo/build/polkit/mac-polkit" ]; then
  install -m 755 "$T/nativo/build/polkit/mac-polkit" "$RAIZ/.local/bin/"
else
  echo "sin libpolkit-agent-1-dev: no se compiló mac-polkit (el agente sigue siendo el de Python)"
fi
echo "compilado del HEAD $(git -C "$REPO" rev-parse --short HEAD)"
