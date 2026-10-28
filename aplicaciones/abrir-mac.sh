#!/bin/bash
# Las .app de Mac se abren con Darling: Fynder, el Launchpad y el Dock llaman a
# mint-macos-abrir-mac (rust/abrir-mac), que pregunta la primera vez como
# Gatekeeper y avisa si la app no puede correr.
#
#   ./abrir-mac.sh            instala el lanzador en ~/.local/bin y crea
#                             ~/.config/mint-macos/darling.conf si no existe
#   ./abrir-mac.sh --quitar   lo deja como estaba: quita el lanzador (o vuelve
#                             al anterior, si había uno) y el darling.conf que
#                             creó este guion
#
# Antes: cd rust && cargo build --release -p mint-macos-abrir-mac
#
# darling.conf dice dónde está Darling (DARLING=) y su prefijo (DPREFIX=). Todo
# guion de mint-macos que llame a darling lo lee y exporta DPREFIX, también para
# el shutdown: sin él, `darling shutdown` busca ~/.darling y sale con rc=1 sin
# apagar nada (27-10-2026).
set -euo pipefail

AQUI="$(cd "$(dirname "$0")" && pwd)"
BIN="$HOME/.local/bin"
LIB="$HOME/.local/lib/mint-macos"
LANZADOR="$BIN/mint-macos-abrir-mac"
ANTERIOR="$LIB/mint-macos-abrir-mac.anterior"
CONF="${XDG_CONFIG_HOME:-$HOME/.config}/mint-macos/darling.conf"
MARCA="# Creado por aplicaciones/abrir-mac.sh"
COMPILADO="$AQUI/../rust/target/release/mint-macos-abrir-mac"

if [ "${1:-}" = "--quitar" ]; then
  if [ -f "$ANTERIOR" ]; then
    install -m 755 "$ANTERIOR" "$LANZADOR" && rm -f "$ANTERIOR"
    echo "  lanzador: vuelve el anterior"
  else
    rm -f "$LANZADOR"
    echo "  lanzador: quitado"
  fi
  if [ -f "$CONF" ] && head -1 "$CONF" | grep -qxF "$MARCA"; then
    rm -f "$CONF"
    echo "  $CONF: quitado"
  fi
  echo "Listo. Fynder ya no abre las apps de Mac."
  exit 0
fi

if [ ! -x "$COMPILADO" ]; then
  echo "Falta compilarlo: cd $AQUI/../rust && cargo build --release -p mint-macos-abrir-mac" >&2
  exit 1
fi

mkdir -p "$BIN" "$LIB" "$(dirname "$CONF")"

# El que había (de una instalación a mano, por ejemplo) se guarda para --quitar.
if [ -f "$LANZADOR" ] && ! cmp -s "$LANZADOR" "$COMPILADO" && [ ! -f "$ANTERIOR" ]; then
  cp -p "$LANZADOR" "$ANTERIOR"
fi
install -m 755 "$COMPILADO" "$LANZADOR"
echo "  lanzador: $LANZADOR"

if [ ! -f "$CONF" ]; then
  cat > "$CONF" <<EOF
$MARCA
# Dónde está Darling y su prefijo. Lo leen mint-macos-abrir-mac y los guiones
# que llaman a darling; DPREFIX se exporta siempre, también para el shutdown.
DARLING=/media/jmalena/Data/darling-instalado/bin/darling
DPREFIX=/media/jmalena/Data/darling-prefijo
EOF
  echo "  $CONF: creado"
else
  echo "  $CONF: ya estaba, no se toca"
fi

case ":$PATH:" in
  *":$BIN:"*) ;;
  *) echo "Ojo: $BIN no está en el PATH de esta terminal; Fynder lo necesita en el de la sesión." >&2 ;;
esac
echo "Listo. Para deshacerlo: $AQUI/abrir-mac.sh --quitar"
