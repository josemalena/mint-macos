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
# (requisitos.sh). Todo lo demás viene en el paquete, también el fork de la
# pantalla de inicio (greeter.tar.gz).
#
# Pasos:
#   1. revisa que el usuario y la versión de Mint sean los del paquete
#   2. pide la clave y sudo requisitos.sh
#   3. Fynder y el Dock a ~/.local (ya compilados)
#   4. lo de Apple a ~/.cache/mint-macos/mac-sistema, que hace de disco de la Mac
#   5. instalar.sh --sin-compilar, Settings.app, Launchpad, el ayudante
#      (Force Quit y ⇧⌘5) y las apps web de Apple
#   6. con la misma clave: el arranque (Plymouth) y la pantalla de inicio de
#      Catalina, y bloquear con ella; y si hay discos APFS en fstab, el
#      vigilante que rehace su montaje cuando el FUSE muere (apfs/vigilar.sh)
#   7. dice lo que queda: iCloud Drive y cerrar sesión
#
# El asistente gráfico corre los mismos pasos uno por uno, sin sudo, y los de
# root se los pide a asistente-root.sh (una sola clave, por pkexec):
#   ./instalar-aqui.sh --lista          los pasos, en orden, con «root» los de root
#   ./instalar-aqui.sh --paso <nombre>  uno solo de los pasos de usuario
set -euo pipefail

AQUI="$(cd "$(dirname "$0")" && pwd)"
REPO="$HOME/mint-macos"
MAC="$HOME/.cache/mint-macos/mac-sistema"

paso() { printf '\n■ %s\n' "$*"; printf '@@paso %s\n' "$*"; }
leer() { sed -n "s/^$1=//p" "$AQUI/origen.txt"; }

p_verificar() {
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
}

p_repo() {
paso "El repo en $REPO"
if [ -e "$REPO" ]; then
  mv "$REPO" "$REPO.antes-$(date +%Y%m%d-%H%M%S)"
  echo "  el que había quedó al lado, con fecha"
fi
tar -xzf "$AQUI/mint-macos.tar.gz" -C "$HOME"
}

p_binarios() {
paso "3. Fynder y el Dock"
tar -xzf "$AQUI/binarios.tar.gz" -C "$HOME"
glib-compile-schemas "$HOME/.local/share/glib-2.0/schemas"
echo "  $(tar -tzf "$AQUI/binarios.tar.gz" | wc -l) archivos en ~/.local"
}

p_apple() {
paso "4. Lo de Apple"
rm -rf "${MAC:?}"; mkdir -p "$MAC"
tar -xf "$AQUI/mac-sistema.tar" -C "$MAC"
[ -f "$AQUI/apple-extra.tar.gz" ] && tar -xzf "$AQUI/apple-extra.tar.gz" -C "$HOME"
echo "  en $MAC (hace de disco de la Mac para los guiones)"
}

p_mint_macos() {
paso "5. mint-macos"
export MAC_SISTEMA="$MAC"
"$REPO/instalar.sh" --sin-compilar
"$REPO/settings/desde-mac.sh"
"$REPO/settings/instalar.sh"
"$REPO/launchpad/instalar.sh"
"$REPO/ayudante/instalar.sh"
"$REPO/icloud/apps-web.sh"
# El dock otra vez, ahora que existen Launchpad y System Preferences: en el
# paso del tema todavía no estaban y el dock se quedaba sin ellos.
PLANK_ORDEN_MAC=1 "$REPO/tema/plank/configurar.sh"
}

# La pantalla de inicio se compila del fork que trae el paquete, no de GitHub.
GREETER_DIR="$HOME/.cache/mint-macos/src/mint-macos-greeter-paquete"
p_greeter() {
[ -f "$AQUI/greeter.tar.gz" ] || return 0
mkdir -p "$(dirname "$GREETER_DIR")"
tar -xzf "$AQUI/greeter.tar.gz" -C "$(dirname "$GREETER_DIR")" --transform "s#^mint-macos-greeter#$(basename "$GREETER_DIR")#"
}

p_bloqueo() {
paso "Bloquear con la pantalla de inicio"
"$REPO/login/bloqueo.sh"
}

p_lo_que_queda() {
paso "Lo que queda"
echo "  - Si la pantalla de inicio no saliera: Ctrl+Alt+F2, entra y  sudo login-mac-revertir"
echo "  - iCloud Drive como carpeta:  $REPO/icloud/icloud.sh instalar, y luego «alta» y «montar»"
echo "    (pide el Apple ID y el código; lo escribes tú)."
echo "  - Cierra sesión y vuelve a entrar."
echo "  - $MAC se puede borrar al terminar; solo hace falta para volver a generar el tema."
}

# Los pasos en orden. Los de root los corre asistente-root.sh en el asistente,
# y sudo aquí.
PASOS="verificar repo root:requisitos binarios apple mint-macos root:arranque greeter root:login bloqueo root:vigilante lo-que-queda"

case "${1:-}" in
  --lista) for p in $PASOS; do echo "$p" | sed 's/^root:/root /'; done; exit 0 ;;
  --paso)
    case "${2:-}" in
      verificar|repo|binarios|apple|mint-macos|greeter|bloqueo|lo-que-queda) "p_$(echo "$2" | tr - _)"; exit 0 ;;
      *) echo "  ✗ paso desconocido o de root: ${2:-}" >&2; exit 2 ;;
    esac ;;
  "") ;;
  *) echo "uso: $0 [--lista | --paso <nombre>]" >&2; exit 2 ;;
esac

# En la terminal: todo seguido, con una sola clave de sudo.
p_verificar
p_repo
paso "2. Requisitos (sudo; baja paquetes de internet)"
echo "  La clave se pide ahora y no se vuelve a pedir."
sudo -v
# Mantiene viva la clave mientras dure la instalación (sudo la olvida a los
# 15 minutos) y se acaba con este proceso.
( while kill -0 $$ 2>/dev/null; do sudo -n -v 2>/dev/null; sleep 50; done ) &
MANTENER=$!
trap 'kill $MANTENER 2>/dev/null || true' EXIT
sudo "$REPO/requisitos.sh"
p_binarios
p_apple
p_mint_macos
paso "6. El arranque y la pantalla de inicio (sudo, con la misma clave)"
sudo "$REPO/tema/arranque/instalar.sh"
p_greeter
if [ -d "$GREETER_DIR" ]; then sudo "$REPO/login/instalar.sh" --activar --fuente "$GREETER_DIR"
else sudo "$REPO/login/instalar.sh" --activar; fi
p_bloqueo
# El vigilante de los montajes APFS, solo si esta máquina los tiene en fstab
# (el paquete no monta ninguno: lo de la Mac viene en mac-sistema.tar).
if awk '$3 == "fsapfs" && $1 !~ /^#/ {f=1} END {exit !f}' "${FSTAB:-/etc/fstab}"; then
  sudo "$REPO/apfs/vigilar.sh" --instalar
else
  echo "  sin discos APFS en fstab: el vigilante de montajes no hace falta"
fi
p_lo_que_queda
