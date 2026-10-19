#!/usr/bin/env bash
# La configuración de la Mac en Linux (José, 18-10-2026): la versión de macOS (el perfil), la
# apariencia, General y Mouse, el Dock y las Hot Corners, la foto de la cuenta y el fondo. La otra
# mitad del migrador es migrar-datos.sh (carpetas y Guest). Lo hace migrar/migrar_config.py.
#
#   ./migrar-config.sh [--usuario-mac NOMBRE] [--disco /dev/sdX2]
#                      [--volumen-sistema N] [--volumen-datos N] [--aplicar] [--informe ARCHIVO]
#   ./migrar-config.sh --deshacer [CARPETA]   la vuelta atrás de la última corrida (o de esa)
#
# Reglas:
#   - Sin --aplicar SIMULA: dice qué haría, qué ya está igual y qué no tiene equivalente.
#   - El disco de la Mac se monta en SOLO LECTURA. Con MAC_DATOS y MAC_SISTEMA ya puestas (un disco
#     montado a mano), usa esas.
#   - Nada del llavero, claves, tokens, cuentas de Mail ni otros usuarios de la Mac.
#   - Con --aplicar, cada cambio anota su valor de antes en
#     ~/.local/share/mint-macos/migracion/<fecha>/deshacer.sh.
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
ARGS=()
USUARIO_MAC="${MAC_USUARIO:-}"
while [ $# -gt 0 ]; do
  case "$1" in
    --deshacer) exec python3 -I "$REPO/migrar/migrar_config.py" --deshacer ${2:+"$2"} ;;
    --disco) export MAC_DISCO="$2"; shift 2 ;;
    --volumen-sistema) export MAC_VOL_SISTEMA="$2"; shift 2 ;;
    --volumen-datos) export MAC_VOL_DATOS="$2"; shift 2 ;;
    --usuario-mac) USUARIO_MAC="$2"; shift 2 ;;
    --aplicar) ARGS+=(--aplicar); shift ;;
    --informe) ARGS+=(--informe "$2"); shift 2 ;;
    -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
    *) echo "✗ parámetro desconocido: $1 (mira --help)"; exit 2 ;;
  esac
done

source "$REPO/tema/comun.sh"
trap desmontar_mac EXIT
printf '\n▸ El disco de la Mac (solo lectura)\n'
montar_mac_datos || { echo "  ✗ no encontré el volumen de datos (prueba --disco y --volumen-datos)"; exit 1; }
montar_mac_sistema || { echo "  ✗ no encontré el volumen de sistema (prueba --volumen-sistema)"; exit 1; }
echo "  datos en $MAC_DATOS; sistema en $MAC_SISTEMA"
USUARIOS="$(ls "$MAC_DATOS/Users" | grep -v -x -E 'Shared|Guest|\.localized' || true)"
if [ -z "$USUARIO_MAC" ]; then
  [ "$(echo "$USUARIOS" | grep -c .)" = 1 ] && USUARIO_MAC="$USUARIOS" \
    || { echo "  ✗ hay varios usuarios en la Mac: $(echo $USUARIOS); di cuál con --usuario-mac"; exit 1; }
fi
[ -d "$MAC_DATOS/Users/$USUARIO_MAC" ] || { echo "  ✗ no existe /Users/$USUARIO_MAC en la Mac"; exit 1; }
printf '\n'
python3 -I "$REPO/migrar/migrar_config.py" --datos "$MAC_DATOS" --sistema "$MAC_SISTEMA" --usuario "$USUARIO_MAC" "${ARGS[@]}"
