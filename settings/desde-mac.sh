#!/usr/bin/env bash
# Saca del disco de la Mac, en SOLO LECTURA y a una carpeta local del usuario,
# los íconos de los paneles de System Preferences que usa Settings.app.
# Nada de esto va al repo: son archivos de Apple y cada quien los saca de su Mac.
#
#   ./desde-mac.sh [--disco /dev/sdX2] [--volumen-sistema N] [--destino DIR]
#
#   --disco            el contenedor APFS (lsblk -f lo marca «apfs»). Sin él,
#                      el primero que haya.
#   --volumen-sistema  índice del volumen de sistema (fsapfsinfo /dev/sdX2 los
#                      lista). Sin él, el que no es «- Data», Preboot, Recovery,
#                      VM ni Update.
#   --destino          dónde dejarlos (por defecto ~/.local/share/mint-macos/settings)
#
# Qué deja:
#   <destino>/iconos/<identificador del panel>.png   p. ej. com.apple.preference.sound.png
#   <destino>/iconos/sistema.png                     el ícono de System Preferences
#   <destino>/orden.json                             los grupos y el orden de los paneles,
#                                                    tal como los define Catalina
#   <destino>/glifos/GoBack@1x.png …                los glifos de la barra de herramientas
#   <destino>/glifos/LockLocked@1x.png …            el candado cerrado y abierto de los paneles
#
# Un ícono que no se pueda abrir (Screen Time, Fibre Channel) no sale; Settings.app
# usa entonces el del tema.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
DESTINO="$HOME/.local/share/mint-macos/settings"
while [ $# -gt 0 ]; do
  case "$1" in
    --disco) export MAC_DISCO="$2"; shift 2 ;;
    --volumen-sistema) export MAC_VOL_SISTEMA="$2"; shift 2 ;;
    --destino) DESTINO="$2"; shift 2 ;;
    -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
    *) echo "✗ parámetro desconocido: $1 (mira --help)"; exit 2 ;;
  esac
done

for c in convert identify python3; do
  command -v "$c" >/dev/null || { echo "✗ Falta $c"; exit 1; }
done

# shellcheck source=../tema/comun.sh
source "$REPO/tema/comun.sh"
trap desmontar_mac EXIT

echo "▸ Montando el volumen de sistema de la Mac (solo lectura)…"
montar_mac_sistema || { echo "✗ No encuentro el disco de la Mac (APFS). Mira --disco y --volumen-sistema."; exit 1; }

mkdir -p "$DESTINO/iconos"
echo "▸ Sacando los íconos de los paneles a $DESTINO"

python3 - "$MAC_SISTEMA" "$DESTINO" "$REPO" <<'PY'
import glob, json, os, plistlib, subprocess, sys

sistema, destino, repo = sys.argv[1], sys.argv[2], sys.argv[3]
paneles = os.path.join(sistema, "System/Library/PreferencePanes")
app = os.path.join(sistema, "System/Applications/System Preferences.app")
salida = os.path.join(destino, "iconos")
MAXIMO = 160


def candidatos(base, nombre):
    """Los archivos que pueden ser ese ícono: el nombre tal cual o con extensión,
    y las variantes @2x."""
    stem, ext = os.path.splitext(nombre)
    exts = [ext] if ext else []
    exts += [".icns", ".tiff", ".png", ".tif"]
    vistos = []
    for e in exts:
        for suf in ("@2x", ""):
            for ruta in glob.glob(base + "/**/" + stem + suf + e, recursive=True):
                if ruta not in vistos:
                    vistos.append(ruta)
    return vistos


def mejor_cuadro(ruta):
    """(índice, lado) del cuadro más grande del archivo, o None si no se lee."""
    r = subprocess.run(["identify", "-format", "%p %w %h\n", ruta],
                       capture_output=True, text=True)
    mejor = None
    for linea in r.stdout.splitlines():
        partes = linea.split()
        if len(partes) < 3:
            continue
        i, w, h = int(partes[0]), int(partes[1]), int(partes[2])
        if mejor is None or w * h > mejor[1] * mejor[1]:
            mejor = (i, min(w, h))
    return mejor


def convertir_icns(ruta, destino_png):
    """ImageMagick no lee .icns; Pillow sí. Se toma el cuadro de 256 px (o el
    más grande que no pase de ahí) y se baja al máximo."""
    from PIL import Image
    im = Image.open(ruta)
    tamanos = sorted({t[0] for t in im.info.get("sizes", [])})
    lado = max([t for t in tamanos if t <= 256] or tamanos or [im.size[0]])
    im.size = (lado, lado)
    im = im.convert("RGBA")
    if lado > MAXIMO:
        im = im.resize((MAXIMO, MAXIMO), Image.LANCZOS)
    im.save(destino_png)
    return os.path.exists(destino_png)


def convertir(ruta, destino_png):
    if ruta.lower().endswith(".icns"):
        try:
            return convertir_icns(ruta, destino_png)
        except Exception:
            return False
    cuadro = mejor_cuadro(ruta)
    if cuadro is None:
        return False
    indice, lado = cuadro
    tam = f"{min(lado, MAXIMO)}x{min(lado, MAXIMO)}"
    r = subprocess.run(["convert", "-background", "none", f"{ruta}[{indice}]",
                        "-resize", tam, destino_png], capture_output=True)
    return os.path.exists(destino_png)


hechos, faltan = 0, []
for p in sorted(glob.glob(paneles + "/*.prefPane")):
    try:
        info = plistlib.load(open(p + "/Contents/Info.plist", "rb"))
    except Exception:
        continue
    ident = info.get("CFBundleIdentifier")
    icono = info.get("NSPrefPaneIconFile") or info.get("CFBundleIconFile")
    if not ident or not icono:
        continue
    destino_png = os.path.join(salida, ident + ".png")
    for ruta in candidatos(p, icono):
        if convertir(ruta, destino_png):
            hechos += 1
            break
    else:
        faltan.append(ident)

# Los que Apple guarda dentro de un catálogo de assets (Assets.car) en vez de
# sueltos: General, Internet Accounts, Spotlight… Se abren con el lector de
# tema/iconos/car.py, que no necesita macOS. El nombre del archivo del Info.plist
# («GeneralPrefsIcon40») es la versión chica; la grande se llama «…Icons».
import re
sys.path.insert(0, os.path.join(repo, "tema", "iconos"))
try:
    import car
except Exception as e:  # falta liblzfse1 o pdftocairo
    car = None
    print("Sin lector de Assets.car:", e)
if car is not None:
    for ident in list(faltan):
        bundle = [p for p in glob.glob(paneles + "/*.prefPane")
                  if plistlib.load(open(p + "/Contents/Info.plist", "rb")).get("CFBundleIdentifier") == ident]
        if not bundle:
            continue
        info = plistlib.load(open(bundle[0] + "/Contents/Info.plist", "rb"))
        stem = os.path.splitext(info.get("NSPrefPaneIconFile") or "")[0]
        catalogo = bundle[0] + "/Contents/Resources/Assets.car"
        if not stem or not os.path.exists(catalogo):
            continue
        for nombre in (re.sub(r"\d+$", "", stem) + "s", stem):
            try:
                im = car.mayor(catalogo, nombre)
            except Exception:
                im = None
            if im is not None:
                im.thumbnail((MAXIMO, MAXIMO))
                im.save(os.path.join(salida, ident + ".png"))
                faltan.remove(ident)
                hechos += 1
                break

    # Los glifos de la barra: atrás, adelante y Show All. Traen vector (PDF) y
    # salen a 1x y 2x, en negro; Settings.app los pinta del color que toque.
    glifos_dir = os.path.join(destino, "glifos")
    apariencia = (glob.glob(sistema + "/System/Library/CoreServices/SystemAppearance.bundle/Contents/Resources/Assets.car")
                  + glob.glob(sistema + "/System/Library/PrivateFrameworks/*/Resources/SystemAppearance.bundle/Contents/Resources/Assets.car"))
    if apariencia:
        car.glifos(apariencia[0], glifos_dir, {"GoBack", "GoForward"})
    catalogo_app = os.path.join(app, "Contents/Resources/Assets.car")
    if os.path.exists(catalogo_app):
        car.glifos(catalogo_app, glifos_dir, {"ToolbarTopSites"})

# El candado de «Click the lock to make changes» (cerrado y abierto), a 1x y 2x:
# viven sueltos en SecurityInterface.framework y los usan todos los paneles.
import shutil
res_seg = os.path.join(sistema, "System/Library/Frameworks/SecurityInterface.framework/Versions/A/Resources")
os.makedirs(os.path.join(destino, "glifos"), exist_ok=True)
for origen, nombre in (("Lock_Locked State", "LockLocked"), ("Lock_Unlocked State", "LockUnlocked")):
    for esc in ("1", "2"):
        f = os.path.join(res_seg, origen + ("@2x" if esc == "2" else "") + ".png")
        if os.path.exists(f):
            shutil.copyfile(f, os.path.join(destino, "glifos", f"{nombre}@{esc}x.png"))

# El ícono de la propia app: el nombre del archivo lo dice su Info.plist.
try:
    info_app = plistlib.load(open(os.path.join(app, "Contents/Info.plist"), "rb"))
    nombre = info_app.get("CFBundleIconFile", "")
    if nombre and not nombre.endswith(".icns"):
        nombre += ".icns"
    ruta = os.path.join(app, "Contents/Resources", nombre)
    if nombre and os.path.exists(ruta):
        convertir(ruta, os.path.join(salida, "sistema.png"))
except Exception:
    pass

# Los grupos y el orden de Catalina.
orden = os.path.join(app, "Contents/Resources/NSPrefPaneGroups.xml")
if os.path.exists(orden):
    datos = plistlib.load(open(orden, "rb"))
    grupos = [{"id": g["identifier"], "paneles": g.get("panes", [])} for g in datos.get("groups", [])]
    json.dump({"grupos": grupos, "resto": datos.get("catchAllGroupID", "addons")},
              open(os.path.join(destino, "orden.json"), "w"), indent=1)

print(f"{hechos} íconos de paneles.")
if faltan:
    print("Sin ícono suelto (se usa el del tema):", ", ".join(sorted(faltan)))
PY

echo "✓ Listo."
