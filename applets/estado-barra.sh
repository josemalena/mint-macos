#!/usr/bin/env bash
# Cambia los menús de estado de la barra entre los applets de Cinnamon y los de Catalina (applets/*@macos).
#   ./estado-barra.sh --activar [--wifi]   reloj@macos, sonido@macos y bluetooth@macos en lugar de calendar@, sound@ y (el ícono de
#                                          blueman); con --wifi también red@macos en lugar de network@ (solo si hay tarjeta Wi-Fi)
#   ./estado-barra.sh --quitar             vuelta atrás: restaura la lista de applets que había (el respaldo)
#   ./estado-barra.sh --estado             enseña qué hay puesto
# Solo toca la lista org.cinnamon enabled-applets (Cinnamon la aplica al momento, sin reiniciar). No borra la configuración
# de los applets de Cinnamon, así que volver atrás los deja como estaban. Hay que instalar antes los applets (install.sh).
set -euo pipefail
RESPALDO="$HOME/.config/mint-macos/applets-estado.respaldo"
LISTA="$(gsettings get org.cinnamon enabled-applets)"

case "${1:-}" in
  --estado) echo "$LISTA" ;;
  --quitar)
    [ -f "$RESPALDO" ] || { echo "no hay respaldo ($RESPALDO): no se tocó nada" >&2; exit 1; }
    gsettings set org.cinnamon enabled-applets "$(cat "$RESPALDO")"
    rm -f "$RESPALDO"
    echo "Applets de Cinnamon otra vez (lista restaurada)." ;;
  --activar)
    for a in reloj sonido bluetooth; do
      [ -d "$HOME/.local/share/cinnamon/applets/$a@macos" ] || { echo "✗ falta el applet $a@macos (corre install.sh)" >&2; exit 1; }
    done
    [ -f "$RESPALDO" ] || { mkdir -p "$(dirname "$RESPALDO")"; printf '%s' "$LISTA" > "$RESPALDO"; }
    WIFI=0; [ "${2:-}" = "--wifi" ] && WIFI=1
    nueva="$(LISTA="$LISTA" WIFI="$WIFI" python3 - <<'PY'
import ast, os
entradas = ast.literal_eval(os.environ["LISTA"].replace("@as ", ""))
def partes(e):
    panel, zona, orden, uuid, ident = e.split(":")
    return [panel, zona, int(orden), uuid, int(ident)]
lista = [partes(e) for e in entradas]
sigue_id = max(p[4] for p in lista) + 1
cambios = {"calendar@cinnamon.org": "reloj@macos", "sound@cinnamon.org": "sonido@macos"}
if os.environ["WIFI"] == "1":
    cambios["network@cinnamon.org"] = "red@macos"
for p in lista:
    nuevo = cambios.get(p[3])
    if nuevo:
        p[3], p[4] = nuevo, sigue_id
        sigue_id += 1
# Bluetooth va antes del primer ícono de la derecha que no sea de xapp/systray (a la izquierda del Wi-Fi o del volumen).
if not any(p[3] == "bluetooth@macos" for p in lista):
    derecha = [p for p in lista if p[1] == "right"]
    ancla = next((p for p in derecha if p[3] in ("red@macos", "network@cinnamon.org", "sonido@macos")), None)
    destino = ancla[2] if ancla else max([p[2] for p in derecha] or [0]) + 1
    for p in derecha:
        if p[2] >= destino:
            p[2] += 1
    lista.append([ancla[0] if ancla else "panel1", "right", destino, "bluetooth@macos", sigue_id])
print("[" + ", ".join("'%s'" % ":".join(str(x) for x in p) for p in lista) + "]")
PY
)"
    gsettings set org.cinnamon enabled-applets "$nueva"
    echo "Menús de estado de Catalina puestos. Vuelta atrás: $0 --quitar"
    echo "El ícono de Bluetooth de blueman (xapp-status) puede quedar duplicado: ver applets/LEEME o el aviso al activar." ;;
  *) echo "uso: $0 --activar [--wifi] | --quitar | --estado" >&2; exit 2 ;;
esac
