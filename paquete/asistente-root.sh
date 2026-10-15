#!/bin/bash
# La parte de root del asistente de instalación. El asistente lo lanza UNA vez
# con pkexec (una sola clave) y le va pidiendo los pasos por la entrada
# estándar, uno por línea, en el orden que hacen falta: requisitos antes de
# instalar mint-macos, y el arranque y el login después, cuando ya están la SF
# y el fondo de Catalina (login/instalar.sh lee el fondo de gsettings y los dos
# leen ~/.local/share/fonts/san-francisco).
#
#   pkexec ./asistente-root.sh            (lee pasos de la entrada estándar)
#   ./asistente-root.sh --probar          sin root: dice qué correría cada paso
#
# Pasos (lista cerrada; cualquier otra línea se rechaza sin correr nada):
#   requisitos   requisitos.sh
#   arranque     tema/arranque/instalar.sh
#   login        login/instalar.sh --activar
#   vigilante    apfs/vigilar.sh --instalar, solo si /etc/fstab tiene fsapfs
#   fin          termina (también al cerrarse la entrada o tras 1 hora sin pasos)
#
# No recibe argumentos de texto libre: el usuario sale de PKEXEC_UID (lo pone
# pkexec, no quien llama) y el repo es ~/mint-macos de ese usuario, el que
# desempaca instalar-aqui.sh. Responde con líneas «@@root-ok <paso>» o
# «@@root-error <paso> <código>», que el asistente lee.
set -uo pipefail

PROBAR=false
[ "${1:-}" = --probar ] && PROBAR=true
[ $# -le 1 ] && { [ $# -eq 0 ] || $PROBAR; } || { echo "@@root-error argumentos 2"; exit 2; }

if $PROBAR; then
  UID_USUARIO="$(id -u)"
else
  [ "$(id -u)" = 0 ] || { echo "@@root-error no-root 1"; exit 1; }
  UID_USUARIO="${PKEXEC_UID:-}"
fi
[[ "$UID_USUARIO" =~ ^[0-9]+$ ]] && [ "$UID_USUARIO" -ge 500 ] && [ "$UID_USUARIO" -ne 65534 ] || { echo "@@root-error usuario 1"; exit 1; }
USUARIO="$(getent passwd "$UID_USUARIO" | cut -d: -f1)"
HOGAR="$(getent passwd "$UID_USUARIO" | cut -d: -f6)"
[[ "$USUARIO" =~ ^[a-z_][a-z0-9_-]*$ ]] && [ -d "$HOGAR" ] || { echo "@@root-error usuario 1"; exit 1; }
REPO="${ASISTENTE_REPO_PRUEBA:-$HOGAR/mint-macos}"
$PROBAR || REPO="$HOGAR/mint-macos"
# El repo tiene que ser del usuario y no un enlace: lo desempaca instalar-aqui.sh.
[ -d "$REPO" ] && [ ! -L "$REPO" ] && [ "$(stat -c %u "$REPO")" = "$UID_USUARIO" ] \
  || { echo "@@root-error repo 1"; exit 1; }

correr() { # paso comando…
  local paso="$1"; shift
  if $PROBAR; then echo "  [$paso] SUDO_USER=$USUARIO $*"; echo "@@root-ok $paso"; return; fi
  # Los guiones de mint-macos sacan el usuario de SUDO_USER, como con sudo.
  if env SUDO_USER="$USUARIO" SUDO_UID="$UID_USUARIO" HOME=/root "$@"; then
    echo "@@root-ok $paso"
  else
    echo "@@root-error $paso $?"
  fi
}

while IFS= read -r -t 3600 PASO; do
  case "$PASO" in
    requisitos) correr requisitos "$REPO/requisitos.sh" ;;
    arranque)   correr arranque "$REPO/tema/arranque/instalar.sh" ;;
    login)
      # El fork que desempacó instalar-aqui.sh (p_greeter), si es del usuario.
      G="$HOGAR/.cache/mint-macos/src/mint-macos-greeter-paquete"
      if [ -d "$G" ] && [ ! -L "$G" ] && [ "$(stat -c %u "$G")" = "$UID_USUARIO" ]; then
        correr login "$REPO/login/instalar.sh" --activar --fuente "$G"
      else
        correr login "$REPO/login/instalar.sh" --activar
      fi ;;
    vigilante)
      if awk '$3 == "fsapfs" && $1 !~ /^#/ {f=1} END {exit !f}' /etc/fstab; then
        correr vigilante "$REPO/apfs/vigilar.sh" --instalar
      else
        echo "  sin discos APFS en fstab: el vigilante no hace falta"; echo "@@root-ok vigilante"
      fi ;;
    fin) echo "@@root-ok fin"; exit 0 ;;
    *) echo "@@root-error paso-desconocido 2" ;;
  esac
done
exit 0
