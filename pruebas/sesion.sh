#!/usr/bin/env bash
# Corre dentro del bus de prueba (lo lanza correr.sh con dbus-run-session): deja
# un gestor de ventanas si hace falta y corre cada caso con su tiempo límite.
#   sesion.sh CASO.sh…
set -uo pipefail

RES="$PRUEBAS_RES"

# Antes de nada: el dconf de este bus tiene que escribir en el HOME de prueba.
dconf write /org/mint-macos/prueba/marca "'$MINT_MACOS_PRUEBA'"
if [ ! -s "$XDG_CONFIG_HOME/dconf/user" ]; then
  echo "  ✗ el dconf de la prueba no escribe en $XDG_CONFIG_HOME: no sigo"
  exit 1
fi

# En Xephyr no hay gestor de ventanas: Muffin, el de Cinnamon (foco, decoración,
# _NET_ACTIVE_WINDOW para wmctrl). En :0 ya está el de José.
if [ "$PRUEBAS_REAL" != true ]; then
  muffin --replace --sm-disable > "$RES/muffin.log" 2>&1 &
  for _ in $(seq 50); do wmctrl -m >/dev/null 2>&1 && break; sleep 0.1; done
  wmctrl -m >/dev/null 2>&1 || { echo "  ✗ Muffin no arrancó"; tail "$RES/muffin.log"; exit 1; }
fi

# cerrar_caso NOMBRE: lo que lanzó el caso y siga vivo.
cerrar_caso() {
  local p
  for p in $(grep -lzx "PRUEBAS_CASO=$1" /proc/[0-9]*/environ 2>/dev/null | cut -d/ -f3); do
    kill "$p" 2>/dev/null || true
  done
}

for c in "$@"; do
  n="$(basename "$c" .sh)"
  limite="$(sed -n 's/^# límite: *//p' "$c" | head -1)"
  inicio=$(date +%s)
  PRUEBAS_CASO="$n" timeout "${limite:-120}" bash -c 'source "$PRUEBAS_LIB"; source "$1"; prueba' _ "$c" \
    > "$RES/$n.log" 2>&1
  r=$?
  cerrar_caso "$n"
  seg=$(( $(date +%s) - inicio ))
  # El dconf de José, después de cada caso: si cambió, no sigue nada más.
  if [ "$(sha256sum "$PRUEBAS_DCONF_JOSE" 2>/dev/null | cut -d' ' -f1 || true)" != "$PRUEBAS_DCONF_ANTES" ]; then
    printf '  ✗ %-28s el dconf de José cambió: paro la corrida\n' "$n"
    exit 2
  fi
  case $r in
    0) printf '  ✓ %-28s %3ss\n' "$n" "$seg" ;;
    77) printf '  – %-28s saltado: %s\n' "$n" "$(tail -1 "$RES/$n.log")" ;;
    124) printf '  ✗ %-28s se pasó de %ss\n' "$n" "${limite:-120}"; tail -5 "$RES/$n.log" | sed 's/^/      /' ;;
    *) printf '  ✗ %-28s\n' "$n"; tail -5 "$RES/$n.log" | sed 's/^/      /' ;;
  esac
done | tee "$RES/resumen.txt"

# El conteo sale del resumen (el for corre en el subshell del tee).
FALLAN=$(grep -c '^  ✗' "$RES/resumen.txt" || true)
printf '  %s bien, %s fallan, %s saltados\n' "$(grep -c '^  ✓' "$RES/resumen.txt")" "$FALLAN" \
  "$(grep -c '^  –' "$RES/resumen.txt")" | tee -a "$RES/resumen.txt"
[ "$FALLAN" = 0 ]
