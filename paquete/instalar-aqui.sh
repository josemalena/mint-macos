#!/usr/bin/env bash
# Instala mint-macos desde un paquete de paquete.sh, en una computadora con
# Linux Mint que no tiene el disco de la Mac. Se corre desde la carpeta del
# paquete, como el usuario que va a usarlo (no con sudo). La clave se pide UNA
# vez, al principio, y se mantiene viva hasta el final: lo que necesita sudo
# (requisitos, el arranque y la pantalla de inicio) entra en la misma corrida.
#
#   ./instalar-aqui.sh
#
# Necesita internet para los paquetes de apt, para compilar keyd y fsapfs
# (requisitos.sh) y para bajar el greeter de la pantalla de inicio. Todo lo
# demás viene en el paquete.
#
# Pasos:
#   1. revisa que el usuario y la versión de Mint sean los del paquete
#   2. pide la clave y sudo requisitos.sh
#   3. Fynder y el Dock a ~/.local (ya compilados)
#   4. lo de Apple a ~/.cache/mint-macos/mac-sistema, que hace de disco de la Mac
#   5. instalar.sh --sin-compilar, Settings.app, Launchpad, el ayudante
#      (Force Quit y ⇧⌘5) y las apps web de Apple
#   6. con la misma clave: el arranque (Plymouth) y la pantalla de inicio de
#      Catalina, y bloquear con ella
#   7. dice lo que queda: iCloud Drive y cerrar sesión
set -euo pipefail

AQUI="$(cd "$(dirname "$0")" && pwd)"
REPO="$HOME/mint-macos"
MAC="$HOME/.cache/mint-macos/mac-sistema"

paso() { printf '\n■ %s\n' "$*"; }
leer() { sed -n "s/^$1=//p" "$AQUI/origen.txt"; }

paso "1. ¿Es la misma clase de computadora?"
[ "$(id -u)" != 0 ] || { echo "  ✗ córrelo como tu usuario, sin sudo"; exit 1; }
if [ "$HOME" != "$(leer home)" ]; then
  echo "  ✗ el paquete se armó para $(leer home) y aquí es $HOME."
  echo "    Fynder y el Dock llevan esa ruta compilada: entra con el usuario $(leer usuario)."
  exit 1
fi
MINT_AQUI="$(. /etc/os-release && echo "$VERSION_ID")"
if [ "$MINT_AQUI" != "$(leer mint)" ]; then
  echo "  ojo: el paquete es de Mint $(leer mint) y esto es Mint $MINT_AQUI."
  echo "  Si Fynder o el Dock no arrancan, hay que compilarlos aquí (./instalar.sh sin --sin-compilar)."
fi
echo "  usuario $USER, Mint $MINT_AQUI, mint-macos $(leer repo | cut -c1-7)"

paso "El repo en $REPO"
if [ -e "$REPO" ]; then
  mv "$REPO" "$REPO.antes-$(date +%Y%m%d-%H%M%S)"
  echo "  el que había quedó al lado, con fecha"
fi
tar -xzf "$AQUI/mint-macos.tar.gz" -C "$HOME"

paso "2. Requisitos (sudo; baja paquetes de internet)"
echo "  La clave se pide ahora y no se vuelve a pedir."
sudo -v
# Mantiene viva la clave mientras dure la instalación (sudo la olvida a los
# 15 minutos) y se acaba con este proceso.
( while kill -0 $$ 2>/dev/null; do sudo -n -v 2>/dev/null; sleep 50; done ) &
MANTENER=$!
trap 'kill $MANTENER 2>/dev/null || true' EXIT
sudo "$REPO/requisitos.sh"

paso "3. Fynder y el Dock"
tar -xzf "$AQUI/binarios.tar.gz" -C "$HOME"
glib-compile-schemas "$HOME/.local/share/glib-2.0/schemas"
echo "  $(tar -tzf "$AQUI/binarios.tar.gz" | wc -l) archivos en ~/.local"

paso "4. Lo de Apple"
rm -rf "$MAC"; mkdir -p "$MAC"
tar -xf "$AQUI/mac-sistema.tar" -C "$MAC"
[ -f "$AQUI/apple-extra.tar.gz" ] && tar -xzf "$AQUI/apple-extra.tar.gz" -C "$HOME"
echo "  en $MAC (hace de disco de la Mac para los guiones)"
export MAC_SISTEMA="$MAC"

paso "5. mint-macos"
"$REPO/instalar.sh" --sin-compilar
"$REPO/settings/desde-mac.sh"
"$REPO/settings/instalar.sh"
"$REPO/launchpad/instalar.sh"
"$REPO/ayudante/instalar.sh"
"$REPO/icloud/apps-web.sh"

paso "6. El arranque y la pantalla de inicio (sudo, con la misma clave)"
sudo "$REPO/tema/arranque/instalar.sh"
sudo "$REPO/login/instalar.sh" --activar
"$REPO/login/bloqueo.sh"

paso "Lo que queda"
echo "  - Si la pantalla de inicio no saliera: Ctrl+Alt+F2, entra y  sudo login-mac-revertir"
echo "  - iCloud Drive como carpeta:  $REPO/icloud/icloud.sh instalar, y luego «alta» y «montar»"
echo "    (pide el Apple ID y el código; lo escribes tú)."
echo "  - Cierra sesión y vuelve a entrar."
echo "  - $MAC se puede borrar al terminar; solo hace falta para volver a generar el tema."
