#!/bin/bash
# La prueba del llavero de verdad (Secret Service) contra un gnome-keyring aparte, con su propio
# HOME y su propio bus: el llavero de la sesión ni se mira.
set -euo pipefail
cd "$(dirname "$0")/.."
export CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}" RUSTUP_HOME="${RUSTUP_HOME:-$HOME/.rustup}"
cargo test --offline -p mint-macos-appleid --no-run -q
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T" XDG_DATA_HOME="$T/data" XDG_CONFIG_HOME="$T/config" XDG_RUNTIME_DIR="$T/run" PRUEBA_LLAVERO_PRIVADO=1
mkdir -p "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR"
dbus-run-session -- bash -c '
  printf "prueba" | gnome-keyring-daemon --unlock --components=secrets >/dev/null 2>&1
  printf "prueba" | gnome-keyring-daemon --start --components=secrets >/dev/null 2>&1
  cargo test --offline -p mint-macos-appleid -- --ignored llavero_del_sistema 2>&1 | grep -E "^test |test result|panicked" -A3
'
