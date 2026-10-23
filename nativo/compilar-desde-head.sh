#!/usr/bin/env bash
# Compila nativo/ del HEAD commiteado (no del árbol de trabajo, que puede estar a medias) y
# deja mac-sesion, mac-gatekeeper, mac-forcequit, mac-launchpad-vala, mac-captura-herramienta-vala, mac-ventanas, mac-preferencias, mac-acerca, mac-acerca-lanzar, mac-tienda, mac-actividad, mac-sesion-lanzar y mac-forcequit-lanzar en RAIZ/.local/bin. Lo usan instalar.sh y paquete.sh.
#   compilar-desde-head.sh RAIZ
set -euo pipefail
RAIZ="${1:?uso: compilar-desde-head.sh RAIZ}"
REPO="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
for c in meson ninja valac; do command -v "$c" >/dev/null || { echo "falta $c" >&2; exit 1; }; done
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
git -C "$REPO" archive HEAD nativo | tar -x -C "$T"
meson setup "$T/nativo/build" "$T/nativo" --buildtype=release --prefix=/usr >/dev/null
# Regla de José (18-10-2026, «cpu al 100%»): una compilación a la vez, con la menor prioridad y dos hilos. Si ya hay otro
# ninja corriendo (el armado de Infra, otra sesión), se espera a que termine.
while pgrep -x ninja >/dev/null; do sleep 5; done
nice -n 19 ionice -c3 ninja -j2 -C "$T/nativo/build" >/dev/null
install -d "$RAIZ/.local/bin"
install -m 755 "$T/nativo/build/sesion/mac-sesion" "$T/nativo/build/gatekeeper/mac-gatekeeper" "$T/nativo/build/forcequit/mac-forcequit" "$T/nativo/build/launchpad/mac-launchpad-vala" "$T/nativo/build/captura/mac-captura-herramienta-vala" "$T/nativo/build/ventanas/mac-ventanas" "$T/nativo/build/preferencias/mac-preferencias" "$T/nativo/build/acerca/mac-acerca" "$T/nativo/mac-acerca-lanzar" "$T/nativo/build/emojis/mac-emojis-vala" "$T/nativo/build/tienda/mac-tienda" "$T/nativo/build/actividad/mac-actividad" "$T/nativo/mac-emojis-lanzar" "$T/nativo/mac-sesion-lanzar" "$T/nativo/mac-forcequit-lanzar" "$RAIZ/.local/bin/"
# El agente de polkit solo sale si hay libpolkit-agent-1-dev; sin él se compila lo demás.
if [ -x "$T/nativo/build/polkit/mac-polkit" ]; then
  install -m 755 "$T/nativo/build/polkit/mac-polkit" "$RAIZ/.local/bin/"
else
  echo "sin libpolkit-agent-1-dev: no se compiló mac-polkit (el agente sigue siendo el de Python)"
fi
# La pantalla de bloqueo en la sesión: se instala el binario, pero no se cablea; eso lo hace
# login/bloqueo.sh --en-sesion, con el sí de José (nativo/bloqueo/LEEME.md).
[ -x "$T/nativo/build/bloqueo/mac-bloqueo" ] && install -m 755 "$T/nativo/build/bloqueo/mac-bloqueo" "$RAIZ/.local/bin/"
# El módulo GTK3 del parpadeo de los menús: se instala pero no entra en GTK_MODULES hasta que se active (nativo/gtkmenu-flash).
if [ -f "$T/nativo/build/gtkmenu-flash/libmint-macos-menu-flash.so" ]; then
  install -d "$RAIZ/.local/lib/mint-macos"
  install -m 755 "$T/nativo/build/gtkmenu-flash/libmint-macos-menu-flash.so" "$RAIZ/.local/lib/mint-macos/"
fi
# El módulo GTK3 que exporta las acciones de ventana de las apps gtkmm (GTK_MODULES; nativo/gtk-acciones).
if [ -f "$T/nativo/build/gtk-acciones/libmint-macos-acciones.so" ]; then
  install -d "$RAIZ/.local/lib/mint-macos"
  install -m 755 "$T/nativo/build/gtk-acciones/libmint-macos-acciones.so" "$RAIZ/.local/lib/mint-macos/"
fi
echo "compilado del HEAD $(git -C "$REPO" rev-parse --short HEAD)"
