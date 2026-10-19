#!/usr/bin/env bash
# Prueba de login/bloqueo.sh (--en-sesion, dm-tool y --deshacer) en una caja: HOME, XDG, bus y gsettings
# propios, DISPLAY de mentira y la marca MINT_MACOS_PRUEBA. systemctl, xset y setsid son de mentira (anotan),
# y hay un «xss-lock» de mentira vivo con la marca, que bloqueo.sh tiene que parar. Control: el xss-lock de la
# sesión real de José sigue vivo y con el mismo pid antes y después (19-10-2026: una prueba sin la marca lo mató).
set -uo pipefail
AQUI="$(cd "$(dirname "$0")" && pwd)"
T="$(mktemp -d)"; trap 'kill $FALSO 2>/dev/null; rm -rf "$T"' EXIT
fallas=0; mal() { echo "  ✗ $*"; fallas=$((fallas + 1)); }
REAL_ANTES="$(pgrep -u "$USER" -x xss-lock | sort | tr '\n' ' ')"
mkdir -p "$T/home/.local/bin" "$T/bin" "$T/run"; chmod 700 "$T/run"
for c in systemctl xset setsid; do printf '#!/bin/sh\necho "%s $*" >> %s/llamadas\n' "$c" "$T" > "$T/bin/$c"; done
cp "$(command -v sleep)" "$T/bin/xss-lock"   # un binario de verdad: pgrep -x mira el nombre del proceso
printf '#!/bin/sh\necho mac-bloqueo "$@"\n' > "$T/home/.local/bin/mac-bloqueo"
printf '#!/bin/sh\ntrue\n' > "$T/bin/dm-tool"
chmod +x "$T"/bin/* "$T/home/.local/bin/mac-bloqueo"
export HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" XDG_DATA_HOME="$T/home/.local/share" XDG_RUNTIME_DIR="$T/run" \
  GSETTINGS_BACKEND=keyfile DISPLAY=:93 MINT_MACOS_PRUEBA="bloqueo-$$" PATH="$T/bin:$PATH" XDG_SEAT_PATH=/org/freedesktop/DisplayManager/Seat0
unset DBUS_SESSION_BUS_ADDRESS
"$T/bin/xss-lock" 300 & FALSO=$!
sleep 0.3
dbus-run-session -- bash -c '
  gsettings set org.cinnamon.desktop.session idle-delay 300
  "'"$AQUI"'/bloqueo.sh" --en-sesion > "$HOME/en-sesion.txt" 2>&1
  gsettings get org.cinnamon.desktop.screensaver custom-screensaver-command > "$HOME/csc-en-sesion.txt"
  "'"$AQUI"'/bloqueo.sh" > "$HOME/dm-tool.txt" 2>&1
  gsettings get org.cinnamon.desktop.screensaver custom-screensaver-command > "$HOME/csc-dm-tool.txt"
'
kill -0 "$FALSO" 2>/dev/null && mal "no paró el xss-lock de la caja"
grep -q "/.local/bin/mac-bloqueo'" "$HOME/csc-en-sesion.txt" || mal "--en-sesion no apunta a mac-bloqueo: $(cat "$HOME/csc-en-sesion.txt")"
grep -q "systemctl --user enable --now mac-bloqueo-vigilante.service" "$T/llamadas" || mal "no encendió el vigilante"
grep -q 'Restart=always' "$HOME/.config/systemd/user/mac-bloqueo-vigilante.service" 2>/dev/null || [ ! -f "$HOME/.config/systemd/user/mac-bloqueo-vigilante.service" ] || mal "el vigilante sin Restart=always"
grep -q "xss-lock --ignore-sleep -- $HOME/.local/bin/mac-bloqueo" "$T/llamadas" || mal "xss-lock no lanza mac-bloqueo"
grep -q "mint-macos-bloquear'" "$HOME/csc-dm-tool.txt" || mal "la vuelta a dm-tool no puso mint-macos-bloquear: $(cat "$HOME/csc-dm-tool.txt")"
grep -q "systemctl --user disable --now mac-bloqueo-vigilante.service" "$T/llamadas" || mal "la vuelta a dm-tool no quitó el vigilante"
REAL_DESPUES="$(pgrep -u "$USER" -x xss-lock | grep -vx "$FALSO" | sort | tr '\n' ' ')"
[ "$REAL_ANTES" = "$REAL_DESPUES" ] || mal "cambió el xss-lock de fuera de la caja: antes «$REAL_ANTES», después «$REAL_DESPUES»"
[ $fallas = 0 ] && echo "  ✓ bloqueo.sh: --en-sesion, la vuelta a dm-tool y nada fuera de la caja (xss-lock real: ${REAL_ANTES:-ninguno})" \
  || { sed 's/^/    /' "$HOME"/en-sesion.txt "$HOME"/dm-tool.txt | tail -20; exit 1; }
