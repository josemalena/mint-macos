#!/bin/bash
# Lo de la versión de macOS activa que no es de una pieza sino de la sesión: hoy, la altura de la barra de menús.
# Lo corre `mint-macos-version --aplicar` (el arranque de la sesión), después de dejar la versión activa en el runtime.
#
#   - Si la versión activa trae el alto de la barra medido (medidas.json: pantalla.alto_barra_menu_pt), pone panels-height a ese valor y
#     guarda el de antes en ~/.config/mint-macos/barra-altura.json para volver.
#   - Si no lo trae (Catalina: sin medidas) y ya se había cambiado, devuelve el valor de antes. Ir y volver deja Catalina en 22.
#   - Solo toca la barra de mint-macos (el panel de arriba con el menú Apple, appmenu y globalmenu); si el valor ya no es el que puso esta
#     misma ruta (la persona lo cambió a mano), no lo pisa y suelta el estado.
#   - Sin gsettings o sin el esquema de Cinnamon no hace nada.
#
#   aplicar-version.sh [VERSIÓN]     (por omisión, la activa)
set -u
AQUI="$(cd "$(dirname "$0")" && pwd)"
ESTADO="${XDG_CONFIG_HOME:-$HOME/.config}/mint-macos/barra-altura.json"
command -v gsettings > /dev/null 2>&1 || exit 0
gsettings get org.cinnamon panels-height > /dev/null 2>&1 || exit 0

exec python3 -I - "$AQUI" "$ESTADO" "${1:-}" <<'PY'
import ast, json, os, subprocess, sys
aqui, estado, version = sys.argv[1:4]
sys.path.insert(0, aqui)
import macos_version

def gs(*a):
    return subprocess.run(['gsettings', *a], capture_output=True, text=True).stdout.strip()

def alturas():
    """panels-height como lista de «id:alto» (una por panel)."""
    return ast.literal_eval(gs('get', 'org.cinnamon', 'panels-height').replace('@as ', ''))

# la barra de mint-macos: un panel arriba y el menú Apple en sus applets
if gs('get', 'org.cinnamon', 'panels-enabled').count('top') != 1 or 'applemenu@macos' not in gs('get', 'org.cinnamon', 'enabled-applets'):
    sys.exit(0)
panel = ast.literal_eval(gs('get', 'org.cinnamon', 'panels-enabled').replace('@as ', ''))[0].split(':')[0]
lista = alturas()
actual = next((int(x.split(':')[1]) for x in lista if x.split(':')[0] == panel), None)
if actual is None:
    sys.exit(0)

def poner(valor):
    nuevas = [('%s:%d' % (panel, valor)) if x.split(':')[0] == panel else x for x in lista]
    subprocess.run(['gsettings', 'set', 'org.cinnamon', 'panels-height', str(nuevas)])

previo = {}
try:
    previo = json.load(open(estado))
except (OSError, ValueError):
    pass
medido = macos_version.medida('pantalla', 'alto_barra_menu_pt', version=version or None)
medido = int(medido) if isinstance(medido, (int, float)) and medido > 0 else None

if medido is None:
    # sin alto medido: si esta ruta lo había cambiado y sigue como lo dejó, se devuelve
    if previo and actual == previo.get('aplicada'):
        poner(int(previo['anterior']))
    if previo:
        os.remove(estado)
    sys.exit(0)

anterior = previo.get('anterior') if previo and actual == previo.get('aplicada') else actual
if actual != medido:
    poner(medido)
os.makedirs(os.path.dirname(estado), exist_ok=True)
json.dump({'anterior': anterior, 'aplicada': medido, 'version': version or macos_version.activa()}, open(estado, 'w'))
PY
