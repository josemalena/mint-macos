#!/usr/bin/env bash
# Saca las etiquetas del Finder (los «tags») de una carpeta del disco de la Mac,
# en SOLO LECTURA, a un archivo oculto del usuario. No copia ningún archivo: solo
# los nombres de las etiquetas y a qué ruta pertenecen.
#
#   ./desde-mac.sh [--carpeta Users/jmalena/Documents] [--destino ARCHIVO]
#
#   --carpeta   la carpeta de la Mac, relativa a la raíz del volumen de datos
#               (por defecto Users/<usuario-mac>/Documents)
#   --destino   dónde dejar el JSON (por defecto
#               ~/.local/share/mint-macos/etiquetas/etiquetas.json)
#   --usuario-mac, --disco, --volumen-datos   como en desde-mac.sh
#
# Si MAC_DATOS ya apunta a la raíz del volumen de datos montado (por ejemplo
# /Volumes/MacMini), se usa; si no, se monta uno aparte en solo lectura.
#
# Dónde viven las etiquetas en macOS:
#   - en cada archivo o carpeta, el atributo extendido
#     com.apple.metadata:_kMDItemUserTags: una lista de «Nombre\nN», con N el
#     color (0 ninguno, 1 gris, 2 verde, 3 morado, 4 azul, 5 amarillo, 6 rojo,
#     7 naranja);
#   - el catálogo (la lista de la barra lateral del Finder, con sus colores y si
#     se ve) en Library/SyncedPreferences/com.apple.finder.plist, clave
#     FinderTagDict.
#
# Salida: la BASE de etiquetas (formato v2): el catálogo y las etiquetas por ruta
# RELATIVA A $HOME («Documents/SISMO/Koralis»), para que valga esté Documents en
# iCloud, en Data o donde sea. Si ya existe, se MEZCLA sin pisar lo etiquetado en
# Linux. Un archivo que iCloud dejó en la nube (.Nombre.icloud) se guarda con su
# nombre real.
#
# Por qué un archivo aparte y no el atributo: ni iCloud Drive (rclone) ni el HDD
# (exFAT) guardan atributos extendidos, y un ext4 solo acepta «user.*», así que
# com.apple.metadata:… no se puede escribir al copiar a Linux. La base es la
# fuente de verdad; user.xdg.tags (la convención de Linux) va solo donde se pueda.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CARPETA=""
DESTINO="$HOME/.local/share/mint-macos/etiquetas/etiquetas.json"
while [ $# -gt 0 ]; do
  case "$1" in
    --carpeta) CARPETA="$2"; shift 2 ;;
    --destino) DESTINO="$2"; shift 2 ;;
    --disco) export MAC_DISCO="$2"; shift 2 ;;
    --volumen-datos) export MAC_VOL_DATOS="$2"; shift 2 ;;
    --usuario-mac) export MAC_USUARIO="$2"; shift 2 ;;
    -h|--help) sed -n '2,32p' "$0"; exit 0 ;;
    *) echo "✗ parámetro desconocido: $1 (mira --help)"; exit 2 ;;
  esac
done

# shellcheck source=../tema/comun.sh
source "$REPO/tema/comun.sh"
trap desmontar_mac EXIT
montar_mac_datos || { echo "✗ No encuentro el volumen de datos de la Mac."; exit 1; }

if [ -z "$CARPETA" ]; then
  usuario="${MAC_USUARIO:-}"
  [ -n "$usuario" ] || usuario="$(ls "$MAC_DATOS/Users" | grep -vE '^(Shared|Guest|\.)' | head -1)"
  CARPETA="Users/$usuario/Documents"
fi
[ -d "$MAC_DATOS/$CARPETA" ] || { echo "✗ No existe $MAC_DATOS/$CARPETA"; exit 1; }

mkdir -p "$(dirname "$DESTINO")"
echo "▸ Leyendo las etiquetas de $CARPETA (solo lectura)…"

python3 - "$MAC_DATOS" "$CARPETA" "$DESTINO" <<'PY'
import json, os, plistlib, re, sys, time

raiz, carpeta, destino = sys.argv[1], sys.argv[2], sys.argv[3]
base = os.path.join(raiz, carpeta)
usuario = carpeta.split("/")[1] if carpeta.startswith("Users/") else ""
COLORES = {0: None, 1: "gris", 2: "verde", 3: "morado", 4: "azul", 5: "amarillo", 6: "rojo", 7: "naranja"}
ATRIBUTO = "com.apple.metadata:_kMDItemUserTags"

# El catálogo del Finder.
catalogo = []
plist = os.path.join(raiz, "Users", usuario, "Library/SyncedPreferences/com.apple.finder.plist")
if os.path.exists(plist):
    try:
        datos = plistlib.load(open(plist, "rb"))
        for t in datos["values"]["FinderTagDict"]["value"]["FinderTags"]:
            color = t.get("l", 0)
            catalogo.append({"nombre": t["n"], "color": color, "color_nombre": COLORES.get(color),
                             "visible": t.get("v", True)})
    except Exception as e:
        print("  catálogo: no se pudo leer:", e, file=sys.stderr)

def nombre_real(n):
    """.Nombre.icloud → Nombre (iCloud deja un marcador oculto del archivo)."""
    m = re.fullmatch(r"\.(.+)\.icloud", n)
    return m.group(1) if m else n

elementos, usan, revisados = {}, {}, 0
inicio = time.time()
for dirpath, dirs, files in os.walk(base):
    for n in dirs + files:
        revisados += 1
        ruta = os.path.join(dirpath, n)
        try:
            if ATRIBUTO not in os.listxattr(ruta):
                continue
            etiquetas = plistlib.loads(os.getxattr(ruta, ATRIBUTO))
        except Exception:
            continue
        if not etiquetas:
            continue
        rel = os.path.relpath(os.path.join(dirpath, nombre_real(n)), base)
        lista = []
        for e in etiquetas:
            nombre, _, color = e.partition("\n")
            c = int(color) if color.isdigit() else 0
            lista.append({"n": nombre, "l": c})
            usan[nombre] = usan.get(nombre, 0) + 1
        elementos[rel] = {"etiquetas": lista, "carpeta": n in dirs, "icloud": nombre_real(n) != n}

for nombre in usan:
    if not any(c["nombre"] == nombre for c in catalogo):
        catalogo.append({"nombre": nombre, "color": 0, "color_nombre": None, "visible": True})

# Las rutas van relativas a $HOME: «Documents/…».
prefijo = os.path.basename(carpeta.rstrip("/"))
nuevos = {f"{prefijo}/{rel}": v for rel, v in elementos.items()}

salida = {"formato": 2, "origen": carpeta,
          "colores": {str(k): v for k, v in COLORES.items() if v},
          "catalogo": catalogo, "elementos": nuevos}

# Si ya hay una base, se mezcla: lo que ya está gana (lo etiquetado en Linux no se pisa).
if os.path.exists(destino):
    try:
        previa = json.load(open(destino, encoding="utf-8"))
        if previa.get("formato") == 2:
            nombres = {c["nombre"] for c in previa["catalogo"]}
            previa["catalogo"] += [c for c in catalogo if c["nombre"] not in nombres]
            for ruta, v in nuevos.items():
                if ruta not in previa["elementos"]:
                    previa["elementos"][ruta] = v
                else:
                    hay = {e["n"] for e in previa["elementos"][ruta]["etiquetas"]}
                    previa["elementos"][ruta]["etiquetas"] += [e for e in v["etiquetas"] if e["n"] not in hay]
            salida = previa
    except Exception as e:
        print("  la base anterior no se pudo leer; se reemplaza:", e, file=sys.stderr)

salida["uso"] = {}
for v in salida["elementos"].values():
    for e in v["etiquetas"]:
        salida["uso"][e["n"]] = salida["uso"].get(e["n"], 0) + 1
salida["uso"] = dict(sorted(salida["uso"].items(), key=lambda kv: -kv[1]))
salida["elementos"] = dict(sorted(salida["elementos"].items()))
with open(destino, "w", encoding="utf-8") as f:
    json.dump(salida, f, ensure_ascii=False, indent=1)
os.chmod(destino, 0o600)
print(f"  {revisados} elementos revisados en {time.time() - inicio:.0f} s")
print(f"  {len(elementos)} con etiquetas ({sum(1 for v in elementos.values() if v['carpeta'])} carpetas)")
for nombre, n in list(salida["uso"].items())[:15]:
    print(f"    {nombre:20} {n}")
PY
echo "✓ Guardado en $DESTINO (solo tuyo; fuera de tus carpetas, así que Fynder no lo muestra)."
