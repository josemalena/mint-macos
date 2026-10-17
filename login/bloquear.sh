#!/usr/bin/env bash
# Un solo bloqueo a la vez (lo llaman Cinnamon y xss-lock; lo instala bloqueo.sh).
#
# Por qué existe (11-10-2026): `dm-tool lock` sale enseguida, pero LightDM, al
# bloquear, le pide a logind LockSession, y logind emite la señal Lock a la
# sesión. xss-lock escucha esa señal y, como su locker (dm-tool) ya terminó,
# lanza otro `dm-tool lock`. Cada lock de más reinicia el greeter (sesiones
# c26, c28, c30 de ~1 s en el journal) y, si llega justo después de poner la
# clave, el escritorio sale un instante y vuelve el greeter, con
# «session_real_start: assertion 'priv->pid == 0' failed» de LightDM.
#
# Lo que hace: pide el bloqueo y se queda vivo hasta que la sesión vuelve a
# estar activa (desbloqueada) y unos segundos más. Mientras tanto, cualquier
# otro pedido de bloqueo sale sin hacer nada (flock). xss-lock, además, no
# lanza un locker nuevo mientras el suyo sigue corriendo, que es el contrato
# que espera. Cada llamada queda anotada con quién la hizo.
set -u

SESION="${XDG_SESSION_ID:-}"
ESTADO="${XDG_STATE_HOME:-$HOME/.local/state}/mint-macos"
LOG="$ESTADO/bloqueo.log"
CANDADO="${XDG_RUNTIME_DIR:-/tmp}/mint-macos-bloqueo.lock"
CALMA=10   # segundos tras desbloquear en que se ignora otro pedido
mkdir -p "$ESTADO"

anota() { printf '%s %s\n' "$(date '+%F %T.%3N')" "$*" >> "$LOG"; }
padre="$(tr '\0' ' ' < /proc/$PPID/cmdline 2>/dev/null | cut -c1-80)"

activa() { [ "$(loginctl show-session "$SESION" -p Active --value 2>/dev/null)" = yes ]; }

exec 9> "$CANDADO"
if ! flock -n 9; then
  anota "ignorado (ya hay un bloqueo en curso) — pedido por: $padre"
  exit 0
fi
if [ -n "$SESION" ] && ! activa; then
  anota "ignorado (la sesión $SESION no está activa: el greeter ya está) — pedido por: $padre"
  exit 0
fi

# xss-lock manda TERM al recibir Unlock de logind; seguimos hasta cumplir la
# calma, o el candado se suelta antes de que lleguen los pedidos tardíos.
trap 'anota "TERM recibido (Unlock de logind): sigo hasta la calma"' TERM

anota "bloqueo — pedido por: $padre"
# El greeter enseña el fondo de escritorio de quien bloquea: se deja al día antes de cambiar de pantalla.
[ -x "$HOME/.local/bin/mint-macos-fondo-login" ] && timeout 5 "$HOME/.local/bin/mint-macos-fondo-login" --exportar >/dev/null 2>&1 || true
dm-tool lock

[ -n "$SESION" ] || { sleep "$CALMA"; exit 0; }

# Esperar a que el greeter tome la pantalla (la sesión deja de estar activa)…
for _ in $(seq 1 40); do activa || break; sleep 0.25; done
# …y a que se desbloquee.
while ! activa; do sleep 0.5; done
anota "desbloqueado"
# Los pedidos que lleguen tarde (señales encoladas) chocan con el candado.
sleep "$CALMA"
