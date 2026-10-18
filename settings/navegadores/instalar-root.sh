#!/bin/bash
# enhanced-h264ify en Firefox, Edge y Chrome, solo en las Macs cuya GPU decodifica
# H.264 pero no VP9 ni AV1 (José, 18-10-2026: la mayoría de las Macs donde va el
# proyecto). YouTube manda VP9 o AV1; sin decodificarlo la GPU, el procesador se
# ahoga. Con la extensión pide H.264 (avc1). REQUIERE ROOT:
#
#   sudo ./instalar-root.sh             la pone si equipo.json dice que hace falta
#   sudo ./instalar-root.sh --siempre   la pone sin mirar la GPU
#   sudo ./instalar-root.sh --quitar    la vuelta atrás: quita lo que puso esto
#   ./instalar-root.sh --probar         sin root: dice si haría falta y qué pondría
#
# Lo corre también settings/instalar-root.sh (después de equipo, que deja el campo
# video.decodifica en /run/mint-macos/equipo.json).
#
# Cómo, para que José pueda quitarla como cualquier extensión suya:
#   Firefox  política Extensions.Install en /etc/firefox/policies/policies.json (se
#            funde con lo que haya). Firefox la instala una vez por cambio de la lista:
#            si se quita, no vuelve. (ExtensionSettings «normal_installed» no deja
#            quitarla, solo apagarla.) Id {9a41dee2-b924-4161-a971-7fb35c053a4a},
#            enhanced-h264ify 2.2.1 de AMO, MIT.
#   Edge,    «extensión externa»: /usr/share/microsoft-edge/extensions/<id>.json y
#   Chrome   /usr/share/google-chrome/extensions/<id>.json con el update_url de la
#            Chrome Web Store. Una política (ExtensionInstallForcelist o
#            ExtensionSettings) la forzaría: en Chromium ni force_installed ni
#            normal_installed dejan quitarla. Id omkfmpieigblcllmkgbflkikinpkodlk
#            (enhanced-h264ify de alextrv, el mismo autor, 2.2.1).
set -euo pipefail

FF_DIR=/etc/firefox/policies
FF="$FF_DIR/policies.json"
FF_URL="https://addons.mozilla.org/firefox/downloads/latest/enhanced-h264ify/latest.xpi"
CRX_ID=omkfmpieigblcllmkgbflkikinpkodlk
CRX_JSON='{"external_update_url": "https://clients2.google.com/service/update2/crx"}'
CHROMIUM_DIRS=(/usr/share/microsoft-edge/extensions /usr/share/google-chrome/extensions)
EQUIPO=/run/mint-macos/equipo.json
MARCA="$FF_DIR/.mint-macos-h264ify"   # «este policies.json lo creó mint-macos»

MODO="${1:-}"
case "$MODO" in ""|--python|--siempre|--quitar|--probar) ;; *) echo "uso: sudo $0 [--siempre | --quitar]" >&2; exit 2 ;; esac
[ "$MODO" = --probar ] || [ "$(id -u)" = 0 ] || { echo "✗ Corre esto con sudo."; exit 1; }

# ¿Hace falta? Decodifica H.264 y no VP9 ni AV1. Sin equipo.json no se decide.
hace_falta() {
  [ -r "$EQUIPO" ] || { echo "sin-dato"; return; }
  python3 -I -c '
import json, sys
v = (json.load(open(sys.argv[1])).get("video") or {}).get("decodifica")
if v is None: print("sin-dato")
elif "h264" in v and "vp9" not in v and "av1" not in v: print("si")
else: print("no")' "$EQUIPO"
}

# Firefox: agregar o quitar la URL de Extensions.Install, sin tocar lo demás.
firefox() {
  python3 -I - "$FF" "$FF_URL" "$1" <<'FIN_PY'
import json, os, sys
ruta, url, accion = sys.argv[1:4]
d = {"policies": {}}
if os.path.exists(ruta):
    d = json.load(open(ruta))
p = d.setdefault("policies", {})
lista = p.setdefault("Extensions", {}).setdefault("Install", [])
if accion == "poner" and url not in lista:
    lista.append(url)
if accion == "quitar":
    p["Extensions"]["Install"] = [u for u in lista if u != url]
    if not p["Extensions"]["Install"]:
        del p["Extensions"]["Install"]
    if not p["Extensions"]:
        del p["Extensions"]
tmp = ruta + ".tmp"
with open(tmp, "w") as f:
    json.dump(d, f, indent=2)
    f.write("\n")
os.chmod(tmp, 0o644)
os.replace(tmp, ruta)
print("vacío" if not d["policies"] else "con-otras")
FIN_PY
}

if [ "$MODO" = --quitar ]; then
  if [ -f "$FF" ]; then
    r="$(firefox quitar)"
    # Si el archivo lo creó esto y ya no le queda nada, se va.
    if [ "$r" = vacío ] && [ -f "$MARCA" ]; then rm -f "$FF" "$MARCA"; rmdir "$FF_DIR" 2>/dev/null || true; fi
    echo "  Firefox: fuera de $FF"
  fi
  for d in "${CHROMIUM_DIRS[@]}"; do rm -f "$d/$CRX_ID.json"; rmdir "$d" 2>/dev/null || true; done
  echo "  Edge y Chrome: fuera. Lo que ya se instaló en cada perfil se quita desde el navegador."
  exit 0
fi

f="$(hace_falta)"
if [ "$MODO" = --probar ]; then
  echo "  hace falta: $f ($(python3 -I -c 'import json,sys; print((json.load(open(sys.argv[1])).get("video") or {}).get("decodifica"))' "$EQUIPO" 2>/dev/null || echo 'sin equipo.json'))"
  echo "  pondría: $FF (Extensions.Install) y ${CHROMIUM_DIRS[*]/%//$CRX_ID.json}"
  exit 0
fi
if [ "$MODO" != --siempre ] && [ "$f" != si ]; then
  case "$f" in
    no) echo "  la GPU decodifica VP9 o AV1: enhanced-h264ify no hace falta" ;;
    *) echo "  equipo.json no dice qué decodifica la GPU (instala settings/equipo primero, o --siempre)" ;;
  esac
  exit 0
fi

install -d -m 755 "$FF_DIR"
[ -f "$FF" ] || touch "$MARCA"
firefox poner >/dev/null
echo "  Firefox: $FF (se instala al abrirlo; about:policies lo enseña)"
for d in "${CHROMIUM_DIRS[@]}"; do
  install -d -m 755 "$d"
  printf '%s\n' "$CRX_JSON" > "$d/$CRX_ID.json"
  chmod 644 "$d/$CRX_ID.json"
done
echo "  Edge y Chrome: ${CHROMIUM_DIRS[*]} (se instala al abrirlos)"
