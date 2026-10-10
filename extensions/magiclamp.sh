#!/usr/bin/env bash
# El «efecto genio» de macOS al minimizar: Magic Lamp de klangman
# (CinnamonMagicLamp@klangman, Cinnamon Spices, GPL-3; su LICENSE viene en la
# carpeta y se instala con ella). No se copia al repo: se baja de
# linuxmint/cinnamon-spices-extensions en un commit fijo y se comprueba el
# hash del árbol de la carpeta antes de instalarla.
#
#   ./magiclamp.sh             la instala y la enciende (sin apagar las demás)
#   ./magiclamp.sh --deshacer  vuelve a como estaba (con el respaldo más nuevo)
#
# Ajustes (los de José hoy; los defaults de la extensión):
#   ML_EFECTO=0 (0 lámpara mágica, 1 «default»)  ML_DURACION=350 (ms)
#   ML_TILES_X=20  ML_TILES_Y=20
set -euo pipefail

UUID=CinnamonMagicLamp@klangman
REPO_SPICES=https://github.com/linuxmint/cinnamon-spices-extensions.git
COMMIT=a4ca07fa03eaff12b6ad300b80305b9d1a913583     # versión 1.1.0 (20-10-2025)
ARBOL=4e7bbdacb993a3b58e99ad989c488c810569a468      # git tree de la carpeta
RUTA="$UUID/files/$UUID"
DESTINO="$HOME/.local/share/cinnamon/extensions/$UUID"
AJUSTES="$HOME/.config/cinnamon/spices/$UUID/$UUID.json"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/mint-macos/src/cinnamon-spices-extensions"
RESP_BASE="$HOME/.local/share/respaldos"
paso() { printf '\n▸ %s\n' "$*"; }

if [ "${1:-}" = --deshacer ]; then
  R="$(ls -d "$RESP_BASE"/magiclamp-* 2>/dev/null | sort | tail -1)"
  [ -n "$R" ] || { echo "No hay respaldo de Magic Lamp."; exit 1; }
  paso "Volviendo a $R"
  gsettings set org.cinnamon enabled-extensions "$(cat "$R/enabled-extensions.txt")"
  rm -rf "${DESTINO:?}"
  [ -d "$R/extension" ] && cp -a "$R/extension" "$DESTINO"
  if [ -f "$R/ajustes.json" ]; then cp -a "$R/ajustes.json" "$AJUSTES"; fi
  echo "  listo"
  exit 0
fi

paso "Magic Lamp 1.1.0 (commit ${COMMIT:0:12})"
mkdir -p "$(dirname "$CACHE")"
if [ ! -d "$CACHE/.git" ]; then
  git init -q "$CACHE"
  git -C "$CACHE" remote add origin "$REPO_SPICES"
  git -C "$CACHE" sparse-checkout set --no-cone "$RUTA/" >/dev/null
fi
git -C "$CACHE" fetch -q --depth 1 --filter=blob:none origin "$COMMIT"
git -C "$CACHE" checkout -q --detach FETCH_HEAD
[ "$(git -C "$CACHE" rev-parse "HEAD:$RUTA")" = "$ARBOL" ] \
  || { echo "  ✗ el árbol de $RUTA no es el esperado ($ARBOL): no se instala"; exit 1; }
echo "  árbol verificado: $ARBOL"

R="$RESP_BASE/magiclamp-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$R"
gsettings get org.cinnamon enabled-extensions > "$R/enabled-extensions.txt"
[ -d "$DESTINO" ] && cp -a "$DESTINO" "$R/extension"
[ -f "$AJUSTES" ] && cp -a "$AJUSTES" "$R/ajustes.json"
echo "  respaldo: $R"

rm -rf "${DESTINO:?}"
mkdir -p "$(dirname "$DESTINO")"
cp -a "$CACHE/$RUTA" "$DESTINO"
echo "  instalada en $DESTINO (con su LICENSE)"

# Los ajustes: el archivo de Cinnamon es el esquema con «value» en cada clave.
mkdir -p "$(dirname "$AJUSTES")"
python3 - "$DESTINO/5.6/settings-schema.json" "$AJUSTES" \
  "${ML_EFECTO:-0}" "${ML_DURACION:-350}" "${ML_TILES_X:-20}" "${ML_TILES_Y:-20}" <<'PY'
import json, os, sys
esquema, destino = sys.argv[1], sys.argv[2]
valores = {'effect': int(sys.argv[3]), 'duration': int(sys.argv[4]),
           'x-tiles': int(sys.argv[5]), 'y-tiles': int(sys.argv[6])}
d = json.load(open(destino)) if os.path.exists(destino) else json.load(open(esquema))
for k, v in valores.items():
    if k in d and isinstance(d[k], dict):
        d[k]['value'] = v
json.dump(d, open(destino, 'w'), indent=4)
print('  ajustes:', ', '.join(f'{k}={v}' for k, v in valores.items()))
PY

# Encendida, sin apagar las demás extensiones.
python3 - "$UUID" <<'PY'
import ast, subprocess, sys
uuid = sys.argv[1]
lista = ast.literal_eval(subprocess.check_output(['gsettings', 'get', 'org.cinnamon', 'enabled-extensions']).decode().replace('@as ', ''))
if uuid not in lista:
    lista.append(uuid)
    subprocess.check_call(['gsettings', 'set', 'org.cinnamon', 'enabled-extensions', str(lista)])
print('  encendida:', ', '.join(lista))
PY
echo "  vuelta atrás: $0 --deshacer"
